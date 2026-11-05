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
    let url = api_url();
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
    if version_key(&version) <= version_key(CURRENT_VERSION) {
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

#[cfg(windows)]
fn verify_signature(path: &Path) -> Result<(), String> {
    use std::os::windows::process::CommandExt;
    let script = "$signature = Get-AuthenticodeSignature -LiteralPath $args[0]; if ($signature.Status -ne 'Valid') { Write-Error ('Installer signature is not valid: ' + $signature.Status); exit 1 }";
    let output = std::process::Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script])
        .arg(path)
        .creation_flags(0x0800_0000)
        .output()
        .map_err(|e| e.to_string())?;
    if output.status.success() {
        Ok(())
    } else {
        let details = String::from_utf8_lossy(if output.stderr.is_empty() { &output.stdout } else { &output.stderr }).trim().to_owned();
        Err(format!("Подпись установщика обновления недействительна. {details}"))
    }
}

#[cfg(not(windows))]
fn verify_signature(_path: &Path) -> Result<(), String> {
    Ok(())
}

pub async fn prepare_install(app: &AppHandle, paths: &AppPaths, release: &ReleaseInfo) -> Result<PathBuf, String> {
    if !supports_auto_install() {
        return Err("Автоустановка доступна только для версии, установленной через инсталлятор. Скачай новый установщик вручную.".into());
    }
    paths.ensure_directories().map_err(|e| e.to_string())?;
    let root = paths.updates_directory().join(&release.version);
    let _ = std::fs::remove_dir_all(&root);
    std::fs::create_dir_all(&root).map_err(|e| e.to_string())?;
    let installer = root.join(&release.asset.name);

    let emit = |percent: u32| {
        let _ = app.emit("update-progress", Progress { percent, message: format!("Скачивание обновления {}: {percent}%", release.version) });
    };
    emit(0);
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
                emit(percent);
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
}
