using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SaveMe.WinUI.Beta.Services;

public sealed class WindowsUpdaterService
{
    private static readonly Lazy<WindowsUpdaterService> LazyInstance = new(() => new WindowsUpdaterService());
    private readonly HttpClient _http;
    private readonly string _updatesDirectory;
    private readonly UpdateConfiguration _config;
    private string? _preparedInstallerPath;
    private string? _preparedApplyLogPath;

    public static WindowsUpdaterService Current => LazyInstance.Value;

    private WindowsUpdaterService()
    {
        _http = new HttpClient();
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("SaveMe-WinUI-Updater");

        var root = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _updatesDirectory = Path.Combine(root, "SaveMe.WinUI.Beta", "updates");
        _config = LoadConfig();
    }

    public bool IsAvailable => !string.IsNullOrWhiteSpace(_config.WindowsLatestReleaseApi);

    public bool SupportsAutoInstall => true;

    public string Summary =>
        IsAvailable
            ? $"Проверяю релизы через GitHub API: {_config.WindowsLatestReleaseApi}"
            : "Проверка обновлений отключена: не найден адрес latest release API.";

    public async Task<UpdateCheckResult> CheckLatestReleaseAsync(string currentVersion, CancellationToken cancellationToken = default)
    {
        if (!IsAvailable)
        {
            return new UpdateCheckResult { Status = "disabled", Release = null };
        }

        using var request = new HttpRequestMessage(HttpMethod.Get, _config.WindowsLatestReleaseApi);
        request.Headers.Accept.ParseAdd("application/vnd.github+json");

        using var response = await _http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        var payload = await response.Content.ReadAsStringAsync(cancellationToken);
        using var document = JsonDocument.Parse(payload);
        var root = document.RootElement;

        var latestTag = root.TryGetProperty("tag_name", out var tagElement) ? tagElement.GetString() ?? "" : "";
        var latestVersion = latestTag.Trim().TrimStart('v', 'V');
        if (string.IsNullOrWhiteSpace(latestVersion))
        {
            throw new InvalidOperationException("GitHub API не вернул tag_name для latest release.");
        }

        if (VersionKey(latestVersion).CompareTo(VersionKey(currentVersion)) <= 0)
        {
            return new UpdateCheckResult { Status = "up_to_date", Release = null };
        }

        var asset = SelectReleaseAsset(root, latestTag);
        var notes = root.TryGetProperty("body", out var bodyElement) ? (bodyElement.GetString() ?? "") : "";
        var htmlUrl = root.TryGetProperty("html_url", out var htmlElement) ? (htmlElement.GetString() ?? "") : "";
        var title = root.TryGetProperty("name", out var nameElement) ? (nameElement.GetString() ?? latestTag) : latestTag;
        var publishedAt = root.TryGetProperty("published_at", out var publishedElement) ? (publishedElement.GetString() ?? "") : "";
        return new UpdateCheckResult
        {
            Status = "update_available",
            Release = new ReleaseInfo
            {
                Version = latestVersion,
                Tag = latestTag,
                Title = title,
                Notes = notes,
                HtmlUrl = htmlUrl,
                PublishedAt = publishedAt,
                Asset = asset,
            }
        };
    }

    public async Task<string> PrepareInstallAsync(
        ReleaseInfo release,
        IProgress<UpdateProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(_updatesDirectory);
        var updateRoot = Path.Combine(_updatesDirectory, release.Version);
        if (Directory.Exists(updateRoot))
        {
            Directory.Delete(updateRoot, recursive: true);
        }
        Directory.CreateDirectory(updateRoot);

        var installerPath = Path.Combine(updateRoot, release.Asset.Name);
        progress?.Report(new UpdateProgress(0, $"Скачивание обновления {release.Version}: 0%"));
        using (var response = await _http.GetAsync(release.Asset.Url, HttpCompletionOption.ResponseHeadersRead, cancellationToken))
        {
            response.EnsureSuccessStatusCode();
            var totalBytes = response.Content.Headers.ContentLength ?? release.Asset.Size;
            await using var source = await response.Content.ReadAsStreamAsync(cancellationToken);
            await using var target = File.Create(installerPath);

            var buffer = new byte[256 * 1024];
            long downloaded = 0;
            var lastPercent = -1;
            while (true)
            {
                var read = await source.ReadAsync(buffer, cancellationToken);
                if (read == 0)
                {
                    break;
                }
                await target.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
                downloaded += read;
                if (totalBytes > 0)
                {
                    var percent = (int)Math.Max(0, Math.Min(100, downloaded * 100 / totalBytes));
                    if (percent != lastPercent)
                    {
                        lastPercent = percent;
                        progress?.Report(new UpdateProgress(percent, $"Скачивание обновления {release.Version}: {percent}%"));
                    }
                }
            }
        }

        progress?.Report(new UpdateProgress(100, $"Скачивание обновления {release.Version}: 100%"));
        VerifyDigest(installerPath, release.Asset.Digest);

        var applyLogPath = Path.Combine(updateRoot, "apply_update.log");
        var installerLogPath = Path.Combine(updateRoot, "installer.log");
        File.WriteAllText(
            applyLogPath,
            $"Prepared installer: {installerPath}{Environment.NewLine}Installer log: {installerLogPath}{Environment.NewLine}"
        );
        _preparedInstallerPath = installerPath;
        _preparedApplyLogPath = applyLogPath;
        return $"Обновление {release.Version} подготовлено. Нажми «Установить обновление», чтобы применить его.";
    }

    public string LaunchPreparedInstall()
    {
        if (string.IsNullOrWhiteSpace(_preparedInstallerPath) || string.IsNullOrWhiteSpace(_preparedApplyLogPath))
        {
            throw new InvalidOperationException("Сначала подготовь обновление через кнопку «Скачать обновление».");
        }
        if (!File.Exists(_preparedInstallerPath))
        {
            throw new InvalidOperationException($"Установщик обновления не найден: {_preparedInstallerPath}");
        }

        var installerLogPath = Path.Combine(Path.GetDirectoryName(_preparedInstallerPath)!, "installer.log");
        var arguments = $"/SP- /CLOSEAPPLICATIONS /FORCECLOSEAPPLICATIONS /NORESTART /LOG=\"{installerLogPath}\"";
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = _preparedInstallerPath,
                Arguments = arguments,
                WorkingDirectory = Path.GetDirectoryName(_preparedInstallerPath),
                UseShellExecute = true,
                Verb = "runas",
            };
            _ = Process.Start(startInfo) ?? throw new InvalidOperationException("Не удалось запустить установщик.");
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException($"Не удалось запустить установщик обновления: {ex.Message}", ex);
        }

        File.AppendAllText(
            _preparedApplyLogPath,
            $"Launched installer: {_preparedInstallerPath}{Environment.NewLine}Installer args: {arguments}{Environment.NewLine}"
        );
        return _preparedApplyLogPath;
    }

    private static ReleaseAsset SelectReleaseAsset(JsonElement root, string latestTag)
    {
        if (!root.TryGetProperty("assets", out var assetsElement) || assetsElement.ValueKind != JsonValueKind.Array)
        {
            throw new InvalidOperationException("GitHub release не содержит assets.");
        }

        var normalizedTag = latestTag.Trim();
        var normalizedVersion = normalizedTag.TrimStart('v', 'V');
        var expected = new[]
        {
            $"SaveMe-Windows-WinUI-Beta-Setup-{normalizedTag}.exe",
            $"SaveMe-Windows-WinUI-Beta-Setup-v{normalizedVersion}.exe",
            $"SaveMe-WinUI-Beta-Setup-v{normalizedVersion}.exe",
            $"SaveStories-Windows-WinUI-Beta-Setup-{normalizedTag}.exe",
            $"SaveStories-Windows-WinUI-Beta-Setup-v{normalizedVersion}.exe",
            $"SaveStories-WinUI-Beta-Setup-v{normalizedVersion}.exe",
        };

        JsonElement? fallback = null;
        foreach (var asset in assetsElement.EnumerateArray())
        {
            var name = asset.TryGetProperty("name", out var nameElement) ? (nameElement.GetString() ?? "") : "";
            if (expected.Contains(name, StringComparer.OrdinalIgnoreCase))
            {
                return ParseAsset(asset);
            }
            if (fallback is null
                && (name.StartsWith("SaveMe-Windows-WinUI-Beta-Setup-", StringComparison.OrdinalIgnoreCase)
                    || name.StartsWith("SaveStories-Windows-WinUI-Beta-Setup-", StringComparison.OrdinalIgnoreCase))
                && name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            {
                fallback = asset;
            }
        }

        if (fallback.HasValue)
        {
            return ParseAsset(fallback.Value);
        }

        throw new InvalidOperationException("Не удалось найти установщик WinUI beta в assets релиза.");
    }

    private static ReleaseAsset ParseAsset(JsonElement asset)
    {
        var name = asset.TryGetProperty("name", out var nameElement) ? (nameElement.GetString() ?? "") : "";
        var url = asset.TryGetProperty("browser_download_url", out var urlElement) ? (urlElement.GetString() ?? "") : "";
        var size = asset.TryGetProperty("size", out var sizeElement) ? sizeElement.GetInt64() : 0;
        var digest = asset.TryGetProperty("digest", out var digestElement) ? (digestElement.GetString() ?? "") : "";
        return new ReleaseAsset
        {
            Name = name,
            Url = url,
            Size = size,
            Digest = digest,
        };
    }

    private static Version VersionKey(string value)
    {
        var parts = value.Trim().TrimStart('v', 'V').Split('.');
        var parsed = new List<int>();
        foreach (var part in parts)
        {
            var digits = new string(part.Where(char.IsDigit).ToArray());
            parsed.Add(int.TryParse(digits, out var number) ? number : 0);
        }
        while (parsed.Count < 3)
        {
            parsed.Add(0);
        }
        return new Version(parsed[0], parsed[1], parsed[2]);
    }

    private static void VerifyDigest(string installerPath, string digest)
    {
        if (!digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        var expected = digest.Split(':', 2)[1].Trim().ToLowerInvariant();
        using var stream = File.OpenRead(installerPath);
        var hash = SHA256.HashData(stream);
        var actual = Convert.ToHexString(hash).ToLowerInvariant();
        if (!string.Equals(expected, actual, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("SHA256 digest релиза не совпал. Обновление остановлено.");
        }
    }

    private static UpdateConfiguration LoadConfig()
    {
        var candidates = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "update_config.json"),
            Path.Combine(AppContext.BaseDirectory, "Resources", "update_config.json"),
        };

        var path = candidates.FirstOrDefault(File.Exists);
        if (path is null)
        {
            return new UpdateConfiguration();
        }

        var json = File.ReadAllText(path);
        var payload = JsonSerializer.Deserialize<UpdateConfiguration>(json) ?? new UpdateConfiguration();
        return payload;
    }
}

public sealed class UpdateCheckResult
{
    public required string Status { get; init; }
    public ReleaseInfo? Release { get; init; }
}

public sealed class ReleaseInfo
{
    public required string Version { get; init; }
    public required string Tag { get; init; }
    public required string Title { get; init; }
    public required string Notes { get; init; }
    public required string HtmlUrl { get; init; }
    public required string PublishedAt { get; init; }
    public required ReleaseAsset Asset { get; init; }
}

public sealed class ReleaseAsset
{
    public required string Name { get; init; }
    public required string Url { get; init; }
    public long Size { get; init; }
    public required string Digest { get; init; }
}

public readonly record struct UpdateProgress(int Percent, string Message);

public sealed class UpdateConfiguration
{
    [JsonPropertyName("repository")]
    public string Repository { get; set; } = "";
    [JsonPropertyName("macosFeedURL")]
    public string MacosFeedUrl { get; set; } = "";
    [JsonPropertyName("windowsLatestReleaseAPI")]
    public string WindowsLatestReleaseApi { get; set; } = "";
    [JsonPropertyName("publicEDKey")]
    public string PublicEdKey { get; set; } = "";
}
