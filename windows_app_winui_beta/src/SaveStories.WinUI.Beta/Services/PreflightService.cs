namespace SaveMe.WinUI.Beta.Services;

public sealed class PreflightService
{
    private static readonly Lazy<PreflightService> LazyInstance = new(() => new PreflightService());
    public static PreflightService Current => LazyInstance.Value;

    private PreflightService()
    {
    }

    public PreflightResult Run()
    {
        var checks = new List<PreflightCheck>();

        checks.Add(Check("Node runtime", () =>
        {
            _ = NodeRuntimeResolver.ResolveNodeExecutable();
            return "OK";
        }));

        checks.Add(Check("node_worker", () =>
        {
            var repoRoot = ResolveRepoRoot();
            var bridgePath = Path.Combine(repoRoot, "node_worker", "bridge.mjs");
            if (!File.Exists(bridgePath))
            {
                throw new InvalidOperationException("bridge.mjs не найден.");
            }
            return "OK";
        }));

        checks.Add(Check("Write Downloads", () =>
        {
            var directory = WorkerBridgeService.Current.GetDefaultDownloadsDirectory();
            Directory.CreateDirectory(directory);
            var probe = Path.Combine(directory, $".write_probe_{Guid.NewGuid():N}.tmp");
            File.WriteAllText(probe, "ok");
            File.Delete(probe);
            return directory;
        }));

        checks.Add(Check("Chromium", () =>
        {
            return ChromiumBootstrapService.Current.IsChromiumInstalled()
                ? "installed"
                : "not installed";
        }));

        checks.Add(Check("Worker deps", () =>
        {
            return ChromiumBootstrapService.Current.IsWorkerDependenciesInstalled()
                ? "installed"
                : "not installed";
        }));

        return new PreflightResult
        {
            Ok = checks.All(x => x.Ok),
            Checks = checks
        };
    }

    private static PreflightCheck Check(string name, Func<string> action)
    {
        try
        {
            return new PreflightCheck { Name = name, Ok = true, Message = action() };
        }
        catch (Exception ex)
        {
            return new PreflightCheck { Name = name, Ok = false, Message = ex.Message };
        }
    }

    private static string ResolveRepoRoot()
    {
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

        throw new InvalidOperationException("Рабочая папка с node_worker не найдена.");
    }
}

public sealed class PreflightResult
{
    public bool Ok { get; init; }
    public required List<PreflightCheck> Checks { get; init; }
}

public sealed class PreflightCheck
{
    public required string Name { get; init; }
    public bool Ok { get; init; }
    public required string Message { get; init; }
}
