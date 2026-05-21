namespace SaveMe.WinUI.Beta.Services;

public sealed class SortingService
{
    public static SortingService Current { get; } = new();

    private SortingService()
    {
    }

    public Dictionary<string, string> ParseRules(string rules)
    {
        var mapping = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rawLine in (rules ?? "").Split('\n'))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#'))
            {
                continue;
            }

            var separatorIndex = line.IndexOf('=');
            if (separatorIndex <= 0 || separatorIndex >= line.Length - 1)
            {
                continue;
            }

            var username = line[..separatorIndex].Trim();
            var target = line[(separatorIndex + 1)..].Trim();
            if (username.Length > 0 && target.Length > 0)
            {
                mapping[username] = target;
            }
        }

        RememberBloggers(mapping.Values.Count > 0
            ? mapping.Select(entry =>
            {
                var targetFolder = TargetRelativeFolder(entry.Key, mapping);
                return new RememberedBloggerPayload
                {
                    Username = entry.Key,
                    CountryFolder = CountryFolder(targetFolder),
                    TargetFolder = targetFolder,
                    LastUsedAt = DateTimeOffset.Now,
                };
            })
            : Array.Empty<RememberedBloggerPayload>());

        return mapping;
    }

    public SortingResult DistributeFromSource(string sourceDirectory, string destinationRoot, string rules)
    {
        var mapping = ParseRules(rules);
        var inputs = new List<SortingInput>();

        if (!Directory.Exists(sourceDirectory))
        {
            return SortingResult.Failed($"Папка Перенос не найдена: {sourceDirectory}");
        }

        Directory.CreateDirectory(destinationRoot);

        foreach (var creatorDirectory in Directory.EnumerateDirectories(sourceDirectory)
            .Where(IsVisibleDirectory))
        {
            var creatorName = Path.GetFileName(creatorDirectory);
            foreach (var filePath in Directory.EnumerateFiles(creatorDirectory)
                .Where(IsVisibleRegularFile))
            {
                inputs.Add(new SortingInput(
                    Id: filePath,
                    Blogger: creatorName,
                    CurrentPath: filePath,
                    TargetRelativeFolder: TargetRelativeFolder(creatorName, mapping)));
            }
        }

        if (inputs.Count == 0)
        {
            return SortingResult.Failed("В выбранной папке нет файлов для сортировки.");
        }

        return Distribute(inputs, destinationRoot);
    }

    public string BuildDigest(IEnumerable<SortedFileRecord> records)
    {
        var blocks = records
            .GroupBy(record => record.CountryFolder, StringComparer.OrdinalIgnoreCase)
            .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase)
            .Select(countryGroup =>
            {
                var bloggerBlocks = countryGroup
                    .GroupBy(record => record.Blogger, StringComparer.OrdinalIgnoreCase)
                    .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase)
                    .Select(bloggerGroup =>
                    {
                        var links = bloggerGroup
                            .OrderBy(record => record.CurrentPath, StringComparer.OrdinalIgnoreCase)
                            .Select(record => record.CurrentPath);
                        return $"{bloggerGroup.Key}{Environment.NewLine}{string.Join(Environment.NewLine, links)}";
                    });
                return $"{countryGroup.Key}{Environment.NewLine}{Environment.NewLine}{string.Join($"{Environment.NewLine}{Environment.NewLine}", bloggerBlocks)}";
            });

        return string.Join($"{Environment.NewLine}{Environment.NewLine}", blocks);
    }

    public string BuildPostProcessedReport(IEnumerable<SortedFileRecord> records)
    {
        var blocks = records
            .GroupBy(ReportHeader, StringComparer.OrdinalIgnoreCase)
            .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase)
            .Select(group =>
            {
                var files = group
                    .OrderBy(record => record.CurrentPath, StringComparer.OrdinalIgnoreCase)
                    .Select(record => record.CurrentPath);
                return $"{group.Key}{Environment.NewLine}{string.Join(Environment.NewLine, files)}";
            });

        return string.Join($"{Environment.NewLine}{Environment.NewLine}", blocks);
    }

    public string BuildGoogleDriveDigest(IEnumerable<GoogleDriveLinkOutcome> outcomes)
    {
        var blocks = outcomes
            .GroupBy(outcome => outcome.Record.CountryFolder, StringComparer.OrdinalIgnoreCase)
            .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase)
            .Select(countryGroup =>
            {
                var bloggerBlocks = countryGroup
                    .GroupBy(outcome => outcome.Record.Blogger, StringComparer.OrdinalIgnoreCase)
                    .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase)
                    .Select(bloggerGroup =>
                    {
                        var links = bloggerGroup
                            .OrderBy(outcome => outcome.Record.CurrentPath, StringComparer.OrdinalIgnoreCase)
                            .Select(outcome =>
                            {
                                if (!string.IsNullOrWhiteSpace(outcome.Link))
                                {
                                    return outcome.Link;
                                }

                                var fileName = Path.GetFileName(outcome.Record.CurrentPath);
                                return $"# не удалось получить ссылку: {fileName}";
                            });
                        return $"{bloggerGroup.Key}{Environment.NewLine}{string.Join(Environment.NewLine, links)}";
                    });
                return $"{countryGroup.Key}{Environment.NewLine}{Environment.NewLine}{string.Join($"{Environment.NewLine}{Environment.NewLine}", bloggerBlocks)}";
            });

        return string.Join($"{Environment.NewLine}{Environment.NewLine}", blocks);
    }

    private SortingResult Distribute(IEnumerable<SortingInput> inputs, string destinationRoot)
    {
        var moved = new List<SortedFileRecord>();
        var failed = new List<string>();
        var movedCount = 0;

        foreach (var input in inputs)
        {
            if (!File.Exists(input.CurrentPath))
            {
                failed.Add(Path.GetFileName(input.CurrentPath));
                continue;
            }

            var destinationDirectory = Path.Combine(new[] { destinationRoot }.Concat(SplitPath(input.TargetRelativeFolder)).ToArray());
            Directory.CreateDirectory(destinationDirectory);

            var destinationPath = UniqueDestinationPath(
                Path.GetFileName(input.CurrentPath),
                destinationDirectory);

            try
            {
                if (!PathsEqual(input.CurrentPath, destinationPath))
                {
                    File.Move(input.CurrentPath, destinationPath);
                    movedCount++;
                }

                moved.Add(new SortedFileRecord(
                    Id: input.Id,
                    Blogger: input.Blogger,
                    CountryFolder: CountryFolder(input.TargetRelativeFolder),
                    TargetRelativeFolder: input.TargetRelativeFolder,
                    CurrentPath: destinationPath));
            }
            catch (Exception ex)
            {
                failed.Add($"{Path.GetFileName(input.CurrentPath)}: {ex.Message}");
            }
        }

        RememberBloggers(moved.Select(record => new RememberedBloggerPayload
        {
            Username = record.Blogger,
            CountryFolder = record.CountryFolder,
            TargetFolder = record.TargetRelativeFolder,
            LastUsedAt = DateTimeOffset.Now,
        }));

        var summary = movedCount > 0
            ? $"Разложено файлов: {movedCount}. Подпапок затронуто: {moved.Select(x => x.TargetRelativeFolder).Distinct(StringComparer.OrdinalIgnoreCase).Count()}."
            : failed.Count > 0
                ? $"Не удалось разложить файлы: {failed.Count}."
                : "Файлы уже лежат в нужных папках.";

        return new SortingResult(
            Success: moved.Count > 0 && failed.Count == 0,
            Summary: summary,
            Records: moved.OrderBy(x => x.CountryFolder).ThenBy(x => x.Blogger).ThenBy(x => x.CurrentPath).ToList(),
            FailedItems: failed);
    }

    private static string TargetRelativeFolder(string username, IReadOnlyDictionary<string, string> mapping)
    {
        if (!mapping.TryGetValue(username, out var mapped) || string.IsNullOrWhiteSpace(mapped))
        {
            return username;
        }

        var parts = SplitPath(mapped.Trim())
            .Where(part => !string.IsNullOrWhiteSpace(part))
            .ToList();
        if (parts.Count == 0)
        {
            return username;
        }

        if (parts.Count == 1)
        {
            parts.Add(username);
        }

        return Path.Combine(parts.ToArray());
    }

    private static string ReportHeader(SortedFileRecord record)
    {
        return string.Equals(record.TargetRelativeFolder, record.Blogger, StringComparison.OrdinalIgnoreCase)
            ? $"[{record.TargetRelativeFolder}]"
            : $"[{record.TargetRelativeFolder} ({record.Blogger})]";
    }

    private static string CountryFolder(string targetRelativeFolder)
    {
        return SplitPath(targetRelativeFolder).FirstOrDefault(part => !string.IsNullOrWhiteSpace(part)) ?? "Без страны";
    }

    private static string[] SplitPath(string value)
    {
        return value.Split(new[] { '/', '\\' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    private static string UniqueDestinationPath(string fileName, string directory)
    {
        var candidate = Path.Combine(directory, fileName);
        if (!File.Exists(candidate))
        {
            return candidate;
        }

        var extension = Path.GetExtension(fileName);
        var stem = Path.GetFileNameWithoutExtension(fileName);
        var (prefix, nextNumber, width) = SplitTrailingNumber(stem);

        for (var index = nextNumber; ; index++)
        {
            var number = width > 0 ? index.ToString($"D{width}") : index.ToString();
            var adjustedName = $"{prefix}{number}{extension}";
            var adjustedPath = Path.Combine(directory, adjustedName);
            if (!File.Exists(adjustedPath))
            {
                return adjustedPath;
            }
        }
    }

    private static (string Prefix, int NextNumber, int Width) SplitTrailingNumber(string stem)
    {
        var index = stem.Length - 1;
        while (index >= 0 && char.IsDigit(stem[index]))
        {
            index--;
        }

        if (index == stem.Length - 1)
        {
            return ($"{stem} ", 2, 0);
        }

        var prefix = stem[..(index + 1)];
        var numberText = stem[(index + 1)..];
        return (prefix, int.TryParse(numberText, out var number) ? number + 1 : 2, numberText.Length);
    }

    private static bool PathsEqual(string left, string right)
    {
        return string.Equals(
            Path.GetFullPath(left).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            Path.GetFullPath(right).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
            StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsVisibleDirectory(string path)
    {
        try
        {
            var attributes = File.GetAttributes(path);
            return attributes.HasFlag(FileAttributes.Directory) &&
                !attributes.HasFlag(FileAttributes.Hidden) &&
                !attributes.HasFlag(FileAttributes.System);
        }
        catch
        {
            return false;
        }
    }

    private static bool IsVisibleRegularFile(string path)
    {
        try
        {
            var attributes = File.GetAttributes(path);
            return !attributes.HasFlag(FileAttributes.Directory) &&
                !attributes.HasFlag(FileAttributes.Hidden) &&
                !attributes.HasFlag(FileAttributes.System);
        }
        catch
        {
            return false;
        }
    }

    private static void RememberBloggers(IEnumerable<RememberedBloggerPayload> bloggers)
    {
        var settings = BetaSettingsStore.Current;
        var merged = settings.RememberedBloggers
            .Where(blogger => !string.IsNullOrWhiteSpace(blogger.Username))
            .GroupBy(blogger => blogger.Username, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.Last(), StringComparer.OrdinalIgnoreCase);

        foreach (var blogger in bloggers)
        {
            if (string.IsNullOrWhiteSpace(blogger.Username))
            {
                continue;
            }
            merged[blogger.Username] = blogger;
        }

        settings.SetRememberedBloggers(merged.Values
            .OrderBy(blogger => blogger.CountryFolder, StringComparer.OrdinalIgnoreCase)
            .ThenBy(blogger => blogger.Username, StringComparer.OrdinalIgnoreCase));
    }
}

public sealed record SortingInput(
    string Id,
    string Blogger,
    string CurrentPath,
    string TargetRelativeFolder);

public sealed record SortedFileRecord(
    string Id,
    string Blogger,
    string CountryFolder,
    string TargetRelativeFolder,
    string CurrentPath);

public sealed record SortingResult(
    bool Success,
    string Summary,
    IReadOnlyList<SortedFileRecord> Records,
    IReadOnlyList<string> FailedItems)
{
    public static SortingResult Failed(string message) => new(false, message, Array.Empty<SortedFileRecord>(), Array.Empty<string>());
}
