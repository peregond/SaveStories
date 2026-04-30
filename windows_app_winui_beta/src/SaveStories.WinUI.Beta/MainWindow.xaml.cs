using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Windowing;
using SaveMe.WinUI.Beta.Pages;
using SaveMe.WinUI.Beta.Services;
using System.Text;
using WinRT.Interop;

namespace SaveMe.WinUI.Beta;

public sealed partial class MainWindow : Window
{
    private bool _startupTasksCompleted;

    public MainWindow()
    {
        InitializeComponent();
        ConfigureWindowBehavior();
        AppNav.Loaded += OnRootLoaded;
        BetaSettingsStore.Current.Load();
        VersionBadgeText.Text = AppVersionProvider.CurrentVersion();
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
            case "sorting":
                ContentFrame.Navigate(typeof(SortingPage));
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
            root.RequestedTheme = theme switch
            {
                BetaTheme.Light => ElementTheme.Light,
                BetaTheme.Dark => ElementTheme.Dark,
                _ => ElementTheme.Default,
            };
        }
    }

    private void ConfigureWindowBehavior()
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
        var appWindow = AppWindow.GetFromWindowId(windowId);
        if (appWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsResizable = true;
            presenter.IsMaximizable = true;
            presenter.IsMinimizable = true;
            presenter.SetBorderAndTitleBar(true, true);
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
        await PromptInstagramLoginIfNeededAsync();
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
            Title = "Подготовка приложения",
            Content = "Для первого запуска нужно автоматически докачать рабочие модули (Node + Chromium). Начать сейчас?",
            PrimaryButtonText = "Начать настройку",
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
            Text = "Подготавливаю установку модулей...",
            TextWrapping = TextWrapping.WrapWholeWords,
        };
        var detailsText = new TextBox
        {
            IsReadOnly = true,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 100,
            MaxHeight = 180,
            PlaceholderText = "Ход установки появится здесь.",
        };
        var logs = new Queue<string>();
        var progressDialog = new ContentDialog
        {
            XamlRoot = root.XamlRoot,
            Title = "Настраиваю SaveMe",
            Content = new StackPanel
            {
                Spacing = 12,
                Children =
                {
                    new ProgressRing { IsActive = true, Width = 24, Height = 24 },
                    statusText,
                    detailsText,
                }
            },
            CloseButtonText = "Свернуть"
        };

        var progress = new Progress<string>(line =>
        {
            var cleaned = NormalizeProgressLine(line);
            if (!string.IsNullOrWhiteSpace(cleaned))
            {
                statusText.Text = cleaned;
                logs.Enqueue(cleaned);
                while (logs.Count > 120)
                {
                    logs.Dequeue();
                }
                detailsText.Text = string.Join(Environment.NewLine, logs);
                detailsText.SelectionStart = detailsText.Text.Length;
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
                Title = "Готово к работе",
                Content = "Все необходимые модули установлены. Можно сразу начинать загрузку Stories и Reels.",
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

    private static string NormalizeProgressLine(string? line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return string.Empty;
        }

        var builder = new StringBuilder(line.Length);
        foreach (var ch in line)
        {
            if (char.IsControl(ch) && ch != '\t' && ch != ' ')
            {
                continue;
            }
            if (ch == '\uFFFD')
            {
                continue;
            }
            builder.Append(ch);
        }

        return builder.ToString().Trim();
    }

    private async Task PromptInstagramLoginIfNeededAsync()
    {
        if (Content is not FrameworkElement root)
        {
            return;
        }

        var runtimeReady = ChromiumBootstrapService.Current.IsWorkerDependenciesInstalled()
            && ChromiumBootstrapService.Current.IsChromiumInstalled();
        if (!runtimeReady)
        {
            return;
        }

        try
        {
            var session = await WorkerBridgeService.Current.RunAsync(
                new WorkerRequest
                {
                    Command = "check_session",
                    Headless = true,
                });
            if (session.Response.Ok || !IsSessionMissing(session.Response))
            {
                return;
            }
        }
        catch (Exception ex)
        {
            DiagnosticsService.Current.LogError("Startup session check failed", ex);
            return;
        }

        var promptDialog = new ContentDialog
        {
            XamlRoot = root.XamlRoot,
            Title = "Вход в Instagram",
            Content = "Сессия Instagram не найдена. Войти через браузер сейчас?",
            PrimaryButtonText = "Войти",
            CloseButtonText = "Позже",
            DefaultButton = ContentDialogButton.Primary,
        };
        var result = await promptDialog.ShowAsync();
        if (result != ContentDialogResult.Primary)
        {
            return;
        }

        await RunInstagramLoginAsync(root);
    }

    private async Task RunInstagramLoginAsync(FrameworkElement root)
    {
        var statusText = new TextBlock
        {
            Text = "Открываю браузер для входа...",
            TextWrapping = TextWrapping.WrapWholeWords,
        };
        var dialog = new ContentDialog
        {
            XamlRoot = root.XamlRoot,
            Title = "Подключение к Instagram",
            Content = new StackPanel
            {
                Spacing = 12,
                Children =
                {
                    new ProgressRing { IsActive = true, Width = 24, Height = 24 },
                    statusText,
                }
            }
        };

        var showTask = dialog.ShowAsync().AsTask();
        try
        {
            var login = await WorkerBridgeService.Current.RunAsync(
                new WorkerRequest
                {
                    Command = "login",
                    Headless = false,
                });
            dialog.Hide();
            await showTask;

            var message = login.Response.Ok
                ? "Вход выполнен, сессия сохранена."
                : $"Вход не завершён: {login.Response.Message}";
            var doneDialog = new ContentDialog
            {
                XamlRoot = root.XamlRoot,
                Title = login.Response.Ok ? "Instagram подключён" : "Вход в Instagram",
                Content = message,
                CloseButtonText = "ОК",
            };
            await doneDialog.ShowAsync();
        }
        catch (Exception ex)
        {
            dialog.Hide();
            await showTask;
            DiagnosticsService.Current.LogError("Startup login flow failed", ex);
            var errorDialog = new ContentDialog
            {
                XamlRoot = root.XamlRoot,
                Title = "Ошибка входа",
                Content = ex.Message,
                CloseButtonText = "ОК",
            };
            await errorDialog.ShowAsync();
        }
    }

    private static bool IsSessionMissing(WorkerResponse response)
    {
        if (string.Equals(response.Status, "session_missing", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return response.Message.Contains("Сначала откройте браузер для входа", StringComparison.OrdinalIgnoreCase)
            || response.Message.Contains("Требуется вход в Instagram", StringComparison.OrdinalIgnoreCase);
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
