//! Настройки приложения в settings.json (папка данных SaveMe). При первом запуске
//! подтягиваются значения из реестра старого Python-клиента (QSettings), чтобы
//! тема, папка сохранения и недавние наборы не потерялись.

use serde::{Deserialize, Serialize};
use std::fs;

use crate::paths::AppPaths;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    pub theme: String,
    pub download_mode: String,
    pub media_filter: String,
    pub save_directory: String,
    pub prevent_sleep: bool,
    pub recent_lists: Vec<Vec<String>>,
    pub last_update_check_at: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            theme: "system".into(),
            download_mode: "background".into(),
            media_filter: "video_only".into(),
            save_directory: String::new(),
            prevent_sleep: true,
            recent_lists: Vec::new(),
            last_update_check_at: String::new(),
        }
    }
}

impl Settings {
    /// Приводит значения к допустимым, чтобы битый файл не ломал запуск воркера.
    pub fn sanitized(mut self) -> Self {
        if !matches!(self.theme.as_str(), "system" | "light" | "dark") {
            self.theme = "system".into();
        }
        if !matches!(self.download_mode.as_str(), "background" | "visible") {
            self.download_mode = "background".into();
        }
        if !matches!(self.media_filter.as_str(), "all" | "video_only") {
            self.media_filter = "video_only".into();
        }
        self.recent_lists.retain(|l| !l.is_empty());
        self.recent_lists.truncate(12);
        self
    }
}

pub fn load(paths: &AppPaths) -> Settings {
    let mut settings = match fs::read_to_string(paths.settings_file()) {
        Ok(text) => serde_json::from_str::<Settings>(&text).unwrap_or_default(),
        Err(_) => migrate_legacy().unwrap_or_default(),
    };
    if settings.save_directory.trim().is_empty() {
        settings.save_directory = paths.default_downloads().to_string_lossy().into_owned();
    }
    settings.sanitized()
}

pub fn save(paths: &AppPaths, settings: &Settings) -> Result<(), String> {
    let settings = settings.clone().sanitized();
    fs::create_dir_all(paths.application_support()).map_err(|e| e.to_string())?;
    let text = serde_json::to_string_pretty(&settings).map_err(|e| e.to_string())?;
    let tmp = paths.settings_file().with_extension("json.tmp");
    fs::write(&tmp, text).map_err(|e| e.to_string())?;
    fs::rename(&tmp, paths.settings_file()).map_err(|e| e.to_string())
}

#[cfg(windows)]
fn migrate_legacy() -> Option<Settings> {
    use winreg::{enums::HKEY_CURRENT_USER, RegKey};
    let key = RegKey::predef(HKEY_CURRENT_USER).open_subkey(r"Software\SaveMe\Windows").ok()?;
    let get = |name: &str| key.get_value::<String, _>(name).ok().filter(|v| !v.trim().is_empty());
    let mut s = Settings::default();
    if let Some(v) = get("theme") { s.theme = v.to_lowercase(); }
    if let Some(v) = get("download_mode") { s.download_mode = v; }
    if let Some(v) = get("media_filter") { s.media_filter = v; }
    if let Some(v) = get("save_directory") { s.save_directory = v; }
    if let Some(v) = get("prevent_sleep_during_downloads") { s.prevent_sleep = matches!(v.to_lowercase().as_str(), "true" | "1"); }
    if let Some(v) = get("recent_batch_lists") {
        if let Ok(lists) = parse_recent(&v) { s.recent_lists = lists; }
    }
    Some(s)
}

#[cfg(not(windows))]
fn migrate_legacy() -> Option<Settings> {
    None
}

/// Старый формат: JSON-массив объектов с полем `profiles` либо массив массивов.
#[cfg_attr(not(windows), allow(dead_code))]
fn parse_recent(raw: &str) -> Result<Vec<Vec<String>>, serde_json::Error> {
    let value: serde_json::Value = serde_json::from_str(raw)?;
    let mut out = Vec::new();
    if let Some(items) = value.as_array() {
        for item in items {
            let list = item.get("profiles").unwrap_or(item);
            if let Some(arr) = list.as_array() {
                let names: Vec<String> = arr.iter().filter_map(|v| v.as_str().map(str::to_owned)).collect();
                if !names.is_empty() {
                    out.push(names);
                }
            }
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizes_invalid_values() {
        let s = Settings { theme: "neon".into(), download_mode: "x".into(), media_filter: "y".into(), ..Settings::default() }.sanitized();
        assert_eq!((s.theme.as_str(), s.download_mode.as_str(), s.media_filter.as_str()), ("system", "background", "video_only"));
    }

    #[test]
    fn partial_file_gets_defaults() {
        let s: Settings = serde_json::from_str(r#"{"theme":"dark"}"#).unwrap();
        assert_eq!(s.theme, "dark");
        assert!(s.prevent_sleep);
    }

    #[test]
    fn parses_both_recent_formats() {
        let a = parse_recent(r#"[["a","b"],["c"]]"#).unwrap();
        let b = parse_recent(r#"[{"title":"x","profiles":["a","b"]},{"profiles":[]}]"#).unwrap();
        assert_eq!(a, vec![vec!["a", "b"], vec!["c"]]);
        assert_eq!(b, vec![vec!["a", "b"]]);
    }
}
