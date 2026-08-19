using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http;
using System.Text;
using System.Text.Json;

namespace SaveMe.WinUI.Beta.Services;

public sealed class ChromiumBootstrapService
{
    private const string NodeVersion = "v24.11.0";
    private const string NodeArchiveName = $"node-{NodeVersion}-win-x64.zip";
    private const string ManagedWorkerFilesMarkerName = ".saveme-managed-worker-files.json";
    private static readonly object WorkerSourceSynchronizationLock = new();
    private static readonly HashSet<string> PreservedWorkerRootNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "node",
        "node_modules",
        "ms-playwright",
        "browser-profile",
        ".venv",
        ".cache",
        "logs",
    };
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
        SynchronizeBundledWorkerSources(progress);

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

    public void SynchronizeBundledWorkerSources(IProgress<string>? progress = null)
    {
        lock (WorkerSourceSynchronizationLock)
        {
            var sourceWorkerDir = Path.Combine(ResolveRepoRoot(), "node_worker");
            if (!Directory.Exists(sourceWorkerDir))
            {
                throw new InvalidOperationException("Не найдена папка node_worker рядом с приложением.");
            }

            var bundledVersion = ReadWorkerPackageVersion(sourceWorkerDir)
                ?? throw new InvalidOperationException("В bundled worker отсутствует корректная версия package.json.");
            var targetWorkerDir = NodeRuntimeResolver.WorkerRoot();
            var installedVersion = ReadWorkerPackageVersion(targetWorkerDir);
            if (installedVersion is not null && CompareWorkerVersions(installedVersion, bundledVersion) > 0)
            {
                progress?.Report("Установленный worker новее bundled-версии; пропускаю понижение.");
                return;
            }

            var requiredSourceFiles = new[] { "package.json", "bridge.mjs" };
            if (requiredSourceFiles.Any(fileName => !File.Exists(Path.Combine(sourceWorkerDir, fileName))))
            {
                throw new InvalidOperationException("Bundled worker неполный: не найдены package.json или bridge.mjs.");
            }

            Directory.CreateDirectory(targetWorkerDir);
            progress?.Report("Обновляю worker...");

            var sourceFiles = EnumerateWorkerSourceFiles(sourceWorkerDir);
            var managedFilesMarkerPath = Path.Combine(targetWorkerDir, ManagedWorkerFilesMarkerName);
            var previouslyManagedFiles = ReadManagedWorkerFiles(managedFilesMarkerPath);

            foreach (var staleRelativePath in previouslyManagedFiles.Except(sourceFiles.Keys, StringComparer.OrdinalIgnoreCase))
            {
                var stalePath = TryResolveManagedWorkerPath(targetWorkerDir, staleRelativePath);
                if (stalePath is null || !File.Exists(stalePath))
                {
                    continue;
                }
                File.Delete(stalePath);
                DeleteEmptyWorkerSourceParents(Path.GetDirectoryName(stalePath), targetWorkerDir);
            }

            foreach (var (relativePath, sourcePath) in sourceFiles)
            {
                var destinationPath = ResolveManagedWorkerPath(targetWorkerDir, relativePath);
                AtomicReplaceFile(sourcePath, destinationPath);
            }

            WriteManagedWorkerFiles(
                managedFilesMarkerPath,
                sourceFiles.Keys.OrderBy(path => path, StringComparer.OrdinalIgnoreCase));
        }
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

    private static void CopyDirectory(
        string sourceDirectory,
        string targetDirectory,
        bool overwrite)
    {
        Directory.CreateDirectory(targetDirectory);

        foreach (var file in Directory.EnumerateFiles(sourceDirectory))
        {
            var fileName = Path.GetFileName(file);
            File.Copy(file, Path.Combine(targetDirectory, fileName), overwrite);
        }

        foreach (var directory in Directory.EnumerateDirectories(sourceDirectory))
        {
            var directoryName = Path.GetFileName(directory);
            CopyDirectory(
                directory,
                Path.Combine(targetDirectory, directoryName),
                overwrite);
        }
    }

    private static bool ShouldPreserveWorkerRootEntry(string name)
    {
        return PreservedWorkerRootNames.Contains(name)
            || name.StartsWith("storage-state", StringComparison.OrdinalIgnoreCase);
    }

    private static Dictionary<string, string> EnumerateWorkerSourceFiles(string sourceWorkerDir)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        void AddSourceFile(string sourceFile)
        {
            var relativePath = NormalizeManagedRelativePath(Path.GetRelativePath(sourceWorkerDir, sourceFile));
            if (!string.Equals(relativePath, ManagedWorkerFilesMarkerName, StringComparison.OrdinalIgnoreCase))
            {
                result.Add(relativePath, sourceFile);
            }
        }

        foreach (var sourceFile in Directory.EnumerateFiles(sourceWorkerDir))
        {
            if (!ShouldPreserveWorkerRootEntry(Path.GetFileName(sourceFile)))
            {
                AddSourceFile(sourceFile);
            }
        }

        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true,
            AttributesToSkip = FileAttributes.ReparsePoint,
        };
        foreach (var sourceDirectory in Directory.EnumerateDirectories(sourceWorkerDir))
        {
            if (ShouldPreserveWorkerRootEntry(Path.GetFileName(sourceDirectory)))
            {
                continue;
            }
            foreach (var sourceFile in Directory.EnumerateFiles(sourceDirectory, "*", options))
            {
                AddSourceFile(sourceFile);
            }
        }
        return result;
    }

    private static IReadOnlyCollection<string> ReadManagedWorkerFiles(string markerPath)
    {
        if (!File.Exists(markerPath))
        {
            return Array.Empty<string>();
        }

        try
        {
            var files = JsonSerializer.Deserialize<string[]>(File.ReadAllText(markerPath));
            return files ?? Array.Empty<string>();
        }
        catch (JsonException)
        {
            return Array.Empty<string>();
        }
    }

    private static void WriteManagedWorkerFiles(string markerPath, IEnumerable<string> relativePaths)
    {
        var json = JsonSerializer.Serialize(relativePaths.ToArray());
        var tempPath = BuildAtomicTempPath(markerPath);
        try
        {
            File.WriteAllText(tempPath, json, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            File.Move(tempPath, markerPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(tempPath))
            {
                File.Delete(tempPath);
            }
        }
    }

    private static void AtomicReplaceFile(string sourcePath, string destinationPath)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
        var tempPath = BuildAtomicTempPath(destinationPath);
        try
        {
            File.Copy(sourcePath, tempPath, overwrite: false);
            File.Move(tempPath, destinationPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(tempPath))
            {
                File.Delete(tempPath);
            }
        }
    }

    private static string BuildAtomicTempPath(string destinationPath)
    {
        var directoryPath = Path.GetDirectoryName(destinationPath)
            ?? throw new InvalidOperationException($"Не удалось определить папку для worker-файла: {destinationPath}");
        return Path.Combine(directoryPath, $".saveme-sync-{Guid.NewGuid():N}.tmp");
    }

    private static string ResolveManagedWorkerPath(string targetWorkerDir, string relativePath)
    {
        return TryResolveManagedWorkerPath(targetWorkerDir, relativePath)
            ?? throw new InvalidOperationException($"Некорректный путь worker: {relativePath}");
    }

    private static string? TryResolveManagedWorkerPath(string targetWorkerDir, string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath))
        {
            return null;
        }

        var normalizedRelativePath = NormalizeManagedRelativePath(relativePath);
        var pathComponents = normalizedRelativePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (pathComponents.Length == 0
            || pathComponents.Any(component => component is "." or "..")
            || pathComponents.Any(component => component.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0))
        {
            return null;
        }

        var topLevelName = pathComponents[0];
        if (topLevelName is "." or ".."
            || ShouldPreserveWorkerRootEntry(topLevelName)
            || string.Equals(normalizedRelativePath, ManagedWorkerFilesMarkerName, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var rootPath = Path.GetFullPath(targetWorkerDir);
        var candidatePath = Path.GetFullPath(
            Path.Combine(rootPath, normalizedRelativePath.Replace('/', Path.DirectorySeparatorChar)));
        var rootPrefix = rootPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;
        return candidatePath.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase)
            ? candidatePath
            : null;
    }

    private static string NormalizeManagedRelativePath(string relativePath)
    {
        return relativePath.Replace('\\', '/');
    }

    private static void DeleteEmptyWorkerSourceParents(string? directoryPath, string targetWorkerDir)
    {
        var rootPath = Path.GetFullPath(targetWorkerDir)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        while (!string.IsNullOrWhiteSpace(directoryPath)
            && !string.Equals(Path.GetFullPath(directoryPath), rootPath, StringComparison.OrdinalIgnoreCase)
            && Directory.Exists(directoryPath)
            && !Directory.EnumerateFileSystemEntries(directoryPath).Any())
        {
            var parent = Path.GetDirectoryName(directoryPath);
            Directory.Delete(directoryPath);
            directoryPath = parent;
        }
    }

    private static int[]? ReadWorkerPackageVersion(string workerRoot)
    {
        var packagePath = Path.Combine(workerRoot, "package.json");
        if (!File.Exists(packagePath))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(packagePath));
            if (!document.RootElement.TryGetProperty("version", out var versionElement)
                || versionElement.ValueKind != JsonValueKind.String
                || versionElement.GetString() is not { } version)
            {
                return null;
            }

            var components = new List<int>();
            foreach (var component in version.Split('.'))
            {
                var digits = new string(component.TakeWhile(char.IsDigit).ToArray());
                if (digits.Length > 0 && int.TryParse(digits, out var value))
                {
                    components.Add(value);
                }
            }
            return components.Count > 0 ? components.ToArray() : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static int CompareWorkerVersions(IReadOnlyList<int> left, IReadOnlyList<int> right)
    {
        var count = Math.Max(left.Count, right.Count);
        for (var index = 0; index < count; index++)
        {
            var leftValue = index < left.Count ? left[index] : 0;
            var rightValue = index < right.Count ? right[index] : 0;
            var comparison = leftValue.CompareTo(rightValue);
            if (comparison != 0)
            {
                return comparison;
            }
        }
        return 0;
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
