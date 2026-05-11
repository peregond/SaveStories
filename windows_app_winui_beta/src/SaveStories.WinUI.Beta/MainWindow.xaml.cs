using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using SaveMe.WinUI.Beta.Pages;
using SaveMe.WinUI.Beta.Services;
using System.Text;
using Windows.UI;
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
        SetStatusChip(NodeStatusDot, NodeStatusText, "check", StatusTone.Caution);
        SetStatusChip(SessionStatusDot, SessionStatusText, "check", StatusTone.Caution);
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
            ApplyPreflightStatus(preflight);
            foreach (var check in preflight.Checks)
            {
                DiagnosticsService.Current.LogInfo($"preflight {check.Name}: {(check.Ok ? "ok" : "failed")} ({check.Message})");
            }
        }
        catch (Exception ex)
        {
            SetStatusChip(NodeStatusDot, NodeStatusText, "error", StatusTone.Error);
            DiagnosticsService.Current.LogError("Preflight failed", ex);
        }

        await PromptRuntimeInstallIfNeededAsync();
        await PromptInstagramLoginIfNeededAsync();
        await RefreshSessionStatusAsync();
        _startupTasksCompleted = true;
        _ = AutoCheckForUpdatesAsync();
    }

    private async void OnRefreshStatusClick(object sender, RoutedEventArgs e)
    {
        await RefreshTopStatusAsync();
    }

    private async Task RefreshTopStatusAsync()
    {
        RefreshStatusButton.IsEnabled = false;
        try
        {
            try
            {
                var preflight = PreflightService.Current.Run();
                ApplyPreflightStatus(preflight);
            }
            catch (Exception ex)
            {
                SetStatusChip(NodeStatusDot, NodeStatusText, "error", StatusTone.Error);
                DiagnosticsService.Current.LogError("Top status preflight failed", ex);
            }

            await RefreshSessionStatusAsync();
        }
        finally
        {
            RefreshStatusButton.IsEnabled = true;
        }
    }

    private void ApplyPreflightStatus(PreflightResult preflight)
    {
        var nodeCoreOk = preflight.Checks
            .Where(check => check.Name is "Node runtime" or "node_worker")
            .All(check => check.Ok);
        var runtimeReady = ChromiumBootstrapService.Current.IsNodeRuntimeInstalled()
            && ChromiumBootstrapService.Current.IsWorkerDependenciesInstalled()
            && ChromiumBootstrapService.Current.IsChromiumInstalled();

        if (nodeCoreOk && runtimeReady)
        {
            SetStatusChip(NodeStatusDot, NodeStatusText, "ready", StatusTone.Success);
            return;
        }

        if (nodeCoreOk)
        {
            SetStatusChip(NodeStatusDot, NodeStatusText, "setup", StatusTone.Caution);
            return;
        }

        SetStatusChip(NodeStatusDot, NodeStatusText, "error", StatusTone.Error);
    }

    private async Task RefreshSessionStatusAsync()
    {
        try
        {
            var runtimeReady = ChromiumBootstrapService.Current.IsNodeRuntimeInstalled()
                && ChromiumBootstrapService.Current.IsWorkerDependenciesInstalled()
                && ChromiumBootstrapService.Current.IsChromiumInstalled();
            if (!runtimeReady)
            {
                SetStatusChip(SessionStatusDot, SessionStatusText, "skip", StatusTone.Neutral);
                return;
            }

            var session = await WorkerBridgeService.Current.RunAsync(
                new WorkerRequest
                {
                    Command = "check_session",
                    Headless = true,
                });
            SetStatusChip(
                SessionStatusDot,
                SessionStatusText,
                session.Response.Ok ? "ready" : "login",
                session.Response.Ok ? StatusTone.Success : StatusTone.Caution);
        }
        catch (Exception ex)
        {
            SetStatusChip(SessionStatusDot, SessionStatusText, "error", StatusTone.Error);
            DiagnosticsService.Current.LogError("Top status session check failed", ex);
        }
    }

    private static void SetStatusChip(Ellipse dot, TextBlock text, string label, StatusTone tone)
    {
        text.Text = label;
        dot.Fill = new SolidColorBrush(tone switch
        {
            StatusTone.Success => Color.FromArgb(255, 16, 124, 16),
            StatusTone.Error => Color.FromArgb(255, 196, 43, 28),
            StatusTone.Neutral => Color.FromArgb(255, 138, 136, 134),
            _ => Color.FromArgb(255, 247, 153, 57),
        });
    }

    private enum StatusTone
    {
        Success,
        Caution,
        Error,
        Neutral,
    }

    private enum RuntimeSetupStage
    {
        Node,
        Worker,
        Dependencies,
        Chromium,
        Ready,
    }

    private async Task PromptRuntimeInstallIfNeededAsync()
    {
        var runtimeReady = ChromiumBootstrapService.Current.IsNodeRuntimeInstalled()
            && ChromiumBootstrapService.Current.IsWorkerDependenciesInstalled()
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
        var stageRows = CreateRuntimeStageRows();
        var detailsText = new TextBox
        {
            IsReadOnly = true,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 88,
            MaxHeight = 150,
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
                    stageRows.container,
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
                var stage = RuntimeSetupStageFromProgress(cleaned);
                if (stage is not null)
                {
                    UpdateRuntimeStageRows(stageRows.rows, stage.Value, failed: false);
                }
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
            statusText.Text = result;
            UpdateRuntimeStageRows(stageRows.rows, RuntimeSetupStage.Ready, failed: false);
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
            var currentStage = RuntimeSetupStageFromProgress(statusText.Text) ?? RuntimeSetupStage.Node;
            UpdateRuntimeStageRows(stageRows.rows, currentStage, failed: true);
            progressDialog.Hide();
            await showTask;
            var errorDialog = new ContentDialog
            {
                XamlRoot = root.XamlRoot,
                Title = "Ошибка установки модулей",
                Content = BuildRuntimeInstallErrorMessage(statusText.Text, ex.Message),
                CloseButtonText = "ОК"
            };
            await errorDialog.ShowAsync();
            return false;
        }
    }

    private static (StackPanel container, Dictionary<RuntimeSetupStage, TextBlock> rows) CreateRuntimeStageRows()
    {
        var rows = new Dictionary<RuntimeSetupStage, TextBlock>();
        var container = new StackPanel
        {
            Spacing = 6,
        };

        foreach (var stage in new[]
        {
            RuntimeSetupStage.Node,
            RuntimeSetupStage.Worker,
            RuntimeSetupStage.Dependencies,
            RuntimeSetupStage.Chromium,
            RuntimeSetupStage.Ready,
        })
        {
            var row = new TextBlock
            {
                TextWrapping = TextWrapping.WrapWholeWords,
            };
            rows[stage] = row;
            container.Children.Add(row);
        }

        UpdateRuntimeStageRows(rows, RuntimeSetupStage.Node, failed: false);
        return (container, rows);
    }

    private static void UpdateRuntimeStageRows(
        IReadOnlyDictionary<RuntimeSetupStage, TextBlock> rows,
        RuntimeSetupStage currentStage,
        bool failed)
    {
        foreach (var entry in rows)
        {
            var stage = entry.Key;
            var row = entry.Value;
            var label = RuntimeStageLabel(stage);
            if (failed && stage == currentStage)
            {
                row.Text = $"! {label} - ошибка";
                row.Opacity = 1.0;
            }
            else if ((int)stage < (int)currentStage)
            {
                row.Text = $"✓ {label}";
                row.Opacity = 0.82;
            }
            else if (stage == currentStage)
            {
                row.Text = $"• {label} - выполняется";
                row.Opacity = 1.0;
            }
            else
            {
                row.Text = $"○ {label}";
                row.Opacity = 0.58;
            }
        }
    }

    private static string RuntimeStageLabel(RuntimeSetupStage stage)
    {
        return stage switch
        {
            RuntimeSetupStage.Node => "Node 24 LTS",
            RuntimeSetupStage.Worker => "Worker",
            RuntimeSetupStage.Dependencies => "Playwright",
            RuntimeSetupStage.Chromium => "Chromium",
            RuntimeSetupStage.Ready => "Готово",
            _ => "Установка",
        };
    }

    private static RuntimeSetupStage? RuntimeSetupStageFromProgress(string? line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return null;
        }

        if (line.Contains("Node 24", StringComparison.OrdinalIgnoreCase))
        {
            return RuntimeSetupStage.Node;
        }
        if (line.Contains("worker", StringComparison.OrdinalIgnoreCase))
        {
            return RuntimeSetupStage.Worker;
        }
        if (line.Contains("Chromium", StringComparison.OrdinalIgnoreCase)
            || line.Contains("chromium", StringComparison.OrdinalIgnoreCase))
        {
            return RuntimeSetupStage.Chromium;
        }
        if (line.Contains("зависим", StringComparison.OrdinalIgnoreCase)
            || line.Contains("npm", StringComparison.OrdinalIgnoreCase)
            || line.Contains("Playwright", StringComparison.OrdinalIgnoreCase))
        {
            return RuntimeSetupStage.Dependencies;
        }

        return null;
    }

    private static string BuildRuntimeInstallErrorMessage(string lastStep, string error)
    {
        var cleanError = NormalizeProgressLine(error);
        if (cleanError.Length > 1200)
        {
            cleanError = cleanError[..1200] + "...";
        }

        return $"Остановилось на этапе: {lastStep}\n\n{cleanError}\n\nМожно повторить установку из настроек приложения.";
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

        var runtimeReady = ChromiumBootstrapService.Current.IsNodeRuntimeInstalled()
            && ChromiumBootstrapService.Current.IsWorkerDependenciesInstalled()
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
