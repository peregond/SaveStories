using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using SaveMe.WinUI.Beta.Services;
using System.Text;

namespace SaveMe.WinUI.Beta;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
        UnhandledException += OnUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += OnAppDomainUnhandledException;
        TaskScheduler.UnobservedTaskException += OnUnobservedTaskException;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            _window = new MainWindow();
            _window.Activate();
        }
        catch (Exception ex)
        {
            DiagnosticsService.Current.LogError("Startup.MainWindowFailed", ex);
            _window = BuildFatalWindow(ex);
            _window.Activate();
        }
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        DiagnosticsService.Current.LogError("Application.UnhandledException", e.Exception);
        e.Handled = true;
    }

    private static Window BuildFatalWindow(Exception ex)
    {
        var diagnosticsPath = DiagnosticsService.Current.LogPath;
        var details = new StringBuilder();
        details.AppendLine("Приложение не смогло корректно запуститься.");
        details.AppendLine();
        details.AppendLine("Ошибка:");
        details.AppendLine(ex.ToString());
        details.AppendLine();
        details.AppendLine($"Лог: {diagnosticsPath}");
        details.AppendLine("Отправь этот текст разработчику.");

        var window = new Window();
        window.Title = "SaveMe — ошибка запуска";
        window.Content = new ScrollViewer
        {
            Padding = new Thickness(20),
            Content = new TextBlock
            {
                Text = details.ToString(),
                TextWrapping = TextWrapping.Wrap,
                FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"),
                FontSize = 13,
            }
        };
        return window;
    }

    private void OnAppDomainUnhandledException(object? sender, System.UnhandledExceptionEventArgs e)
    {
        if (e.ExceptionObject is Exception ex)
        {
            DiagnosticsService.Current.LogError("AppDomain.UnhandledException", ex);
        }
        else
        {
            DiagnosticsService.Current.LogError("AppDomain.UnhandledException", new Exception(e.ExceptionObject?.ToString() ?? "unknown"));
        }
    }

    private void OnUnobservedTaskException(object? sender, System.Threading.Tasks.UnobservedTaskExceptionEventArgs e)
    {
        DiagnosticsService.Current.LogError("TaskScheduler.UnobservedTaskException", e.Exception);
        e.SetObserved();
    }
}
