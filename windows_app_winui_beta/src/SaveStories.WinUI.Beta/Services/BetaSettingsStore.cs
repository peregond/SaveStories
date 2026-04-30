using System.Text.Json;

namespace SaveMe.WinUI.Beta.Services;

public enum BetaTheme
{
    System,
    Dark,
    Light,
}

public sealed class BetaSettingsStore
{
    private const string FileName = "settings.json";
    private const int CurrentSchemaVersion = 4;
    private static readonly Lazy<BetaSettingsStore> LazyInstance = new(() => new BetaSettingsStore());

    private readonly string _settingsDirectory;
    private readonly string _settingsPath;

    public static BetaSettingsStore Current => LazyInstance.Value;

    public BetaTheme Theme { get; private set; } = BetaTheme.System;
    public bool RuntimePromptShown { get; private set; }
    public string LastUpdateCheckAt { get; private set; } = "";
    public string SortingSourceDirectory { get; private set; } = "";
    public string SortingDestinationDirectory { get; private set; } = "";
    public string SortingRules { get; private set; } = "";
    public List<RememberedBloggerPayload> RememberedBloggers { get; private set; } = new();

    public event EventHandler<BetaTheme>? ThemeChanged;

    private BetaSettingsStore()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _settingsDirectory = Path.Combine(root, "SaveMe.WinUI");
        _settingsPath = Path.Combine(_settingsDirectory, FileName);
    }

    public void Load()
    {
        try
        {
            MigrateLegacyDirectoryIfNeeded();
            if (!File.Exists(_settingsPath))
            {
                return;
            }

            var json = File.ReadAllText(_settingsPath);
            var payload = JsonSerializer.Deserialize<SettingsPayload>(json);
            var schemaVersion = payload?.SchemaVersion ?? 1;
            Theme = ParseTheme(payload?.Theme);
            if (schemaVersion < 3)
            {
                Theme = BetaTheme.System;
            }
            RuntimePromptShown = payload?.RuntimePromptShown ?? false;
            LastUpdateCheckAt = payload?.LastUpdateCheckAt ?? "";
            SortingSourceDirectory = payload?.SortingSourceDirectory ?? "";
            SortingDestinationDirectory = payload?.SortingDestinationDirectory ?? "";
            SortingRules = payload?.SortingRules ?? "";
            RememberedBloggers = payload?.RememberedBloggers ?? new List<RememberedBloggerPayload>();
            if (schemaVersion < CurrentSchemaVersion)
            {
                Save();
            }
        }
        catch
        {
            Theme = BetaTheme.System;
            RuntimePromptShown = false;
            LastUpdateCheckAt = "";
            SortingSourceDirectory = "";
            SortingDestinationDirectory = "";
            SortingRules = "";
            RememberedBloggers = new List<RememberedBloggerPayload>();
        }
    }

    public void SetTheme(BetaTheme theme)
    {
        if (Theme == theme)
        {
            return;
        }

        Theme = theme;
        Save();
        ThemeChanged?.Invoke(this, Theme);
    }

    public string SettingsDirectory => _settingsDirectory;

    public void MarkRuntimePromptShown()
    {
        if (RuntimePromptShown)
        {
            return;
        }

        RuntimePromptShown = true;
        Save();
    }

    public void SetLastUpdateCheckAt(string isoDateTime)
    {
        LastUpdateCheckAt = isoDateTime ?? "";
        Save();
    }

    public void SetSortingSourceDirectory(string path)
    {
        SortingSourceDirectory = path ?? "";
        Save();
    }

    public void SetSortingDestinationDirectory(string path)
    {
        SortingDestinationDirectory = path ?? "";
        Save();
    }

    public void SetSortingRules(string rules)
    {
        SortingRules = rules ?? "";
        Save();
    }

    public void SetRememberedBloggers(IEnumerable<RememberedBloggerPayload> bloggers)
    {
        RememberedBloggers = bloggers.ToList();
        Save();
    }

    private void Save()
    {
        Directory.CreateDirectory(_settingsDirectory);
        var payload = new SettingsPayload
        {
            SchemaVersion = CurrentSchemaVersion,
            Theme = Theme switch
            {
                BetaTheme.Light => "light",
                BetaTheme.Dark => "dark",
                _ => "system",
            },
            RuntimePromptShown = RuntimePromptShown,
            LastUpdateCheckAt = LastUpdateCheckAt,
            SortingSourceDirectory = SortingSourceDirectory,
            SortingDestinationDirectory = SortingDestinationDirectory,
            SortingRules = SortingRules,
            RememberedBloggers = RememberedBloggers,
        };
        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(_settingsPath, json);
    }

    private static BetaTheme ParseTheme(string? value)
    {
        if (string.Equals(value, "light", StringComparison.OrdinalIgnoreCase))
        {
            return BetaTheme.Light;
        }

        if (string.Equals(value, "dark", StringComparison.OrdinalIgnoreCase))
        {
            return BetaTheme.Dark;
        }

        return BetaTheme.System;
    }

    private void MigrateLegacyDirectoryIfNeeded()
    {
        if (Directory.Exists(_settingsDirectory))
        {
            return;
        }

        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var legacyDirectories = new[]
        {
            Path.Combine(root, "SaveMe.WinUI.Beta"),
            Path.Combine(root, "SaveStories.WinUI.Beta"),
        };
        var legacyDirectory = legacyDirectories.FirstOrDefault(Directory.Exists);
        if (legacyDirectory is not null)
        {
            Directory.Move(legacyDirectory, _settingsDirectory);
        }
    }

    private sealed class SettingsPayload
    {
        public int SchemaVersion { get; set; } = CurrentSchemaVersion;
        public string? Theme { get; set; }
        public bool RuntimePromptShown { get; set; }
        public string? LastUpdateCheckAt { get; set; }
        public string? SortingSourceDirectory { get; set; }
        public string? SortingDestinationDirectory { get; set; }
        public string? SortingRules { get; set; }
        public List<RememberedBloggerPayload>? RememberedBloggers { get; set; }
    }
}

public sealed class RememberedBloggerPayload
{
    public string Username { get; set; } = "";
    public string CountryFolder { get; set; } = "";
    public string TargetFolder { get; set; } = "";
    public DateTimeOffset LastUsedAt { get; set; } = DateTimeOffset.Now;
}
