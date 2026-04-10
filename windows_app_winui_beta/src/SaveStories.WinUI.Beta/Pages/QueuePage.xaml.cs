using Microsoft.UI.Xaml.Controls;
using SaveStories.WinUI.Beta.Services;
using System.Collections.ObjectModel;
using System.Text;
using System.Text.Json;

namespace SaveStories.WinUI.Beta.Pages;

public sealed partial class QueuePage : Page
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

    public QueuePage()
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
        var lines = ParseInputLines(QueueInputTextBox.Text);
        var added = AddQueueItems(lines);

        QueueInputTextBox.Text = string.Empty;
        AppendLog($"Добавлено профилей: {added}");
        RefreshQueueSummary();
    }

    private void OnClearInputClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        QueueInputTextBox.Text = string.Empty;
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

    private async void OnRunQueueClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_isRunning)
        {
            return;
        }

        if (_queue.Count == 0)
        {
            var lines = ParseInputLines(QueueInputTextBox.Text);
            AddQueueItems(lines);
            QueueInputTextBox.Text = string.Empty;
            RefreshQueueSummary();
        }

        if (_queue.Count == 0)
        {
            QueueStatusTitleText.Text = "Ожидание";
            QueueStatusDetailText.Text = "Добавь хотя бы один профиль.";
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
            "Запускаю пакетную выгрузку stories...");
    }

    private async void OnStopQueueClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (!_isRunning)
        {
            return;
        }

        _runCts?.Cancel();
        await WorkerBridgeService.Current.CancelCurrentAsync();
        QueueStatusTitleText.Text = "Остановка";
        QueueStatusDetailText.Text = "Отправлен запрос на остановку очереди.";
        AppendLog("Запрошена остановка очереди.");
    }

    private async Task RunWorkerCommandAsync(WorkerRequest request, string runningMessage)
    {
        _runCts = new CancellationTokenSource();
        _isRunning = true;
        RunQueueButton.IsEnabled = false;
        StopQueueButton.IsEnabled = true;
        RetryFailedQueueButton.IsEnabled = false;
        QueueStatusTitleText.Text = "Загружаю";
        QueueStatusDetailText.Text = runningMessage;
        AppendLog(runningMessage);

        try
        {
            var result = await WorkerBridgeService.Current.RunAsync(request, _runCts.Token);
            ApplyWorkerResult(result.Response);
        }
        catch (OperationCanceledException)
        {
            QueueStatusTitleText.Text = "Остановлено";
            QueueStatusDetailText.Text = "Операция остановлена пользователем.";
            AppendLog("[cancelled] Операция остановлена.");
        }
        catch (TimeoutException ex)
        {
            QueueStatusTitleText.Text = "Ошибка";
            QueueStatusDetailText.Text = ex.Message;
            AppendLog($"[timeout] {ex.Message}");
        }
        catch (Exception ex)
        {
            QueueStatusTitleText.Text = "Ошибка";
            QueueStatusDetailText.Text = ex.Message;
            AppendLog($"[worker_exception] {ex.Message}");
        }
        finally
        {
            FlushPendingLogs();
            _runCts?.Dispose();
            _runCts = null;
            _isRunning = false;
            RunQueueButton.IsEnabled = true;
            StopQueueButton.IsEnabled = false;
        }
    }

    private void ApplyWorkerResult(WorkerResponse response)
    {
        QueueStatusTitleText.Text = response.Ok ? "Готово" : "Ошибка";
        QueueStatusDetailText.Text = response.Message;
        AppendLog($"[{response.Status}] {response.Message}");

        foreach (var line in response.Logs)
        {
            AppendLog(line);
        }

        var foundCount = response.Data.TryGetValue("foundCount", out var found) ? found : "0";
        var savedCount = response.Data.TryGetValue("savedCount", out var saved) ? saved : response.Items.Count.ToString();
        var processedCount = response.Data.TryGetValue("processedCount", out var processed) ? processed : _queue.Count.ToString();
        _lastFailedProfiles.Clear();
        if (response.Data.TryGetValue("batchResults", out var batchResultsJson) && !string.IsNullOrWhiteSpace(batchResultsJson))
        {
            TryExtractFailedProfiles(batchResultsJson, _lastFailedProfiles);
        }
        RetryFailedQueueButton.IsEnabled = _lastFailedProfiles.Count > 0;
        QueueResultSummaryText.Text = $"Профилей: {_queue.Count}  ·  Обработано: {processedCount}  ·  Найдено: {foundCount}  ·  Сохранено: {savedCount}";
        DiagnosticsService.Current.LogInfo($"queue_result ok={response.Ok} saved={savedCount} failed={_lastFailedProfiles.Count}");
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

        QueueLogsTextBox.Text = _logBuilder.ToString();
        QueueLogsTextBox.SelectionStart = QueueLogsTextBox.Text.Length;
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
        RetryFailedQueueButton.IsEnabled = false;
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
