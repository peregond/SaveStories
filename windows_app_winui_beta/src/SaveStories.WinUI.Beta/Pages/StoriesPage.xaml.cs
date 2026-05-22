using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml;
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
    private readonly NotionInfluencerSource _notionInfluencerSource = new();
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _logFlushTimer;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _liveStatsTimer;
    private bool _isRunning;
    private bool _isRefreshingNotionInfluencers;
    private CancellationTokenSource? _runCts;
    private string _outputDirectory;
    private int _liveProcessedProfiles;
    private int _saveDirectoryBaselineFiles;
    private int _saveDirectoryBaselineFolders;
    private const int MaxLogLines = 1500;
    private static readonly HashSet<string> SupportedMediaExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".jpg",
        ".jpeg",
        ".png",
        ".webp",
        ".mp4",
        ".mov",
        ".m4v",
    };

    public StoriesPage()
    {
        InitializeComponent();
        QueueListView.ItemsSource = _queue;
        HeadlessModeRadio.IsChecked = true;
        SaveVideoOnlyRadio.IsChecked = true;
        NotionInfluencerToggle.IsOn = BetaSettingsStore.Current.NotionInfluencerSourceEnabled;
        _outputDirectory = string.IsNullOrWhiteSpace(BetaSettingsStore.Current.StoriesOutputDirectory)
            ? WorkerBridgeService.Current.GetDefaultDownloadsDirectory()
            : BetaSettingsStore.Current.StoriesOutputDirectory;
        Directory.CreateDirectory(_outputDirectory);
        OutputDirectoryText.Text = _outputDirectory;
        _logFlushTimer = DispatcherQueue.CreateTimer();
        _logFlushTimer.Interval = TimeSpan.FromMilliseconds(120);
        _logFlushTimer.IsRepeating = false;
        _logFlushTimer.Tick += (_, _) => FlushPendingLogs();
        _liveStatsTimer = DispatcherQueue.CreateTimer();
        _liveStatsTimer.Interval = TimeSpan.FromSeconds(2);
        _liveStatsTimer.IsRepeating = true;
        _liveStatsTimer.Tick += (_, _) => RefreshLiveDownloadStats();
        UpdateModeDescription();
        UpdateMediaDescription();
        UpdateNotionInfluencerSummary();
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

        if (NotionInfluencerToggle.IsOn)
        {
            var refreshed = await RefreshNotionInfluencersAsync(replaceQueue: true);
            if (!refreshed)
            {
                return;
            }
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
        RefreshNotionInfluencersButton.IsEnabled = false;
        NotionInfluencerToggle.IsEnabled = false;
        RetryFailedButton.IsEnabled = false;
        StatusTitleText.Text = "Загружаю";
        StatusDetailText.Text = runningMessage;
        _liveProcessedProfiles = 0;
        if (string.Equals(request.Command, "download_profile_batch", StringComparison.OrdinalIgnoreCase))
        {
            ResetLiveDownloadStatsBaseline();
            _liveStatsTimer.Start();
            ResultSummaryText.Text = $"Профилей: {_queue.Count}  ·  Обработано: 0/{_queue.Count}  ·  Идёт запуск...";
        }
        AppendLog(runningMessage);

        try
        {
            var progress = new Progress<string>(line =>
            {
                DispatcherQueue.TryEnqueue(() => HandleWorkerProgress(line));
            });
            var workerTimeout = BuildWorkerTimeout(request);
            if (string.Equals(request.Command, "download_profile_batch", StringComparison.OrdinalIgnoreCase))
            {
                AppendLog($"batch_timeout_minutes={workerTimeout.TotalMinutes:0}");
            }
            var result = await WorkerBridgeService.Current.RunAsync(request, _runCts.Token, timeout: workerTimeout, progress: progress);
            ApplyWorkerResult(result.Response);
            if (string.Equals(request.Command, "download_profile_batch", StringComparison.OrdinalIgnoreCase))
            {
                await OfferEmptyFolderCleanupAsync();
            }
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
            if (string.Equals(request.Command, "download_profile_batch", StringComparison.OrdinalIgnoreCase))
            {
                RefreshLiveDownloadStats();
                _liveStatsTimer.Stop();
            }
            _runCts?.Dispose();
            _runCts = null;
            _isRunning = false;
            DownloadButton.IsEnabled = true;
            CancelButton.IsEnabled = false;
            ChangeOutputDirectoryButton.IsEnabled = true;
            OpenOutputDirectoryButton.IsEnabled = true;
            RefreshNotionInfluencersButton.IsEnabled = true;
            NotionInfluencerToggle.IsEnabled = true;
        }
    }

    private static TimeSpan BuildWorkerTimeout(WorkerRequest request)
    {
        if (!string.Equals(request.Command, "download_profile_batch", StringComparison.OrdinalIgnoreCase))
        {
            return TimeSpan.FromMinutes(20);
        }

        var profileCount = Math.Max(1, request.Urls?.Count ?? 0);
        var minutesPerProfile = request.Headless == true ? 1.5 : 3.0;
        var timeoutMinutes = Math.Clamp(20 + profileCount * minutesPerProfile, 30, 720);
        return TimeSpan.FromMinutes(timeoutMinutes);
    }

    private void HandleWorkerProgress(string line)
    {
        AppendLog(line);

        if (line.StartsWith("batch_slot_", StringComparison.OrdinalIgnoreCase)
            && line.Contains("_start=", StringComparison.OrdinalIgnoreCase))
        {
            var profile = DisplayProfileFromProgress(line);
            StatusTitleText.Text = "Загружаю";
            StatusDetailText.Text = $"Сейчас обрабатывается: {profile}";
            ResultSummaryText.Text = $"Профилей: {_queue.Count}  ·  Обработано: {_liveProcessedProfiles}/{_queue.Count}  ·  Сейчас: {profile}";
            RefreshLiveDownloadStats();
            return;
        }

        if (line.StartsWith("batch_slot_", StringComparison.OrdinalIgnoreCase)
            && line.Contains("_done=", StringComparison.OrdinalIgnoreCase))
        {
            _liveProcessedProfiles = Math.Min(_queue.Count, _liveProcessedProfiles + 1);
            var profile = DisplayProfileFromProgress(line);
            StatusTitleText.Text = "Загружаю";
            StatusDetailText.Text = $"Готов профиль: {profile}";
            ResultSummaryText.Text = $"Профилей: {_queue.Count}  ·  Обработано: {_liveProcessedProfiles}/{_queue.Count}  ·  Последний: {profile}";
            RefreshLiveDownloadStats();
        }
    }

    private static string DisplayProfileFromProgress(string line)
    {
        var separator = line.IndexOf('=');
        if (separator < 0 || separator >= line.Length - 1)
        {
            return line;
        }

        var value = line[(separator + 1)..].Trim();
        if (Uri.TryCreate(value, UriKind.Absolute, out var uri))
        {
            var username = uri.AbsolutePath.Trim('/').Split('/', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(username))
            {
                return username;
            }
        }
        return value;
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

    private void OnNotionInfluencerToggleToggled(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        BetaSettingsStore.Current.SetNotionInfluencerSourceEnabled(NotionInfluencerToggle.IsOn);
        UpdateNotionInfluencerSummary();
    }

    private async void OnRefreshNotionInfluencersClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        await RefreshNotionInfluencersAsync(replaceQueue: true);
    }

    private async Task<bool> RefreshNotionInfluencersAsync(bool replaceQueue)
    {
        if (_isRunning || _isRefreshingNotionInfluencers)
        {
            return false;
        }

        _isRefreshingNotionInfluencers = true;
        RefreshNotionInfluencersButton.IsEnabled = false;
        NotionInfluencerToggle.IsEnabled = false;
        DownloadButton.IsEnabled = false;
        NotionInfluencerSummaryText.Text = "Загружаю свежий список из Notion...";
        StatusTitleText.Text = "Notion";
        StatusDetailText.Text = "Получаю список инфлюенсеров из Notion.";
        AppendLog("Загружаю свежий список инфлюенсеров из Notion.");

        try
        {
            var profiles = await _notionInfluencerSource.FetchProfilesAsync();
            if (profiles.Count == 0)
            {
                NotionInfluencerSummaryText.Text = "В Notion не найдено профилей.";
                StatusTitleText.Text = "Ошибка Notion";
                StatusDetailText.Text = "В Notion-списке не найдено профилей.";
                AppendLog("В Notion-списке не найдено профилей.");
                return false;
            }

            if (replaceQueue)
            {
                _queue.Clear();
                foreach (var profile in profiles)
                {
                    _queue.Add(profile);
                }
                AppendLog($"Очередь заменена свежим Notion-списком: {profiles.Count} профилей.");
            }
            else
            {
                var added = AddQueueItems(profiles);
                AppendLog($"Из Notion-списка добавлено новых профилей: {added}.");
            }

            NotionInfluencerSummaryText.Text = $"Notion обновлён в {DateTime.Now:HH:mm}: {profiles.Count} профилей.";
            StatusTitleText.Text = "Готово";
            StatusDetailText.Text = "Список Notion загружен.";
            RefreshQueueSummary();
            return true;
        }
        catch (Exception ex)
        {
            NotionInfluencerSummaryText.Text = $"Не удалось обновить Notion: {ex.Message}";
            StatusTitleText.Text = "Ошибка Notion";
            StatusDetailText.Text = NotionInfluencerSummaryText.Text;
            AppendLog($"[notion_error] {ex.Message}");
            return false;
        }
        finally
        {
            _isRefreshingNotionInfluencers = false;
            RefreshNotionInfluencersButton.IsEnabled = true;
            NotionInfluencerToggle.IsEnabled = true;
            DownloadButton.IsEnabled = !_isRunning;
        }
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
        RefreshLiveDownloadStats();
        DiagnosticsService.Current.LogInfo($"stories_result ok={response.Ok} saved={savedCount} failed={_lastFailedProfiles.Count}");
    }

    private void ResetLiveDownloadStatsBaseline()
    {
        var snapshot = SnapshotOutputDirectory(_outputDirectory);
        _saveDirectoryBaselineFiles = snapshot.Files;
        _saveDirectoryBaselineFolders = snapshot.Folders;
        LiveDownloadStatsText.Text = "Файлов загружено: 0  ·  Папок создано: 0";
    }

    private void RefreshLiveDownloadStats()
    {
        var snapshot = SnapshotOutputDirectory(_outputDirectory);
        var files = Math.Max(snapshot.Files - _saveDirectoryBaselineFiles, 0);
        var folders = Math.Max(snapshot.Folders - _saveDirectoryBaselineFolders, 0);
        LiveDownloadStatsText.Text = $"Файлов загружено: {files}  ·  Папок создано: {folders}";
    }

    private static (int Files, int Folders) SnapshotOutputDirectory(string root)
    {
        if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
        {
            return (0, 0);
        }

        var files = 0;
        var folders = 0;

        try
        {
            folders = Directory.EnumerateDirectories(root)
                .Count(path => !EmptyFolderCleanupService.IsIgnorableFilesystemEntry(path));
        }
        catch
        {
            folders = 0;
        }

        try
        {
            foreach (var file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
            {
                if (EmptyFolderCleanupService.IsIgnorableFilesystemEntry(file))
                {
                    continue;
                }

                if (SupportedMediaExtensions.Contains(Path.GetExtension(file)))
                {
                    files++;
                }
            }
        }
        catch
        {
            files = 0;
        }

        return (files, folders);
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

    private void UpdateNotionInfluencerSummary()
    {
        NotionInfluencerSummaryText.Text = NotionInfluencerToggle.IsOn
            ? "Перед запуском очередь обновится из Notion."
            : "Автосписок Notion выключен.";
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

    private void OnChangeOutputDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_isRunning)
        {
            return;
        }

        try
        {
            ChangeOutputDirectoryButton.IsEnabled = false;
            var newPath = ShellFolderService.PickFolder(App.MainWindow, "Папка сохранения", _outputDirectory) ?? string.Empty;
            if (string.IsNullOrWhiteSpace(newPath))
            {
                return;
            }

            Directory.CreateDirectory(newPath);
            _outputDirectory = newPath;
            BetaSettingsStore.Current.SetStoriesOutputDirectory(_outputDirectory);
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

    private async Task OfferEmptyFolderCleanupAsync()
    {
        var emptyFolders = EmptyFolderCleanupService.FindDeletableEmptyFolders(_outputDirectory).ToList();
        if (emptyFolders.Count == 0)
        {
            AppendLog("Пустых папок после выгрузки stories не найдено.");
            return;
        }

        AppendLog($"Найдены пустые папки после выгрузки stories: {emptyFolders.Count}.");
        var preview = string.Join(Environment.NewLine, emptyFolders.Select(Path.GetFileName).Where(name => !string.IsNullOrWhiteSpace(name)).Take(12));
        if (emptyFolders.Count > 12)
        {
            preview += $"{Environment.NewLine}и ещё {emptyFolders.Count - 12}";
        }

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "Удалить пустые папки?",
            Content = new ScrollViewer
            {
                MaxHeight = 260,
                Content = new TextBlock
                {
                    Text = $"После выгрузки stories найдены пустые папки. Папка «На перенос» и её содержимое не трогаются.{Environment.NewLine}{Environment.NewLine}{preview}",
                    TextWrapping = TextWrapping.WrapWholeWords,
                },
            },
            PrimaryButtonText = "Удалить",
            CloseButtonText = "Не удалять",
            DefaultButton = ContentDialogButton.Primary,
        };

        var result = await dialog.ShowAsync();
        if (result != ContentDialogResult.Primary)
        {
            AppendLog("Удаление пустых папок пропущено.");
            return;
        }

        var cleanup = EmptyFolderCleanupService.DeleteEmptyFolders(emptyFolders);
        foreach (var folder in cleanup.FailedFolders)
        {
            AppendLog($"[empty_folder_cleanup_error] {Path.GetFileName(folder)}: папка не удалена.");
        }

        StatusTitleText.Text = "Готово";
        StatusDetailText.Text = cleanup.RemovedFolders.Count == 0
            ? "Пустые папки не удалены."
            : $"Удалено пустых папок: {cleanup.RemovedFolders.Count}.";
        AppendLog(cleanup.RemovedFolders.Count == 0
            ? "Пустые папки не удалены."
            : $"Удалены пустые папки после выгрузки stories: {string.Join(", ", cleanup.RemovedFolderNames)}.");
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
