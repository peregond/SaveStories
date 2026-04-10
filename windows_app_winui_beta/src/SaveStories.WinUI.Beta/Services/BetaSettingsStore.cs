using System.Text.Json;

namespace SaveStories.WinUI.Beta.Services;

public enum BetaTheme
{
    Dark,
    Light,
}

public sealed class BetaSettingsStore
{
    private const string FileName = "settings.json";
    private const int CurrentSchemaVersion = 2;
    private static readonly Lazy<BetaSettingsStore> LazyInstance = new(() => new BetaSettingsStore());

    private readonly string _settingsDirectory;
    private readonly string _settingsPath;

    public static BetaSettingsStore Current => LazyInstance.Value;

    public BetaTheme Theme { get; private set; } = BetaTheme.Dark;
    public bool RuntimePromptShown { get; private set; }
    public string LastUpdateCheckAt { get; private set; } = "";

    public event EventHandler<BetaTheme>? ThemeChanged;

    private BetaSettingsStore()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _settingsDirectory = Path.Combine(root, "SaveStories.WinUI.Beta");
        _settingsPath = Path.Combine(_settingsDirectory, FileName);
    }

    public void Load()
    {
        try
        {
            if (!File.Exists(_settingsPath))
            {
                return;
            }

            var json = File.ReadAllText(_settingsPath);
            var payload = JsonSerializer.Deserialize<SettingsPayload>(json);
            var schemaVersion = payload?.SchemaVersion ?? 1;
            Theme = ParseTheme(payload?.Theme);
            RuntimePromptShown = payload?.RuntimePromptShown ?? false;
            LastUpdateCheckAt = payload?.LastUpdateCheckAt ?? "";
            if (schemaVersion < CurrentSchemaVersion)
            {
                Save();
            }
        }
        catch
        {
            Theme = BetaTheme.Dark;
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
            Theme = Theme == BetaTheme.Light ? "light" : "dark",
            RuntimePromptShown = RuntimePromptShown,
            LastUpdateCheckAt = LastUpdateCheckAt,
        };
        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(_settingsPath, json);
    }

    private static BetaTheme ParseTheme(string? value)
    {
        return string.Equals(value, "light", StringComparison.OrdinalIgnoreCase)
            ? BetaTheme.Light
            : BetaTheme.Dark;
    }

    private sealed class SettingsPayload
    {
        public int SchemaVersion { get; set; } = CurrentSchemaVersion;
        public string? Theme { get; set; }
        public bool RuntimePromptShown { get; set; }
        public string? LastUpdateCheckAt { get; set; }
    }
}
