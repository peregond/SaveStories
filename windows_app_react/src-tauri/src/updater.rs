//! Автообновление из GitHub Releases. Логика и ключи установщика повторяют
//! windows_app/savestories_windows/updater.py, чтобы релизы и сам Inno Setup не менялись.

use std::io::Read;
use std::path::{Path, PathBuf};

use futures_util::StreamExt;
use serde::Serialize;
use serde_json::Value;
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Emitter};

use crate::paths::AppPaths;

const UPDATE_CONFIG: &str = include_str!("../../../Sources/SaveStories/Resources/update_config.json");
pub const CURRENT_VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Clone, Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ReleaseAsset {
    pub name: String,
    pub url: String,
    pub size: u64,
    pub digest: String,
    pub checksum_url: String,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReleaseInfo {
    pub version: String,
    pub tag: String,
    pub title: String,
    pub notes: String,
    pub html_url: String,
    pub published_at: String,
    pub asset: ReleaseAsset,
}

#[derive(Clone, Debug, Serialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum CheckResult {
    Disabled,
    UpToDate,
    UpdateAvailable { release: Box<ReleaseInfo> },
}

#[derive(Serialize, Clone)]
struct Progress {
    percent: u32,
    message: String,
}

fn api_url() -> String {
    serde_json::from_str::<Value>(UPDATE_CONFIG)
        .ok()
        .and_then(|v| v.get("windowsLatestReleaseAPI").and_then(Value::as_str).map(|s| s.trim().to_owned()))
        .unwrap_or_default()
}

/// Автоустановка доступна только из установленной версии (рядом лежит unins000.exe).
pub fn supports_auto_install() -> bool {
    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("unins000.exe").exists()))
        .unwrap_or(false)
}

pub fn version_key(value: &str) -> (u32, u32, u32) {
    let mut parts = value.trim_start_matches(['v', 'V']).split('.').map(|part| {
        part.chars().filter(char::is_ascii_digit).collect::<String>().parse::<u32>().unwrap_or(0)
    });
    (parts.next().unwrap_or(0), parts.next().unwrap_or(0), parts.next().unwrap_or(0))
}

fn client() -> Result<reqwest::Client, String> {
    reqwest::Client::builder()
        .user_agent("SaveMe-Updater")
        .timeout(std::time::Duration::from_secs(600))
        .build()
        .map_err(|e| e.to_string())
}

pub async fn check_latest() -> Result<CheckResult, String> {
    check_latest_at(&api_url(), CURRENT_VERSION).await
}

pub async fn check_latest_at(url: &str, current_version: &str) -> Result<CheckResult, String> {
    if url.is_empty() {
        return Ok(CheckResult::Disabled);
    }
    let payload: Value = client()?
        .get(url)
        .header("Accept", "application/vnd.github+json")
        .timeout(std::time::Duration::from_secs(20))
        .send()
        .await
        .and_then(|r| r.error_for_status())
        .map_err(|e| format!("Не удалось проверить обновления: {e}"))?
        .json()
        .await
        .map_err(|e| e.to_string())?;

    let text = |key: &str| payload.get(key).and_then(Value::as_str).unwrap_or("").trim().to_owned();
    let tag = text("tag_name");
    let version = tag.trim_start_matches('v').to_owned();
    if version.is_empty() {
        return Err("GitHub API не вернул tag_name для latest release.".into());
    }
    if version_key(&version) <= version_key(current_version) {
        return Ok(CheckResult::UpToDate);
    }
    let assets = payload.get("assets").and_then(Value::as_array).cloned().unwrap_or_default();
    let asset = select_asset(&assets, &tag)?;
    let title = Some(text("name")).filter(|t| !t.is_empty()).unwrap_or_else(|| tag.clone());
    Ok(CheckResult::UpdateAvailable {
        release: Box::new(ReleaseInfo {
            version,
            tag,
            title,
            notes: text("body"),
            html_url: text("html_url"),
            published_at: text("published_at"),
            asset,
        }),
    })
}

pub fn select_asset(assets: &[Value], latest_tag: &str) -> Result<ReleaseAsset, String> {
    let tag = latest_tag.trim();
    let version = tag.trim_start_matches(['v', 'V']);
    let expected = [
        format!("SaveMe-Windows-Setup-{tag}.exe"),
        format!("SaveMe-Windows-Setup-v{version}.exe"),
        format!("SaveMe-Windows-Setup-{version}.exe"),
        format!("SaveStories-Windows-Setup-{tag}.exe"),
        format!("SaveStories-Windows-Setup-v{version}.exe"),
        format!("SaveStories-Windows-Setup-{version}.exe"),
    ];
    let field = |a: &Value, key: &str| a.get(key).and_then(Value::as_str).unwrap_or("").to_owned();
    let checksum_url = |name: &str| {
        let wanted = format!("{name}.sha256");
        assets.iter().find(|a| field(a, "name") == wanted).map(|a| field(a, "browser_download_url")).unwrap_or_default()
    };
    let to_asset = |a: &Value| {
        let name = field(a, "name");
        ReleaseAsset {
            url: field(a, "browser_download_url"),
            size: a.get("size").and_then(Value::as_u64).unwrap_or(0),
            digest: field(a, "digest"),
            checksum_url: checksum_url(&name),
            name,
        }
    };
    if let Some(a) = assets.iter().find(|a| expected.contains(&field(a, "name"))) {
        return Ok(to_asset(a));
    }
    let fallback = assets.iter().find(|a| {
        let name = field(a, "name");
        (name.starts_with("SaveMe-Windows-Setup-") || name.starts_with("SaveStories-Windows-Setup-")) && name.ends_with(".exe")
    });
    if let Some(a) = fallback {
        return Ok(to_asset(a));
    }
    let available = assets.iter().map(|a| field(a, "name")).collect::<Vec<_>>().join(", ");
    Err(format!(
        "Не удалось найти установщик Windows в assets релиза. Ожидались: {}. Доступно: {}.",
        expected.join(", "),
        if available.is_empty() { "пусто".into() } else { available }
    ))
}

fn sha256_file(path: &Path) -> Result<String, String> {
    let mut file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = file.read(&mut buf).map_err(|e| e.to_string())?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hasher.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

pub fn verify_digest(path: &Path, digest: &str, checksum_text: &str) -> Result<(), String> {
    let expected = if let Some(rest) = digest.strip_prefix("sha256:") {
        rest.trim().to_lowercase()
    } else {
        checksum_text.split_whitespace().next().unwrap_or("").to_lowercase()
    };
    if expected.is_empty() {
        return Err("У релиза нет SHA256 digest для установщика. Автоустановка остановлена.".into());
    }
    if expected.len() != 64 || !expected.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("SHA256 digest релиза имеет некорректный формат. Обновление остановлено.".into());
    }
    if sha256_file(path)? != expected {
        return Err("SHA256 release digest не совпал. Обновление остановлено.".into());
    }
    Ok(())
}

/// Что делать с установщиком по статусу Authenticode. Релизы пока не подписаны (`NotSigned`), как и у WinUI-клиента,
/// поэтому их принимаем (целостность проверяет SHA-256 из релиза). Подписанный, но повреждённый или недоверенный
/// файл (`HashMismatch`, `NotTrusted`, `UnknownError`…) — отвергаем: это признак подмены.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn signature_verdict(status: &str) -> Result<(), String> {
    match status.trim() {
        "Valid" | "NotSigned" => Ok(()),
        other => Err(format!("Подпись установщика обновления недействительна (статус {other}). Обновление остановлено.")),
    }
}

#[cfg(windows)]
fn verify_signature(path: &Path) -> Result<(), String> {
    use std::os::windows::process::CommandExt;
    // Путь передаём через переменную окружения: `-Command` склеивает остальные аргументы с текстом команды
    // (путь превращался в часть выражения и мог быть выполнен), а так в команду он не попадает вовсе.
    let output = std::process::Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "(Get-AuthenticodeSignature -LiteralPath $env:SAVEME_SIGNATURE_PATH).Status"])
        .env("SAVEME_SIGNATURE_PATH", path)
        .creation_flags(0x0800_0000)
        .output()
        .map_err(|e| format!("Не удалось проверить подпись установщика: {e}"))?;
    if !output.status.success() {
        return Err(format!("Не удалось проверить подпись установщика: {}", String::from_utf8_lossy(&output.stderr).trim()));
    }
    signature_verdict(&String::from_utf8_lossy(&output.stdout))
}

#[cfg(not(windows))]
fn verify_signature(_path: &Path) -> Result<(), String> {
    Ok(())
}

pub async fn prepare_install(app: &AppHandle, paths: &AppPaths, release: &ReleaseInfo) -> Result<PathBuf, String> {
    if !supports_auto_install() {
        return Err("Автоустановка доступна только для версии, установленной через инсталлятор. Скачай новый установщик вручную.".into());
    }
    let version = release.version.clone();
    download_installer(paths, release, |percent| {
        let _ = app.emit("update-progress", Progress { percent, message: format!("Скачивание обновления {version}: {percent}%") });
    })
    .await
}

/// Скачивает установщик, сверяет SHA-256 и подпись. Выделено из `prepare_install`, чтобы проверять весь путь без окна приложения.
pub async fn download_installer(paths: &AppPaths, release: &ReleaseInfo, on_progress: impl Fn(u32)) -> Result<PathBuf, String> {
    paths.ensure_directories().map_err(|e| e.to_string())?;
    let root = paths.updates_directory().join(&release.version);
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).map_err(|e| e.to_string())?;
    // Имя приходит от сервера: только простое имя файла, без каталогов и «..».
    if Path::new(&release.asset.name).file_name().and_then(|n| n.to_str()) != Some(release.asset.name.as_str()) || release.asset.name.contains("..") {
        return Err("Недопустимое имя файла установщика в релизе. Обновление остановлено.".into());
    }
    let installer = root.join(&release.asset.name);

    on_progress(0);
    let http = client()?;
    let response = http.get(&release.asset.url).send().await.and_then(|r| r.error_for_status()).map_err(|e| format!("Не удалось скачать обновление: {e}"))?;
    let total = response.content_length().filter(|n| *n > 0).unwrap_or(release.asset.size);
    let mut file = std::fs::File::create(&installer).map_err(|e| e.to_string())?;
    let mut stream = response.bytes_stream();
    let (mut done, mut last) = (0u64, u32::MAX);
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| e.to_string())?;
        std::io::Write::write_all(&mut file, &chunk).map_err(|e| e.to_string())?;
        done += chunk.len() as u64;
        if total > 0 {
            let percent = ((done * 100) / total).min(100) as u32;
            if percent != last {
                last = percent;
                on_progress(percent);
            }
        }
    }
    drop(file);

    let checksum_text = if release.asset.checksum_url.is_empty() {
        String::new()
    } else {
        http.get(&release.asset.checksum_url).timeout(std::time::Duration::from_secs(20)).send().await
            .and_then(|r| r.error_for_status()).map_err(|e| e.to_string())?
            .text().await.map_err(|e| e.to_string())?
    };
    verify_digest(&installer, &release.asset.digest, &checksum_text)?;
    verify_signature(&installer)?;
    Ok(installer)
}

#[cfg(windows)]
pub fn launch_installer(installer: &Path) -> Result<(), String> {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::UI::Shell::ShellExecuteW;
    let wide = |s: &std::ffi::OsStr| s.encode_wide().chain(Some(0)).collect::<Vec<u16>>();
    let dir = installer.parent().unwrap_or(Path::new("."));
    let log = dir.join("installer.log");
    let args = format!("/SP- /CLOSEAPPLICATIONS /FORCECLOSEAPPLICATIONS /NORESTART /LOG=\"{}\"", log.display());
    let result = unsafe {
        ShellExecuteW(
            std::ptr::null_mut(),
            wide("runas".as_ref()).as_ptr(),
            wide(installer.as_os_str()).as_ptr(),
            wide(args.as_ref()).as_ptr(),
            wide(dir.as_os_str()).as_ptr(),
            1,
        )
    };
    if (result as isize) <= 32 {
        return Err(format!("ShellExecuteW не смог запустить установщик (код {}).", result as isize));
    }
    Ok(())
}

#[cfg(not(windows))]
pub fn launch_installer(_installer: &Path) -> Result<(), String> {
    Err("Установка обновлений поддерживается только в Windows.".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn compares_versions_like_python_client() {
        assert!(version_key("0.6.86") > version_key("0.6.85"));
        assert!(version_key("v0.10.0") > version_key("0.9.9"));
        assert_eq!(version_key("1.2"), (1, 2, 0));
        assert_eq!(version_key("0.6.85-beta"), (0, 6, 85));
    }

    #[test]
    fn picks_exact_installer_and_checksum() {
        let assets = vec![
            json!({"name": "SaveMe-Windows-Setup-v0.7.0.exe.sha256", "browser_download_url": "https://x/sum"}),
            json!({"name": "SaveMe-Windows-Setup-v0.7.0.exe", "browser_download_url": "https://x/setup", "size": 10, "digest": "sha256:ab"}),
        ];
        let asset = select_asset(&assets, "v0.7.0").unwrap();
        assert_eq!(asset.url, "https://x/setup");
        assert_eq!(asset.checksum_url, "https://x/sum");
    }

    #[test]
    fn falls_back_to_any_setup_and_reports_missing() {
        let assets = vec![json!({"name": "SaveMe-Windows-Setup-custom.exe", "browser_download_url": "https://x/c"})];
        assert_eq!(select_asset(&assets, "v9.9.9").unwrap().name, "SaveMe-Windows-Setup-custom.exe");
        assert!(select_asset(&[json!({"name": "notes.txt"})], "v1.0.0").is_err());
    }

    #[test]
    fn digest_must_match_and_be_present() {
        let path = std::env::temp_dir().join(format!("saveme-digest-{}", std::process::id()));
        std::fs::write(&path, b"abc").unwrap();
        let good = "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
        assert!(verify_digest(&path, good, "").is_ok());
        assert!(verify_digest(&path, &good.replace("ba78", "ba79"), "").is_err());
        assert!(verify_digest(&path, "", "").is_err());
        assert!(verify_digest(&path, "", &good[7..]).is_ok());
    }

    // ---- Весь путь обновления против локального HTTP-сервера (тот же код, что в приложении, без окна и без GitHub)

    use crate::util::temp_dir;
    use std::collections::HashMap;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    /// Минимальный HTTP-сервер. `routes` получает адрес сервера (`http://127.0.0.1:порт`) и возвращает путь → тело ответа.
    async fn serve(routes: impl FnOnce(&str) -> HashMap<String, Vec<u8>>) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let routes = std::sync::Arc::new(routes(&base));
        tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else { break };
                let routes = routes.clone();
                tokio::spawn(async move {
                    let mut buf = vec![0u8; 4096];
                    let n = socket.read(&mut buf).await.unwrap_or(0);
                    let request = String::from_utf8_lossy(&buf[..n]).into_owned();
                    let path = request.split_whitespace().nth(1).unwrap_or("/").to_string();
                    let response = match routes.get(&path) {
                        Some(body) => {
                            let mut r = format!("HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len()).into_bytes();
                            r.extend_from_slice(body);
                            r
                        }
                        None => b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_vec(),
                    };
                    let _ = socket.write_all(&response).await;
                    let _ = socket.shutdown().await;
                });
            }
        });
        base
    }

    fn sha256_hex(bytes: &[u8]) -> String {
        Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
    }

    /// Сервер «релизов» (как GitHub): API `/latest` и установщик. `served` — что реально отдаём, `declared` — под что считаем digest.
    async fn release_server(declared: &[u8], served: &[u8], with_digest: bool) -> String {
        let name = "SaveMe-Windows-Setup-v9.9.9.exe";
        let digest = if with_digest { format!("sha256:{}", sha256_hex(declared)) } else { String::new() };
        let served = served.to_vec();
        serve(|base| {
            let api = serde_json::json!({
                "tag_name": "v9.9.9", "name": "SaveMe 9.9.9", "body": "Заметки", "html_url": format!("{base}/release"), "published_at": "2026-11-06T00:00:00Z",
                "assets": [{"name": name, "browser_download_url": format!("{base}/{name}"), "size": served.len(), "digest": digest}],
            });
            HashMap::from([("/latest".to_string(), api.to_string().into_bytes()), (format!("/{name}"), served)])
        })
        .await
    }

    fn fake_installer() -> Vec<u8> {
        // Не настоящий exe и без подписи — как наши релизы; достаточно большой, чтобы прийти несколькими кусками.
        let mut bytes = b"MZ fake unsigned installer ".to_vec();
        bytes.extend((0..400_000u32).map(|i| (i % 251) as u8));
        bytes
    }

    fn test_paths(name: &str) -> AppPaths {
        let root = temp_dir(name);
        AppPaths::with_support(root.clone(), root.join("data"))
    }

    #[tokio::test]
    async fn update_flow_end_to_end_against_a_local_server() {
        let bytes = fake_installer();
        let base = release_server(&bytes, &bytes, true).await;

        // 1. Проверка версии
        let found = check_latest_at(&format!("{base}/latest"), "0.6.86").await.unwrap();
        let CheckResult::UpdateAvailable { release } = found else { panic!("ожидалось обновление, получено {found:?}") };
        assert_eq!(release.version, "9.9.9");
        assert_eq!(release.asset.name, "SaveMe-Windows-Setup-v9.9.9.exe");
        assert!(matches!(check_latest_at(&format!("{base}/latest"), "9.9.9").await.unwrap(), CheckResult::UpToDate));
        assert!(matches!(check_latest_at(&format!("{base}/latest"), "10.0.0").await.unwrap(), CheckResult::UpToDate));
        assert!(matches!(check_latest_at("", "0.6.86").await.unwrap(), CheckResult::Disabled));

        // 2. Скачивание, прогресс, SHA-256 и подпись (на Windows — настоящий PowerShell: наш установщик не подписан)
        let paths = test_paths("update-e2e");
        let seen = std::sync::Mutex::new(Vec::new());
        let installer = download_installer(&paths, &release, |p| seen.lock().unwrap().push(p)).await.unwrap();
        assert_eq!(std::fs::read(&installer).unwrap(), bytes);
        let seen = seen.into_inner().unwrap();
        assert_eq!(seen.first(), Some(&0));
        assert_eq!(seen.last(), Some(&100));
        assert!(seen.windows(2).all(|w| w[0] <= w[1]), "прогресс не убывает: {seen:?}");
    }

    #[tokio::test]
    async fn tampered_installer_is_rejected() {
        let good = fake_installer();
        let mut evil = good.clone();
        evil[1000] ^= 0xFF;
        let base = release_server(&good, &evil, true).await;
        let CheckResult::UpdateAvailable { release } = check_latest_at(&format!("{base}/latest"), "0.6.86").await.unwrap() else { panic!() };
        let err = download_installer(&test_paths("update-tamper"), &release, |_| {}).await.unwrap_err();
        assert!(err.contains("SHA256"), "{err}");
    }

    #[tokio::test]
    async fn installer_name_cannot_escape_the_updates_folder() {
        let bytes = fake_installer();
        let base = release_server(&bytes, &bytes, true).await;
        let CheckResult::UpdateAvailable { release } = check_latest_at(&format!("{base}/latest"), "0.6.86").await.unwrap() else { panic!() };
        for evil in ["..\\..\\evil.exe", "../../evil.exe", "sub/dir.exe", "..", "a..b.exe"] {
            let mut r = release.clone();
            r.asset.name = evil.to_string();
            let err = download_installer(&test_paths("update-name"), &r, |_| {}).await.unwrap_err();
            assert!(err.contains("Недопустимое имя"), "{evil}: {err}");
        }
    }

    #[tokio::test]
    async fn release_without_a_digest_is_rejected() {
        let bytes = fake_installer();
        let base = release_server(&bytes, &bytes, false).await;
        let CheckResult::UpdateAvailable { release } = check_latest_at(&format!("{base}/latest"), "0.6.86").await.unwrap() else { panic!() };
        let err = download_installer(&test_paths("update-nodigest"), &release, |_| {}).await.unwrap_err();
        assert!(err.contains("digest"), "{err}");
    }

    #[tokio::test]
    async fn unreachable_server_gives_a_readable_error() {
        let err = check_latest_at("http://127.0.0.1:1/latest", "0.6.86").await.unwrap_err();
        assert!(err.contains("Не удалось проверить обновления"), "{err}");
    }

    #[test]
    fn signature_policy_accepts_unsigned_but_rejects_broken_signatures() {
        assert!(signature_verdict("Valid").is_ok());
        assert!(signature_verdict("NotSigned\r\n").is_ok(), "наши релизы пока не подписаны, как и у WinUI-клиента");
        for bad in ["HashMismatch", "NotTrusted", "UnknownError", "NotSupportedFileFormat", ""] {
            assert!(signature_verdict(bad).is_err(), "{bad}");
        }
    }
}
