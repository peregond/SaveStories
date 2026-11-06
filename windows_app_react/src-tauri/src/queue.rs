//! Очередь профилей на диске (queue.json), чтобы список не терялся при закрытии или падении приложения.
//! Файл не доверенный: при чтении данные приводятся к допустимым, повреждённый файл не ломает запуск.

use std::collections::HashSet;
use std::fs;

use serde::{Deserialize, Serialize};

use crate::paths::AppPaths;

pub const MAX_ENTRIES: usize = 5000;
const MAX_URL: usize = 2048;
const MAX_MESSAGE: usize = 500;
const STATUSES: [&str; 5] = ["pending", "running", "completed", "failed", "stopped"];

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QueueEntry {
    pub url: String,
    pub status: String,
    #[serde(default)]
    pub message: String,
}

pub fn sanitize(entries: Vec<QueueEntry>) -> Vec<QueueEntry> {
    let mut seen = HashSet::new();
    entries
        .into_iter()
        .filter_map(|mut e| {
            e.url = e.url.trim().to_string();
            if e.url.is_empty() || e.url.len() > MAX_URL || !seen.insert(e.url.to_lowercase()) {
                return None;
            }
            if !STATUSES.contains(&e.status.as_str()) {
                e.status = "pending".into();
            }
            e.message = e.message.chars().take(MAX_MESSAGE).collect();
            Some(e)
        })
        .take(MAX_ENTRIES)
        .collect()
}

pub fn load(paths: &AppPaths) -> Vec<QueueEntry> {
    let file = paths.queue_file();
    let Ok(text) = fs::read_to_string(&file) else { return Vec::new() };
    match serde_json::from_str::<Vec<QueueEntry>>(&text) {
        Ok(list) => sanitize(list),
        Err(_) => {
            // Не удаляем молча: повреждённый файл можно посмотреть и приложить к отчёту.
            let _ = fs::rename(&file, file.with_extension("json.bad"));
            Vec::new()
        }
    }
}

pub fn save(paths: &AppPaths, entries: Vec<QueueEntry>) -> Result<(), String> {
    let file = paths.queue_file();
    let entries = sanitize(entries);
    if entries.is_empty() {
        return match fs::remove_file(&file) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(e.to_string()),
        };
    }
    fs::create_dir_all(paths.application_support()).map_err(|e| e.to_string())?;
    let tmp = file.with_extension("json.tmp");
    fs::write(&tmp, serde_json::to_string(&entries).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    fs::rename(&tmp, &file).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::temp_dir;

    fn entry(url: &str, status: &str) -> QueueEntry {
        QueueEntry { url: url.into(), status: status.into(), message: String::new() }
    }

    fn paths(name: &str) -> AppPaths {
        let root = temp_dir(name);
        AppPaths::with_support(root.clone(), root.join("data"))
    }

    #[test]
    fn sanitize_cleans_untrusted_data() {
        let long = "x".repeat(MAX_URL + 1);
        let mut with_long_message = entry("https://www.instagram.com/c/", "failed");
        with_long_message.message = "я".repeat(MAX_MESSAGE + 50);
        let cleaned = sanitize(vec![
            entry("  https://www.instagram.com/a/  ", "completed"),
            entry("HTTPS://WWW.INSTAGRAM.COM/A/", "pending"), // дубликат без учёта регистра
            entry("", "pending"),
            entry(&long, "pending"),
            entry("https://www.instagram.com/b/", "hacked"), // неизвестный статус
            with_long_message,
        ]);
        assert_eq!(cleaned.len(), 3);
        assert_eq!(cleaned[0].url, "https://www.instagram.com/a/");
        assert_eq!(cleaned[1].status, "pending");
        assert_eq!(cleaned[2].message.chars().count(), MAX_MESSAGE);
    }

    #[test]
    fn sanitize_caps_the_size() {
        let many: Vec<_> = (0..MAX_ENTRIES + 10).map(|i| entry(&format!("u{i}"), "pending")).collect();
        assert_eq!(sanitize(many).len(), MAX_ENTRIES);
    }

    #[test]
    fn saves_and_loads_round_trip_and_clears() {
        let p = paths("queue-roundtrip");
        assert!(load(&p).is_empty(), "нет файла — пустая очередь");
        let list = vec![entry("https://www.instagram.com/a/", "completed"), entry("https://www.instagram.com/b/", "running")];
        save(&p, list.clone()).unwrap();
        assert_eq!(load(&p), list);
        save(&p, vec![]).unwrap();
        assert!(!p.queue_file().exists(), "пустая очередь удаляет файл");
        save(&p, vec![]).unwrap();
    }

    #[test]
    fn corrupt_file_is_set_aside_not_fatal() {
        let p = paths("queue-corrupt");
        fs::create_dir_all(p.application_support()).unwrap();
        fs::write(p.queue_file(), "{ not json").unwrap();
        assert!(load(&p).is_empty());
        assert!(p.queue_file().with_extension("json.bad").exists());
        assert!(!p.queue_file().exists());
    }
}
