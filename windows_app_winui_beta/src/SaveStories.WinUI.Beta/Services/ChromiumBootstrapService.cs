using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http;
using System.Text;

namespace SaveMe.WinUI.Beta.Services;

public sealed class ChromiumBootstrapService
{
    private const string NodeVersion = "v24.11.0";
    private const string NodeArchiveName = $"node-{NodeVersion}-win-x64.zip";
    private static readonly HttpClient Http = new();
    private static readonly Lazy<ChromiumBootstrapService> LazyInstance = new(() => new ChromiumBootstrapService());

    public static ChromiumBootstrapService Current => LazyInstance.Value;

    private ChromiumBootstrapService()
    {
    }

    public string GetBootstrapSummary()
    {
        return "После установки .exe приложение докачивает Node 24 LTS, node зависимости и Chromium в локальную папку пользователя.";
    }

    public string GetTargetDirectory()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(root, "SaveMe", "worker", "ms-playwright");
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

    public bool IsWorkerDependenciesInstalled()
    {
        var cliPath = Path.Combine(GetWorkerDirectory(), "node_modules", "playwright", "cli.js");
        return File.Exists(cliPath);
    }

    public bool IsNodeRuntimeInstalled()
    {
        return File.Exists(NodeRuntimeResolver.InstalledNodeExecutablePath())
            && File.Exists(NodeRuntimeResolver.InstalledNpmCliPath());
    }

    public string GetWorkerDirectory()
    {
        return NodeRuntimeResolver.WorkerRoot();
    }

    public async Task<string> EnsureRuntimeInstalledAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(GetWorkerDirectory());
        Directory.CreateDirectory(GetTargetDirectory());

        await EnsureNodeRuntimeInstalledAsync(progress, cancellationToken);
        CopyWorkerToAppSupport(progress);

        var workerDir = GetWorkerDirectory();
        var cliPath = Path.Combine(workerDir, "node_modules", "playwright", "cli.js");
        if (!File.Exists(cliPath))
        {
            progress?.Report("Устанавливаю зависимости Playwright...");
            var npmInstall = NodeRuntimeResolver.ResolveNpmInstallCommand("ci --omit=dev");
            await RunProcessAsync(
                fileName: npmInstall.fileName,
                arguments: npmInstall.arguments,
                workingDirectory: workerDir,
                env: null,
                progress: progress,
                cancellationToken: cancellationToken);
        }

        return await InstallChromiumAsync(progress, cancellationToken);
    }

    public async Task<string> InstallChromiumAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        if (IsChromiumInstalled())
        {
            return "Chromium уже установлен.";
        }

        var nodeWorkerDir = GetWorkerDirectory();
        var cliPath = Path.Combine(nodeWorkerDir, "node_modules", "playwright", "cli.js");

        if (!Directory.Exists(nodeWorkerDir))
        {
            throw new InvalidOperationException("Не найдена локальная папка worker. Запусти установку движка ещё раз.");
        }

        if (!File.Exists(cliPath))
        {
            throw new InvalidOperationException("Не найден Playwright CLI. Запусти установку движка ещё раз.");
        }

        Directory.CreateDirectory(GetTargetDirectory());

        progress?.Report("Запускаю playwright install chromium...");
        var nodeExecutable = NodeRuntimeResolver.ResolveNodeExecutable();
        var output = await RunProcessAsync(
            fileName: nodeExecutable,
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

    public async Task EnsureNodeRuntimeInstalledAsync(IProgress<string>? progress = null, CancellationToken cancellationToken = default)
    {
        var nodeExe = NodeRuntimeResolver.InstalledNodeExecutablePath();
        var npmCli = NodeRuntimeResolver.InstalledNpmCliPath();
        if (File.Exists(nodeExe) && File.Exists(npmCli))
        {
            progress?.Report("Node 24 LTS уже установлен.");
            return;
        }

        var nodeUrl = $"https://nodejs.org/dist/{NodeVersion}/{NodeArchiveName}";
        var tempRoot = Path.Combine(Path.GetTempPath(), $"SaveMe-node-{Guid.NewGuid():N}");
        var zipPath = Path.Combine(tempRoot, NodeArchiveName);
        var extractRoot = Path.Combine(tempRoot, "extract");

        try
        {
            progress?.Report("Скачиваю Node 24 LTS...");
            Directory.CreateDirectory(tempRoot);
            await using (var stream = await Http.GetStreamAsync(nodeUrl, cancellationToken))
            await using (var file = File.Create(zipPath))
            {
                await stream.CopyToAsync(file, cancellationToken);
            }

            progress?.Report("Распаковываю Node 24 LTS...");
            ZipFile.ExtractToDirectory(zipPath, extractRoot, overwriteFiles: true);
            var extractedNode = Directory.GetDirectories(extractRoot, "node-*").FirstOrDefault()
                ?? throw new InvalidOperationException("Не удалось распаковать Node runtime.");

            var targetRoot = NodeRuntimeResolver.InstalledNodeRoot();
            if (Directory.Exists(targetRoot))
            {
                Directory.Delete(targetRoot, recursive: true);
            }
            Directory.CreateDirectory(Path.GetDirectoryName(targetRoot)!);
            CopyDirectory(extractedNode, targetRoot, overwrite: true);
        }
        finally
        {
            try
            {
                if (Directory.Exists(tempRoot))
                {
                    Directory.Delete(tempRoot, recursive: true);
                }
            }
            catch
            {
                // Best-effort cleanup only.
            }
        }

        if (!File.Exists(nodeExe) || !File.Exists(npmCli))
        {
            throw new InvalidOperationException("Node runtime скачан, но node.exe или npm-cli.js не найдены.");
        }
    }

    private static void CopyWorkerToAppSupport(IProgress<string>? progress)
    {
        var sourceWorkerDir = Path.Combine(ResolveRepoRoot(), "node_worker");
        if (!Directory.Exists(sourceWorkerDir))
        {
            throw new InvalidOperationException("Не найдена папка node_worker рядом с приложением.");
        }

        var targetWorkerDir = NodeRuntimeResolver.WorkerRoot();
        Directory.CreateDirectory(targetWorkerDir);
        progress?.Report("Копирую worker...");
        CopyDirectory(
            sourceWorkerDir,
            targetWorkerDir,
            overwrite: true,
            excludedRootNames: new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "node",
                "node_modules",
                "ms-playwright",
                "browser-profile",
                ".venv",
                ".cache",
                "logs",
            });
    }

    private static void CopyDirectory(
        string sourceDirectory,
        string targetDirectory,
        bool overwrite,
        ISet<string>? excludedRootNames = null)
    {
        Directory.CreateDirectory(targetDirectory);

        foreach (var file in Directory.EnumerateFiles(sourceDirectory))
        {
            var fileName = Path.GetFileName(file);
            if (excludedRootNames?.Contains(fileName) == true)
            {
                continue;
            }
            File.Copy(file, Path.Combine(targetDirectory, fileName), overwrite);
        }

        foreach (var directory in Directory.EnumerateDirectories(sourceDirectory))
        {
            var directoryName = Path.GetFileName(directory);
            if (excludedRootNames?.Contains(directoryName) == true)
            {
                continue;
            }
            CopyDirectory(
                directory,
                Path.Combine(targetDirectory, directoryName),
                overwrite,
                excludedRootNames: null);
        }
    }

    private static string ResolveRepoRoot()
    {
        var explicitRoot = Environment.GetEnvironmentVariable("SAVEME_WINUI_REPO_ROOT");
        if (string.IsNullOrWhiteSpace(explicitRoot))
        {
            explicitRoot = Environment.GetEnvironmentVariable("SAVESTORIES_BETA_REPO_ROOT");
        }
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
            "Не удалось найти рабочую папку с node_worker рядом с приложением."
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
