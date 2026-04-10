using Microsoft.UI.Xaml.Controls;
using SaveStories.WinUI.Beta.Services;
using System.Collections.ObjectModel;

namespace SaveStories.WinUI.Beta.Pages;

public sealed partial class ReelsPage : Page
{
    private readonly ObservableCollection<string> _queue = new();
    private readonly ObservableCollection<string> _downloads = new();
    private bool _isRunning;
    private CancellationTokenSource? _runCts;

    public ReelsPage()
    {
        InitializeComponent();
        ReelsQueueListView.ItemsSource = _queue;
        ReelsDownloadsListView.ItemsSource = _downloads;
        RefreshQueueSummary();
    }

    private void OnAddLinksClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var lines = ParseInputLines(ReelsInputTextBox.Text);
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

        ReelsInputTextBox.Text = string.Empty;
        AppendLog($"Добавлено ссылок Reels: {added}");
        RefreshQueueSummary();
    }

    private void OnClearInputClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        ReelsInputTextBox.Text = string.Empty;
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
            var lines = ParseInputLines(ReelsInputTextBox.Text);
            foreach (var line in lines)
            {
                if (!_queue.Contains(line))
                {
                    _queue.Add(line);
                }
            }
            ReelsInputTextBox.Text = string.Empty;
            RefreshQueueSummary();
        }

        if (_queue.Count == 0)
        {
            ReelsStatusTitleText.Text = "Ожидание";
            ReelsStatusDetailText.Text = "Добавь хотя бы одну ссылку Reels.";
            return;
        }

        await RunWorkerCommandAsync(
            new WorkerRequest
            {
                Command = "download_reels_urls",
                Urls = _queue.ToList(),
                OutputDirectory = WorkerBridgeService.Current.GetDefaultDownloadsDirectory(),
                Headless = true,
            },
            "Запускаю выгрузку Reels...");
    }

    private async Task RunWorkerCommandAsync(WorkerRequest request, string runningMessage)
    {
        _runCts = new CancellationTokenSource();
        _isRunning = true;
        RunReelsButton.IsEnabled = false;
        StopReelsButton.IsEnabled = true;
        ReelsStatusTitleText.Text = "Загружаю";
        ReelsStatusDetailText.Text = runningMessage;
        AppendLog(runningMessage);

        try
        {
            var result = await WorkerBridgeService.Current.RunAsync(request, _runCts.Token);
            ApplyWorkerResult(result.Response);
        }
        catch (OperationCanceledException)
        {
            ReelsStatusTitleText.Text = "Остановлено";
            ReelsStatusDetailText.Text = "Операция остановлена пользователем.";
            AppendLog("[cancelled] Операция остановлена.");
        }
        catch (TimeoutException ex)
        {
            ReelsStatusTitleText.Text = "Ошибка";
            ReelsStatusDetailText.Text = ex.Message;
            AppendLog($"[timeout] {ex.Message}");
        }
        catch (Exception ex)
        {
            ReelsStatusTitleText.Text = "Ошибка";
            ReelsStatusDetailText.Text = ex.Message;
            AppendLog($"[worker_exception] {ex.Message}");
        }
        finally
        {
            _runCts?.Dispose();
            _runCts = null;
            _isRunning = false;
            RunReelsButton.IsEnabled = true;
            StopReelsButton.IsEnabled = false;
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
        ReelsStatusTitleText.Text = "Остановка";
        ReelsStatusDetailText.Text = "Отправлен запрос на остановку текущей задачи.";
        AppendLog("Запрошена остановка текущей задачи.");
    }

    private void ApplyWorkerResult(WorkerResponse response)
    {
        ReelsStatusTitleText.Text = response.Ok ? "Готово" : "Ошибка";
        ReelsStatusDetailText.Text = response.Message;
        AppendLog($"[{response.Status}] {response.Message}");

        foreach (var line in response.Logs)
        {
            AppendLog(line);
        }

        foreach (var item in response.Items)
        {
            var name = Path.GetFileName(item.LocalPath);
            if (string.IsNullOrWhiteSpace(name))
            {
                name = item.LocalPath;
            }
            _downloads.Insert(0, name);
        }

        var savedCount = response.Data.TryGetValue("savedCount", out var saved) ? saved : response.Items.Count.ToString();
        var filesCount = response.Items.Count.ToString();
        ReelsResultSummaryText.Text = $"Ссылок: {_queue.Count}  ·  Сохранено: {savedCount}  ·  Файлов: {filesCount}";
    }

    private void AppendLog(string line)
    {
        ReelsLogsTextBox.Text += $"{DateTime.Now:HH:mm:ss}  {line}{Environment.NewLine}";
    }

    private void RefreshQueueSummary()
    {
        ReelsQueueSummaryText.Text = $"Очередь: {_queue.Count} ссылок.";
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
