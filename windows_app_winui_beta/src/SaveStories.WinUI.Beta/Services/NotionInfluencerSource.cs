using System.Text.Json;
using System.Text.RegularExpressions;

namespace SaveMe.WinUI.Beta.Services;

public sealed partial class NotionInfluencerSource
{
    public const string DefaultPageUrl = "https://narrow-park-cda.notion.site/334f65c3de678035bfecd4b7bf2a7fa7";

    private static readonly HttpClient Http = new();

    public async Task<IReadOnlyList<string>> FetchProfilesAsync(
        string pageUrl = DefaultPageUrl,
        CancellationToken cancellationToken = default)
    {
        var pageId = PageIdFromUrl(pageUrl);
        var endpoint = ApiEndpointFromUrl(pageUrl);
        object cursor = new Dictionary<string, object?> { ["stack"] = Array.Empty<object>() };
        var chunkNumber = 0;
        var profiles = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        while (chunkNumber < 10)
        {
            var payload = new Dictionary<string, object?>
            {
                ["pageId"] = pageId,
                ["limit"] = 100,
                ["cursor"] = cursor,
                ["chunkNumber"] = chunkNumber,
                ["verticalColumns"] = false,
            };
            using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
            {
                Content = new StringContent(JsonSerializer.Serialize(payload), System.Text.Encoding.UTF8, "application/json"),
            };
            request.Headers.UserAgent.ParseAdd("SaveMe-WinUI-NotionInfluencerSource");

            using var response = await Http.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);

            foreach (var profile in ParseProfiles(document.RootElement))
            {
                if (seen.Add(profile))
                {
                    profiles.Add(profile);
                }
            }

            if (!TryGetNextCursor(document.RootElement, out cursor))
            {
                break;
            }

            chunkNumber++;
        }

        return profiles;
    }

    public static IReadOnlyList<string> ParseProfiles(JsonElement root)
    {
        if (!root.TryGetProperty("recordMap", out var recordMap)
            || !recordMap.TryGetProperty("block", out var blocks)
            || blocks.ValueKind != JsonValueKind.Object)
        {
            return [];
        }

        var blockValues = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        foreach (var block in blocks.EnumerateObject())
        {
            if (block.Value.TryGetProperty("value", out var valueContainer)
                && valueContainer.TryGetProperty("value", out var value)
                && value.ValueKind == JsonValueKind.Object)
            {
                blockValues[block.Name] = value.Clone();
            }
        }

        var profiles = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        void CollectProfiles(JsonElement value)
        {
            if (!value.TryGetProperty("properties", out var properties)
                || !properties.TryGetProperty("title", out var title))
            {
                return;
            }

            foreach (var profile in ExtractProfiles(NotionRichText(title)))
            {
                if (seen.Add(profile))
                {
                    profiles.Add(profile);
                }
            }
        }

        void Visit(string id, bool includeSelf = true)
        {
            if (!visited.Add(id) || !blockValues.TryGetValue(id, out var value))
            {
                return;
            }

            if (includeSelf)
            {
                CollectProfiles(value);
            }

            if (!value.TryGetProperty("content", out var content) || content.ValueKind != JsonValueKind.Array)
            {
                return;
            }

            foreach (var child in content.EnumerateArray())
            {
                if (child.ValueKind == JsonValueKind.String)
                {
                    Visit(child.GetString() ?? "");
                }
            }
        }

        foreach (var page in blockValues.Where(pair =>
                     pair.Value.TryGetProperty("type", out var type)
                     && string.Equals(type.GetString(), "page", StringComparison.OrdinalIgnoreCase)))
        {
            Visit(page.Key, includeSelf: false);
        }

        foreach (var id in blockValues.Keys)
        {
            Visit(id);
        }

        return profiles;
    }

    public static IReadOnlyList<string> ExtractProfiles(string text)
    {
        var profiles = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        void AppendUsername(string raw)
        {
            var username = NormalizeInstagramUsername(raw);
            if (username is null)
            {
                return;
            }

            var url = $"https://www.instagram.com/{username}/";
            if (seen.Add(url))
            {
                profiles.Add(url);
            }
        }

        foreach (Match match in InstagramUrlRegex().Matches(text))
        {
            AppendUsername(match.Groups[1].Value);
        }

        foreach (Match match in InstagramHandleRegex().Matches(text))
        {
            AppendUsername(match.Groups[1].Value);
        }

        if (profiles.Count == 0)
        {
            foreach (var token in TokenSeparatorRegex().Split(text))
            {
                AppendUsername(token);
            }
        }

        return profiles;
    }

    private static string NotionRichText(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.String)
        {
            return value.GetString() ?? "";
        }

        if (value.ValueKind != JsonValueKind.Array)
        {
            return "";
        }

        var parts = new List<string>();
        foreach (var fragment in value.EnumerateArray())
        {
            if (fragment.ValueKind == JsonValueKind.String)
            {
                parts.Add(fragment.GetString() ?? "");
            }
            else if (fragment.ValueKind == JsonValueKind.Array && fragment.GetArrayLength() > 0)
            {
                var text = fragment[0];
                if (text.ValueKind == JsonValueKind.String)
                {
                    parts.Add(text.GetString() ?? "");
                }
            }
        }

        return string.Concat(parts);
    }

    private static bool TryGetNextCursor(JsonElement root, out object cursor)
    {
        cursor = new Dictionary<string, object?>();
        if (!root.TryGetProperty("cursor", out var cursorElement)
            || cursorElement.ValueKind != JsonValueKind.Object
            || !cursorElement.TryGetProperty("stack", out var stack)
            || stack.ValueKind != JsonValueKind.Array
            || stack.GetArrayLength() == 0)
        {
            return false;
        }

        cursor = JsonSerializer.Deserialize<object>(cursorElement.GetRawText()) ?? new Dictionary<string, object?>();
        return true;
    }

    private static string PageIdFromUrl(string pageUrl)
    {
        var match = Regex.Match(pageUrl, "[0-9a-fA-F]{32}");
        if (!match.Success)
        {
            throw new InvalidOperationException("Некорректная ссылка на Notion-страницу.");
        }

        var compact = match.Value.ToLowerInvariant();
        return string.Join(
            "-",
            compact[..8],
            compact[8..12],
            compact[12..16],
            compact[16..20],
            compact[20..]);
    }

    private static string ApiEndpointFromUrl(string pageUrl)
    {
        var uri = new Uri(pageUrl);
        return $"{uri.Scheme}://{uri.Host}/api/v3/loadCachedPageChunk";
    }

    private static string? NormalizeInstagramUsername(string raw)
    {
        var username = raw
            .Trim()
            .Trim('@', '*', '/', '\\', '.', ',', ';', ':', '!', '?', '(', ')', '[', ']', '{', '}', '<', '>', '"', '\'', '`');

        if (!InstagramUsernameRegex().IsMatch(username))
        {
            return null;
        }

        var blocked = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "instagram",
            "profile",
            "profiles",
            "username",
            "user",
            "name",
            "link",
            "links",
        };
        return blocked.Contains(username) ? null : username;
    }

    [GeneratedRegex(@"https?://(?:www\.)?instagram\.com/([A-Za-z0-9._]{1,30})(?:/|\b)", RegexOptions.IgnoreCase)]
    private static partial Regex InstagramUrlRegex();

    [GeneratedRegex(@"(?<![A-Za-z0-9._])@([A-Za-z0-9._]{1,30})(?![A-Za-z0-9._])")]
    private static partial Regex InstagramHandleRegex();

    [GeneratedRegex(@"[\s,;]+")]
    private static partial Regex TokenSeparatorRegex();

    [GeneratedRegex(@"^[A-Za-z0-9._]{1,30}$")]
    private static partial Regex InstagramUsernameRegex();
}
