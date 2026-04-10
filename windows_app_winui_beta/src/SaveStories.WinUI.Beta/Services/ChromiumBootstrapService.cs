using System.Diagnostics;
using System.Text;

namespace SaveStories.WinUI.Beta.Services;

public sealed class ChromiumBootstrapService
{
    private static readonly Lazy<ChromiumBootstrapService> LazyInstance = new(() => new ChromiumBootstrapService());

    public static ChromiumBootstrapService Current => LazyInstance.Value;

    private ChromiumBootstrapService()
    {
    }

    public string GetBootstrapSummary()
    {
        return "Chromium скачивается отдельным действием после установки и хранится вне .exe.";
    }

    public string GetTargetDirectory()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(root, "SaveStories", "worker", "ms-playwright");
    }

    public bool IsChromiumInstalled()
    {
        var root = GetTargetDirectory();
        if (!Directory.Exists(root))
        {
            return false;
        }

        return Directory.EnumerateFiles(root, "chrome.exe", SearchOption.AllDirectories).Any();
    }

    public async Task<string> InstallChromiumAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        if (IsChromiumInstalled())
        {
            return "Chromium уже установлен.";
        }

        var repoRoot = ResolveRepoRoot();
        var nodeWorkerDir = Path.Combine(repoRoot, "node_worker");
        var cliPath = Path.Combine(nodeWorkerDir, "node_modules", "playwright", "cli.js");

        if (!Directory.Exists(nodeWorkerDir))
        {
            throw new InvalidOperationException("Не найдена папка node_worker. Укажи SAVESTORIES_BETA_REPO_ROOT.");
        }

        if (!File.Exists(cliPath))
        {
            throw new InvalidOperationException(
                "Не найден playwright CLI. Выполни `npm ci` в node_worker или собери beta-пакет с зависимостями."
            );
        }

        Directory.CreateDirectory(GetTargetDirectory());

        progress?.Report("Запускаю playwright install chromium...");
        var output = await RunProcessAsync(
            fileName: "node",
            arguments: $"\"{cliPath}\" install chromium",
            workingDirectory: nodeWorkerDir,
            env: new Dictionary<string, string>
            {
                ["PLAYWRIGHT_BROWSERS_PATH"] = GetTargetDirectory(),
            },
            progress: progress,
            cancellationToken: cancellationToken);

        if (!IsChromiumInstalled())
        {
            throw new InvalidOperationException("Команда завершилась, но Chromium не найден в целевой папке.\n" + output);
        }

        return "Chromium успешно установлен.";
    }

    private static string ResolveRepoRoot()
    {
        var explicitRoot = Environment.GetEnvironmentVariable("SAVESTORIES_BETA_REPO_ROOT");
        if (!string.IsNullOrWhiteSpace(explicitRoot) && Directory.Exists(explicitRoot))
        {
            return explicitRoot;
        }

        var current = new DirectoryInfo(AppContext.BaseDirectory);
        for (var i = 0; i < 12 && current is not null; i++)
        {
            var candidate = Path.Combine(current.FullName, "node_worker");
            if (Directory.Exists(candidate))
            {
                return current.FullName;
            }
            current = current.Parent;
        }

        throw new InvalidOperationException(
            "Не удалось найти корень репозитория рядом с beta-приложением. Укажи SAVESTORIES_BETA_REPO_ROOT."
        );
    }

    private static async Task<string> RunProcessAsync(
        string fileName,
        string arguments,
        string workingDirectory,
        IDictionary<string, string>? env,
        IProgress<string>? progress,
        CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            WorkingDirectory = workingDirectory,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        if (env is not null)
        {
            foreach (var (key, value) in env)
            {
                startInfo.Environment[key] = value;
            }
        }

        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        var outputBuilder = new StringBuilder();
        var errorBuilder = new StringBuilder();

        process.OutputDataReceived += (_, args) =>
        {
            if (string.IsNullOrWhiteSpace(args.Data))
            {
                return;
            }
            outputBuilder.AppendLine(args.Data);
            progress?.Report(args.Data);
        };

        process.ErrorDataReceived += (_, args) =>
        {
            if (string.IsNullOrWhiteSpace(args.Data))
            {
                return;
            }
            errorBuilder.AppendLine(args.Data);
            progress?.Report(args.Data);
        };

        if (!process.Start())
        {
            throw new InvalidOperationException($"Не удалось запустить процесс: {fileName}");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        await process.WaitForExitAsync(cancellationToken);

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"Команда завершилась с кодом {process.ExitCode}.\n{errorBuilder}\n{outputBuilder}"
            );
        }

        return $"{outputBuilder}\n{errorBuilder}";
    }
}
