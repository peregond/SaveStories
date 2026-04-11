using System.Text;

namespace SaveMe.WinUI.Beta.Services;

public sealed class DiagnosticsService
{
    private static readonly Lazy<DiagnosticsService> LazyInstance = new(() => new DiagnosticsService());
    private readonly string _logDirectory;
    private readonly string _logPath;
    private readonly object _writeLock = new();

    public static DiagnosticsService Current => LazyInstance.Value;

    private DiagnosticsService()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _logDirectory = Path.Combine(root, "SaveMe.WinUI", "logs");
        _logPath = Path.Combine(_logDirectory, "app.log");
    }

    public string LogPath => _logPath;

    public void LogInfo(string message)
    {
        Append("INFO", message);
    }

    public void LogError(string message, Exception? exception = null)
    {
        var full = exception is null ? message : $"{message}\n{exception}";
        Append("ERROR", full);
    }

    public string ExportSnapshot()
    {
        Directory.CreateDirectory(_logDirectory);
        var target = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "Downloads",
            $"SaveMe-WinUI-diagnostics-{DateTime.Now:yyyyMMdd-HHmmss}.txt");
        var source = File.Exists(_logPath) ? File.ReadAllText(_logPath) : "Логов пока нет.";
        var payload = new StringBuilder();
        payload.AppendLine($"Timestamp: {DateTime.Now:O}");
        payload.AppendLine($"AppVersion: {AppVersionProvider.CurrentVersion()}");
        payload.AppendLine($"Machine: {Environment.MachineName}");
        payload.AppendLine($"OS: {Environment.OSVersion}");
        payload.AppendLine($"LogPath: {_logPath}");
        payload.AppendLine();
        payload.AppendLine(source);
        File.WriteAllText(target, payload.ToString(), Encoding.UTF8);
        return target;
    }

    private void Append(string level, string message)
    {
        try
        {
            Directory.CreateDirectory(_logDirectory);
            var line = $"{DateTime.Now:O} [{level}] {message}{Environment.NewLine}";
            lock (_writeLock)
            {
                File.AppendAllText(_logPath, line, Encoding.UTF8);
            }
        }
        catch
        {
            // ignore diagnostics write failures
        }
    }
}
