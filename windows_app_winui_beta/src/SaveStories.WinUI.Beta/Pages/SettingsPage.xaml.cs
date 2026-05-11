using Microsoft.UI.Xaml.Controls;
using SaveMe.WinUI.Beta.Services;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;

namespace SaveMe.WinUI.Beta.Pages;

public sealed partial class SettingsPage : Page
{
    private CancellationTokenSource? _chromiumInstallCts;
    private CancellationTokenSource? _updateCts;

    public SettingsPage()
    {
        InitializeComponent();
        Unloaded += OnUnloaded;
        BetaSettingsStore.Current.ThemeChanged += OnThemeChanged;
        ApplyThemeButtons(BetaSettingsStore.Current.Theme);
        UpdateSummaryText.Text = WindowsUpdaterService.Current.Summary;
        ChromiumSummaryText.Text = ChromiumBootstrapService.Current.GetBootstrapSummary();
        ChromiumPathText.Text = $"Папка: {ChromiumBootstrapService.Current.GetTargetDirectory()}";
        var nodeInstalled = ChromiumBootstrapService.Current.IsNodeRuntimeInstalled();
        var dependenciesInstalled = ChromiumBootstrapService.Current.IsWorkerDependenciesInstalled();
        var chromiumInstalled = ChromiumBootstrapService.Current.IsChromiumInstalled();
        ChromiumStatusText.Text = nodeInstalled && dependenciesInstalled && chromiumInstalled
            ? "Состояние: runtime модули уже установлены."
            : "Состояние: нужно докачать runtime модули.";
        ChromiumLogText.Text = "Лог установки появится здесь.";
        DiagnosticsService.Current.LogInfo("Settings page opened.");
    }

    private void OnUnloaded(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        BetaSettingsStore.Current.ThemeChanged -= OnThemeChanged;
        Unloaded -= OnUnloaded;
    }

    private void OnThemeChanged(object? sender, BetaTheme theme)
    {
        ApplyThemeButtons(theme);
    }

    private void OnSystemThemeClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        BetaSettingsStore.Current.SetTheme(BetaTheme.System);
        ApplyThemeButtons(BetaTheme.System);
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
        ChromiumStatusText.Text = "Докачиваю runtime модули...";
        ChromiumLogText.Text = string.Empty;

        var progress = new Progress<string>(line =>
        {
            var cleaned = NormalizeProgressLine(line);
            if (!string.IsNullOrWhiteSpace(cleaned))
            {
                ChromiumLogText.Text += cleaned + Environment.NewLine;
            }
        });

        try
        {
            var result = await ChromiumBootstrapService.Current.EnsureRuntimeInstalledAsync(progress, _chromiumInstallCts.Token);
            ChromiumStatusText.Text = $"Состояние: {result}";
            DiagnosticsService.Current.LogInfo(result);
        }
        catch (Exception ex)
        {
            ChromiumStatusText.Text = "Состояние: ошибка установки runtime модулей.";
            ChromiumLogText.Text += Environment.NewLine + ex.Message;
            DiagnosticsService.Current.LogError("Runtime install failed", ex);
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "Ошибка установки runtime модулей",
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

    private async void OnCheckUpdatesClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (!WindowsUpdaterService.Current.IsAvailable)
        {
            UpdateSummaryText.Text = "Автообновление недоступно: не настроен источник release API.";
            return;
        }
        if (_updateCts is not null)
        {
            return;
        }

        CheckUpdatesButton.IsEnabled = false;
        CheckUpdatesButton.Content = "Проверяю...";
        UpdateProgressBar.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
        UpdateSummaryText.Text = "Проверяю latest release в GitHub...";
        try
        {
            var result = await WindowsUpdaterService.Current.CheckLatestReleaseAsync(AppVersionProvider.CurrentVersion());
            BetaSettingsStore.Current.SetLastUpdateCheckAt(DateTimeOffset.Now.ToString("O"));

            if (result.Status == "up_to_date")
            {
                UpdateSummaryText.Text = $"Уже установлена актуальная версия {AppVersionProvider.CurrentVersion()}.";
                return;
            }

            if (result.Status == "update_available" && result.Release is not null)
            {
                UpdateSummaryText.Text = $"Доступна версия {result.Release.Version}.";
                await ShowUpdatePromptAsync(result.Release);
                return;
            }

            UpdateSummaryText.Text = "Обновления пока недоступны.";
        }
        catch (Exception ex)
        {
            UpdateSummaryText.Text = $"Ошибка проверки обновлений: {ex.Message}";
            DiagnosticsService.Current.LogError("Update check failed", ex);
        }
        finally
        {
            if (_updateCts is null)
            {
                CheckUpdatesButton.Content = "Проверить и установить";
                CheckUpdatesButton.IsEnabled = true;
            }
        }
    }

    private async Task DownloadAndInstallUpdateAsync(ReleaseInfo release)
    {
        if (_updateCts is not null)
        {
            return;
        }

        _updateCts = new CancellationTokenSource();
        CheckUpdatesButton.IsEnabled = false;
        CheckUpdatesButton.Content = "Скачиваю обновление...";
        UpdateProgressBar.Visibility = Microsoft.UI.Xaml.Visibility.Visible;
        UpdateProgressBar.IsIndeterminate = false;
        UpdateProgressBar.Value = 0;

        var progress = new Progress<UpdateProgress>(update =>
        {
            UpdateProgressBar.Value = update.Percent;
            UpdateSummaryText.Text = update.Message;
        });

        try
        {
            var message = await WindowsUpdaterService.Current.PrepareInstallAsync(
                release,
                progress,
                _updateCts.Token);
            UpdateSummaryText.Text = message;
            DiagnosticsService.Current.LogInfo($"Update prepared: {release.Version}");

            var logPath = WindowsUpdaterService.Current.LaunchPreparedInstall();
            UpdateSummaryText.Text = $"Запускаю установщик обновления. Лог: {logPath}";
            DiagnosticsService.Current.LogInfo($"Launching prepared update. Log: {logPath}");
            await Task.Delay(700);
            Microsoft.UI.Xaml.Application.Current.Exit();
        }
        catch (Exception ex)
        {
            UpdateSummaryText.Text = $"Ошибка обновления: {ex.Message}";
            DiagnosticsService.Current.LogError("Update install failed", ex);
            CheckUpdatesButton.Content = "Проверить и установить";
            CheckUpdatesButton.IsEnabled = true;
            UpdateProgressBar.Visibility = Microsoft.UI.Xaml.Visibility.Collapsed;
        }
        finally
        {
            _updateCts?.Dispose();
            _updateCts = null;
        }
    }

    private void OnRunPreflightClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        var result = PreflightService.Current.Run();
        PreflightSummaryText.Text = result.Ok ? "Система готова к работе." : "Найдены проблемы, смотри детали ниже.";
        PreflightDetailsTextBox.Text = string.Join(
            Environment.NewLine,
            result.Checks.Select(x => $"{(x.Ok ? "OK" : "FAIL")} · {x.Name}: {x.Message}"));
        DiagnosticsService.Current.LogInfo($"Preflight run. ok={result.Ok}");
    }

    private async void OnExportDiagnosticsClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        try
        {
            var path = DiagnosticsService.Current.ExportSnapshot();
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "Диагностика сохранена",
                Content = path,
                CloseButtonText = "ОК"
            };
            await dialog.ShowAsync();
        }
        catch (Exception ex)
        {
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "Ошибка экспорта диагностики",
                Content = ex.Message,
                CloseButtonText = "ОК"
            };
            await dialog.ShowAsync();
        }
    }

    private async Task ShowUpdatePromptAsync(ReleaseInfo release)
    {
        var details = string.IsNullOrWhiteSpace(release.Notes)
            ? "GitHub release опубликован без release notes."
            : release.Notes;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "Доступно обновление",
            PrimaryButtonText = "Скачать и установить",
            CloseButtonText = "Позже",
            DefaultButton = ContentDialogButton.Primary,
            Content = new StackPanel
            {
                Spacing = 8,
                Children =
                {
                    new TextBlock
                    {
                        Text = $"Доступна новая версия SaveMe {release.Version}. После подтверждения начнётся загрузка и сразу запустится установка поверх текущей сборки.",
                        TextWrapping = Microsoft.UI.Xaml.TextWrapping.WrapWholeWords,
                    },
                    new Expander
                    {
                        Header = "Показать подробности",
                        Content = new ScrollViewer
                        {
                            MaxHeight = 180,
                            Content = new TextBlock
                            {
                                Text = details,
                                TextWrapping = Microsoft.UI.Xaml.TextWrapping.WrapWholeWords,
                            }
                        }
                    }
                }
            }
        };
        var result = await dialog.ShowAsync();
        if (result == ContentDialogResult.Primary)
        {
            await DownloadAndInstallUpdateAsync(release);
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

    private async void OnLoginInstagramClick(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_updateCts is not null || _chromiumInstallCts is not null)
        {
            return;
        }

        LoginInstagramButton.IsEnabled = false;
        ChromiumStatusText.Text = "Открываю браузер для входа в Instagram...";
        try
        {
            var login = await WorkerBridgeService.Current.RunAsync(
                new WorkerRequest
                {
                    Command = "login",
                    Headless = false,
                });
            ChromiumStatusText.Text = login.Response.Ok
                ? "Состояние: сессия Instagram сохранена."
                : $"Состояние: вход не завершён ({login.Response.Message})";

            var verify = await WorkerBridgeService.Current.RunAsync(
                new WorkerRequest
                {
                    Command = "check_session",
                    Headless = true,
                });
            if (verify.Response.Ok)
            {
                ChromiumStatusText.Text = "Состояние: сессия Instagram активна.";
            }
        }
        catch (Exception ex)
        {
            ChromiumStatusText.Text = $"Состояние: ошибка входа ({ex.Message})";
            DiagnosticsService.Current.LogError("Instagram login failed", ex);
        }
        finally
        {
            LoginInstagramButton.IsEnabled = true;
        }
    }

    private void ApplyThemeButtons(BetaTheme theme)
    {
        SystemThemeButton.IsEnabled = theme != BetaTheme.System;
        LightThemeButton.IsEnabled = theme != BetaTheme.Light;
        DarkThemeButton.IsEnabled = theme != BetaTheme.Dark;
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
}
