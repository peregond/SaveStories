using Microsoft.UI.Xaml.Controls;
using SaveStories.WinUI.Beta.Services;
using System.Collections.ObjectModel;

namespace SaveStories.WinUI.Beta.Pages;

public sealed partial class StoriesPage : Page
{
    private readonly ObservableCollection<string> _queue = new();
    private bool _isRunning;
    private CancellationTokenSource? _runCts;

    public StoriesPage()
    {
        InitializeComponent();
        QueueListView.ItemsSource = _queue;
        RefreshQueueSummary();
    }

    private void OnAddProfilesClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var lines = ParseInputLines(ProfilesInputTextBox.Text);
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
            foreach (var line in lines)
            {
                if (!_queue.Contains(line))
                {
                    _queue.Add(line);
                }
            }
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
        var filesCount = response.Items.Count.ToString();
        ResultSummaryText.Text = $"Профилей: {profilesCount}  ·  Найдено: {foundCount}  ·  Сохранено: {savedCount}  ·  Файлов: {filesCount}";
    }

    private void AppendLog(string line)
    {
        LogsTextBox.Text += $"{DateTime.Now:HH:mm:ss}  {line}{Environment.NewLine}";
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
