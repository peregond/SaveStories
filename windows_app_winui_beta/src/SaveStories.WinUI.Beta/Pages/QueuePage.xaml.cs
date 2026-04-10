using Microsoft.UI.Xaml.Controls;
using SaveStories.WinUI.Beta.Services;
using System.Collections.ObjectModel;

namespace SaveStories.WinUI.Beta.Pages;

public sealed partial class QueuePage : Page
{
    private readonly ObservableCollection<string> _queue = new();
    private bool _isRunning;
    private CancellationTokenSource? _runCts;

    public QueuePage()
    {
        InitializeComponent();
        QueueListView.ItemsSource = _queue;
        RefreshQueueSummary();
    }

    private void OnAddProfilesClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var lines = ParseInputLines(QueueInputTextBox.Text);
        var added = 0;
        foreach (var line in lines)
        {
            if (_queue.Contains(line))
            {
                continue;
            }
            _queue.Add(line);
            added++;
        }

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
            foreach (var line in lines)
            {
                if (!_queue.Contains(line))
                {
                    _queue.Add(line);
                }
            }
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
        QueueResultSummaryText.Text = $"Профилей: {_queue.Count}  ·  Найдено: {foundCount}  ·  Сохранено: {savedCount}";
    }

    private void AppendLog(string line)
    {
        QueueLogsTextBox.Text += $"{DateTime.Now:HH:mm:ss}  {line}{Environment.NewLine}";
    }

    private void RefreshQueueSummary()
    {
        QueueSummaryText.Text = $"Очередь: {_queue.Count} профилей.";
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
