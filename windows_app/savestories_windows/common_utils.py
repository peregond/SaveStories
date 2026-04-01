from __future__ import annotations

import os
from pathlib import Path


def normalize_profile_link(raw: str) -> str:
    trimmed = raw.strip()
    if not trimmed:
        return trimmed
    if "instagram.com" in trimmed:
        return trimmed
    username = trimmed.strip("@/ ")
    return f"https://www.instagram.com/{username}/"


def parse_batch_links(raw: str) -> list[str]:
    links: list[str] = []
    for line in raw.splitlines():
        for part in line.split(","):
            value = part.strip()
            if value:
                links.append(normalize_profile_link(value))
    return links


def batch_status_title(value: str) -> str:
    mapping = {
        "pending": "В очереди",
        "running": "Скачивается",
        "completed": "Готово",
        "failed": "Ошибка",
        "stopped": "Остановлено",
    }
    return mapping.get(value, value)


def suggested_recent_list_title(urls: list[str]) -> str:
    if not urls:
        return "Недавний список"
    first = normalize_profile_link(urls[0]).rstrip("/").split("/")[-1] or "profiles"
    if len(urls) == 1:
        return first
    return f"{first} +{len(urls) - 1}"


def snapshot_download_counts(root: Path) -> tuple[int, int]:
    if not root.exists():
        return (0, 0)
    file_count = 0
    folder_count = 0
    media_suffixes = {".jpg", ".jpeg", ".png", ".webp", ".mp4", ".mov", ".m4v"}
    try:
        for _, directories, filenames in os.walk(root):
            folder_count += len(directories)
            file_count += sum(1 for name in filenames if Path(name).suffix.lower() in media_suffixes)
    except Exception:
        return (0, 0)
    return (file_count, folder_count)
