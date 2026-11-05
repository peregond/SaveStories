//! Пути приложения. Повторяют windows_app/savestories_windows/app_paths.py,
//! чтобы новый клиент работал с теми же данными, профилем браузера и сессией Instagram.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub const APP_NAME: &str = "SaveMe";
const LEGACY_APP_NAMES: [&str; 2] = ["SaveStories", "DimaSave"];

#[derive(Clone, Debug)]
pub struct AppPaths {
    resource_root: PathBuf,
}

fn env_path(key: &str) -> Option<PathBuf> {
    std::env::var_os(key).filter(|v| !v.is_empty()).map(PathBuf::from)
}

fn home_dir() -> PathBuf {
    env_path("USERPROFILE").or_else(|| env_path("HOME")).unwrap_or_else(|| PathBuf::from("."))
}

fn local_root() -> PathBuf {
    env_path("LOCALAPPDATA")
        .or_else(|| env_path("APPDATA"))
        .unwrap_or_else(|| home_dir().join("AppData").join("Local"))
}

impl AppPaths {
    pub fn new() -> Self {
        Self { resource_root: detect_resource_root() }
    }

    #[cfg(test)]
    pub fn with_root(root: PathBuf) -> Self {
        Self { resource_root: root }
    }

    pub fn resource_root(&self) -> &Path {
        &self.resource_root
    }

    pub fn application_support(&self) -> PathBuf {
        env_path("SAVESTORIES_APP_SUPPORT").unwrap_or_else(|| local_root().join(APP_NAME))
    }

    pub fn worker_root(&self) -> PathBuf {
        self.application_support().join("worker")
    }

    pub fn browser_profile(&self) -> PathBuf {
        self.worker_root().join("browser-profile")
    }

    pub fn manifests_directory(&self) -> PathBuf {
        self.application_support().join("manifests")
    }

    pub fn logs_directory(&self) -> PathBuf {
        self.application_support().join("logs")
    }

    pub fn updates_directory(&self) -> PathBuf {
        self.application_support().join("updates")
    }

    pub fn settings_file(&self) -> PathBuf {
        self.application_support().join("settings.json")
    }

    pub fn playwright_browsers(&self) -> PathBuf {
        let bundled = self.resource_root.join("runtime").join("ms-playwright");
        if bundled.exists() {
            bundled
        } else {
            self.worker_root().join("ms-playwright")
        }
    }

    pub fn default_downloads(&self) -> PathBuf {
        match env_path("USERPROFILE") {
            Some(profile) => profile.join("Downloads").join(APP_NAME),
            None => self.application_support().join("Downloads"),
        }
    }

    pub fn node_worker_script(&self) -> Option<PathBuf> {
        let candidate = self.resource_root.join("node_worker").join("bridge.mjs");
        candidate.exists().then_some(candidate)
    }

    pub fn embedded_node(&self) -> Option<PathBuf> {
        ["node.exe", "bin/node.exe", "bin/node", "node"]
            .iter()
            .map(|name| self.resource_root.join("runtime").join("node").join(name))
            .find(|p| p.exists())
    }

    pub fn has_embedded_runtime(&self) -> bool {
        self.embedded_node().is_some() && self.node_worker_script().is_some() && self.playwright_browsers().exists()
    }

    /// Программа и скрипт для запуска воркера: встроенный Node, иначе Node из PATH.
    pub fn node_command(&self) -> Result<(PathBuf, PathBuf), String> {
        let script = self
            .node_worker_script()
            .ok_or_else(|| "Не удалось найти node_worker/bridge.mjs. Переустанови приложение.".to_string())?;
        if let Some(node) = self.embedded_node() {
            return Ok((node, script));
        }
        Ok((PathBuf::from("node"), script))
    }

    pub fn ensure_directories(&self) -> io::Result<()> {
        self.migrate_legacy_application_support();
        for dir in [
            self.application_support(),
            self.worker_root(),
            self.browser_profile(),
            self.manifests_directory(),
            self.logs_directory(),
            self.updates_directory(),
            self.playwright_browsers(),
            self.default_downloads(),
        ] {
            fs::create_dir_all(dir)?;
        }
        Ok(())
    }

    fn migrate_legacy_application_support(&self) {
        if env_path("SAVESTORIES_APP_SUPPORT").is_some() {
            return;
        }
        let root = local_root();
        let current = root.join(APP_NAME);
        if current.exists() {
            return;
        }
        for legacy in LEGACY_APP_NAMES {
            let old = root.join(legacy);
            if old.exists() {
                let _ = fs::rename(old, &current);
                return;
            }
        }
    }
}

fn detect_resource_root() -> PathBuf {
    if let Some(root) = env_path("SAVEME_RESOURCE_ROOT") {
        return root;
    }
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(Path::to_path_buf))
        .unwrap_or_else(|| PathBuf::from("."));
    // Установленная версия: node_worker лежит рядом с exe. В разработке поднимаемся к корню репозитория.
    let mut dir = Some(exe_dir.as_path());
    for _ in 0..8 {
        match dir {
            Some(d) if d.join("node_worker").join("bridge.mjs").exists() => return d.to_path_buf(),
            Some(d) => dir = d.parent(),
            None => break,
        }
    }
    exe_dir
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("saveme-paths-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn finds_embedded_node_and_worker() {
        let root = temp("embedded");
        fs::create_dir_all(root.join("runtime/node")).unwrap();
        fs::write(root.join("runtime/node/node.exe"), b"").unwrap();
        fs::create_dir_all(root.join("node_worker")).unwrap();
        fs::write(root.join("node_worker/bridge.mjs"), b"").unwrap();
        let paths = AppPaths::with_root(root.clone());
        let (node, script) = paths.node_command().unwrap();
        assert_eq!(node, root.join("runtime/node/node.exe"));
        assert_eq!(script, root.join("node_worker/bridge.mjs"));
    }

    #[test]
    fn falls_back_to_system_node() {
        let root = temp("fallback");
        fs::create_dir_all(root.join("node_worker")).unwrap();
        fs::write(root.join("node_worker/bridge.mjs"), b"").unwrap();
        let (node, _) = AppPaths::with_root(root).node_command().unwrap();
        assert_eq!(node, PathBuf::from("node"));
    }

    #[test]
    fn missing_worker_is_an_error() {
        let root = temp("missing");
        assert!(AppPaths::with_root(root).node_command().is_err());
    }
}
