using Microsoft.UI.Xaml;
using SaveStories.WinUI.Beta.Services;

namespace SaveStories.WinUI.Beta;

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
        _window = new MainWindow();
        _window.Activate();
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        DiagnosticsService.Current.LogError("Application.UnhandledException", e.Exception);
    }

    private void OnAppDomainUnhandledException(object? sender, System.UnhandledExceptionEventArgs e)
    {
        if (e.ExceptionObject is Exception ex)
        {
            DiagnosticsService.Current.LogError("AppDomain.UnhandledException", ex);
        }
        else
        {
            DiagnosticsService.Current.LogError("AppDomain.UnhandledException", new Exception(String(e.ExceptionObject)));
        }
    }

    private void OnUnobservedTaskException(object? sender, System.Threading.Tasks.UnobservedTaskExceptionEventArgs e)
    {
        DiagnosticsService.Current.LogError("TaskScheduler.UnobservedTaskException", e.Exception);
        e.SetObserved();
    }
}
