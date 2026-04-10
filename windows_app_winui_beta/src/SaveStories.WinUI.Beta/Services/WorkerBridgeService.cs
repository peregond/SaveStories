using System.Diagnostics;
using System.Text.Json;

namespace SaveStories.WinUI.Beta.Services;

public sealed class WorkerBridgeService
{
    private static readonly Lazy<WorkerBridgeService> LazyInstance = new(() => new WorkerBridgeService());
    private static readonly TimeSpan DefaultTimeout = TimeSpan.FromMinutes(20);
    private readonly SemaphoreSlim _runGate = new(1, 1);
    private readonly object _processLock = new();
    private Process? _activeProcess;

    public static WorkerBridgeService Current => LazyInstance.Value;

    private WorkerBridgeService()
    {
    }

    public string GetDefaultDownloadsDirectory()
    {
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Path.Combine(profile, "Downloads", "SaveStories");
    }

    public string GetAppSupportDirectory()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(root, "SaveStories");
    }

    public async Task<WorkerRunResult> RunAsync(
        WorkerRequest request,
        CancellationToken cancellationToken = default,
        TimeSpan? timeout = null)
    {
        await _runGate.WaitAsync(cancellationToken);
        try
        {
            return await RunCoreAsync(request, cancellationToken, timeout ?? DefaultTimeout);
        }
        finally
        {
            lock (_processLock)
            {
                _activeProcess = null;
            }
            _runGate.Release();
        }
    }

    public Task CancelCurrentAsync()
    {
        lock (_processLock)
        {
            if (_activeProcess is { HasExited: false } process)
            {
                try
                {
                    process.Kill(entireProcessTree: true);
                }
                catch
                {
                    // no-op: process may exit during cancellation race
                }
            }
        }
        return Task.CompletedTask;
    }

    private async Task<WorkerRunResult> RunCoreAsync(
        WorkerRequest request,
        CancellationToken cancellationToken,
        TimeSpan timeout)
    {
        var repoRoot = ResolveRepoRoot();
        var workerScript = Path.Combine(repoRoot, "node_worker", "bridge.mjs");
        if (!File.Exists(workerScript))
        {
            throw new InvalidOperationException("Не найден node_worker/bridge.mjs. Укажи SAVESTORIES_BETA_REPO_ROOT.");
        }

        EnsureRuntimeDirectories();

        var startInfo = new ProcessStartInfo
        {
            FileName = "node",
            Arguments = $"\"{workerScript}\"",
            WorkingDirectory = repoRoot,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        var appSupport = GetAppSupportDirectory();
        startInfo.Environment["SAVESTORIES_APP_SUPPORT"] = appSupport;
        startInfo.Environment["SAVESTORIES_BROWSER_PROFILE"] = Path.Combine(appSupport, "worker", "browser-profile");
        startInfo.Environment["SAVESTORIES_MANIFESTS"] = Path.Combine(appSupport, "manifests");
        startInfo.Environment["SAVESTORIES_PLAYWRIGHT_BROWSERS"] = Path.Combine(appSupport, "worker", "ms-playwright");
        startInfo.Environment["SAVESTORIES_DEFAULT_DOWNLOADS"] = GetDefaultDownloadsDirectory();
        startInfo.Environment["SAVESTORIES_WORKER_RUNTIME"] = "node";

        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new InvalidOperationException("Не удалось запустить node worker.");
        }
        lock (_processLock)
        {
            _activeProcess = process;
        }

        var requestJson = JsonSerializer.Serialize(request);
        await process.StandardInput.WriteLineAsync(requestJson);
        await process.StandardInput.FlushAsync();
        process.StandardInput.Close();

        using var timeoutCts = new CancellationTokenSource(timeout);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeoutCts.Token);
        using var cancellationRegistration = linkedCts.Token.Register(() =>
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch
            {
                // no-op
            }
        });

        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        try
        {
            await process.WaitForExitAsync(linkedCts.Token);
        }
        catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException($"Команда worker превысила таймаут {timeout.TotalMinutes:0} мин.");
        }

        var stdout = await stdoutTask;
        var stderr = await stderrTask;

        if (string.IsNullOrWhiteSpace(stdout))
        {
            return new WorkerRunResult
            {
                Response = new WorkerResponse
                {
                    Ok = false,
                    Status = "process_error",
                    Message = string.IsNullOrWhiteSpace(stderr)
                        ? $"Worker завершился с кодом {process.ExitCode}."
                        : stderr.Trim(),
                },
                StdoutRaw = stdout,
                StderrRaw = stderr,
            };
        }

        WorkerResponse response;
        try
        {
            response = JsonSerializer.Deserialize<WorkerResponse>(stdout) ?? new WorkerResponse
            {
                Ok = false,
                Status = "parse_error",
                Message = "Worker вернул пустой JSON-ответ.",
            };
        }
        catch (Exception ex)
        {
            response = new WorkerResponse
            {
                Ok = false,
                Status = "parse_error",
                Message = $"Не удалось распарсить ответ worker: {ex.Message}",
                Logs = new List<string> { stdout },
            };
        }

        if (!string.IsNullOrWhiteSpace(stderr))
        {
            foreach (var line in stderr.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                response.Logs.Add(line);
            }
        }

        return new WorkerRunResult
        {
            Response = response,
            StdoutRaw = stdout,
            StderrRaw = stderr,
        };
    }

    private void EnsureRuntimeDirectories()
    {
        var appSupport = GetAppSupportDirectory();
        Directory.CreateDirectory(appSupport);
        Directory.CreateDirectory(Path.Combine(appSupport, "worker"));
        Directory.CreateDirectory(Path.Combine(appSupport, "worker", "browser-profile"));
        Directory.CreateDirectory(Path.Combine(appSupport, "worker", "ms-playwright"));
        Directory.CreateDirectory(Path.Combine(appSupport, "manifests"));
        Directory.CreateDirectory(GetDefaultDownloadsDirectory());
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
            var candidate = Path.Combine(current.FullName, "node_worker", "bridge.mjs");
            if (File.Exists(candidate))
            {
                return current.FullName;
            }
            current = current.Parent;
        }

        throw new InvalidOperationException("Не удалось найти корень репозитория. Укажи SAVESTORIES_BETA_REPO_ROOT.");
    }
}
