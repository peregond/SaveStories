namespace SaveMe.WinUI.Beta.Services;

internal static class NodeRuntimeResolver
{
    public static string ResolveNodeExecutable()
    {
        var bundledNode = GetBundledNodeExecutablePath();
        if (File.Exists(bundledNode))
        {
            return bundledNode;
        }

        var pathNode = FindOnPath("node.exe");
        if (pathNode is not null)
        {
            return pathNode;
        }

        throw new InvalidOperationException(
            "Node.js runtime не найден. Переустанови приложение из актуального .exe или установи Node.js 24+."
        );
    }

    public static (string fileName, string arguments) ResolveNpmInstallCommand(string npmArguments)
    {
        var bundledNode = GetBundledNodeExecutablePath();
        var bundledNpmCli = GetBundledNpmCliPath();
        if (File.Exists(bundledNode) && File.Exists(bundledNpmCli))
        {
            return (bundledNode, $"\"{bundledNpmCli}\" {npmArguments}");
        }

        var npmCmd = FindOnPath("npm.cmd");
        if (npmCmd is not null)
        {
            return (npmCmd, npmArguments);
        }

        throw new InvalidOperationException(
            "npm не найден. Переустанови приложение из актуального .exe или установи Node.js 24+."
        );
    }

    private static string GetBundledNodeExecutablePath()
    {
        return Path.Combine(AppContext.BaseDirectory, "runtime", "node", "node.exe");
    }

    private static string GetBundledNpmCliPath()
    {
        return Path.Combine(AppContext.BaseDirectory, "runtime", "node", "node_modules", "npm", "bin", "npm-cli.js");
    }

    private static string? FindOnPath(string fileName)
    {
        var path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        foreach (var entry in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(entry.Trim(), fileName);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
            catch
            {
                // skip malformed entries
            }
        }

        return null;
    }
}
