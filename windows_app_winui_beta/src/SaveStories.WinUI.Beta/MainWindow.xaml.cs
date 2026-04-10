using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using SaveStories.WinUI.Beta.Pages;
using SaveStories.WinUI.Beta.Services;

namespace SaveStories.WinUI.Beta;

public sealed partial class MainWindow : Window
{
    private bool _startupTasksCompleted;

    public MainWindow()
    {
        InitializeComponent();
        AppNav.Loaded += OnRootLoaded;
        BetaSettingsStore.Current.Load();
        VersionBadgeText.Text = $"{AppVersionProvider.CurrentVersion()}-beta";
        DiagnosticsService.Current.LogInfo($"Startup version={AppVersionProvider.CurrentVersion()}");
        ApplyTheme(BetaSettingsStore.Current.Theme);
        BetaSettingsStore.Current.ThemeChanged += OnThemeChanged;
        AppNav.SelectedItem = AppNav.MenuItems[0];
        ContentFrame.Navigate(typeof(StoriesPage));
    }

    private void OnNavigationSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is not string tag)
        {
            return;
        }

        switch (tag)
        {
            case "stories":
                ContentFrame.Navigate(typeof(StoriesPage));
                break;
            case "queue":
                ContentFrame.Navigate(typeof(QueuePage));
                break;
            case "reels":
                ContentFrame.Navigate(typeof(ReelsPage));
                break;
            case "settings":
                ContentFrame.Navigate(typeof(SettingsPage));
                break;
        }
    }

    private void OnThemeChanged(object? sender, BetaTheme theme)
    {
        ApplyTheme(theme);
    }

    private void ApplyTheme(BetaTheme theme)
    {
        if (Content is FrameworkElement root)
        {
            root.RequestedTheme = theme == BetaTheme.Light ? ElementTheme.Light : ElementTheme.Dark;
        }
    }

    private async void OnRootLoaded(object sender, RoutedEventArgs e)
    {
        AppNav.Loaded -= OnRootLoaded;
        await RunStartupChecksAsync();
    }

    private async Task RunStartupChecksAsync()
    {
        try
        {
            var preflight = PreflightService.Current.Run();
            foreach (var check in preflight.Checks)
            {
                DiagnosticsService.Current.LogInfo($"preflight {check.Name}: {(check.Ok ? "ok" : "failed")} ({check.Message})");
            }
        }
        catch (Exception ex)
        {
            DiagnosticsService.Current.LogError("Preflight failed", ex);
        }

        await PromptRuntimeInstallIfNeededAsync();
        _startupTasksCompleted = true;
        _ = AutoCheckForUpdatesAsync();
    }

    private async Task PromptRuntimeInstallIfNeededAsync()
    {
        if (BetaSettingsStore.Current.RuntimePromptShown)
        {
            return;
        }

        var runtimeReady = ChromiumBootstrapService.Current.IsWorkerDependenciesInstalled()
            && ChromiumBootstrapService.Current.IsChromiumInstalled();
        if (runtimeReady)
        {
            BetaSettingsStore.Current.MarkRuntimePromptShown();
            return;
        }

        if (Content is not FrameworkElement root)
        {
            return;
        }

        var promptDialog = new ContentDialog
        {
            XamlRoot = root.XamlRoot,
            Title = "Нужна докачка модулей",
            Content = "Для работы Stories/Reels нужно докачать runtime-модули (node зависимости и Chromium). Сделать это сейчас?",
            PrimaryButtonText = "Докачать",
            CloseButtonText = "Позже",
            DefaultButton = ContentDialogButton.Primary
        };

        var result = await promptDialog.ShowAsync();
        if (result != ContentDialogResult.Primary)
        {
            return;
        }

        var installed = await InstallRuntimeWithProgressDialogAsync(root);
        if (installed)
        {
            BetaSettingsStore.Current.MarkRuntimePromptShown();
        }
    }

    private async Task<bool> InstallRuntimeWithProgressDialogAsync(FrameworkElement root)
    {
        var statusText = new TextBlock
        {
            Text = "Подготавливаю установку модулей..."
        };
        var progressDialog = new ContentDialog
        {
            XamlRoot = root.XamlRoot,
            Title = "Установка модулей",
            Content = new StackPanel
            {
                Spacing = 12,
                Children =
                {
                    new ProgressRing { IsActive = true, Width = 24, Height = 24 },
                    statusText
                }
            }
        };

        var progress = new Progress<string>(line =>
        {
            if (!string.IsNullOrWhiteSpace(line))
            {
                statusText.Text = line;
            }
        });

        var showTask = progressDialog.ShowAsync().AsTask();
        try
        {
            var result = await ChromiumBootstrapService.Current.EnsureRuntimeInstalledAsync(progress);
            progressDialog.Hide();
            await showTask;

            var okDialog = new ContentDialog
            {
                XamlRoot = root.XamlRoot,
                Title = "Готово",
                Content = result,
                CloseButtonText = "ОК"
            };
            await okDialog.ShowAsync();
            return true;
        }
        catch (Exception ex)
        {
            progressDialog.Hide();
            await showTask;
            var errorDialog = new ContentDialog
            {
                XamlRoot = root.XamlRoot,
                Title = "Ошибка установки модулей",
                Content = ex.Message,
                CloseButtonText = "ОК"
            };
            await errorDialog.ShowAsync();
            return false;
        }
    }

    private async Task AutoCheckForUpdatesAsync()
    {
        try
        {
            if (!_startupTasksCompleted || !WindowsUpdaterService.Current.IsAvailable)
            {
                return;
            }

            var lastCheckRaw = BetaSettingsStore.Current.LastUpdateCheckAt;
            if (DateTimeOffset.TryParse(lastCheckRaw, out var lastCheck))
            {
                if (DateTimeOffset.Now - lastCheck < TimeSpan.FromHours(6))
                {
                    return;
                }
            }

            var result = await WindowsUpdaterService.Current.CheckLatestReleaseAsync(AppVersionProvider.CurrentVersion());
            BetaSettingsStore.Current.SetLastUpdateCheckAt(DateTimeOffset.Now.ToString("O"));
            if (result.Status == "update_available" && result.Release is not null)
            {
                DiagnosticsService.Current.LogInfo($"Update available: {result.Release.Version}");
                var dialog = new ContentDialog
                {
                    XamlRoot = (Content as FrameworkElement)?.XamlRoot,
                    Title = "Доступно обновление",
                    Content = $"Найдена новая версия {result.Release.Version}. Открой «Настройки», чтобы скачать и установить обновление.",
                    CloseButtonText = "ОК"
                };
                await dialog.ShowAsync();
            }
        }
        catch (Exception ex)
        {
            DiagnosticsService.Current.LogError("Auto update check failed", ex);
        }
    }
}
