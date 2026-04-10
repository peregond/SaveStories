using Microsoft.UI.Xaml.Controls;
using SaveStories.WinUI.Beta.Services;
using System.Collections.ObjectModel;
using System.Text;
using System.Text.Json;

namespace SaveStories.WinUI.Beta.Pages;

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
    private const int MaxLogLines = 1500;

    public StoriesPage()
    {
        InitializeComponent();
        QueueListView.ItemsSource = _queue;
        _logFlushTimer = DispatcherQueue.CreateTimer();
        _logFlushTimer.Interval = TimeSpan.FromMilliseconds(120);
        _logFlushTimer.IsRepeating = false;
        _logFlushTimer.Tick += (_, _) => FlushPendingLogs();
        RefreshQueueSummary();
    }

    private void OnAddProfilesClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var lines = ParseInputLines(ProfilesInputTextBox.Text);
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
                Headless = true,
            },
            "Проверяю сессию Instagram...");
    }

    private async void OnDownloadClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_isRunning)
        {
            return;
        }

        if (_queue.Count == 0)
        {
            var lines = ParseInputLines(ProfilesInputTextBox.Text);
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
                OutputDirectory = WorkerBridgeService.Current.GetDefaultDownloadsDirectory(),
                Headless = true,
                MediaFilter = "video_only",
            },
            "Запускаю выгрузку stories...");
    }

    private async Task RunWorkerCommandAsync(WorkerRequest request, string runningMessage)
    {
        _runCts = new CancellationTokenSource();
        _isRunning = true;
        DownloadButton.IsEnabled = false;
        CancelButton.IsEnabled = true;
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
        QueueSummaryText.Text = $"Очередь: {_queue.Count} профилей.";
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

    private static List<string> ParseInputLines(string input)
    {
        return input
            .Split('\n')
            .Select(x => x.Trim())
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }
}
