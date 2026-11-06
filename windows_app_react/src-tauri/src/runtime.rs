//! Среда выполнения: проверка готовности, докачка Chromium после установки, диагностика.
//! Аналог ChromiumBootstrapService / PreflightService / DiagnosticsService из WinUI-клиента.
//! Node и node_modules кладутся в установщик, а Chromium (~150 МБ) докачивается при первом запуске
//! в %LOCALAPPDATA%\SaveMe\worker\ms-playwright — туда же, где его ищет WinUI-клиент.

use std::path::{Path, PathBuf};
use std::process::Stdio;

use serde::Serialize;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;

use crate::paths::AppPaths;

#[derive(Clone, Debug, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeStatus {
    pub chromium_installed: bool,
    pub worker_deps_installed: bool,
    pub node_available: bool,
    pub browsers_dir: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct PreflightCheck {
    pub name: String,
    pub ok: bool,
    pub message: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct Preflight {
    pub ok: bool,
    pub checks: Vec<PreflightCheck>,
}

/// Ищет исполняемый файл Chromium в папке Playwright (ограниченная глубина).
pub fn find_chromium(root: &Path) -> Option<PathBuf> {
    fn walk(dir: &Path, depth: usize) -> Option<PathBuf> {
        if depth == 0 {
            return None;
        }
        let entries = std::fs::read_dir(dir).ok()?;
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().to_lowercase();
            if path.is_file() && (name == "chrome.exe" || name == "chrome") {
                return Some(path);
            }
            if path.is_dir() {
                if let Some(found) = walk(&path, depth - 1) {
                    return Some(found);
                }
            }
        }
        None
    }
    walk(root, 5)
}

fn playwright_cli(paths: &AppPaths) -> PathBuf {
    paths.resource_root().join("node_worker").join("node_modules").join("playwright").join("cli.js")
}

pub fn status(paths: &AppPaths) -> RuntimeStatus {
    let browsers = paths.playwright_browsers();
    RuntimeStatus {
        chromium_installed: find_chromium(&browsers).is_some(),
        worker_deps_installed: playwright_cli(paths).exists(),
        node_available: paths.node_command().is_ok() && (paths.embedded_node().is_some() || which_node()),
        browsers_dir: browsers.to_string_lossy().into_owned(),
    }
}

fn which_node() -> bool {
    std::process::Command::new("node").arg("--version").stdout(Stdio::null()).stderr(Stdio::null()).status().map(|s| s.success()).unwrap_or(false)
}

/// `node playwright/cli.js install chromium`; строки вывода передаются в `on_line`.
pub async fn install_chromium<F: Fn(&str) + Send + Sync + 'static>(paths: &AppPaths, on_line: F) -> Result<String, String> {
    let cli = playwright_cli(paths);
    if !cli.exists() {
        return Err("Не найдены зависимости воркера (node_modules/playwright). Переустановите приложение.".into());
    }
    let (node, _) = paths.node_command()?;
    let browsers = paths.playwright_browsers();
    std::fs::create_dir_all(&browsers).map_err(|e| format!("Не удалось создать папку браузеров: {e}"))?;

    let mut std_cmd = std::process::Command::new(node);
    std_cmd.arg(&cli).args(["install", "chromium"]).env("PLAYWRIGHT_BROWSERS_PATH", &browsers);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        std_cmd.creation_flags(0x0800_0000);
    }
    let mut cmd = Command::from(std_cmd);
    cmd.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).kill_on_drop(true);
    on_line("Скачиваю Chromium для Playwright…");
    let mut child = cmd.spawn().map_err(|e| format!("Не удалось запустить установку Chromium: {e}"))?;

    let on_line = std::sync::Arc::new(on_line);
    let mut tasks = Vec::new();
    if let Some(out) = child.stdout.take() {
        let cb = on_line.clone();
        tasks.push(tokio::spawn(async move {
            let mut lines = BufReader::new(out).lines();
            while let Ok(Some(l)) = lines.next_line().await { cb(&l); }
        }));
    }
    if let Some(err) = child.stderr.take() {
        let cb = on_line.clone();
        tasks.push(tokio::spawn(async move {
            let mut lines = BufReader::new(err).lines();
            while let Ok(Some(l)) = lines.next_line().await { cb(&l); }
        }));
    }
    let exit = child.wait().await.map_err(|e| e.to_string())?;
    for t in tasks {
        let _ = t.await;
    }
    if !exit.success() {
        return Err(format!("Установка Chromium завершилась с ошибкой (код {}).", exit.code().unwrap_or(-1)));
    }
    if find_chromium(&browsers).is_none() {
        return Err("Установка завершилась, но Chromium не найден в папке браузеров.".into());
    }
    Ok("Chromium установлен.".into())
}

fn check(name: &str, action: impl FnOnce() -> Result<String, String>) -> PreflightCheck {
    match action() {
        Ok(message) => PreflightCheck { name: name.into(), ok: true, message },
        Err(message) => PreflightCheck { name: name.into(), ok: false, message },
    }
}

pub fn preflight(paths: &AppPaths, downloads: &Path) -> Preflight {
    let st = status(paths);
    let checks = vec![
        check("Node runtime", || {
            paths.node_command().map(|(n, _)| n.to_string_lossy().into_owned()).and_then(|n| {
                if st.node_available { Ok(n) } else { Err("Node не найден.".to_string()) }
            })
        }),
        check("node_worker", || paths.node_worker_script().map(|p| p.to_string_lossy().into_owned()).ok_or_else(|| "bridge.mjs не найден.".to_string())),
        check("Запись в папку загрузок", || {
            std::fs::create_dir_all(downloads).map_err(|e| e.to_string())?;
            let probe = downloads.join(format!(".write_probe_{}.tmp", std::process::id()));
            std::fs::write(&probe, "ok").map_err(|e| e.to_string())?;
            let _ = std::fs::remove_file(&probe);
            Ok(downloads.to_string_lossy().into_owned())
        }),
        check("Chromium", || if st.chromium_installed { Ok("установлен".into()) } else { Err("не установлен".into()) }),
        check("Зависимости воркера", || if st.worker_deps_installed { Ok("установлены".into()) } else { Err("не установлены".into()) }),
    ];
    Preflight { ok: checks.iter().all(|c| c.ok), checks }
}

/// Хвост самых свежих лог-файлов воркера (по ~200 строк).
fn recent_logs(dir: &Path) -> String {
    let mut files: Vec<(std::time::SystemTime, PathBuf)> = std::fs::read_dir(dir)
        .map(|rd| rd.flatten().filter(|e| e.path().is_file()).filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path()))).collect())
        .unwrap_or_default();
    files.sort_by_key(|(t, _)| std::cmp::Reverse(*t));
    let mut out = String::new();
    for (_, path) in files.into_iter().take(2) {
        let text = std::fs::read_to_string(&path).unwrap_or_default();
        let lines: Vec<&str> = text.lines().collect();
        let tail = &lines[lines.len().saturating_sub(200)..];
        out.push_str(&format!("\n--- {} ---\n{}\n", path.display(), tail.join("\n")));
    }
    out
}

/// Сохраняет отчёт в папку логов и возвращает путь. Пароли и куки в отчёт не попадают.
pub fn export_diagnostics(paths: &AppPaths, version: &str, downloads: &Path) -> Result<PathBuf, String> {
    paths.ensure_directories().map_err(|e| e.to_string())?;
    let pf = preflight(paths, downloads);
    let st = status(paths);
    let mut report = format!("SaveMe {version}\nДанные: {}\nБраузеры: {}\n\nПроверка готовности ({}):\n", paths.application_support().display(), st.browsers_dir, if pf.ok { "ОК" } else { "есть проблемы" });
    for c in &pf.checks {
        report.push_str(&format!("  [{}] {}: {}\n", if c.ok { "ok" } else { "!!" }, c.name, c.message));
    }
    report.push_str(&recent_logs(&paths.logs_directory()));
    let path = paths.logs_directory().join(format!("diagnostics-{}.txt", crate::util::iso_now().replace([':', '-'], "")));
    std::fs::write(&path, report).map_err(|e| e.to_string())?;
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::temp_dir;

    #[test]
    fn finds_chromium_in_nested_folder() {
        let root = temp_dir("chromium");
        assert!(find_chromium(&root).is_none());
        let exe = root.join("chromium-1208/chrome-win/chrome.exe");
        std::fs::create_dir_all(exe.parent().unwrap()).unwrap();
        std::fs::write(&exe, "").unwrap();
        assert_eq!(find_chromium(&root), Some(exe));
    }

    #[test]
    fn preflight_reports_missing_pieces_and_exports_diagnostics() {
        let root = temp_dir("preflight");
        let paths = AppPaths::with_support(root.clone(), root.join("data"));
        let pf = preflight(&paths, &root.join("dl"));
        assert!(!pf.ok);
        assert!(pf.checks.iter().any(|c| c.name == "node_worker" && !c.ok));
        assert!(pf.checks.iter().any(|c| c.name.starts_with("Запись") && c.ok));
        let file = export_diagnostics(&paths, "0.0.0-test", &root.join("dl")).unwrap();
        let text = std::fs::read_to_string(file).unwrap();
        assert!(text.contains("SaveMe 0.0.0-test") && text.contains("[!!] Chromium"));
    }
}
