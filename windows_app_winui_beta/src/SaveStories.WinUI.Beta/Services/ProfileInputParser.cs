using System.Text.RegularExpressions;

namespace SaveMe.WinUI.Beta.Services;

public static partial class ProfileInputParser
{
    public static IReadOnlyList<string> ParseProfiles(string? input)
    {
        if (string.IsNullOrWhiteSpace(input))
        {
            return [];
        }

        var profiles = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var token in ProfileTokenSeparator().Split(input))
        {
            var normalized = NormalizeProfile(token);
            if (normalized is null || !seen.Add(normalized))
            {
                continue;
            }

            profiles.Add(normalized);
        }

        return profiles;
    }

    public static string? NormalizeProfile(string? raw)
    {
        var value = CleanToken(raw);
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        if (value.Contains("instagram.com", StringComparison.OrdinalIgnoreCase))
        {
            return NormalizeInstagramUrl(value);
        }

        var username = CleanUsername(value);
        return username.Length == 0 ? null : $"https://www.instagram.com/{username}/";
    }

    private static string? NormalizeInstagramUrl(string value)
    {
        var candidate = value.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || value.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                ? value
                : $"https://{value}";

        if (!Uri.TryCreate(candidate, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps)
            || !(uri.Host.Equals("instagram.com", StringComparison.OrdinalIgnoreCase)
                || uri.Host.EndsWith(".instagram.com", StringComparison.OrdinalIgnoreCase)))
        {
            return null;
        }

        var segments = uri.AbsolutePath
            .Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (segments.Length == 0)
        {
            return null;
        }

        var usernameSegment = segments[0];
        if (usernameSegment.Equals("stories", StringComparison.OrdinalIgnoreCase))
        {
            if (segments.Length < 2 || segments[1].Equals("highlights", StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }
            usernameSegment = segments[1];
        }
        else if (usernameSegment.Equals("reel", StringComparison.OrdinalIgnoreCase)
            || usernameSegment.Equals("reels", StringComparison.OrdinalIgnoreCase)
            || usernameSegment.Equals("p", StringComparison.OrdinalIgnoreCase)
            || usernameSegment.Equals("tv", StringComparison.OrdinalIgnoreCase)
            || usernameSegment.Equals("explore", StringComparison.OrdinalIgnoreCase)
            || usernameSegment.Equals("accounts", StringComparison.OrdinalIgnoreCase)
            || usernameSegment.Equals("direct", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var username = CleanUsername(usernameSegment);
        return username.Length == 0 ? null : $"https://www.instagram.com/{username}/";
    }

    private static string CleanToken(string? raw)
    {
        return (raw ?? string.Empty)
            .Trim()
            .Trim('<', '>', '"', '\'', '`', '(', ')', '[', ']', '{', '}', ',', ';');
    }

    private static string CleanUsername(string raw)
    {
        var username = CleanToken(raw)
            .TrimStart('@')
            .Trim('*', ',', ';', ':', '!', '?', '/', '\\');

        return InstagramUsernameChars().Replace(username, string.Empty);
    }

    [GeneratedRegex(@"[\s,;]+")]
    private static partial Regex ProfileTokenSeparator();

    [GeneratedRegex(@"[^A-Za-z0-9._]")]
    private static partial Regex InstagramUsernameChars();
}
