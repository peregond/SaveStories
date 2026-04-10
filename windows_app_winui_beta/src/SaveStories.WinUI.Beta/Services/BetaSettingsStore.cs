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
    private static readonly Lazy<BetaSettingsStore> LazyInstance = new(() => new BetaSettingsStore());

    private readonly string _settingsDirectory;
    private readonly string _settingsPath;

    public static BetaSettingsStore Current => LazyInstance.Value;

    public BetaTheme Theme { get; private set; } = BetaTheme.Dark;

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
            Theme = ParseTheme(payload?.Theme);
        }
        catch
        {
            Theme = BetaTheme.Dark;
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

    private void Save()
    {
        Directory.CreateDirectory(_settingsDirectory);
        var payload = new SettingsPayload
        {
            Theme = Theme == BetaTheme.Light ? "light" : "dark",
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
        public string? Theme { get; set; }
    }
}
