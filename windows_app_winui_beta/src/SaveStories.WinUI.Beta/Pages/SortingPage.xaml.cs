using Microsoft.UI.Xaml.Controls;
using SaveMe.WinUI.Beta;
using SaveMe.WinUI.Beta.Services;
using Windows.ApplicationModel.DataTransfer;

namespace SaveMe.WinUI.Beta.Pages;

public sealed partial class SortingPage : Page
{
    private readonly NotionRoutingRulesSource _notionRoutingRulesSource = new();
    private List<SortedFileRecord> _lastRecords = new();
    private string _lastDigest = "";
    private bool _isRefreshingNotionRules;

    public SortingPage()
    {
        InitializeComponent();
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
            _lastDigest = SortingService.Current.BuildDigest(_lastRecords);
            DigestTextBox.Text = _lastDigest;
            CopyDigestButton.IsEnabled = !string.IsNullOrWhiteSpace(_lastDigest);
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
        SortingStatusText.Text = "Дайджест скопирован в буфер обмена.";
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
