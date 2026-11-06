//! Настройки приложения в settings.json (папка данных SaveMe). При первом запуске
//! подтягиваются значения из реестра старого Python-клиента (QSettings), чтобы
//! тема, папка сохранения и недавние наборы не потерялись.

use serde::{Deserialize, Serialize};
use std::fs;

use crate::paths::AppPaths;
use crate::sorting::RememberedBlogger;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    pub theme: String,
    pub automatic_theme_by_time: bool,
    pub download_mode: String,
    pub media_filter: String,
    pub save_directory: String,
    pub prevent_sleep: bool,
    pub recent_lists: Vec<Vec<String>>,
    pub last_update_check_at: String,
    pub runtime_prompt_shown: bool,
    // Сортировка
    pub empty_folder_cleanup_directory: String,
    pub sorting_source_directory: String,
    pub sorting_destination_directory: String,
    pub sorting_rules: String,
    pub remembered_bloggers: Vec<RememberedBlogger>,
    // Notion
    pub notion_influencer_enabled: bool,
    pub notion_routing_rules_enabled: bool,
    pub notion_influencer_last_refresh_at: String,
    pub notion_influencer_cached_profiles: Vec<String>,
    pub notion_routing_rules_last_refresh_at: String,
    pub notion_routing_rules_cached_rules: String,
    // Уникализатор
    pub unik_output_directory: String,
    /// Настройки раздела целиком (JSON): интерфейс сам хранит и разбирает их.
    pub unik_options: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            theme: "system".into(),
            automatic_theme_by_time: true,
            download_mode: "background".into(),
            media_filter: "video_only".into(),
            save_directory: String::new(),
            prevent_sleep: true,
            recent_lists: Vec::new(),
            last_update_check_at: String::new(),
            runtime_prompt_shown: false,
            empty_folder_cleanup_directory: String::new(),
            sorting_source_directory: String::new(),
            sorting_destination_directory: String::new(),
            sorting_rules: String::new(),
            remembered_bloggers: Vec::new(),
            notion_influencer_enabled: false,
            notion_routing_rules_enabled: false,
            notion_influencer_last_refresh_at: String::new(),
            notion_influencer_cached_profiles: Vec::new(),
            notion_routing_rules_last_refresh_at: String::new(),
            notion_routing_rules_cached_rules: String::new(),
            unik_output_directory: String::new(),
            unik_options: String::new(),
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
        Err(_) => migrate_winui().or_else(migrate_legacy).unwrap_or_default(),
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

/// Ключ без учёта регистра: WinUI пишет PascalCase, мы — camelCase.
fn pick<'a>(v: &'a serde_json::Value, key: &str) -> Option<&'a serde_json::Value> {
    v.as_object()?.iter().find(|(k, _)| k.eq_ignore_ascii_case(key)).map(|(_, v)| v)
}

fn text(v: &serde_json::Value, key: &str) -> Option<String> {
    pick(v, key)?.as_str().map(str::to_string)
}

/// Импорт settings.json выпускаемого WinUI-клиента (%LOCALAPPDATA%\SaveMe.WinUI).
pub fn import_winui(raw: &str) -> Option<Settings> {
    let v: serde_json::Value = serde_json::from_str(raw).ok()?;
    let mut s = Settings::default();
    if let Some(t) = text(&v, "Theme") { s.theme = t.to_lowercase(); }
    if let Some(b) = pick(&v, "AutomaticThemeByTimeEnabled").and_then(|x| x.as_bool()) { s.automatic_theme_by_time = b; }
    if let Some(b) = pick(&v, "RuntimePromptShown").and_then(|x| x.as_bool()) { s.runtime_prompt_shown = b; }
    if let Some(t) = text(&v, "StoriesOutputDirectory") { s.save_directory = t; }
    if let Some(t) = text(&v, "EmptyFolderCleanupDirectory") { s.empty_folder_cleanup_directory = t; }
    if let Some(t) = text(&v, "SortingSourceDirectory") { s.sorting_source_directory = t; }
    if let Some(t) = text(&v, "SortingDestinationDirectory") { s.sorting_destination_directory = t; }
    if let Some(t) = text(&v, "SortingRules") { s.sorting_rules = t; }
    if let Some(b) = pick(&v, "NotionInfluencerSourceEnabled").and_then(|x| x.as_bool()) { s.notion_influencer_enabled = b; }
    if let Some(b) = pick(&v, "NotionRoutingRulesSourceEnabled").and_then(|x| x.as_bool()) { s.notion_routing_rules_enabled = b; }
    if let Some(t) = text(&v, "NotionInfluencerLastRefreshAt") { s.notion_influencer_last_refresh_at = t; }
    if let Some(t) = text(&v, "NotionRoutingRulesLastRefreshAt") { s.notion_routing_rules_last_refresh_at = t; }
    if let Some(t) = text(&v, "NotionRoutingRulesCachedRules") { s.notion_routing_rules_cached_rules = t; }
    if let Some(arr) = pick(&v, "NotionInfluencerCachedProfiles").and_then(|x| x.as_array()) {
        s.notion_influencer_cached_profiles = arr.iter().filter_map(|x| x.as_str().map(str::to_string)).collect();
    }
    if let Some(arr) = pick(&v, "RememberedBloggers").and_then(|x| x.as_array()) {
        s.remembered_bloggers = arr
            .iter()
            .map(|b| RememberedBlogger {
                username: text(b, "Username").unwrap_or_default(),
                country_folder: text(b, "CountryFolder").unwrap_or_default(),
                target_folder: text(b, "TargetFolder").unwrap_or_default(),
                last_used_at: text(b, "LastUsedAt").unwrap_or_default(),
            })
            .filter(|b| !b.username.is_empty())
            .collect();
    }
    Some(s)
}

fn migrate_winui() -> Option<Settings> {
    let root = std::env::var_os("LOCALAPPDATA").map(std::path::PathBuf::from)?;
    ["SaveMe.WinUI", "SaveMe.WinUI.Beta", "SaveStories.WinUI.Beta"]
        .iter()
        .map(|dir| root.join(dir).join("settings.json"))
        .find_map(|path| fs::read_to_string(path).ok())
        .and_then(|text| import_winui(&text))
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
    fn imports_winui_settings_with_pascal_case_keys() {
        let raw = r#"{"SchemaVersion":10,"Theme":"Dark","AutomaticThemeByTimeEnabled":false,"StoriesOutputDirectory":"D:\\Stories",
          "SortingSourceDirectory":"D:\\Src","SortingDestinationDirectory":"D:\\Dst","SortingRules":"a = DE",
          "NotionRoutingRulesSourceEnabled":true,"NotionInfluencerCachedProfiles":["https://www.instagram.com/a/"],
          "RememberedBloggers":[{"Username":"a","CountryFolder":"DE","TargetFolder":"DE\\a","LastUsedAt":"2026-10-01T10:00:00+03:00"}]}"#;
        let s = import_winui(raw).unwrap();
        assert_eq!(s.theme, "dark");
        assert!(!s.automatic_theme_by_time && s.notion_routing_rules_enabled);
        assert_eq!(s.save_directory, "D:\\Stories");
        assert_eq!(s.sorting_rules, "a = DE");
        assert_eq!(s.notion_influencer_cached_profiles.len(), 1);
        assert_eq!(s.remembered_bloggers[0].country_folder, "DE");
        assert!(import_winui("not json").is_none());
    }

    #[test]
    fn parses_both_recent_formats() {
        let a = parse_recent(r#"[["a","b"],["c"]]"#).unwrap();
        let b = parse_recent(r#"[{"title":"x","profiles":["a","b"]},{"profiles":[]}]"#).unwrap();
        assert_eq!(a, vec![vec!["a", "b"], vec!["c"]]);
        assert_eq!(b, vec![vec!["a", "b"]]);
    }
}
