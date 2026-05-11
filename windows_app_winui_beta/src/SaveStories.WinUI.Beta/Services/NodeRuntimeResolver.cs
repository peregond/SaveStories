namespace SaveMe.WinUI.Beta.Services;

internal static class NodeRuntimeResolver
{
    public static string WorkerRoot()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        return Path.Combine(root, "SaveMe", "worker");
    }

    public static string InstalledNodeRoot()
    {
        return Path.Combine(WorkerRoot(), "node");
    }

    public static string InstalledNodeExecutablePath()
    {
        return Path.Combine(InstalledNodeRoot(), "node.exe");
    }

    public static string InstalledNpmCliPath()
    {
        return Path.Combine(InstalledNodeRoot(), "node_modules", "npm", "bin", "npm-cli.js");
    }

    public static string ResolveNodeExecutable()
    {
        var installedNode = InstalledNodeExecutablePath();
        if (File.Exists(installedNode))
        {
            return installedNode;
        }

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
            "Node.js runtime не найден. Запусти установку движка при первом запуске или в настройках приложения."
        );
    }

    public static (string fileName, string arguments) ResolveNpmInstallCommand(string npmArguments)
    {
        var installedNode = InstalledNodeExecutablePath();
        var installedNpmCli = InstalledNpmCliPath();
        if (File.Exists(installedNode) && File.Exists(installedNpmCli))
        {
            return (installedNode, $"\"{installedNpmCli}\" {npmArguments}");
        }

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
            "npm не найден. Запусти установку движка при первом запуске или в настройках приложения."
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
