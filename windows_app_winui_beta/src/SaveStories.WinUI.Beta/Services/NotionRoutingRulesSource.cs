using System.Text.Json;
using System.Text.RegularExpressions;

namespace SaveMe.WinUI.Beta.Services;

public sealed partial class NotionRoutingRulesSource
{
    public const string DefaultPageUrl = "https://narrow-park-cda.notion.site/366f65c3de6780e8bb03f4bdda65f5f8";

    private static readonly HttpClient Http = new();

    public async Task<string> FetchRulesAsync(
        string pageUrl = DefaultPageUrl,
        CancellationToken cancellationToken = default)
    {
        var pageId = PageIdFromUrl(pageUrl);
        var endpoint = ApiEndpointFromUrl(pageUrl);
        object cursor = new Dictionary<string, object?> { ["stack"] = Array.Empty<object>() };
        var chunkNumber = 0;
        var chunks = new List<string>();

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
            request.Headers.UserAgent.ParseAdd("SaveMe-WinUI-NotionRoutingRulesSource");

            using var response = await Http.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);

            var rules = ParseRules(document.RootElement);
            if (!string.IsNullOrWhiteSpace(rules))
            {
                chunks.Add(rules);
            }

            if (!TryGetNextCursor(document.RootElement, out cursor))
            {
                break;
            }

            chunkNumber++;
        }

        var lines = string.Join(Environment.NewLine, chunks)
            .Split(Environment.NewLine, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase);
        return string.Join(Environment.NewLine, lines);
    }

    public static string ParseRules(JsonElement root)
    {
        if (!root.TryGetProperty("recordMap", out var recordMap)
            || !recordMap.TryGetProperty("block", out var blocks)
            || blocks.ValueKind != JsonValueKind.Object)
        {
            return "";
        }

        var texts = new List<string>();
        foreach (var block in blocks.EnumerateObject())
        {
            if (block.Value.TryGetProperty("value", out var valueContainer)
                && valueContainer.TryGetProperty("value", out var value)
                && value.TryGetProperty("properties", out var properties)
                && properties.TryGetProperty("title", out var title))
            {
                texts.Add(NotionRichText(title));
            }
        }

        return NormalizeRules(string.Join(Environment.NewLine, texts));
    }

    public static string NormalizeRules(string text)
    {
        var rules = new List<string>();
        foreach (var rawLine in text.Split('\n', StringSplitOptions.TrimEntries))
        {
            var line = rawLine.Trim();
            if (line.Length == 0
                || line.Contains("Правила для сортировки", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var separator = line.IndexOf('=');
            if (separator < 0)
            {
                continue;
            }

            var left = line[..separator];
            var target = line[(separator + 1)..].Trim();
            if (target.Length == 0)
            {
                continue;
            }

            foreach (var username in NormalizedUsernames(left))
            {
                rules.Add($"{username} = {target}");
            }
        }

        return string.Join(Environment.NewLine, rules);
    }

    private static IEnumerable<string> NormalizedUsernames(string value)
    {
        foreach (var rawPart in value.Split(':', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            var part = ParentheticalRegex().Replace(rawPart, "");
            var cleaned = part.Trim().Trim('@', '*', '/', '\\', '.', ',', ';', ':', '!', '?', '[', ']', '{', '}', '<', '>', '"', '\'', '`');
            if (cleaned.Length > 0)
            {
                yield return cleaned;
            }
        }
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
            throw new InvalidOperationException("Некорректная ссылка на Notion-страницу с правилами.");
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

    [GeneratedRegex(@"\s*\([^)]*\)")]
    private static partial Regex ParentheticalRegex();
}
