using Microsoft.UI.Xaml.Controls;
using SaveMe.WinUI.Beta;
using SaveMe.WinUI.Beta.Services;
using Windows.ApplicationModel.DataTransfer;

namespace SaveMe.WinUI.Beta.Pages;

public sealed partial class SortingPage : Page
{
    private List<SortedFileRecord> _lastRecords = new();
    private string _lastDigest = "";

    public SortingPage()
    {
        InitializeComponent();
        SourceDirectoryText.Text = DisplayPath(BetaSettingsStore.Current.SortingSourceDirectory);
        DestinationDirectoryText.Text = DisplayPath(BetaSettingsStore.Current.SortingDestinationDirectory);
        RulesTextBox.Text = BetaSettingsStore.Current.SortingRules;
        RefreshRememberedBloggers();
    }

    private async void OnChangeSourceDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var path = await PickFolderAsync("Папка Перенос", BetaSettingsStore.Current.SortingSourceDirectory);
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        Directory.CreateDirectory(path);
        BetaSettingsStore.Current.SetSortingSourceDirectory(path);
        SourceDirectoryText.Text = DisplayPath(path);
    }

    private async void OnChangeDestinationDirectoryClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var path = await PickFolderAsync("Папка назначения", BetaSettingsStore.Current.SortingDestinationDirectory);
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

    private void OnRunSortingClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var source = BetaSettingsStore.Current.SortingSourceDirectory;
        var destination = BetaSettingsStore.Current.SortingDestinationDirectory;
        if (string.IsNullOrWhiteSpace(source) || string.IsNullOrWhiteSpace(destination))
        {
            SortingStatusText.Text = "Сначала выбери папку Перенос и папку назначения.";
            return;
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

    private async Task<string?> PickFolderAsync(string title, string? initialDirectory)
    {
        await Task.Yield();

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
