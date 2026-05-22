using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace SaveMe.WinUI.Beta.Services;

public sealed class GoogleDriveLinkExporter
{
    private static readonly TimeSpan MetadataRetryDelay = TimeSpan.FromSeconds(2);
    private const int MetadataRetryCount = 15;

    public Task<IReadOnlyList<GoogleDriveLinkOutcome>> ExportLinksAsync(IEnumerable<SortedFileRecord> records)
    {
        var snapshot = records.ToList();
        return Task.Run<IReadOnlyList<GoogleDriveLinkOutcome>>(() =>
        {
            var links = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
            var errors = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
            var pending = snapshot.ToList();

            for (var attempt = 0; attempt <= MetadataRetryCount && pending.Count > 0; attempt++)
            {
                foreach (var record in pending.ToList())
                {
                    try
                    {
                        var link = MetadataLinkFor(record.CurrentPath);
                        links[record.CurrentPath] = link;
                        errors[record.CurrentPath] = link is null ? "Google Drive metadata не найдена." : null;
                        if (!string.IsNullOrWhiteSpace(link))
                        {
                            pending.Remove(record);
                        }
                    }
                    catch (Exception ex)
                    {
                        links[record.CurrentPath] = null;
                        errors[record.CurrentPath] = ex.Message;
                        pending.Remove(record);
                    }
                }

                if (pending.Count > 0 && attempt < MetadataRetryCount)
                {
                    Thread.Sleep(MetadataRetryDelay);
                }
            }

            return snapshot
                .Select(record => new GoogleDriveLinkOutcome(
                    record,
                    links.GetValueOrDefault(record.CurrentPath),
                    errors.GetValueOrDefault(record.CurrentPath) ?? "Google Drive metadata не найдена."))
                .ToList();
        });
    }

    private static string? MetadataLinkFor(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath))
        {
            return null;
        }

        foreach (var streamName in EnumerateAlternateDataStreams(filePath))
        {
            if (!streamName.Contains("com.google.drivefs.item-id", StringComparison.OrdinalIgnoreCase) &&
                !streamName.Contains("com.google.drivefs.url", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var metadata = ReadStreamText(filePath + StreamPathSuffix(streamName));
            var link = LinkFromMetadata(streamName, metadata);
            if (!string.IsNullOrWhiteSpace(link))
            {
                return link;
            }
        }

        return null;
    }

    private static string ReadStreamText(string adsPath)
    {
        return File.ReadAllText(adsPath).Trim('\0', '\r', '\n', '\t', ' ');
    }

    private static string? LinkFromMetadata(string streamName, string metadata)
    {
        if (string.IsNullOrWhiteSpace(metadata))
        {
            return null;
        }

        var driveUrl = Regex.Match(metadata, @"https://drive\.google\.com/[^\s""'<>]+", RegexOptions.IgnoreCase);
        if (driveUrl.Success)
        {
            return driveUrl.Value;
        }

        var openId = Regex.Match(metadata, @"(?:open\?id=|/file/d/|/folders/)([A-Za-z0-9_-]+)", RegexOptions.IgnoreCase);
        if (openId.Success)
        {
            return $"https://drive.google.com/open?id={openId.Groups[1].Value}";
        }

        if (streamName.Contains("com.google.drivefs.item-id", StringComparison.OrdinalIgnoreCase))
        {
            var itemId = metadata
                .Split(new[] { '\r', '\n', '\0' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .FirstOrDefault(IsGoogleDriveItemId);
            if (!string.IsNullOrWhiteSpace(itemId))
            {
                return $"https://drive.google.com/open?id={itemId}";
            }
        }

        return null;
    }

    private static bool IsGoogleDriveItemId(string value)
    {
        return value.Length >= 10 &&
            value.Length <= 128 &&
            value.All(character => char.IsLetterOrDigit(character) || character is '_' or '-');
    }

    private static string StreamPathSuffix(string streamName)
    {
        var suffix = streamName;
        if (suffix.EndsWith(":$DATA", StringComparison.OrdinalIgnoreCase))
        {
            suffix = suffix[..^":$DATA".Length];
        }
        return suffix.StartsWith(':') ? suffix : $":{suffix}";
    }

    private static IEnumerable<string> EnumerateAlternateDataStreams(string filePath)
    {
        var results = new List<string>();
        var handle = FindFirstStreamW(filePath, 0, out var data, 0);
        if (handle == InvalidHandleValue)
        {
            return results;
        }

        try
        {
            AddStreamName(data.cStreamName);
            while (FindNextStreamW(handle, out data))
            {
                AddStreamName(data.cStreamName);
            }
        }
        finally
        {
            FindClose(handle);
        }

        return results;

        void AddStreamName(string? name)
        {
            if (string.IsNullOrWhiteSpace(name) || string.Equals(name, "::$DATA", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }
            results.Add(name);
        }
    }

    private static readonly IntPtr InvalidHandleValue = new(-1);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr FindFirstStreamW(
        string lpFileName,
        int infoLevel,
        out Win32FindStreamData lpFindStreamData,
        int dwFlags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool FindNextStreamW(
        IntPtr hFindStream,
        out Win32FindStreamData lpFindStreamData);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FindClose(IntPtr hFindFile);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Win32FindStreamData
    {
        public long StreamSize;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 296)]
        public string cStreamName;
    }
}

public sealed record GoogleDriveLinkOutcome(
    SortedFileRecord Record,
    string? Link,
    string? ErrorMessage);
