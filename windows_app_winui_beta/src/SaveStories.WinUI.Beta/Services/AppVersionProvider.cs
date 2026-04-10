namespace SaveStories.WinUI.Beta.Services;

public static class AppVersionProvider
{
    public static string CurrentVersion()
    {
        var versionPath = Path.Combine(AppContext.BaseDirectory, "VERSION");
        if (File.Exists(versionPath))
        {
            var value = File.ReadAllText(versionPath).Trim();
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return "0.0.0";
    }
}
