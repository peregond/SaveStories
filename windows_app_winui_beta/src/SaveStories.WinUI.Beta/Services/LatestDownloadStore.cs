namespace SaveMe.WinUI.Beta.Services;

public sealed class LatestDownloadStore
{
    private static readonly Lazy<LatestDownloadStore> LazyInstance = new(() => new LatestDownloadStore());
    private readonly object _gate = new();
    private List<WorkerItem> _items = new();

    public static LatestDownloadStore Current => LazyInstance.Value;

    private LatestDownloadStore()
    {
    }

    public IReadOnlyList<WorkerItem> Items
    {
        get
        {
            lock (_gate)
            {
                return _items.Select(Clone).ToList();
            }
        }
    }

    public int Count
    {
        get
        {
            lock (_gate)
            {
                return _items.Count;
            }
        }
    }

    public void Replace(IEnumerable<WorkerItem> items)
    {
        lock (_gate)
        {
            _items = items
                .Where(item => !string.IsNullOrWhiteSpace(item.LocalPath))
                .GroupBy(item => string.IsNullOrWhiteSpace(item.Id) ? item.LocalPath : item.Id, StringComparer.OrdinalIgnoreCase)
                .Select(group => Clone(group.Last()))
                .ToList();
        }
    }

    public void UpdatePaths(IEnumerable<SortedFileRecord> records)
    {
        lock (_gate)
        {
            var pathsById = records
                .Where(record => !string.IsNullOrWhiteSpace(record.Id))
                .GroupBy(record => record.Id, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(group => group.Key, group => group.Last().CurrentPath, StringComparer.OrdinalIgnoreCase);

            _items = _items.Select(item =>
            {
                var key = string.IsNullOrWhiteSpace(item.Id) ? item.LocalPath : item.Id;
                if (!pathsById.TryGetValue(key, out var updatedPath))
                {
                    return item;
                }

                return Clone(item, updatedPath);
            }).ToList();
        }
    }

    private static WorkerItem Clone(WorkerItem item, string? localPath = null)
    {
        return new WorkerItem
        {
            Id = item.Id,
            SourceUrl = item.SourceUrl,
            PageUrl = item.PageUrl,
            LocalPath = localPath ?? item.LocalPath,
            MetadataPath = item.MetadataPath,
            MediaType = item.MediaType,
            CreatedAt = item.CreatedAt,
        };
    }
}
