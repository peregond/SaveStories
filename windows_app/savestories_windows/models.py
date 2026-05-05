from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(slots=True)
class WorkerRequest:
    command: str
    url: str | None = None
    urls: list[str] | None = None
    outputDirectory: str | None = None
    headless: bool | None = None
    mediaFilter: str | None = None


@dataclass(slots=True)
class WorkerItem:
    id: str
    sourceURL: str
    pageURL: str
    localPath: str
    metadataPath: str
    mediaType: str
    createdAt: str


@dataclass(slots=True)
class WorkerCounts:
    found: int = 0
    saved: int = 0
    processed: int = 0
    failed: int = 0


@dataclass(slots=True)
class WorkerBatchResult:
    url: str
    status: str
    message: str
    foundCount: int = 0
    savedCount: int = 0


@dataclass(slots=True)
class WorkerRuntime:
    kind: str = ""
    executable: str = ""
    browserProfile: str = ""
    playwrightBrowsers: str = ""
    manifests: str = ""


@dataclass(slots=True)
class WorkerResponse:
    ok: bool
    status: str
    message: str
    protocolVersion: int | None = None
    data: dict[str, str] = field(default_factory=dict)
    counts: WorkerCounts | None = None
    batchResults: list[WorkerBatchResult] = field(default_factory=list)
    runtime: WorkerRuntime | None = None
    diagnostics: dict[str, object] = field(default_factory=dict)
    items: list[WorkerItem] = field(default_factory=list)
    logs: list[str] = field(default_factory=list)

    @classmethod
    def process_failure(cls, message: str) -> "WorkerResponse":
        return cls(ok=False, status="process_error", message=message)


@dataclass(slots=True)
class BatchEntry:
    url: str
    status: str = "pending"
    message: str = "Ожидает запуска."

