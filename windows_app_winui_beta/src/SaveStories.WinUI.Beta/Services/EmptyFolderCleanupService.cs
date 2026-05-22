namespace SaveMe.WinUI.Beta.Services;

public sealed record EmptyFolderCleanupResult(
    IReadOnlyList<string> RemovedFolders,
    IReadOnlyList<string> FailedFolders)
{
    public IReadOnlyList<string> RemovedFolderNames => RemovedFolders
        .Select(Path.GetFileName)
        .Where(name => !string.IsNullOrWhiteSpace(name))
        .Select(name => name!)
        .ToList();
}

public static class EmptyFolderCleanupService
{
    public static IReadOnlyList<string> FindDeletableEmptyFolders(string root)
    {
        if (string.IsNullOrWhiteSpace(root) || !Directory.Exists(root))
        {
            return Array.Empty<string>();
        }

        try
        {
            var candidates = Directory.EnumerateDirectories(root, "*", SearchOption.AllDirectories)
                .Where(path => !IsProtectedTransferDirectory(path))
                .OrderByDescending(DirectoryDepth)
                .ToList();

            var deletable = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var folder in candidates)
            {
                if (IsEffectivelyEmptyDirectoryAfterDeletingKnownEmptyChildren(folder, deletable))
                {
                    deletable.Add(Path.GetFullPath(folder));
                }
            }

            return candidates
                .Where(folder => deletable.Contains(Path.GetFullPath(folder)))
                .ToList();
        }
        catch
        {
            return Array.Empty<string>();
        }
    }

    public static EmptyFolderCleanupResult DeleteEmptyFolders(IEnumerable<string> folders)
    {
        var removed = new List<string>();
        var failed = new List<string>();
        foreach (var folder in folders
            .Where(folder => !IsProtectedTransferDirectory(folder))
            .OrderByDescending(DirectoryDepth))
        {
            try
            {
                if (!Directory.Exists(folder))
                {
                    continue;
                }

                if (IsEffectivelyEmptyDirectory(folder))
                {
                    Directory.Delete(folder, recursive: true);
                    removed.Add(folder);
                }
            }
            catch
            {
                failed.Add(folder);
            }
        }

        return new EmptyFolderCleanupResult(removed, failed);
    }

    private static bool IsEffectivelyEmptyDirectoryAfterDeletingKnownEmptyChildren(string directory, ISet<string> knownEmptyDirectories)
    {
        try
        {
            foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
            {
                if (IsIgnorableFilesystemEntry(entry))
                {
                    continue;
                }

                if (Directory.Exists(entry) && knownEmptyDirectories.Contains(Path.GetFullPath(entry)))
                {
                    continue;
                }

                return false;
            }

            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool IsEffectivelyEmptyDirectory(string directory)
    {
        try
        {
            foreach (var entry in Directory.EnumerateFileSystemEntries(directory))
            {
                if (IsIgnorableFilesystemEntry(entry))
                {
                    continue;
                }

                return false;
            }

            return true;
        }
        catch
        {
            return false;
        }
    }

    public static bool IsIgnorableFilesystemEntry(string path)
    {
        try
        {
            var name = Path.GetFileName(path);
            if (string.Equals(name, ".DS_Store", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(name, "desktop.ini", StringComparison.OrdinalIgnoreCase) ||
                string.Equals(name, "Thumbs.db", StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            return false;
        }
        catch
        {
            return false;
        }
    }

    private static bool IsProtectedTransferDirectory(string path)
    {
        try
        {
            return Path.GetFullPath(path)
                .Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                .Any(component => string.Equals(component, "На перенос", StringComparison.OrdinalIgnoreCase));
        }
        catch
        {
            return false;
        }
    }

    private static int DirectoryDepth(string path)
    {
        return path.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).Length;
    }
}
