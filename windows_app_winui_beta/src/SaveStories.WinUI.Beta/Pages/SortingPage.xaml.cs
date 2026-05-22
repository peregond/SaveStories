using Microsoft.UI.Xaml.Controls;
using SaveMe.WinUI.Beta;
using SaveMe.WinUI.Beta.Services;
using Windows.ApplicationModel.DataTransfer;

namespace SaveMe.WinUI.Beta.Pages;

public sealed partial class SortingPage : Page
{
    private readonly NotionRoutingRulesSource _notionRoutingRulesSource = new();
    private readonly GoogleDriveLinkExporter _googleDriveLinkExporter = new();
    private List<SortedFileRecord> _lastRecords = new();
    private string _lastDigest = "";
    private string _lastLinksDigest = "";
    private bool _isRefreshingNotionRules;

    public SortingPage()
    {
        InitializeComponent();
        EmptyFolderCleanupDirectoryText.Text = DisplayPath(BetaSettingsStore.Current.EmptyFolderCleanupDirectory);
        SourceDirectoryText.Text = DisplayPath(BetaSettingsStore.Current.SortingSourceDirectory);
        DestinationDirectoryText.Text = DisplayPath(BetaSettingsStore.Current.SortingDestinationDirectory);
        RulesTextBox.Text = BetaSettingsStore.Current.SortingRules;
        NotionRoutingRulesToggle.IsOn = BetaSettingsStore.Current.NotionRoutingRulesSourceEnabled;
        UpdateNotionRoutingRulesSummary();
        RefreshRememberedBloggers();
    }

    private void OnChangeSourceDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var path = PickFolder("Папка «На перенос»", BetaSettingsStore.Current.SortingSourceDirectory);
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        Directory.CreateDirectory(path);
        BetaSettingsStore.Current.SetSortingSourceDirectory(path);
        SourceDirectoryText.Text = DisplayPath(path);
    }

    private void OnChangeEmptyFolderCleanupDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var path = PickFolder("Папка для очистки пустых подпапок", BetaSettingsStore.Current.EmptyFolderCleanupDirectory);
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        Directory.CreateDirectory(path);
        BetaSettingsStore.Current.SetEmptyFolderCleanupDirectory(path);
        EmptyFolderCleanupDirectoryText.Text = DisplayPath(path);
        EmptyFolderCleanupStatusText.Text = "Папка для очистки выбрана.";
        SortingStatusText.Text = "Папка для очистки выбрана.";
    }

    private void OnChangeDestinationDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var path = PickFolder("WhiteList INF Исходники", BetaSettingsStore.Current.SortingDestinationDirectory);
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        Directory.CreateDirectory(path);
        BetaSettingsStore.Current.SetSortingDestinationDirectory(path);
        DestinationDirectoryText.Text = DisplayPath(path);
    }

    private void OnOpenSourceDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        OpenDirectory(BetaSettingsStore.Current.SortingSourceDirectory);
    }

    private void OnOpenDestinationDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        OpenDirectory(BetaSettingsStore.Current.SortingDestinationDirectory);
    }

    private void OnOpenEmptyFolderCleanupDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        OpenDirectory(BetaSettingsStore.Current.EmptyFolderCleanupDirectory);
    }

    private async void OnDeleteEmptyFoldersClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var root = BetaSettingsStore.Current.EmptyFolderCleanupDirectory;
        if (string.IsNullOrWhiteSpace(root))
        {
            EmptyFolderCleanupStatusText.Text = "Сначала выбери папку для очистки.";
            SortingStatusText.Text = "Сначала выбери папку для очистки.";
            return;
        }

        var deletableFolders = EmptyFolderCleanupService.FindDeletableEmptyFolders(root).ToList();
        if (deletableFolders.Count == 0)
        {
            EmptyFolderCleanupStatusText.Text = "Пустых папок в выбранной папке не найдено.";
            SortingStatusText.Text = "Пустых папок в выбранной папке не найдено.";
            return;
        }

        EmptyFolderCleanupStatusText.Text = $"Найдено пустых папок: {deletableFolders.Count}. Жду подтверждения.";
        var preview = string.Join(Environment.NewLine, deletableFolders.Select(Path.GetFileName).Where(name => !string.IsNullOrWhiteSpace(name)).Take(12));
        if (deletableFolders.Count > 12)
        {
            preview += $"{Environment.NewLine}и ещё {deletableFolders.Count - 12}";
        }

        var dialog = new ContentDialog
        {
            Title = "Удалить пустые папки?",
            Content = new TextBlock
            {
                Text = $"Приложение удалит только пустые папки из списка ниже. Папка «На перенос» и её содержимое не трогаются.{Environment.NewLine}{Environment.NewLine}{preview}",
                TextWrapping = Microsoft.UI.Xaml.TextWrapping.WrapWholeWords,
            },
            PrimaryButtonText = "Удалить",
            CloseButtonText = "Не удалять",
            XamlRoot = XamlRoot,
        };

        if (await dialog.ShowAsync() != ContentDialogResult.Primary)
        {
            EmptyFolderCleanupStatusText.Text = "Очистка пустых папок отменена.";
            SortingStatusText.Text = "Очистка пустых папок отменена.";
            return;
        }

        var cleanup = EmptyFolderCleanupService.DeleteEmptyFolders(deletableFolders);
        foreach (var folder in cleanup.FailedFolders)
        {
            DiagnosticsService.Current.LogError($"Windows empty folder cleanup failed for {folder}", new IOException("Папка не удалена."));
        }

        EmptyFolderCleanupStatusText.Text = cleanup.FailedFolders.Count == 0
            ? $"Удалено пустых папок: {cleanup.RemovedFolders.Count}."
            : $"Удалено пустых папок: {cleanup.RemovedFolders.Count}. Ошибок: {cleanup.FailedFolders.Count}.";
        SortingStatusText.Text = EmptyFolderCleanupStatusText.Text;
    }

    private void OnRulesChanged(object sender, TextChangedEventArgs e)
    {
        BetaSettingsStore.Current.SetSortingRules(RulesTextBox.Text);
        SortingService.Current.ParseRules(RulesTextBox.Text);
        RefreshRememberedBloggers();
    }

    private async void OnRunSortingClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var source = BetaSettingsStore.Current.SortingSourceDirectory;
        var destination = BetaSettingsStore.Current.SortingDestinationDirectory;
        if (string.IsNullOrWhiteSpace(source) || string.IsNullOrWhiteSpace(destination))
        {
            SortingStatusText.Text = "Сначала выбери папку Перенос и папку назначения.";
            return;
        }

        if (NotionRoutingRulesToggle.IsOn)
        {
            var refreshed = await RefreshNotionRoutingRulesAsync();
            if (!refreshed)
            {
                return;
            }
        }

        try
        {
            var result = SortingService.Current.DistributeFromSource(source, destination, RulesTextBox.Text);
            _lastRecords = result.Records.ToList();
            _lastDigest = SortingService.Current.BuildPostProcessedReport(_lastRecords);
            _lastLinksDigest = "";
            DigestTextBox.Text = _lastDigest;
            var hasResult = !string.IsNullOrWhiteSpace(_lastDigest);
            CopyDigestButton.IsEnabled = hasResult;
            CopyLinksButton.IsEnabled = hasResult;
            GoogleDriveLinkStatusText.Text = hasResult
                ? "Список готов. Можно скопировать локальный список или собрать Drive-ссылки."
                : "Ссылки Google Drive ещё не собирались.";
            SortingStatusText.Text = result.FailedItems.Count == 0
                ? result.Summary
                : $"{result.Summary} Ошибок: {result.FailedItems.Count}.";
            RefreshRememberedBloggers();
        }
        catch (Exception ex)
        {
            SortingStatusText.Text = ex.Message;
            DiagnosticsService.Current.LogError("Windows sorting failed", ex);
        }
    }

    private void OnCopyDigestClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_lastDigest))
        {
            return;
        }

        var data = new DataPackage();
        data.SetText(_lastDigest);
        Clipboard.SetContent(data);
        GoogleDriveLinkStatusText.Text = "Список папок и файлов скопирован в буфер обмена.";
        SortingStatusText.Text = GoogleDriveLinkStatusText.Text;
    }

    private async void OnCopyLinksClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_lastRecords.Count == 0)
        {
            GoogleDriveLinkStatusText.Text = "Нет результата сортировки для сбора ссылок.";
            SortingStatusText.Text = GoogleDriveLinkStatusText.Text;
            return;
        }

        CopyLinksButton.IsEnabled = false;
        GoogleDriveLinkStatusText.Text = $"Собираю Google Drive ссылки для {_lastRecords.Count} файлов...";
        SortingStatusText.Text = GoogleDriveLinkStatusText.Text;

        try
        {
            var outcomes = await _googleDriveLinkExporter.ExportLinksAsync(_lastRecords);
            _lastLinksDigest = SortingService.Current.BuildGoogleDriveDigest(outcomes);
            if (string.IsNullOrWhiteSpace(_lastLinksDigest))
            {
                GoogleDriveLinkStatusText.Text = "Не удалось собрать Drive-ссылки: дайджест пуст.";
                SortingStatusText.Text = GoogleDriveLinkStatusText.Text;
                return;
            }

            var data = new DataPackage();
            data.SetText(_lastLinksDigest);
            Clipboard.SetContent(data);
            DigestTextBox.Text = _lastLinksDigest;

            var successCount = outcomes.Count(outcome => !string.IsNullOrWhiteSpace(outcome.Link));
            var failureCount = outcomes.Count - successCount;
            GoogleDriveLinkStatusText.Text = failureCount == 0
                ? $"Google Drive ссылки собраны: {successCount}. Результат скопирован в буфер."
                : $"Ссылки собраны: {successCount}. Ошибок: {failureCount}. Сводка скопирована в буфер.";
            SortingStatusText.Text = GoogleDriveLinkStatusText.Text;
        }
        catch (Exception ex)
        {
            GoogleDriveLinkStatusText.Text = $"Не удалось собрать Drive-ссылки: {ex.Message}";
            SortingStatusText.Text = GoogleDriveLinkStatusText.Text;
            DiagnosticsService.Current.LogError("Windows Google Drive link export failed", ex);
        }
        finally
        {
            CopyLinksButton.IsEnabled = _lastRecords.Count > 0;
        }
    }

    private void OnNotionRoutingRulesToggleToggled(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        BetaSettingsStore.Current.SetNotionRoutingRulesSourceEnabled(NotionRoutingRulesToggle.IsOn);
        UpdateNotionRoutingRulesSummary();
    }

    private async void OnRefreshNotionRoutingRulesClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        await RefreshNotionRoutingRulesAsync();
    }

    private async Task<bool> RefreshNotionRoutingRulesAsync()
    {
        if (_isRefreshingNotionRules)
        {
            return false;
        }

        _isRefreshingNotionRules = true;
        RefreshNotionRoutingRulesButton.IsEnabled = false;
        NotionRoutingRulesToggle.IsEnabled = false;
        NotionRoutingRulesSummaryText.Text = "Загружаю правила из Notion...";
        SortingStatusText.Text = "Загружаю правила сортировки из Notion...";

        try
        {
            var rules = await _notionRoutingRulesSource.FetchRulesAsync();
            if (string.IsNullOrWhiteSpace(rules))
            {
                NotionRoutingRulesSummaryText.Text = "В Notion не найдено правил.";
                SortingStatusText.Text = NotionRoutingRulesSummaryText.Text;
                return false;
            }

            RulesTextBox.Text = rules;
            BetaSettingsStore.Current.SetSortingRules(rules);
            SortingService.Current.ParseRules(rules);
            RefreshRememberedBloggers();

            var count = rules.Split(Environment.NewLine, StringSplitOptions.RemoveEmptyEntries).Length;
            NotionRoutingRulesSummaryText.Text = $"Notion обновлён: {count} правил.";
            SortingStatusText.Text = NotionRoutingRulesSummaryText.Text;
            return true;
        }
        catch (Exception ex)
        {
            NotionRoutingRulesSummaryText.Text = $"Не удалось обновить Notion: {ex.Message}";
            SortingStatusText.Text = NotionRoutingRulesSummaryText.Text;
            DiagnosticsService.Current.LogError("Windows Notion routing rules refresh failed", ex);
            return false;
        }
        finally
        {
            _isRefreshingNotionRules = false;
            RefreshNotionRoutingRulesButton.IsEnabled = true;
            NotionRoutingRulesToggle.IsEnabled = true;
        }
    }

    private string? PickFolder(string title, string? initialDirectory)
    {
        try
        {
            return ShellFolderService.PickFolder(App.MainWindow, title, initialDirectory);
        }
        catch (Exception ex)
        {
            SortingStatusText.Text = $"Не удалось открыть выбор папки: {ex.Message}";
            DiagnosticsService.Current.LogError("Windows folder picker failed", ex);
            return null;
        }
    }

    private void RefreshRememberedBloggers()
    {
        var remembered = BetaSettingsStore.Current.RememberedBloggers
            .OrderBy(blogger => blogger.CountryFolder, StringComparer.OrdinalIgnoreCase)
            .ThenBy(blogger => blogger.Username, StringComparer.OrdinalIgnoreCase)
            .ToList();
        RememberedSummaryText.Text = remembered.Count == 0
            ? "Блогеры появятся здесь после правил или переноса."
            : $"Запомнено блогеров: {remembered.Count}.";
        RememberedBloggersListView.ItemsSource = remembered
            .Select(blogger => $"{blogger.CountryFolder}: {blogger.Username}")
            .ToList();
    }

    private void UpdateNotionRoutingRulesSummary()
    {
        NotionRoutingRulesSummaryText.Text = NotionRoutingRulesToggle.IsOn
            ? "Перед сортировкой правила обновятся из Notion."
            : "Автоправила Notion выключены.";
    }

    private static string DisplayPath(string value)
    {
        return string.IsNullOrWhiteSpace(value) ? "Папка ещё не выбрана." : value;
    }

    private void OpenDirectory(string path)
    {
        try
        {
            ShellFolderService.OpenFolder(path);
        }
        catch (Exception ex)
        {
            SortingStatusText.Text = $"Не удалось открыть папку: {ex.Message}";
            DiagnosticsService.Current.LogError("Windows open folder failed", ex);
        }
    }

}
