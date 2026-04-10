using Microsoft.UI.Xaml.Controls;
using SaveStories.WinUI.Beta.Services;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace SaveStories.WinUI.Beta.Pages;

public sealed partial class SettingsPage : Page
{
    private CancellationTokenSource? _chromiumInstallCts;

    public SettingsPage()
    {
        InitializeComponent();
        ApplyThemeButtons(BetaSettingsStore.Current.Theme);
        ChromiumSummaryText.Text = ChromiumBootstrapService.Current.GetBootstrapSummary();
        ChromiumPathText.Text = $"Папка: {ChromiumBootstrapService.Current.GetTargetDirectory()}";
        ChromiumStatusText.Text = ChromiumBootstrapService.Current.IsChromiumInstalled()
            ? "Состояние: Chromium уже установлен."
            : "Состояние: Chromium ещё не установлен.";
        ChromiumLogText.Text = "Лог установки появится здесь.";
    }

    private void OnDarkThemeClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        BetaSettingsStore.Current.SetTheme(BetaTheme.Dark);
        ApplyThemeButtons(BetaTheme.Dark);
    }

    private void OnLightThemeClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        BetaSettingsStore.Current.SetTheme(BetaTheme.Light);
        ApplyThemeButtons(BetaTheme.Light);
    }

    private async void OnInstallChromiumClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_chromiumInstallCts is not null)
        {
            return;
        }

        _chromiumInstallCts = new CancellationTokenSource();
        InstallChromiumButton.IsEnabled = false;
        ChromiumProgressBar.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
        ChromiumStatusText.Text = "Устанавливаю Chromium...";
        ChromiumLogText.Text = string.Empty;

        var progress = new Progress<string>(line =>
        {
            ChromiumLogText.Text += line + Environment.NewLine;
        });

        try
        {
            var result = await ChromiumBootstrapService.Current.InstallChromiumAsync(progress, _chromiumInstallCts.Token);
            ChromiumStatusText.Text = $"Состояние: {result}";
        }
        catch (Exception ex)
        {
            ChromiumStatusText.Text = "Состояние: ошибка установки.";
            ChromiumLogText.Text += Environment.NewLine + ex.Message;
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "Ошибка установки Chromium",
                Content = ex.Message,
                CloseButtonText = "Закрыть"
            };
            await dialog.ShowAsync();
        }
        finally
        {
            _chromiumInstallCts.Dispose();
            _chromiumInstallCts = null;
            InstallChromiumButton.IsEnabled = true;
            ChromiumProgressBar.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
        }
    }

    private void OnOpenChromiumFolderClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var folder = ChromiumBootstrapService.Current.GetTargetDirectory();
        Directory.CreateDirectory(folder);
        Process.Start(new ProcessStartInfo
        {
            FileName = "explorer.exe",
            Arguments = folder,
            UseShellExecute = true
        });
    }

    private void ApplyThemeButtons(BetaTheme theme)
    {
        DarkThemeButton.IsEnabled = theme != BetaTheme.Dark;
        LightThemeButton.IsEnabled = theme != BetaTheme.Light;
    }
}
