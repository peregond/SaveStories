#!/usr/bin/env python3

from __future__ import annotations

import json
import mimetypes
import os
import platform
import re
import sys
import time
import urllib.parse
import urllib.request
import uuid
import base64
import threading
from datetime import datetime, timezone
from hashlib import sha256
from importlib import metadata
from pathlib import Path
from typing import Any


def emit(ok: bool, status: str, message: str, *, data: dict[str, str] | None = None,
         items: list[dict[str, str]] | None = None, logs: list[str] | None = None) -> None:
    payload = {
        "ok": ok,
        "status": status,
        "message": message,
        "data": data or {},
        "items": items or [],
        "logs": logs or [],
    }
    sys.stdout.write(json.dumps(payload))
    sys.stdout.flush()


def read_request() -> dict[str, Any]:
    raw = sys.stdin.read().strip()
    if not raw:
        raise RuntimeError("Worker received an empty request.")
    return json.loads(raw)


def env_path(name: str, fallback: Path) -> Path:
    value = os.environ.get(name)
    if value:
        return Path(value).expanduser()
    return fallback


def can_write(directory: Path) -> bool:
    candidate = directory
    while candidate != candidate.parent:
        if candidate.exists():
            return os.access(candidate, os.W_OK)
        candidate = candidate.parent
    return False


def current_platform() -> str:
    return platform.system().lower()


def preferred_app_support_path() -> Path:
    system = current_platform()
    if system == "darwin":
        return Path.home() / "Library" / "Application Support" / "DimaSave"
    if system == "windows":
        root = os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA")
        if root:
            return Path(root) / "DimaSave"
        return Path.home() / "AppData" / "Local" / "DimaSave"
    return Path.home() / ".local" / "share" / "DimaSave"


def preferred_downloads_path() -> Path:
    system = current_platform()
    if system == "windows":
        root = os.environ.get("USERPROFILE")
        if root:
            return Path(root) / "Downloads" / "DimaSave"
    return Path.home() / "Downloads" / "DimaSave"


def default_app_support() -> Path:
    preferred = preferred_app_support_path()
    if can_write(preferred.parent):
        return preferred
    return Path.cwd() / ".runtime" / "DimaSave"


def default_downloads(app_support: Path) -> Path:
    preferred = preferred_downloads_path()
    if can_write(preferred.parent):
        return preferred
    return app_support / "Downloads"


APP_SUPPORT = env_path(
    "DIMASAVE_APP_SUPPORT",
    default_app_support(),
)
WORKER_ROOT = APP_SUPPORT / "worker"
BROWSER_PROFILE = env_path(
    "DIMASAVE_BROWSER_PROFILE",
    WORKER_ROOT / "browser-profile",
)
PLAYWRIGHT_BROWSERS = env_path(
    "DIMASAVE_PLAYWRIGHT_BROWSERS",
    WORKER_ROOT / "ms-playwright",
)
MANIFESTS_DIRECTORY = env_path(
    "DIMASAVE_MANIFESTS",
    APP_SUPPORT / "manifests",
)
SESSION_STATE = env_path(
    "DIMASAVE_SESSION_STATE",
    WORKER_ROOT / "storage-state.json",
)
DEFAULT_DOWNLOADS = env_path(
    "DIMASAVE_DEFAULT_DOWNLOADS",
    default_downloads(APP_SUPPORT),
)
BATCH_VISIBLE_CHUNK_SIZE = 5
BATCH_BACKGROUND_CHUNK_SIZE = 5


def ensure_directories() -> None:
    APP_SUPPORT.mkdir(parents=True, exist_ok=True)
    WORKER_ROOT.mkdir(parents=True, exist_ok=True)
    BROWSER_PROFILE.mkdir(parents=True, exist_ok=True)
    PLAYWRIGHT_BROWSERS.mkdir(parents=True, exist_ok=True)
    MANIFESTS_DIRECTORY.mkdir(parents=True, exist_ok=True)
    DEFAULT_DOWNLOADS.mkdir(parents=True, exist_ok=True)


def chunked(values: list[str], size: int) -> list[list[str]]:
    if size <= 0:
        return [values]
    return [values[index:index + size] for index in range(0, len(values), size)]


def batch_failure_result(url: str, message: str) -> dict[str, Any]:
    return {
        "url": url,
        "status": "failed",
        "message": message,
        "foundCount": 0,
        "savedCount": 0,
    }


def close_session_with_timeout(session: "BrowserSession", logs: list[str] | None = None, timeout_seconds: float = 5.0) -> None:
    if session is None:
        return

    error_holder: list[BaseException] = []

    def worker() -> None:
        try:
            session.close()
        except BaseException as exc:  # pragma: no cover - cleanup path
            error_holder.append(exc)

    thread = threading.Thread(target=worker, daemon=True)
    thread.start()
    thread.join(timeout_seconds)

    if thread.is_alive():
        if logs is not None:
            logs.append(f"session_close_timeout={timeout_seconds}")
        return

    if error_holder and logs is not None:
        logs.append(f"session_close_error={error_holder[0]}")


def import_playwright():
    try:
        from playwright.sync_api import sync_playwright
        return sync_playwright
    except Exception as exc:  # pragma: no cover - direct runtime dependency path
        raise RuntimeError(
            "Playwright не установлен. Подготовьте среду в настройках приложения."
        ) from exc


class StoryMedia:
    def __init__(
        self,
        source_url: str,
        media_type: str,
        page_url: str,
        poster_url: str | None = None,
        captured_at: float = 0.0,
        width: int = 0,
        height: int = 0,
    ) -> None:
        self.source_url = source_url
        self.media_type = media_type
        self.page_url = page_url
        self.poster_url = poster_url
        self.captured_at = captured_at
        self.width = width
        self.height = height


class ResolvedStoryItem:
    def __init__(
        self,
        item_id: str,
        username: str,
        page_url: str,
        source_url: str,
        media_type: str,
        taken_at: int = 0,
    ) -> None:
        self.item_id = item_id
        self.username = username
        self.page_url = page_url
        self.source_url = source_url
        self.media_type = media_type
        self.taken_at = taken_at


class BrowserSession:
    def __init__(
        self,
        playwright: Any,
        context: Any,
        browser: Any | None = None,
        background: bool = False,
    ) -> None:
        self.playwright = playwright
        self.context = context
        self.browser = browser
        self.background = background

    def first_page(self):
        return self.context.pages[0] if self.context.pages else self.context.new_page()

    def close(self) -> None:
        try:
            self.context.close()
        finally:
            if self.browser is not None:
                self.browser.close()
            self.playwright.stop()


def environment_command() -> None:
    ensure_directories()
    logs = [
        f"app_support={APP_SUPPORT}",
        f"browser_profile={BROWSER_PROFILE}",
        f"playwright_browsers={PLAYWRIGHT_BROWSERS}",
        f"session_state={SESSION_STATE}",
        f"manifests={MANIFESTS_DIRECTORY}",
        f"default_downloads={DEFAULT_DOWNLOADS}",
        f"python={sys.executable}",
    ]

    try:
        version = metadata.version("playwright")
        logs.append(f"playwright={version}")
        emit(
            True,
            "environment_ready",
            "Среда воркера готова. Пакет Playwright установлен.",
            data={
                "python": sys.executable,
                "playwrightInstalled": "true",
                "browserProfile": str(BROWSER_PROFILE),
                "playwrightBrowsers": str(PLAYWRIGHT_BROWSERS),
                "sessionState": str(SESSION_STATE),
                "manifests": str(MANIFESTS_DIRECTORY),
            },
            logs=logs,
        )
    except Exception:
        emit(
            False,
            "environment_missing",
            "Playwright не найден. Подготовьте среду в настройках приложения, чтобы установить Chromium.",
            data={
                "python": sys.executable,
                "playwrightInstalled": "false",
                "browserProfile": str(BROWSER_PROFILE),
                "playwrightBrowsers": str(PLAYWRIGHT_BROWSERS),
                "sessionState": str(SESSION_STATE),
                "manifests": str(MANIFESTS_DIRECTORY),
            },
            logs=logs,
        )


def launch_context(headless: bool = False):
    os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", str(PLAYWRIGHT_BROWSERS))
    sync_playwright = import_playwright()
    playwright = sync_playwright().start()
    executable_path = resolve_chromium_executable()
    executable = str(executable_path) if executable_path is not None else None
    launch_options: dict[str, Any] = {
        "user_data_dir": str(BROWSER_PROFILE),
        "headless": bool(headless),
        "viewport": {"width": 1440, "height": 940},
        "accept_downloads": True,
    }
    if executable is not None:
        launch_options["executable_path"] = executable

    context = playwright.chromium.launch_persistent_context(**launch_options)
    return BrowserSession(playwright=playwright, context=context, background=headless)


def resolve_chromium_executable() -> Path | None:
    patterns = [
        "chromium-*/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
        "chromium-*/chrome-mac/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
        "chromium-*/chrome-win/chrome.exe",
        "chromium-*/chrome-win64/chrome.exe",
        "chromium-*/chrome-linux/chrome",
    ]

    for pattern in patterns:
        matches = sorted(PLAYWRIGHT_BROWSERS.glob(pattern))
        for candidate in matches:
            if candidate.is_file():
                return candidate

    return None


def persist_session_state(context, logs: list[str] | None = None) -> None:
    try:
        SESSION_STATE.parent.mkdir(parents=True, exist_ok=True)
        context.storage_state(path=str(SESSION_STATE))
        if logs is not None:
            logs.append(f"storage_state_saved={SESSION_STATE}")
    except Exception as exc:
        if logs is not None:
            logs.append(f"storage_state_error={exc}")


def prepare_background_window(session: BrowserSession, page, logs: list[str] | None = None) -> None:
    if not session.background:
        return

    try:
        cdp = page.context.new_cdp_session(page)
        window_info = cdp.send("Browser.getWindowForTarget")
        window_id = window_info.get("windowId")
        if window_id is not None:
            cdp.send(
                "Browser.setWindowBounds",
                {"windowId": window_id, "bounds": {"windowState": "minimized"}},
            )
            if logs is not None:
                logs.append("background_window=minimized")
    except Exception as exc:
        if logs is not None:
            logs.append(f"background_window_error={exc}")


def has_active_instagram_session(context) -> bool:
    try:
        cookies = context.cookies()
    except Exception:
        return False

    for cookie in cookies:
        name = str(cookie.get("name", "")).lower()
        value = str(cookie.get("value", ""))
        domain = str(cookie.get("domain", "")).lower()
        if name == "sessionid" and value and "instagram.com" in domain:
            return True

    return False


def is_logged_in(page) -> bool:
    if has_active_instagram_session(page.context):
        return True

    try:
        if page.locator('input[name="username"], input[name="password"]').count() > 0:
            return False
    except Exception:
        pass

    try:
        if page.locator(
            'a[href="/direct/inbox/"], a[href="/accounts/edit/"], svg[aria-label="Home"], svg[aria-label="Домой"]'
        ).count() > 0:
            return True
    except Exception:
        pass

    lowered_url = page.url.lower()
    if "/accounts/login" in lowered_url or "login" in lowered_url:
        return False

    if "/challenge/" in lowered_url or "/checkpoint/" in lowered_url:
        return False

    return False


def wait_for_login(page, timeout_seconds: int = 600) -> bool:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        page.wait_for_timeout(1000)
        if is_logged_in(page):
            return True
    return False


def login_command() -> None:
    ensure_directories()
    logs: list[str] = []
    session = None

    try:
        session = launch_context(headless=False)
        page = session.first_page()
        page.goto("https://www.instagram.com/accounts/login/", wait_until="domcontentloaded")
        page.wait_for_timeout(1500)
        logs.append(f"opened={page.url}")

        if is_logged_in(page):
            emit(
                True,
                "already_logged_in",
                "Сохранённая сессия Instagram уже существует.",
                data={"loggedIn": "true", "currentURL": page.url},
                logs=logs,
            )
            return

        logged_in = wait_for_login(page)
        if not logged_in:
            emit(
                False,
                "login_timeout",
                "Браузер для входа был открыт, но до истечения таймаута активная сессия Instagram не появилась.",
                data={"loggedIn": "false", "currentURL": page.url},
                logs=logs,
            )
            return

        persist_session_state(page.context, logs)
        emit(
            True,
            "login_ready",
            "Сессия Instagram обнаружена и сохранена в постоянном профиле браузера.",
            data={"loggedIn": "true", "currentURL": page.url},
            logs=logs,
        )
    except Exception as exc:
        emit(False, "login_error", str(exc), logs=logs)
    finally:
        if session:
            close_session_with_timeout(session)


def check_session_command(headless: bool = True) -> None:
    ensure_directories()
    logs: list[str] = []
    session = None

    try:
        session = launch_context(headless=headless)
        page = session.first_page()
        prepare_background_window(session, page, logs)
        page.goto("https://www.instagram.com/", wait_until="domcontentloaded")
        logged_in = is_logged_in(page)
        logs.append(f"checked={page.url}")

        if logged_in:
            persist_session_state(page.context, logs)
            emit(
                True,
                "session_ready",
                "Сессия Instagram выглядит действительной.",
                data={"loggedIn": "true", "currentURL": page.url},
                logs=logs,
            )
        else:
            emit(
                False,
                "session_missing",
                "Активная сессия Instagram не найдена. Сначала откройте браузер для входа.",
                data={"loggedIn": "false", "currentURL": page.url},
                logs=logs,
            )
    except Exception as exc:
        emit(False, "session_error", str(exc), logs=logs)
    finally:
        if session:
            close_session_with_timeout(session)


def sanitize_filename(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-")
    cleaned = cleaned.rstrip(" .")
    reserved = {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
    }
    if cleaned.upper() in reserved:
        cleaned = f"_{cleaned}"
    return cleaned or "story"


def extension_for(content_type: str | None, url: str, media_type: str) -> str:
    if content_type:
        guessed = mimetypes.guess_extension(content_type.split(";")[0].strip())
        if guessed:
            return guessed

    parsed = urllib.parse.urlparse(url)
    suffix = Path(parsed.path).suffix
    if suffix:
        return suffix

    return ".mp4" if media_type == "video" else ".jpg"


def normalize_media_url(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    query = urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
    filtered = [(key, value) for key, value in query if key not in {"bytestart", "byteend"}]
    normalized_query = urllib.parse.urlencode(filtered)
    return urllib.parse.urlunparse(parsed._replace(query=normalized_query))


def looks_like_fragmented_mp4(body: bytes) -> bool:
    prefix = body[:64]
    return b"moof" in prefix and b"ftyp" not in prefix


def fetch_media_bytes(
    source_url: str,
    *,
    browser_context: Any | None = None,
    referer_url: str | None = None,
) -> tuple[bytes, str | None]:
    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
    }
    if referer_url:
        headers["Referer"] = referer_url

    context_request = getattr(browser_context, "request", None) if browser_context is not None else None
    if context_request is not None:
        response = context_request.get(
            source_url,
            headers=headers,
            timeout=60_000,
            fail_on_status_code=True,
            ignore_https_errors=True,
            max_retries=1,
        )
        content_type = response.headers.get("content-type")
        body = response.body()
        return body, content_type

    request = urllib.request.Request(source_url, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        content_type = response.headers.get("Content-Type")
        body = response.read()

    return body, content_type


def download_media(
    source_url: str,
    destination_dir: Path,
    media_type: str,
    username: str,
    index: int,
    *,
    browser_context: Any | None = None,
    referer_url: str | None = None,
) -> tuple[Path, str]:
    destination_dir.mkdir(parents=True, exist_ok=True)
    normalized_url = normalize_media_url(source_url)

    body, content_type = fetch_media_bytes(
        normalized_url,
        browser_context=browser_context,
        referer_url=referer_url,
    )

    if media_type == "video" and looks_like_fragmented_mp4(body):
        raise RuntimeError("Скачан только фрагмент видео вместо полного файла.")

    suffix = extension_for(content_type, normalized_url, media_type)
    filename = f"{sanitize_filename(username)}-{index:03d}{suffix}"
    path = destination_dir / filename
    path.write_bytes(body)
    return path, normalized_url


def write_manifest(item_id: str, page_url: str, source_url: str, local_path: Path, media_type: str, created_at: str) -> Path:
    payload = {
        "id": item_id,
        "createdAt": created_at,
        "pageURL": page_url,
        "sourceURL": source_url,
        "localPath": str(local_path),
        "mediaType": media_type,
        "sha256": sha256(local_path.read_bytes()).hexdigest(),
    }
    manifest_path = MANIFESTS_DIRECTORY / f"{item_id}.json"
    manifest_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    return manifest_path


def is_story_media_url(url: str) -> bool:
    lowered = url.lower()
    parsed = urllib.parse.urlparse(url)
    host = parsed.netloc.lower()
    path = parsed.path.lower()
    query = parsed.query.lower()

    if not lowered.startswith("http"):
        return False

    if "static.cdninstagram.com" in host:
        return False

    if "rsrc.php" in path:
        return False

    if "profile_pic" in lowered or "profilepic" in lowered:
        return False

    excluded_tokens = [
        "s100x100",
        "s150x150",
        "s240x240",
        "s320x320",
        "dst-jpg_s",
        "ig_app_icon",
        "favicon",
        "avatar",
    ]
    if any(token in lowered or token in query for token in excluded_tokens):
        return False

    allowed_hosts = ["scontent", "fbcdn", "cdninstagram", "video"]
    if not any(token in host for token in allowed_hosts):
        return False

    return True


def decode_efg_payload(url: str) -> dict[str, Any]:
    parsed = urllib.parse.urlparse(url)
    query = dict(urllib.parse.parse_qsl(parsed.query, keep_blank_values=True))
    encoded = query.get("efg")
    if not encoded:
        return {}

    try:
        padded = encoded + "=" * (-len(encoded) % 4)
        decoded = base64.urlsafe_b64decode(padded.encode("utf-8"))
        payload = json.loads(decoded.decode("utf-8"))
        if isinstance(payload, dict):
            return payload
    except Exception:
        return {}

    return {}


def media_variant_tag(url: str) -> str:
    payload = decode_efg_payload(url)
    tag = payload.get("vencode_tag")
    if isinstance(tag, str):
        return tag.lower()
    return ""


def is_audio_only_variant(url: str) -> bool:
    tag = media_variant_tag(url)
    if not tag:
        return False

    if "_audio" in tag:
        return True

    return tag.endswith("audio")


def should_skip_media_variant(url: str) -> bool:
    tag = media_variant_tag(url)
    if not tag:
        lowered = url.lower()
        return "clips" in lowered or "reel" in lowered

    if is_audio_only_variant(url):
        return True

    if "dash_vp9-basic" in tag or "vp9-basic" in tag:
        return True

    if "clips" in tag or "reel" in tag:
        return True

    return False


def media_variant_score(url: str, media_type: str) -> int:
    tag = media_variant_tag(url)
    lowered = url.lower()
    score = 0

    if media_type == "image":
        if "story" in tag:
            score += 50
        if "profile_pic" in tag:
            score -= 100
        return score

    if "story" in tag:
        score += 100
    if "xpv_progressive" in tag or "progressive" in tag:
        score += 180
    if is_audio_only_variant(url):
        score -= 500
    if "clips" in tag or "reel" in tag:
        score -= 200
    if "audio" in tag or "aac" in tag or "haac" in tag:
        score -= 30
    if "avc" in tag or "h264" in tag:
        score += 120
    if "hevc" in tag or "h265" in tag:
        score += 60
    if "vp9-basic" in tag:
        score -= 180
    if "vp9" in tag:
        score -= 120
    if "dash_ln" in tag:
        score -= 30
    if "dash" in tag and "audio" not in tag:
        score -= 20
    if "dashinit" in lowered or "video_dashinit" in lowered:
        score -= 240
    if "_nc_vs=" in lowered or "vs=" in lowered:
        score += 70

    return score


def install_json_capture(page, logs: list[str]) -> list[dict[str, Any]]:
    payloads: list[dict[str, Any]] = []

    def on_response(response) -> None:
        try:
            content_type = response.headers.get("content-type", "").lower()
            url = response.url.lower()
            if "json" not in content_type:
                return

            if not any(token in url for token in ["story", "reel", "graphql", "feed", "api"]):
                return

            payload = response.json()
            if not isinstance(payload, (dict, list)):
                return

            payloads.append(
                {
                    "url": response.url,
                    "captured_at": time.time(),
                    "payload": payload,
                }
            )
        except Exception as exc:
            logs.append(f"json_capture_error={exc}")

    page.on("response", on_response)
    return payloads


def media_candidate_area(candidate: dict[str, Any]) -> int:
    width = int(candidate.get("width", 0) or 0)
    height = int(candidate.get("height", 0) or 0)
    return width * height


def candidate_dimensions(candidate: dict[str, Any], item: dict[str, Any] | None = None) -> tuple[int, int]:
    width = int(candidate.get("width", 0) or 0)
    height = int(candidate.get("height", 0) or 0)
    if width > 0 and height > 0:
        return width, height

    if item:
        item_width = int(item.get("original_width", 0) or item.get("width", 0) or 0)
        item_height = int(item.get("original_height", 0) or item.get("height", 0) or 0)
        if item_width > 0 and item_height > 0:
            return item_width, item_height

        dimensions = item.get("dimensions")
        if isinstance(dimensions, dict):
            item_width = int(dimensions.get("width", 0) or 0)
            item_height = int(dimensions.get("height", 0) or 0)
            if item_width > 0 and item_height > 0:
                return item_width, item_height

    return width, height


def candidate_story_ratio(width: int, height: int) -> float:
    if width <= 0 or height <= 0:
        return 0
    return width / height


def is_story_ratio(width: int, height: int, *, strict: bool = True) -> bool:
    if width <= 0 or height <= 0:
        return False

    if height <= width:
        return False

    ratio = candidate_story_ratio(width, height)
    min_ratio = 0.52 if strict else 0.46
    max_ratio = 0.60 if strict else 0.68
    min_width = 320 if strict else 180
    min_height = 560 if strict else 280

    return min_ratio <= ratio <= max_ratio and width >= min_width and height >= min_height


def story_ratio_bonus(width: int, height: int) -> int:
    ratio = candidate_story_ratio(width, height)
    if ratio <= 0:
        return -300

    distance = abs(ratio - 0.5625)
    if distance <= 0.01:
        return 140
    if distance <= 0.025:
        return 90
    if distance <= 0.04:
        return 45
    return -20


def response_url_likely_story(url: str) -> bool:
    lowered = url.lower()
    if "/stories/highlights/" in lowered or "highlight" in lowered:
        return False
    if "story" in lowered or "/stories/" in lowered:
        return True
    if "feed" in lowered:
        return False
    return False


def is_highlight_story_url(url: str) -> bool:
    lowered = url.lower()
    return "/stories/highlights/" in lowered or "/highlights/" in lowered


def is_active_story_page(url: str, username: str | None = None) -> bool:
    lowered = url.lower()
    if is_highlight_story_url(lowered):
        return False
    if "/stories/" not in lowered:
        return False
    if username:
        return f"/stories/{sanitize_filename(username).lower()}/" in lowered
    return True


def passes_story_shape_gate(url: str, width: int, height: int) -> bool:
    tag = media_variant_tag(url)
    if width > 0 and height > 0:
        return is_story_ratio(width, height, strict="story" not in tag)
    return "story" in tag


def choose_best_image_url(item: dict[str, Any]) -> str | None:
    candidates: list[dict[str, Any]] = []

    image_versions = item.get("image_versions2")
    if isinstance(image_versions, dict):
        nested = image_versions.get("candidates")
        if isinstance(nested, list):
            candidates.extend([candidate for candidate in nested if isinstance(candidate, dict)])

    display_resources = item.get("display_resources")
    if isinstance(display_resources, list):
        candidates.extend([candidate for candidate in display_resources if isinstance(candidate, dict)])

    best_url: str | None = None
    best_score = -10**9
    for candidate in candidates:
        url = candidate.get("url")
        if not isinstance(url, str) or not is_story_media_url(url):
            continue

        width, height = candidate_dimensions(candidate, item)
        if not passes_story_shape_gate(url, width, height):
            continue

        score = (
            media_variant_score(url, "image")
            + max(width * height, media_candidate_area(candidate)) // 5000
            + story_ratio_bonus(width, height)
        )
        if score > best_score:
            best_score = score
            best_url = normalize_media_url(url)

    return best_url


def choose_best_video_url(item: dict[str, Any]) -> str | None:
    video_versions = item.get("video_versions")
    if not isinstance(video_versions, list):
        return None

    preferred_urls: list[tuple[int, str]] = []
    best_url: str | None = None
    best_score = -10**9
    for candidate in video_versions:
        if not isinstance(candidate, dict):
            continue

        url = candidate.get("url")
        if not isinstance(url, str) or not is_story_media_url(url):
            continue

        if should_skip_media_variant(url):
            continue

        width, height = candidate_dimensions(candidate, item)
        if not passes_story_shape_gate(url, width, height):
            continue

        normalized_url = normalize_media_url(url)
        score = (
            media_variant_score(url, "video")
            + max(width * height, media_candidate_area(candidate)) // 5000
            + story_ratio_bonus(width, height)
        )
        candidate_type = candidate.get("type")
        if candidate_type == 101:
            score += 25
        if candidate_type == 102:
            score += 10

        tag = media_variant_tag(url)
        lowered = url.lower()
        if any(token in tag for token in ["xpv_progressive", "progressive", "avc", "h264"]):
            preferred_urls.append((score, normalized_url))
        if any(token in lowered for token in ["xpv_progressive", "progressive"]) and "dash" not in lowered:
            preferred_urls.append((score + 20, normalized_url))

        if score > best_score:
            best_score = score
            best_url = normalized_url

    if preferred_urls:
        preferred_urls.sort(key=lambda item: item[0], reverse=True)
        return preferred_urls[0][1]

    return best_url


def extract_item_username(item: dict[str, Any]) -> str:
    for key in ["user", "owner"]:
        value = item.get(key)
        if isinstance(value, dict):
            username = value.get("username")
            if isinstance(username, str) and username:
                return username

    return ""


def resolve_story_item_from_dict(item: dict[str, Any], expected_username: str) -> ResolvedStoryItem | None:
    if not any(key in item for key in ["video_versions", "image_versions2", "display_resources"]):
        return None

    username = extract_item_username(item) or expected_username
    if expected_username and username and sanitize_filename(username) != sanitize_filename(expected_username):
        return None

    item_id = item.get("id") or item.get("pk")
    if item_id is None:
        return None

    item_id_str = str(item_id)
    if not item_id_str:
        return None

    media_type = "video" if isinstance(item.get("video_versions"), list) else "image"
    source_url = choose_best_video_url(item) if media_type == "video" else choose_best_image_url(item)
    if not source_url:
        return None

    page_username = sanitize_filename(username or expected_username)
    page_url = f"https://www.instagram.com/stories/{page_username}/{item_id_str}/"
    taken_at = int(item.get("taken_at", 0) or 0)
    return ResolvedStoryItem(
        item_id=item_id_str,
        username=page_username,
        page_url=page_url,
        source_url=source_url,
        media_type=media_type,
        taken_at=taken_at,
    )


def walk_story_items(node: Any, expected_username: str, seen_ids: set[str], out: list[ResolvedStoryItem]) -> None:
    if isinstance(node, dict):
        resolved = resolve_story_item_from_dict(node, expected_username)
        if resolved and resolved.item_id not in seen_ids:
            seen_ids.add(resolved.item_id)
            out.append(resolved)

        for value in node.values():
            walk_story_items(value, expected_username, seen_ids, out)
        return

    if isinstance(node, list):
        for value in node:
            walk_story_items(value, expected_username, seen_ids, out)


def resolve_story_items_from_payloads(
    payloads: list[dict[str, Any]],
    expected_username: str,
    *,
    captured_after: float | None = None,
) -> list[ResolvedStoryItem]:
    filtered_payloads: list[dict[str, Any]] = []
    story_payloads: list[dict[str, Any]] = []

    for entry in payloads:
        captured_at = entry.get("captured_at")
        if captured_after is not None and isinstance(captured_at, (int, float)) and captured_at < captured_after:
            continue
        filtered_payloads.append(entry)
        entry_url = entry.get("url")
        if isinstance(entry_url, str) and response_url_likely_story(entry_url):
            story_payloads.append(entry)

    preferred_entries = story_payloads or filtered_payloads
    seen_ids: set[str] = set()
    resolved: list[ResolvedStoryItem] = []

    for entry in preferred_entries:
        payload = entry.get("payload")
        walk_story_items(payload, expected_username, seen_ids, resolved)

    resolved.sort(key=lambda item: item.taken_at or 0)
    return resolved


def wait_for_metadata_story_items(
    page,
    payloads: list[dict[str, Any]],
    expected_username: str,
    logs: list[str],
    timeout_seconds: int = 12,
    captured_after: float | None = None,
) -> list[ResolvedStoryItem]:
    deadline = time.time() + timeout_seconds
    best_result: list[ResolvedStoryItem] = []

    while time.time() < deadline:
        resolved = resolve_story_items_from_payloads(payloads, expected_username, captured_after=captured_after)
        if resolved:
            best_result = resolved
            if len(resolved) > 1:
                break
        page.wait_for_timeout(600)

    if best_result:
        logs.append(f"metadata_story_items={len(best_result)}")

    return best_result


def next_story_index(destination_dir: Path, username: str) -> int:
    prefix = f"{sanitize_filename(username)}-"
    highest = 0

    for candidate in destination_dir.glob(f"{prefix}*"):
        match = re.match(rf"^{re.escape(prefix)}(\d+)", candidate.name)
        if not match:
            continue
        highest = max(highest, int(match.group(1)))

    return highest + 1


def install_network_capture(page, logs: list[str]) -> list[StoryMedia]:
    captured: list[StoryMedia] = []
    seen_urls: set[str] = set()

    def on_response(response) -> None:
        try:
            headers = response.headers
            content_type = headers.get("content-type", "")
            url = response.url

            if url in seen_urls:
                return

            media_type: str | None = None
            lowered = url.lower()
            if content_type.startswith("video/") or lowered.endswith(".mp4"):
                media_type = "video"
            elif content_type.startswith("image/") or lowered.endswith((".jpg", ".jpeg", ".png", ".webp")):
                media_type = "image"

            if media_type is None:
                return

            if not is_story_media_url(url):
                return

            if should_skip_media_variant(url):
                return

            seen_urls.add(url)
            captured.append(
                StoryMedia(
                    source_url=normalize_media_url(url),
                    media_type=media_type,
                    page_url=page.url,
                    captured_at=time.time(),
                )
            )
        except Exception as exc:
            logs.append(f"network_capture_error={exc}")

    page.on("response", on_response)
    return captured


def story_viewer_ready(page) -> bool:
    script = """
    () => {
      const hasDialog = !!document.querySelector('[role="dialog"]');
      const hasProgress = document.querySelectorAll('div[role="progressbar"]').length > 0;
      const hasCenteredMedia = [...document.querySelectorAll('video, img')].some((node) => {
        const rect = node.getBoundingClientRect();
        const centerX = window.innerWidth / 2;
        const centerY = window.innerHeight / 2;
        return (
          rect.width > 180 &&
          rect.height > 280 &&
          rect.left <= centerX &&
          rect.right >= centerX &&
          rect.top <= centerY &&
          rect.bottom >= centerY
        );
      });
      return hasDialog || hasProgress || hasCenteredMedia;
    }
    """
    try:
        return bool(page.evaluate(script))
    except Exception:
        return False


def extract_media_candidate(page) -> StoryMedia | None:
    script = """
    () => {
      const viewportCenterX = window.innerWidth / 2;
      const viewportCenterY = window.innerHeight / 2;
      const hasDialog = !!document.querySelector('[role="dialog"]');
      const nodes = [...document.querySelectorAll('video, img')];
      const visible = nodes
        .map((node) => {
          const rect = node.getBoundingClientRect();
          const style = window.getComputedStyle(node);
          const centerX = rect.left + (rect.width / 2);
          const centerY = rect.top + (rect.height / 2);
          const containsViewportCenter =
            rect.left <= viewportCenterX &&
            rect.right >= viewportCenterX &&
            rect.top <= viewportCenterY &&
            rect.bottom >= viewportCenterY;
          const distanceToCenter = Math.hypot(centerX - viewportCenterX, centerY - viewportCenterY);
          const inDialog = !!node.closest('[role="dialog"]');
          const inHeader = !!node.closest('header');
          const inLink = !!node.closest('a');
          return {
            tag: node.tagName.toLowerCase(),
            src: node.currentSrc || node.src || '',
            poster: node.poster || '',
            width: rect.width,
            height: rect.height,
            ratio: rect.height > 0 ? (rect.width / rect.height) : 0,
            area: rect.width * rect.height,
            hidden: style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0',
            containsViewportCenter,
            distanceToCenter,
            inDialog,
            inHeader,
            inLink,
          };
        })
        .filter((item) =>
          !item.hidden &&
          item.src &&
          item.width > 180 &&
          item.height > 280 &&
          item.height > item.width &&
          item.ratio >= 0.46 &&
          item.ratio <= 0.68 &&
          (!hasDialog || item.inDialog) &&
          !item.inHeader &&
          (item.containsViewportCenter || item.inDialog) &&
          !(item.inLink && !item.containsViewportCenter && !item.inDialog)
        )
        .sort((a, b) => {
          if (a.containsViewportCenter !== b.containsViewportCenter) {
            return a.containsViewportCenter ? -1 : 1;
          }
          if (a.inDialog !== b.inDialog) {
            return a.inDialog ? -1 : 1;
          }
          if (Math.abs(a.area - b.area) > 1000) {
            return b.area - a.area;
          }
          return a.distanceToCenter - b.distanceToCenter;
        });

      return visible[0] || null;
    }
    """
    candidate = page.evaluate(script)
    if not candidate:
        return None

    source_url = normalize_media_url(candidate.get("src", ""))
    if not is_story_media_url(source_url):
        return None

    media_type = "video" if candidate.get("tag") == "video" else "image"
    return StoryMedia(
        source_url=source_url,
        media_type=media_type,
        page_url=page.url,
        poster_url=candidate.get("poster") or None,
        captured_at=time.time(),
        width=int(candidate.get("width", 0) or 0),
        height=int(candidate.get("height", 0) or 0),
    )


def latest_network_candidate(page, network_candidates: list[StoryMedia], seen_sources: set[str]) -> StoryMedia | None:
    now = time.time()
    viable: list[StoryMedia] = []
    for candidate in reversed(network_candidates):
        if candidate.source_url in seen_sources:
            continue
        if now - candidate.captured_at > 20:
            continue
        if not is_active_story_page(candidate.page_url) and not is_active_story_page(page.url):
            continue
        if should_skip_media_variant(candidate.source_url):
            continue
        tag = media_variant_tag(candidate.source_url)
        if "story" not in tag:
            continue
        candidate.page_url = page.url
        viable.append(candidate)

    if not viable:
        return None

    viable.sort(key=lambda item: (media_variant_score(item.source_url, item.media_type), item.captured_at), reverse=True)
    return viable[0]


def wait_for_story_media(page, network_candidates: list[StoryMedia], seen_sources: set[str], timeout_seconds: int = 20) -> StoryMedia | None:
    deadline = time.time() + timeout_seconds
    network_fallback_deadline = time.time() + min(timeout_seconds, 8)
    while time.time() < deadline:
        if is_highlight_story_url(page.url):
            return None

        if not is_active_story_page(page.url):
            page.wait_for_timeout(800)
            continue

        if not story_viewer_ready(page):
            page.wait_for_timeout(800)
            continue

        candidate = extract_media_candidate(page)
        if candidate:
            return candidate

        if time.time() < network_fallback_deadline:
            page.wait_for_timeout(800)
            continue

        candidate = latest_network_candidate(page, network_candidates, seen_sources)
        if candidate:
            return candidate

        page.wait_for_timeout(800)
    return None


def story_signature(page_url: str, source_url: str) -> str:
    return f"{page_url}|{normalize_media_url(source_url)}"


def advance_to_next_story(page, network_candidates: list[StoryMedia], seen_sources: set[str], previous_signature: str, logs: list[str]) -> bool:
    actions = [
        ("click", lambda: click_next_story(page)),
        ("arrow", lambda: page.keyboard.press("ArrowRight")),
        ("space", lambda: page.keyboard.press("Space")),
    ]

    for action_name, action in actions:
        try:
            action()
        except Exception as exc:
            logs.append(f"advance_action_error={action_name}:{exc}")
            continue

        page.wait_for_timeout(1200)

        if "/stories/" not in page.url:
            return False

        next_media = wait_for_story_media(page, network_candidates, seen_sources, timeout_seconds=6)
        if not next_media:
            continue

        next_signature = story_signature(next_media.page_url, next_media.source_url)
        if next_signature != previous_signature:
            return True

    return False


def click_next_story(page) -> None:
    viewport = page.viewport_size or {"width": 1440, "height": 900}
    page.mouse.click(viewport["width"] * 0.85, viewport["height"] * 0.5)


def click_profile_story_ring(page, username: str, logs: list[str]) -> bool:
    candidate_selectors = [
        f'a[href="/stories/{username}/"]',
        f'a[href="/stories/{username}"]',
        f'header a[href="/stories/{username}/"]',
        f'header a[href="/stories/{username}"]',
    ]

    for selector in candidate_selectors:
        try:
            locator = page.locator(selector).first
            if locator.count() == 0:
                continue
            locator.click(timeout=2500)
            page.wait_for_timeout(1500)
            if is_active_story_page(page.url, username):
                logs.append(f"profile_story_opened_via={selector}")
                return True
            if is_highlight_story_url(page.url):
                logs.append(f"profile_story_rejected_highlight={selector}")
                try:
                    page.goto(f"https://www.instagram.com/{username}/", wait_until="domcontentloaded")
                    page.wait_for_timeout(1200)
                except Exception:
                    pass
        except Exception:
            continue

    return False


def persist_story_items(
    resolved_items: list[ResolvedStoryItem],
    destination_dir: Path,
    username: str,
    *,
    browser_context: Any | None = None,
) -> tuple[list[dict[str, str]], list[str]]:
    logs: list[str] = []
    items: list[dict[str, str]] = []
    seen_sources: set[str] = set()
    seen_hashes: set[str] = set()
    next_index = next_story_index(destination_dir, username)

    for resolved in resolved_items:
        normalized_source = normalize_media_url(resolved.source_url)
        if normalized_source in seen_sources:
            logs.append(f"skipped_current_source={normalized_source}")
            continue

        local_path, final_source_url = download_media(
            normalized_source,
            destination_dir,
            resolved.media_type,
            username,
            next_index,
            browser_context=browser_context,
            referer_url=resolved.page_url,
        )
        file_hash = sha256(local_path.read_bytes()).hexdigest()
        if file_hash in seen_hashes:
            local_path.unlink(missing_ok=True)
            seen_sources.add(final_source_url)
            logs.append(f"skipped_current_hash={file_hash}")
            continue

        item_id = uuid.uuid4().hex
        created_at = datetime.now(timezone.utc).isoformat()
        manifest_path = write_manifest(
            item_id=item_id,
            page_url=resolved.page_url,
            source_url=final_source_url,
            local_path=local_path,
            media_type=resolved.media_type,
            created_at=created_at,
        )
        items.append(
            {
                "id": item_id,
                "sourceURL": final_source_url,
                "pageURL": resolved.page_url,
                "localPath": str(local_path),
                "metadataPath": str(manifest_path),
                "mediaType": resolved.media_type,
                "createdAt": created_at,
            }
        )
        seen_sources.add(final_source_url)
        seen_hashes.add(file_hash)
        next_index += 1
        logs.append(f"saved={local_path}")
        logs.append(f"manifest={manifest_path}")

    return items, logs


def collect_story_sequence(
    page,
    destination_dir: Path,
    username: str,
    json_payloads: list[dict[str, Any]],
    network_candidates: list[StoryMedia],
    metadata_captured_after: float | None = None,
    persist_metadata_items: bool = True,
) -> tuple[list[dict[str, str]], list[str]]:
    logs: list[str] = []

    if is_highlight_story_url(page.url):
        logs.append(f"highlight_page_rejected={page.url}")
        return [], logs

    if not is_active_story_page(page.url, username):
        logs.append(f"active_story_page_missing={page.url}")
        return [], logs

    resolved_items = wait_for_metadata_story_items(
        page,
        json_payloads,
        username,
        logs,
        timeout_seconds=12,
        captured_after=metadata_captured_after,
    )
    if resolved_items and persist_metadata_items:
        saved_items, persist_logs = persist_story_items(
            resolved_items,
            destination_dir,
            username,
            browser_context=page.context,
        )
        logs.extend(persist_logs)
        if saved_items:
            return saved_items, logs
        logs.append("metadata_only_no_new_items")

    seen_sources: set[str] = set()
    seen_hashes: set[str] = set()
    seen_signatures: set[str] = set()
    items: list[dict[str, str]] = []
    next_index = next_story_index(destination_dir, username)

    for _ in range(50):
        media = wait_for_story_media(page, network_candidates, seen_sources, timeout_seconds=20)
        if not media:
            logs.append("На странице не найдено видимого media из story.")
            break

        normalized_source = normalize_media_url(media.source_url)
        signature = story_signature(media.page_url, normalized_source)
        if signature in seen_signatures:
            if not advance_to_next_story(page, network_candidates, seen_sources | {normalized_source}, signature, logs):
                break
            continue

        if normalized_source in seen_sources:
            seen_signatures.add(signature)
            logs.append(f"skipped_current_source={normalized_source}")
        else:
            local_path, final_source_url = download_media(
                normalized_source,
                destination_dir,
                media.media_type,
                username,
                next_index,
                browser_context=page.context,
                referer_url=media.page_url,
            )
            file_hash = sha256(local_path.read_bytes()).hexdigest()
            if file_hash in seen_hashes:
                local_path.unlink(missing_ok=True)
                seen_signatures.add(signature)
                seen_sources.add(final_source_url)
                logs.append(f"skipped_current_hash={file_hash}")
            else:
                item_id = uuid.uuid4().hex
                created_at = datetime.now(timezone.utc).isoformat()
                manifest_path = write_manifest(
                    item_id=item_id,
                    page_url=media.page_url,
                    source_url=final_source_url,
                    local_path=local_path,
                    media_type=media.media_type,
                    created_at=created_at,
                )
                items.append(
                    {
                        "id": item_id,
                        "sourceURL": final_source_url,
                        "pageURL": media.page_url,
                        "localPath": str(local_path),
                        "metadataPath": str(manifest_path),
                        "mediaType": media.media_type,
                        "createdAt": created_at,
                    }
                )
                seen_signatures.add(signature)
                seen_sources.add(final_source_url)
                seen_hashes.add(file_hash)
                next_index += 1
                logs.append(f"saved={local_path}")
                logs.append(f"manifest={manifest_path}")

        if not advance_to_next_story(page, network_candidates, seen_sources | {normalized_source}, signature, logs):
            break

    return items, logs


def ensure_logged_in(page) -> None:
    if is_logged_in(page):
        return
    raise RuntimeError("Требуется вход в Instagram. Сначала откройте браузер для входа.")


def extract_found_count(logs: list[str], fallback: int) -> int:
    for line in reversed(logs):
        if line.startswith("metadata_story_items="):
            raw = line.split("=", 1)[1]
            if raw.isdigit():
                return int(raw)
    return fallback


def click_story_gate_if_needed(page, logs: list[str]) -> None:
    button_selectors = [
        'button:has-text("Посмотреть историю")',
        'button:has-text("Посмотреть сторис")',
        'button:has-text("View story")',
        'button:has-text("Watch story")',
    ]

    for selector in button_selectors:
        try:
            locator = page.locator(selector).first
            if locator.count() == 0:
                continue
            locator.click(timeout=2000)
            page.wait_for_timeout(1500)
            logs.append(f"story_gate_clicked={selector}")
            return
        except Exception:
            continue

    generic_buttons = page.get_by_role("button").all()
    for button in generic_buttons:
        try:
            title = (button.inner_text(timeout=500) or "").strip().lower()
        except Exception:
            continue

        if any(
            phrase in title
            for phrase in [
                "посмотреть историю",
                "посмотреть сторис",
                "view story",
                "watch story",
            ]
        ):
            try:
                button.click(timeout=1500)
                page.wait_for_timeout(1500)
                logs.append(f"story_gate_clicked_by_text={title}")
                return
            except Exception:
                continue


def story_url_command(url: str, output_directory: str | None) -> None:
    ensure_directories()
    root_destination = Path(output_directory or DEFAULT_DOWNLOADS).expanduser()
    username = extract_username(url)
    destination = root_destination / sanitize_filename(username)
    logs: list[str] = []
    session = None

    try:
        session = launch_context(headless=True)
        page = session.first_page()
        prepare_background_window(session, page, logs)
        json_payloads = install_json_capture(page, logs)
        network_candidates = install_network_capture(page, logs)
        story_capture_started_at = time.time()
        page.goto(url, wait_until="domcontentloaded")
        ensure_logged_in(page)
        persist_session_state(page.context, logs)
        click_story_gate_if_needed(page, logs)
        logs.append(f"opened={page.url}")

        items, sequence_logs = collect_story_sequence(
            page,
            destination,
            username,
            json_payloads,
            network_candidates,
            metadata_captured_after=story_capture_started_at,
            persist_metadata_items=False,
        )
        logs.extend(sequence_logs)
        found_count = extract_found_count(sequence_logs, len(items))

        if not items:
            emit(
                False,
                "download_empty",
                "По указанной ссылке не удалось получить media из story.",
                data={"foundCount": str(found_count), "savedCount": "0"},
                logs=logs,
            )
            return

        emit(
            True,
            "download_complete",
            f"Сохранено файлов из story: {len(items)}.",
            data={"foundCount": str(found_count), "savedCount": str(len(items))},
            items=items,
            logs=logs,
        )
    except Exception as exc:
        emit(False, "download_error", str(exc), logs=logs)
    finally:
        if session:
            close_session_with_timeout(session)


def extract_username(value: str) -> str:
    parsed = urllib.parse.urlparse(value)
    if parsed.netloc:
        parts = [part for part in parsed.path.split("/") if part]
        if parts and parts[0] == "stories" and len(parts) > 1:
            return sanitize_filename(parts[1])
        if parts:
            return sanitize_filename(parts[0])
    return sanitize_filename(value.strip().lstrip("@"))


def profile_command(profile_url: str, output_directory: str | None, headless: bool = True) -> None:
    ensure_directories()
    session = None

    try:
        session = launch_context(headless=headless)
        page = session.first_page()
        prepare_background_window(session, page, [])
        result = download_profile_with_page(page, profile_url, output_directory)
        emit(
            result["ok"],
            result["status"],
            result["message"],
            data=result["data"],
            items=result["items"],
            logs=result["logs"],
        )
    finally:
        if session:
            close_session_with_timeout(session)


def download_profile_with_page(page, profile_url: str, output_directory: str | None) -> dict[str, Any]:
    username = extract_username(profile_url)
    if not username:
        return {
            "ok": False,
            "status": "profile_error",
            "message": "Не удалось извлечь имя пользователя из ссылки на профиль.",
            "data": {"foundCount": "0", "savedCount": "0"},
            "items": [],
            "logs": [],
            "username": "",
            "profileUrl": profile_url,
        }

    root_destination = Path(output_directory or DEFAULT_DOWNLOADS).expanduser()
    destination = root_destination / sanitize_filename(username)
    logs: list[str] = []

    try:
        json_payloads = install_json_capture(page, logs)
        network_candidates = install_network_capture(page, logs)

        profile_page_url = f"https://www.instagram.com/{username}/"
        page.goto(profile_page_url, wait_until="domcontentloaded")
        ensure_logged_in(page)
        persist_session_state(page.context, logs)
        page.wait_for_timeout(1500)
        logs.append(f"profile_download_directory={destination}")
        opened = click_profile_story_ring(page, username, logs)
        if not opened:
            fallback = f"https://www.instagram.com/stories/{username}/"
            page.goto(fallback, wait_until="domcontentloaded")
            ensure_logged_in(page)
            logs.append(f"profile_fallback={fallback}")

        click_story_gate_if_needed(page, logs)
        logs.append(f"opened={page.url}")

        if is_highlight_story_url(page.url):
            return {
                "ok": False,
                "status": "download_empty",
                "message": f"Для профиля {username} нет активных stories. Открылись highlights, они пропущены.",
                "data": {"foundCount": "0", "savedCount": "0"},
                "items": [],
                "logs": logs + [f"highlight_page_skipped={page.url}"],
                "username": username,
                "profileUrl": profile_url,
            }

        if not is_active_story_page(page.url, username):
            return {
                "ok": False,
                "status": "download_empty",
                "message": f"Для профиля {username} активные stories не найдены.",
                "data": {"foundCount": "0", "savedCount": "0"},
                "items": [],
                "logs": logs + [f"active_story_page_missing_after_open={page.url}"],
                "username": username,
                "profileUrl": profile_url,
            }

        json_payloads.clear()
        network_candidates.clear()
        story_capture_started_at = time.time()
        items, sequence_logs = collect_story_sequence(
            page,
            destination,
            username,
            json_payloads,
            network_candidates,
            metadata_captured_after=story_capture_started_at,
        )
        logs.extend(sequence_logs)
        found_count = extract_found_count(sequence_logs, len(items))

        if not items:
            return {
                "ok": False,
                "status": "download_empty",
                "message": f"Для профиля {username} не удалось получить активные stories.",
                "data": {"foundCount": str(found_count), "savedCount": "0"},
                "items": [],
                "logs": logs,
                "username": username,
                "profileUrl": profile_url,
            }

        return {
            "ok": True,
            "status": "download_complete",
            "message": f"Для профиля {username} сохранено файлов: {len(items)}.",
            "data": {"foundCount": str(found_count), "savedCount": str(len(items))},
            "items": items,
            "logs": logs,
            "username": username,
            "profileUrl": profile_url,
        }
    except Exception as exc:
        return {
            "ok": False,
            "status": "download_error",
            "message": str(exc),
            "data": {"foundCount": "0", "savedCount": "0"},
            "items": [],
            "logs": logs,
            "username": username,
            "profileUrl": profile_url,
        }


def profile_batch_command(profile_urls: list[str], output_directory: str | None, headless: bool = True) -> None:
    ensure_directories()
    normalized_urls = [str(entry).strip() for entry in profile_urls if str(entry).strip()]
    if not normalized_urls:
        emit(False, "request_error", "Для пакетной выгрузки нужен хотя бы один профиль.")
        return

    logs: list[str] = []
    items: list[dict[str, str]] = []
    batch_results: list[dict[str, Any]] = []
    total_found = 0
    total_saved = 0
    success_count = 0
    chunk_size = BATCH_BACKGROUND_CHUNK_SIZE if headless else BATCH_VISIBLE_CHUNK_SIZE
    normalized_profiles = [
        entry if "instagram.com" in entry else f"https://www.instagram.com/{extract_username(entry)}/"
        for entry in normalized_urls
    ]
    profile_chunks = chunked(normalized_profiles, chunk_size)
    logs.append(f"batch_chunk_size={chunk_size}")
    logs.append(f"batch_chunk_count={len(profile_chunks)}")
    session = None
    page = None

    try:
        session = launch_context(headless=headless)
        page = session.first_page()
        prepare_background_window(session, page, logs)

        for chunk_index, profile_chunk in enumerate(profile_chunks, start=1):
            logs.append(f"batch_chunk_{chunk_index}_start={len(profile_chunk)}")

            if page is None or page.is_closed():
                page = session.context.new_page()
                prepare_background_window(session, page, logs)
                logs.append(f"batch_page_recreated_chunk={chunk_index}")

            if chunk_index > 1:
                try:
                    page.goto("about:blank")
                    page.wait_for_timeout(700)
                except Exception as exc:
                    logs.append(f"batch_chunk_reset_error={chunk_index}:{exc}")

            for normalized_url in profile_chunk:
                logs.append(f"batch_profile_start={normalized_url}")

                try:
                    if page is None or page.is_closed():
                        page = session.context.new_page()
                        prepare_background_window(session, page, logs)
                        logs.append(f"batch_page_recreated_profile={normalized_url}")

                    result = download_profile_with_page(page, normalized_url, output_directory)
                except Exception as exc:
                    result = {
                        "ok": False,
                        "status": "download_error",
                        "message": f"Пакетная выгрузка прервана на профиле {extract_username(normalized_url)}: {exc}",
                        "data": {"foundCount": "0", "savedCount": "0"},
                        "items": [],
                        "logs": [f"batch_profile_exception={normalized_url}:{exc}"],
                        "username": extract_username(normalized_url),
                        "profileUrl": normalized_url,
                    }

                found_count = int(result["data"].get("foundCount", "0") or 0)
                saved_count = int(result["data"].get("savedCount", "0") or 0)
                total_found += found_count
                total_saved += saved_count
                if result["ok"]:
                    success_count += 1
                items.extend(result["items"])
                logs.extend([f"[{result.get('username') or normalized_url}] {entry}" for entry in result["logs"]])
                batch_results.append(
                    {
                        "url": normalized_url,
                        "status": "completed" if result["ok"] else "failed",
                        "message": result["message"],
                        "foundCount": found_count,
                        "savedCount": saved_count,
                    }
                )
                logs.append(f"batch_profile_done={normalized_url}")

                if headless:
                    try:
                        page.goto("about:blank")
                    except Exception as exc:
                        logs.append(f"batch_profile_reset_error={normalized_url}:{exc}")

            logs.append(f"batch_chunk_{chunk_index}_done={len(profile_chunk)}")

        ok = success_count > 0
        status = "batch_complete" if ok else "batch_failed"
        message = (
            f"Пакетная выгрузка завершена. Обработано профилей: {len(normalized_urls)}."
            if ok
            else "Не удалось получить активные stories ни для одного профиля из очереди."
        )
        emit(
            ok,
            status,
            message,
            data={
                "foundCount": str(total_found),
                "savedCount": str(total_saved),
                "processedCount": str(len(normalized_urls)),
                "batchResults": json.dumps(batch_results),
            },
            items=items,
            logs=logs,
        )
    except Exception as exc:
        processed_urls = {entry["url"] for entry in batch_results}
        for normalized_url in normalized_profiles:
            if normalized_url not in processed_urls:
                batch_results.append(batch_failure_result(normalized_url, f"Пакетная выгрузка прервана: {exc}"))
        emit(
            False,
            "download_error",
            str(exc),
            data={
                "foundCount": str(total_found),
                "savedCount": str(total_saved),
                "processedCount": str(len(batch_results)),
                "batchResults": json.dumps(batch_results),
            },
            items=items,
            logs=logs,
        )
    finally:
        if session:
            close_session_with_timeout(session, logs)


def main() -> None:
    try:
        request = read_request()
        command = request.get("command")
        url = request.get("url")
        urls = request.get("urls") or []
        output_directory = request.get("outputDirectory")
        headless = request.get("headless")
        if headless is None:
            headless = True

        if command == "environment":
            environment_command()
        elif command == "login":
            login_command()
        elif command == "check_session":
            check_session_command(headless=bool(headless))
        elif command == "download_story_url":
            if not url:
                emit(False, "request_error", "Для download_story_url нужна ссылка.")
                return
            story_url_command(url, output_directory)
        elif command == "download_profile_stories":
            if not url:
                emit(False, "request_error", "Для download_profile_stories нужна ссылка на профиль или имя пользователя.")
                return
            profile_command(url, output_directory, headless=bool(headless))
        elif command == "download_profile_batch":
            profile_batch_command(list(urls), output_directory, headless=bool(headless))
        else:
            emit(False, "request_error", f"Неподдерживаемая команда: {command}")
    except Exception as exc:
        emit(False, "worker_exception", str(exc))


if __name__ == "__main__":
    main()
