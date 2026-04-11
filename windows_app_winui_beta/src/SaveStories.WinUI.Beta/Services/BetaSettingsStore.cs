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
    private const int CurrentSchemaVersion = 3;
    private static readonly Lazy<BetaSettingsStore> LazyInstance = new(() => new BetaSettingsStore());

    private readonly string _settingsDirectory;
    private readonly string _settingsPath;

    public static BetaSettingsStore Current => LazyInstance.Value;

    public BetaTheme Theme { get; private set; } = BetaTheme.System;
    public bool RuntimePromptShown { get; private set; }
    public string LastUpdateCheckAt { get; private set; } = "";

    public event EventHandler<BetaTheme>? ThemeChanged;

    private BetaSettingsStore()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _settingsDirectory = Path.Combine(root, "SaveMe.WinUI.Beta");
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
        var legacyDirectory = Path.Combine(root, "SaveStories.WinUI.Beta");
        if (Directory.Exists(legacyDirectory))
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
    }
}
