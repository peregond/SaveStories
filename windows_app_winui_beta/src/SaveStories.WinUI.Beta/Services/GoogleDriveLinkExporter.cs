using System.Runtime.InteropServices;

namespace SaveMe.WinUI.Beta.Services;

public sealed class GoogleDriveLinkExporter
{
    public Task<IReadOnlyList<GoogleDriveLinkOutcome>> ExportLinksAsync(IEnumerable<SortedFileRecord> records)
    {
        var snapshot = records.ToList();
        return Task.Run<IReadOnlyList<GoogleDriveLinkOutcome>>(() => snapshot
            .Select(record =>
            {
                try
                {
                    var link = MetadataLinkFor(record.CurrentPath);
                    return new GoogleDriveLinkOutcome(record, link, link is null ? "Google Drive metadata не найдена." : null);
                }
                catch (Exception ex)
                {
                    return new GoogleDriveLinkOutcome(record, null, ex.Message);
                }
            })
            .ToList());
    }

    private static string? MetadataLinkFor(string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath))
        {
            return null;
        }

        foreach (var streamName in EnumerateAlternateDataStreams(filePath))
        {
            if (!streamName.Contains("com.google.drivefs.item-id", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var adsPath = filePath + StreamPathSuffix(streamName);
            var itemId = File.ReadAllText(adsPath).Trim();
            if (!string.IsNullOrWhiteSpace(itemId))
            {
                return $"https://drive.google.com/open?id={itemId}";
            }
        }

        return null;
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
