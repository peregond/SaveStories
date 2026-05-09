using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using SaveMe.WinUI.Beta.Services;
using System.Text;
using Windows.ApplicationModel.DataTransfer;

namespace SaveMe.WinUI.Beta;

public partial class App : Application
{
    private Window? _window;

    public static Window? MainWindow { get; private set; }

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
            MainWindow = _window;
            _window.Activate();
        }
        catch (Exception ex)
        {
            DiagnosticsService.Current.LogError("Startup.MainWindowFailed", ex);
            _window = BuildFatalWindow(ex);
            MainWindow = _window;
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
        var detailsText = details.ToString();

        var detailsBox = new TextBox
        {
            Text = detailsText,
            IsReadOnly = true,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas"),
            FontSize = 13,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch,
        };

        var copyButton = new Button
        {
            Content = "Скопировать текст",
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        copyButton.Click += (_, _) =>
        {
            var data = new DataPackage();
            data.SetText(detailsText);
            Clipboard.SetContent(data);
        };

        var window = new Window();
        window.Title = "SaveMe — ошибка запуска";
        window.Content = new Grid
        {
            Padding = new Thickness(20),
            RowDefinitions =
            {
                new RowDefinition { Height = GridLength.Auto },
                new RowDefinition { Height = new GridLength(12) },
                new RowDefinition { Height = new GridLength(1, GridUnitType.Star) },
            },
            Children =
            {
                copyButton,
                detailsBox,
            },
        };
        Grid.SetRow(copyButton, 0);
        Grid.SetRow(detailsBox, 2);
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
