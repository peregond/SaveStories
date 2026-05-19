using Microsoft.UI.Xaml.Controls;
using SaveMe.WinUI.Beta;
using SaveMe.WinUI.Beta.Services;
using System.Collections.ObjectModel;
using System.Text;
using System.Text.Json;

namespace SaveMe.WinUI.Beta.Pages;

public sealed partial class StoriesPage : Page
{
    private readonly ObservableCollection<string> _queue = new();
    private readonly Queue<string> _logLines = new();
    private readonly List<string> _pendingLogs = new();
    private readonly StringBuilder _logBuilder = new();
    private readonly List<string> _lastFailedProfiles = new();
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _logFlushTimer;
    private bool _isRunning;
    private CancellationTokenSource? _runCts;
    private string _outputDirectory;
    private const int MaxLogLines = 1500;

    public StoriesPage()
    {
        InitializeComponent();
        QueueListView.ItemsSource = _queue;
        HeadlessModeRadio.IsChecked = true;
        SaveVideoOnlyRadio.IsChecked = true;
        _outputDirectory = WorkerBridgeService.Current.GetDefaultDownloadsDirectory();
        OutputDirectoryText.Text = _outputDirectory;
        _logFlushTimer = DispatcherQueue.CreateTimer();
        _logFlushTimer.Interval = TimeSpan.FromMilliseconds(120);
        _logFlushTimer.IsRepeating = false;
        _logFlushTimer.Tick += (_, _) => FlushPendingLogs();
        UpdateModeDescription();
        UpdateMediaDescription();
        RefreshQueueSummary();
    }

    private void OnAddProfilesClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var lines = ProfileInputParser.ParseProfiles(ProfilesInputTextBox.Text);
        var added = AddQueueItems(lines);

        ProfilesInputTextBox.Text = string.Empty;
        AppendLog($"Добавлено профилей: {added}");
        RefreshQueueSummary();
    }

    private void OnClearInputClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        ProfilesInputTextBox.Text = string.Empty;
    }

    private async void OnCheckSessionClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_isRunning)
        {
            return;
        }

        await RunWorkerCommandAsync(
            new WorkerRequest
            {
                Command = "check_session",
                Headless = IsHeadlessMode(),
            },
            "Проверяю сессию Instagram...");

        if (string.Equals(StatusTitleText.Text, "Ошибка", StringComparison.OrdinalIgnoreCase)
            && IsSessionMissingText(StatusDetailText.Text))
        {
            await PromptLoginFromSessionCheckAsync();
        }
    }

    private async void OnDownloadClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_isRunning)
        {
            return;
        }

        if (_queue.Count == 0)
        {
            var lines = ProfileInputParser.ParseProfiles(ProfilesInputTextBox.Text);
            AddQueueItems(lines);
            ProfilesInputTextBox.Text = string.Empty;
            RefreshQueueSummary();
        }

        if (_queue.Count == 0)
        {
            StatusTitleText.Text = "Ожидание";
            StatusDetailText.Text = "Добавь хотя бы один профиль.";
            return;
        }

        await RunWorkerCommandAsync(
            new WorkerRequest
            {
                Command = "download_profile_batch",
                Urls = _queue.ToList(),
                OutputDirectory = _outputDirectory,
                Headless = IsHeadlessMode(),
                MediaFilter = GetMediaFilter(),
            },
            "Запускаю выгрузку stories...");
    }

    private async Task RunWorkerCommandAsync(WorkerRequest request, string runningMessage)
    {
        _runCts = new CancellationTokenSource();
        _isRunning = true;
        DownloadButton.IsEnabled = false;
        CancelButton.IsEnabled = true;
        ChangeOutputDirectoryButton.IsEnabled = false;
        OpenOutputDirectoryButton.IsEnabled = false;
        RetryFailedButton.IsEnabled = false;
        StatusTitleText.Text = "Загружаю";
        StatusDetailText.Text = runningMessage;
        AppendLog(runningMessage);

        try
        {
            var result = await WorkerBridgeService.Current.RunAsync(request, _runCts.Token);
            ApplyWorkerResult(result.Response);
        }
        catch (OperationCanceledException)
        {
            StatusTitleText.Text = "Остановлено";
            StatusDetailText.Text = "Операция остановлена пользователем.";
            AppendLog("[cancelled] Операция остановлена.");
        }
        catch (TimeoutException ex)
        {
            StatusTitleText.Text = "Ошибка";
            StatusDetailText.Text = ex.Message;
            AppendLog($"[timeout] {ex.Message}");
        }
        catch (Exception ex)
        {
            StatusTitleText.Text = "Ошибка";
            StatusDetailText.Text = ex.Message;
            AppendLog($"[worker_exception] {ex.Message}");
        }
        finally
        {
            FlushPendingLogs();
            _runCts?.Dispose();
            _runCts = null;
            _isRunning = false;
            DownloadButton.IsEnabled = true;
            CancelButton.IsEnabled = false;
            ChangeOutputDirectoryButton.IsEnabled = true;
            OpenOutputDirectoryButton.IsEnabled = true;
        }
    }

    private async void OnStopClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (!_isRunning)
        {
            return;
        }

        _runCts?.Cancel();
        await WorkerBridgeService.Current.CancelCurrentAsync();
        StatusTitleText.Text = "Остановка";
        StatusDetailText.Text = "Отправлен запрос на остановку текущей задачи.";
        AppendLog("Запрошена остановка текущей задачи.");
    }

    private void OnClearQueueClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_isRunning)
        {
            return;
        }

        _queue.Clear();
        RefreshQueueSummary();
        AppendLog("Очередь очищена.");
    }

    private void ApplyWorkerResult(WorkerResponse response)
    {
        if (response.Ok)
        {
            StatusTitleText.Text = "Готово";
        }
        else
        {
            StatusTitleText.Text = "Ошибка";
        }

        StatusDetailText.Text = response.Message;
        AppendLog($"[{response.Status}] {response.Message}");
        foreach (var line in response.Logs)
        {
            AppendLog(line);
        }

        var profilesCount = _queue.Count;
        var savedCount = response.Data.TryGetValue("savedCount", out var saved) ? saved : response.Items.Count.ToString();
        var foundCount = response.Data.TryGetValue("foundCount", out var found) ? found : "0";
        var processedCount = response.Data.TryGetValue("processedCount", out var processed) ? processed : profilesCount.ToString();
        _lastFailedProfiles.Clear();
        if (response.Data.TryGetValue("batchResults", out var batchResultsJson) && !string.IsNullOrWhiteSpace(batchResultsJson))
        {
            TryExtractFailedProfiles(batchResultsJson, _lastFailedProfiles);
        }
        RetryFailedButton.IsEnabled = _lastFailedProfiles.Count > 0;
        var filesCount = response.Items.Count.ToString();
        ResultSummaryText.Text = $"Профилей: {profilesCount}  ·  Обработано: {processedCount}  ·  Найдено: {foundCount}  ·  Сохранено: {savedCount}  ·  Файлов: {filesCount}";
        DiagnosticsService.Current.LogInfo($"stories_result ok={response.Ok} saved={savedCount} failed={_lastFailedProfiles.Count}");
    }

    private void AppendLog(string line)
    {
        _pendingLogs.Add($"{DateTime.Now:HH:mm:ss}  {line}");
        if (!_logFlushTimer.IsRunning)
        {
            _logFlushTimer.Start();
        }
    }

    private void RefreshQueueSummary()
    {
        var modeLabel = IsHeadlessMode() ? "в фоне" : "видимо";
        var mediaLabel = SaveVideoOnlyRadio.IsChecked == true ? "только видео" : "фото и видео";
        QueueSummaryText.Text = $"Очередь: {_queue.Count} профилей · режим: {modeLabel} · контент: {mediaLabel}.";
    }

    private int AddQueueItems(IEnumerable<string> lines)
    {
        var added = 0;
        foreach (var line in lines)
        {
            if (_queue.Any(existing => string.Equals(existing, line, StringComparison.OrdinalIgnoreCase)))
            {
                continue;
            }
            _queue.Add(line);
            added++;
        }

        return added;
    }

    private void FlushPendingLogs()
    {
        if (_pendingLogs.Count == 0)
        {
            return;
        }

        foreach (var line in _pendingLogs)
        {
            _logLines.Enqueue(line);
        }
        _pendingLogs.Clear();

        while (_logLines.Count > MaxLogLines)
        {
            _logLines.Dequeue();
        }

        _logBuilder.Clear();
        foreach (var line in _logLines)
        {
            _logBuilder.AppendLine(line);
        }

        LogsTextBox.Text = _logBuilder.ToString();
        LogsTextBox.SelectionStart = LogsTextBox.Text.Length;
    }

    private void OnRetryFailedClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_isRunning || _lastFailedProfiles.Count == 0)
        {
            return;
        }

        _queue.Clear();
        foreach (var profile in _lastFailedProfiles)
        {
            _queue.Add(profile);
        }
        RetryFailedButton.IsEnabled = false;
        AppendLog($"Сформирована очередь из неудачных профилей: {_queue.Count}");
        RefreshQueueSummary();
    }

    private async void OnChangeOutputDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_isRunning)
        {
            return;
        }

        try
        {
            ChangeOutputDirectoryButton.IsEnabled = false;
            var newPath = await ShellFolderService.PickFolderAsync(App.MainWindow, "Папка сохранения", _outputDirectory) ?? string.Empty;
            if (string.IsNullOrWhiteSpace(newPath))
            {
                return;
            }

            Directory.CreateDirectory(newPath);
            _outputDirectory = newPath;
            OutputDirectoryText.Text = _outputDirectory;
            AppendLog($"Папка сохранения обновлена: {_outputDirectory}");
        }
        catch (Exception ex)
        {
            AppendLog($"[folder_error] {ex.Message}");
        }
        finally
        {
            ChangeOutputDirectoryButton.IsEnabled = true;
        }
    }

    private void OnOpenOutputDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_isRunning)
        {
            return;
        }

        try
        {
            ShellFolderService.OpenFolder(_outputDirectory);
        }
        catch (Exception ex)
        {
            AppendLog($"[open_folder_error] {ex.Message}");
        }
    }

    private void OnBrowserModeChecked(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        UpdateModeDescription();
        RefreshQueueSummary();
    }

    private void OnMediaModeChecked(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        UpdateMediaDescription();
        RefreshQueueSummary();
    }

    private bool IsHeadlessMode()
    {
        return HeadlessModeRadio.IsChecked == true;
    }

    private string GetMediaFilter()
    {
        return SaveVideoOnlyRadio.IsChecked == true ? "video_only" : "all";
    }

    private void UpdateModeDescription()
    {
        BrowserModeDescriptionText.Text = IsHeadlessMode()
            ? "Браузер скрыт, работает незаметно"
            : "Открывается окно Chromium, можно наблюдать";
    }

    private void UpdateMediaDescription()
    {
        MediaModeDescriptionText.Text = SaveVideoOnlyRadio.IsChecked == true
            ? "Фото пропускаются"
            : "Скачиваются все сторис";
    }

    private static void TryExtractFailedProfiles(string json, List<string> output)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            if (document.RootElement.ValueKind != JsonValueKind.Array)
            {
                return;
            }

            foreach (var entry in document.RootElement.EnumerateArray())
            {
                var status = entry.TryGetProperty("status", out var statusElement) ? (statusElement.GetString() ?? "") : "";
                if (string.Equals(status, "completed", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                var url = entry.TryGetProperty("url", out var urlElement) ? (urlElement.GetString() ?? "") : "";
                if (!string.IsNullOrWhiteSpace(url))
                {
                    output.Add(url.Trim());
                }
            }
        }
        catch
        {
            // ignore malformed batch results
        }
    }

    private async Task PromptLoginFromSessionCheckAsync()
    {
        var prompt = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "Сессия не найдена",
            Content = "Чтобы продолжить, войди в Instagram через браузер.",
            PrimaryButtonText = "Войти",
            CloseButtonText = "Отмена",
            DefaultButton = ContentDialogButton.Primary,
        };
        var result = await prompt.ShowAsync();
        if (result != ContentDialogResult.Primary)
        {
            return;
        }

        await RunWorkerCommandAsync(
            new WorkerRequest
            {
                Command = "login",
                Headless = false,
            },
            "Открываю браузер для входа в Instagram...");

        await RunWorkerCommandAsync(
            new WorkerRequest
            {
                Command = "check_session",
                Headless = true,
            },
            "Проверяю сессию после входа...");
    }

    private static bool IsSessionMissingText(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        return text.Contains("Сначала откройте браузер для входа", StringComparison.OrdinalIgnoreCase)
            || text.Contains("Требуется вход в Instagram", StringComparison.OrdinalIgnoreCase)
            || text.Contains("сессия Instagram не найдена", StringComparison.OrdinalIgnoreCase);
    }
}
