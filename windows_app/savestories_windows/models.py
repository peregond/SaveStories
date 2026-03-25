from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(slots=True)
class WorkerRequest:
    command: str
    url: str | None = None
    urls: list[str] | None = None
    outputDirectory: str | None = None
    headless: bool | None = None


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
class WorkerResponse:
    ok: bool
    status: str
    message: str
    data: dict[str, str] = field(default_factory=dict)
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
