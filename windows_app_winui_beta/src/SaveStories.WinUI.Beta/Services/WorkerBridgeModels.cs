using System.Text.Json.Serialization;

namespace SaveStories.WinUI.Beta.Services;

public sealed class WorkerRequest
{
    [JsonPropertyName("command")]
    public string Command { get; set; } = string.Empty;

    [JsonPropertyName("url")]
    public string? Url { get; set; }

    [JsonPropertyName("urls")]
    public List<string>? Urls { get; set; }

    [JsonPropertyName("outputDirectory")]
    public string? OutputDirectory { get; set; }

    [JsonPropertyName("headless")]
    public bool? Headless { get; set; }

    [JsonPropertyName("mediaFilter")]
    public string? MediaFilter { get; set; }
}

public sealed class WorkerItem
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("sourceURL")]
    public string SourceUrl { get; set; } = string.Empty;

    [JsonPropertyName("pageURL")]
    public string PageUrl { get; set; } = string.Empty;

    [JsonPropertyName("localPath")]
    public string LocalPath { get; set; } = string.Empty;

    [JsonPropertyName("metadataPath")]
    public string MetadataPath { get; set; } = string.Empty;

    [JsonPropertyName("mediaType")]
    public string MediaType { get; set; } = string.Empty;

    [JsonPropertyName("createdAt")]
    public string CreatedAt { get; set; } = string.Empty;
}

public sealed class WorkerResponse
{
    [JsonPropertyName("ok")]
    public bool Ok { get; set; }

    [JsonPropertyName("status")]
    public string Status { get; set; } = "unknown";

    [JsonPropertyName("message")]
    public string Message { get; set; } = string.Empty;

    [JsonPropertyName("data")]
    public Dictionary<string, string> Data { get; set; } = new();

    [JsonPropertyName("items")]
    public List<WorkerItem> Items { get; set; } = new();

    [JsonPropertyName("logs")]
    public List<string> Logs { get; set; } = new();
}

public sealed class WorkerRunResult
{
    public required WorkerResponse Response { get; init; }
    public required string StdoutRaw { get; init; }
    public required string StderrRaw { get; init; }
}
