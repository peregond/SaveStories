//! Раскладка файлов по странам и блогерам. Порт windows_app_winui_beta/.../SortingService.cs.
//! Модуль не знает о настройках: «запомненных блогеров» возвращает наружу, а сохраняет вызывающий код.

use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::path::{Path, PathBuf, MAIN_SEPARATOR};

use serde::{Deserialize, Serialize};

use crate::util::NL;

pub const NO_COUNTRY: &str = "Без страны";

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct RememberedBlogger {
    pub username: String,
    pub country_folder: String,
    pub target_folder: String,
    pub last_used_at: String,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct SortedFileRecord {
    pub id: String,
    pub blogger: String,
    pub country_folder: String,
    pub target_relative_folder: String,
    pub original_path: String,
    pub current_path: String,
}

/// Файл из последней выгрузки воркера (поля как в ответе node_worker).
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct SortItem {
    pub id: String,
    #[serde(rename = "localPath")]
    pub local_path: String,
    #[serde(rename = "sourceURL")]
    pub source_url: String,
}

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SortingResult {
    pub success: bool,
    pub summary: String,
    pub records: Vec<SortedFileRecord>,
    pub failed_items: Vec<String>,
}

impl SortingResult {
    fn failed(message: impl Into<String>) -> Self {
        Self { success: false, summary: message.into(), ..Self::default() }
    }
}

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UndoResult {
    pub summary: String,
    pub restored_records: Vec<SortedFileRecord>,
    pub failed_items: Vec<String>,
}

struct Input {
    id: String,
    blogger: String,
    current_path: String,
    target: String,
}

// ---------------------------------------------------------------- правила

/// Правила `username = Страна (XX)/Папка`; ключи без учёта регистра, порядок первого появления.
#[derive(Clone, Debug, Default)]
pub struct Rules {
    entries: Vec<(String, String)>,
    index: HashMap<String, usize>,
}

impl Rules {
    pub fn len(&self) -> usize {
        self.entries.len()
    }
    pub fn get(&self, username: &str) -> Option<&str> {
        self.index.get(&username.to_lowercase()).map(|i| self.entries[*i].1.as_str())
    }
    pub fn iter(&self) -> impl Iterator<Item = (&str, &str)> {
        self.entries.iter().map(|(k, v)| (k.as_str(), v.as_str()))
    }
}

pub fn parse_rules(text: &str) -> Rules {
    let mut rules = Rules::default();
    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some(sep) = line.find('=') else { continue };
        if sep == 0 || sep >= line.len() - 1 {
            continue;
        }
        let username = line[..sep].trim();
        let target = line[sep + 1..].trim();
        if username.is_empty() || target.is_empty() {
            continue;
        }
        let key = username.to_lowercase();
        match rules.index.get(&key) {
            Some(i) => rules.entries[*i].1 = target.to_string(),
            None => {
                rules.index.insert(key, rules.entries.len());
                rules.entries.push((username.to_string(), target.to_string()));
            }
        }
    }
    rules
}

fn split_path(value: &str) -> Vec<String> {
    value.split(['/', '\\']).map(str::trim).filter(|p| !p.is_empty()).map(str::to_string).collect()
}

fn join_parts(parts: &[String]) -> String {
    parts.join(&MAIN_SEPARATOR.to_string())
}

pub fn target_relative_folder(username: &str, rules: &Rules) -> String {
    let Some(mapped) = rules.get(username).filter(|m| !m.trim().is_empty()) else {
        return username.to_string();
    };
    let mut parts = split_path(mapped.trim());
    if parts.is_empty() {
        return username.to_string();
    }
    if parts.len() == 1 {
        parts.push(username.to_string());
    }
    join_parts(&parts)
}

pub fn country_folder(target: &str, blogger: &str) -> String {
    if target.eq_ignore_ascii_case(blogger) || target.to_lowercase() == blogger.to_lowercase() {
        return NO_COUNTRY.to_string();
    }
    split_path(target).into_iter().next().unwrap_or_else(|| NO_COUNTRY.to_string())
}

/// Блогеры, которые появляются в списке «запомненных» после разбора правил.
pub fn bloggers_from_rules(rules: &Rules, now: &str) -> Vec<RememberedBlogger> {
    rules
        .iter()
        .map(|(username, _)| {
            let target = target_relative_folder(username, rules);
            RememberedBlogger {
                username: username.to_string(),
                country_folder: country_folder(&target, username),
                target_folder: target,
                last_used_at: now.to_string(),
            }
        })
        .collect()
}

pub fn bloggers_from_records(records: &[SortedFileRecord], now: &str) -> Vec<RememberedBlogger> {
    records
        .iter()
        .map(|r| RememberedBlogger {
            username: r.blogger.clone(),
            country_folder: r.country_folder.clone(),
            target_folder: r.target_relative_folder.clone(),
            last_used_at: now.to_string(),
        })
        .collect()
}

/// Слияние: ключ — username без учёта регистра, новые значения заменяют старые; порядок как в C#.
pub fn merge_bloggers(existing: &[RememberedBlogger], fresh: Vec<RememberedBlogger>) -> Vec<RememberedBlogger> {
    let mut merged: HashMap<String, RememberedBlogger> = HashMap::new();
    for b in existing.iter().cloned().chain(fresh) {
        if !b.username.trim().is_empty() {
            merged.insert(b.username.to_lowercase(), b);
        }
    }
    let mut list: Vec<_> = merged.into_values().collect();
    list.sort_by_key(|b| (b.country_folder.to_lowercase(), b.username.to_lowercase()));
    list
}

// ---------------------------------------------------------------- раскладка

fn is_hidden_or_system(path: &Path) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        return fs::metadata(path).map(|m| m.file_attributes() & 0x6 != 0).unwrap_or(true);
    }
    #[cfg(not(windows))]
    {
        path.file_name().map(|n| n.to_string_lossy().starts_with('.')).unwrap_or(true)
    }
}

fn file_name(path: &str) -> String {
    Path::new(path).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}

fn normalized(path: &str) -> String {
    path.replace(['/', '\\'], &MAIN_SEPARATOR.to_string()).trim_end_matches(MAIN_SEPARATOR).to_lowercase()
}

pub fn paths_equal(a: &str, b: &str) -> bool {
    normalized(a) == normalized(b)
}

pub fn distribute_from_source(source: &str, destination_root: &str, rules_text: &str) -> SortingResult {
    let rules = parse_rules(rules_text);
    let source_path = Path::new(source);
    if !source_path.is_dir() {
        return SortingResult::failed(format!("Папка Перенос не найдена: {source}"));
    }
    if let Err(e) = fs::create_dir_all(destination_root) {
        return SortingResult::failed(format!("Не удалось создать папку назначения: {e}"));
    }

    let mut inputs = Vec::new();
    let mut creators: Vec<PathBuf> = fs::read_dir(source_path)
        .map(|rd| rd.flatten().map(|e| e.path()).filter(|p| p.is_dir() && !is_hidden_or_system(p)).collect())
        .unwrap_or_default();
    creators.sort();
    for creator in creators {
        let name = creator.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let mut files: Vec<PathBuf> = fs::read_dir(&creator)
            .map(|rd| rd.flatten().map(|e| e.path()).filter(|p| p.is_file() && !is_hidden_or_system(p)).collect())
            .unwrap_or_default();
        files.sort();
        for file in files {
            let current = file.to_string_lossy().into_owned();
            inputs.push(Input { id: current.clone(), blogger: name.clone(), current_path: current, target: target_relative_folder(&name, &rules) });
        }
    }
    if inputs.is_empty() {
        return SortingResult::failed("В выбранной папке нет файлов для сортировки.");
    }
    distribute(inputs, destination_root)
}

fn source_username(item: &SortItem) -> String {
    let parent = Path::new(&item.local_path)
        .parent()
        .and_then(|p| p.file_name())
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    if !parent.trim().is_empty() {
        return parent;
    }
    if let Some(rest) = item.source_url.split("://").nth(1) {
        if let Some(name) = rest.split('/').skip(1).find(|s| !s.is_empty()) {
            return name.to_string();
        }
    }
    "Без профиля".to_string()
}

pub fn distribute_downloaded_items(items: &[SortItem], destination_root: &str, rules_text: &str) -> SortingResult {
    let rules = parse_rules(rules_text);
    let inputs: Vec<Input> = items
        .iter()
        .filter(|i| !i.local_path.trim().is_empty())
        .map(|i| {
            let blogger = source_username(i);
            Input {
                id: if i.id.trim().is_empty() { i.local_path.clone() } else { i.id.clone() },
                target: target_relative_folder(&blogger, &rules),
                blogger,
                current_path: i.local_path.clone(),
            }
        })
        .collect();
    if inputs.is_empty() {
        return SortingResult::failed("Нет файлов из последней выгрузки для раскладки.");
    }
    if let Err(e) = fs::create_dir_all(destination_root) {
        return SortingResult::failed(format!("Не удалось создать папку назначения: {e}"));
    }
    distribute(inputs, destination_root)
}

/// `rename`, а между томами — копирование с удалением (как File.Move в .NET).
fn move_file(from: &Path, to: &Path) -> std::io::Result<()> {
    if fs::rename(from, to).is_ok() {
        return Ok(());
    }
    fs::copy(from, to)?;
    fs::remove_file(from)
}

fn sort_records(records: &mut [SortedFileRecord]) {
    records.sort_by_key(|r| (r.country_folder.to_lowercase(), r.blogger.to_lowercase(), r.current_path.to_lowercase()));
}

fn distribute(inputs: Vec<Input>, destination_root: &str) -> SortingResult {
    let mut moved: Vec<SortedFileRecord> = Vec::new();
    let mut failed: Vec<String> = Vec::new();
    let mut moved_count = 0usize;

    for input in inputs {
        let current = Path::new(&input.current_path);
        if !current.is_file() {
            failed.push(file_name(&input.current_path));
            continue;
        }
        let mut dest_dir = PathBuf::from(destination_root);
        for part in split_path(&input.target) {
            dest_dir.push(part);
        }
        if let Err(e) = fs::create_dir_all(&dest_dir) {
            failed.push(format!("{}: {e}", file_name(&input.current_path)));
            continue;
        }
        let name = file_name(&input.current_path);
        // Файл уже в нужной папке — оставляем как есть, а не переименовываем в «имя 2».
        let already_there = current.parent().map(|p| paths_equal(&p.to_string_lossy(), &dest_dir.to_string_lossy())).unwrap_or(false);
        let dest_path = if already_there { current.to_path_buf() } else { unique_destination_path(&name, &dest_dir) };

        let outcome = if paths_equal(&input.current_path, &dest_path.to_string_lossy()) {
            Ok(false)
        } else {
            move_file(current, &dest_path).map(|_| true)
        };
        match outcome {
            Ok(did_move) => {
                if did_move {
                    moved_count += 1;
                }
                moved.push(SortedFileRecord {
                    id: input.id,
                    country_folder: country_folder(&input.target, &input.blogger),
                    blogger: input.blogger,
                    target_relative_folder: input.target,
                    original_path: input.current_path,
                    current_path: dest_path.to_string_lossy().into_owned(),
                });
            }
            Err(e) => failed.push(format!("{name}: {e}")),
        }
    }

    let folders = {
        let mut set: Vec<String> = moved.iter().map(|r| r.target_relative_folder.to_lowercase()).collect();
        set.sort();
        set.dedup();
        set.len()
    };
    let summary = if moved_count > 0 {
        format!("Разложено файлов: {moved_count}. Подпапок затронуто: {folders}.")
    } else if !failed.is_empty() {
        format!("Не удалось разложить файлы: {}.", failed.len())
    } else {
        "Файлы уже лежат в нужных папках.".to_string()
    };
    sort_records(&mut moved);
    SortingResult { success: !moved.is_empty() && failed.is_empty(), summary, records: moved, failed_items: failed }
}

pub fn undo_distribution(records: &[SortedFileRecord]) -> UndoResult {
    let mut restored = Vec::new();
    let mut failed = Vec::new();
    for record in records.iter().rev() {
        if record.original_path.trim().is_empty() || record.current_path.trim().is_empty() {
            continue;
        }
        let current = Path::new(&record.current_path);
        if !current.is_file() {
            failed.push(file_name(&record.current_path));
            continue;
        }
        let Some(original_dir) = Path::new(&record.original_path).parent().filter(|p| !p.as_os_str().is_empty()) else {
            failed.push(file_name(&record.current_path));
            continue;
        };
        let attempt = (|| -> std::io::Result<PathBuf> {
            fs::create_dir_all(original_dir)?;
            let target = if Path::new(&record.original_path).exists() && !paths_equal(&record.current_path, &record.original_path) {
                unique_destination_path(&file_name(&record.original_path), original_dir)
            } else {
                PathBuf::from(&record.original_path)
            };
            if !paths_equal(&record.current_path, &target.to_string_lossy()) {
                move_file(current, &target)?;
            }
            Ok(target)
        })();
        match attempt {
            Ok(target) => {
                let mut r = record.clone();
                r.original_path = record.current_path.clone();
                r.current_path = target.to_string_lossy().into_owned();
                restored.push(r);
            }
            Err(e) => failed.push(format!("{}: {e}", file_name(&record.current_path))),
        }
    }
    sort_records(&mut restored);
    let summary = if failed.is_empty() {
        format!("Отменён перенос файлов: {}.", restored.len())
    } else {
        format!("Отменён перенос файлов: {}. Ошибок: {}.", restored.len(), failed.len())
    };
    UndoResult { summary, restored_records: restored, failed_items: failed }
}

/// «имя.jpg» → «имя 2.jpg», «img001.jpg» → «img002.jpg».
pub fn unique_destination_path(file_name: &str, directory: &Path) -> PathBuf {
    let candidate = directory.join(file_name);
    if !candidate.exists() {
        return candidate;
    }
    let path = Path::new(file_name);
    let extension = path.extension().map(|e| format!(".{}", e.to_string_lossy())).unwrap_or_default();
    let stem = path.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
    let (prefix, next, width) = split_trailing_number(&stem);
    let mut index = next;
    loop {
        let number = if width > 0 { format!("{index:0width$}") } else { index.to_string() };
        let adjusted = directory.join(format!("{prefix}{number}{extension}"));
        if !adjusted.exists() {
            return adjusted;
        }
        index += 1;
    }
}

fn split_trailing_number(stem: &str) -> (String, u64, usize) {
    let digits = stem.chars().rev().take_while(char::is_ascii_digit).count();
    if digits == 0 {
        return (format!("{stem} "), 2, 0);
    }
    let split = stem.len() - digits;
    let (prefix, number) = stem.split_at(split);
    (prefix.to_string(), number.parse::<u64>().map(|n| n + 1).unwrap_or(2), number.len())
}

// ---------------------------------------------------------------- дайджесты

struct Group<'a, T> {
    key: String,
    items: Vec<&'a T>,
}

/// Группировка без учёта регистра, порядок по ключу (OrdinalIgnoreCase), отображается первый вариант написания.
fn group_ci<'a, T>(items: impl IntoIterator<Item = &'a T>, key: impl Fn(&T) -> String) -> Vec<Group<'a, T>> {
    let mut map: BTreeMap<String, Group<'a, T>> = BTreeMap::new();
    for item in items {
        let k = key(item);
        map.entry(k.to_lowercase()).or_insert_with(|| Group { key: k, items: Vec::new() }).items.push(item);
    }
    map.into_values().collect()
}

fn by_path_ci(a: &&SortedFileRecord, b: &&SortedFileRecord) -> std::cmp::Ordering {
    a.current_path.to_lowercase().cmp(&b.current_path.to_lowercase())
}

fn nl2() -> String {
    format!("{NL}{NL}")
}

#[allow(dead_code)]
pub fn build_digest(records: &[SortedFileRecord]) -> String {
    let blocks: Vec<String> = group_ci(records, |r| r.country_folder.clone())
        .into_iter()
        .map(|country| {
            let bloggers: Vec<String> = group_ci(country.items.iter().copied(), |r| r.blogger.clone())
                .into_iter()
                .map(|b| {
                    let mut items = b.items;
                    items.sort_by(by_path_ci);
                    let links: Vec<&str> = items.iter().map(|r| r.current_path.as_str()).collect();
                    format!("{}{NL}{}", b.key, links.join(NL))
                })
                .collect();
            format!("{}{}{}", country.key, nl2(), bloggers.join(&nl2()))
        })
        .collect();
    blocks.join(&nl2())
}

fn report_header(r: &SortedFileRecord) -> String {
    if r.target_relative_folder.to_lowercase() == r.blogger.to_lowercase() {
        format!("[{}]", r.target_relative_folder)
    } else {
        format!("[{} ({})]", r.target_relative_folder, r.blogger)
    }
}

pub fn build_post_processed_report(records: &[SortedFileRecord]) -> String {
    let blocks: Vec<String> = group_ci(records, report_header)
        .into_iter()
        .map(|g| {
            let mut items = g.items;
            items.sort_by(by_path_ci);
            let files: Vec<&str> = items.iter().map(|r| r.current_path.as_str()).collect();
            format!("{}{NL}{}", g.key, files.join(NL))
        })
        .collect();
    blocks.join(&nl2())
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DriveOutcome {
    pub record: SortedFileRecord,
    pub link: Option<String>,
    pub error_message: Option<String>,
}

const DRIVE_PREFIX: &str = "https://drive.google.com/";

/// Достаёт ссылки Drive из строки, по одной на строку (как `NormalizeGoogleDriveLinkLines`).
pub fn normalize_drive_link_lines(link: &str) -> String {
    let lower = link.to_ascii_lowercase();
    let starts: Vec<usize> = lower.match_indices(DRIVE_PREFIX).map(|(i, _)| i).collect();
    let mut found = Vec::new();
    for (n, &start) in starts.iter().enumerate() {
        let body = start + DRIVE_PREFIX.len();
        let limit = starts.get(n + 1).copied().unwrap_or(link.len());
        let end = link[body..limit]
            .find(|c: char| c.is_whitespace() || matches!(c, '"' | '\'' | '<' | '>'))
            .map(|i| body + i)
            .unwrap_or(limit);
        if end > body {
            found.push(&link[start..end]);
        }
    }
    if found.is_empty() { link.trim().to_string() } else { found.join(NL) }
}

pub fn build_google_drive_digest(outcomes: &[DriveOutcome]) -> String {
    let blocks: Vec<String> = group_ci(outcomes, |o| o.record.country_folder.clone())
        .into_iter()
        .map(|country| {
            let bloggers: Vec<String> = group_ci(country.items.iter().copied(), |o| o.record.blogger.clone())
                .into_iter()
                .map(|b| {
                    let mut items = b.items;
                    items.sort_by_key(|o| o.record.current_path.to_lowercase());
                    let lines: Vec<String> = items
                        .iter()
                        .map(|o| match o.link.as_deref().filter(|l| !l.trim().is_empty()) {
                            Some(link) => normalize_drive_link_lines(link),
                            None => format!("# не удалось получить ссылку: {}", file_name(&o.record.current_path)),
                        })
                        .collect();
                    format!("{}{NL}{}", b.key, lines.join(NL))
                })
                .collect();
            format!("{}{}{}", country.key, nl2(), bloggers.join(&nl2()))
        })
        .collect();
    blocks.join(&nl2())
}


#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::temp_dir;

    fn write(path: &Path, text: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, text).unwrap();
    }

    #[test]
    fn parses_rules_like_winui() {
        let r = parse_rules("# комментарий\n  Anna = Germany (DE)  \nbob=Australia (AU)/Bob Folder\nbroken=\n=x\nANNA = Austria (AT)\nnoeq");
        assert_eq!(r.len(), 2);
        assert_eq!(r.get("anna"), Some("Austria (AT)"));
        assert_eq!(r.get("BOB"), Some("Australia (AU)/Bob Folder"));
        assert_eq!(r.iter().next().unwrap().0, "Anna");
    }

    #[test]
    fn target_folder_and_country() {
        let r = parse_rules("anna = Germany (DE)\nbob = Australia (AU)/Bob Folder");
        let sep = MAIN_SEPARATOR;
        assert_eq!(target_relative_folder("anna", &r), format!("Germany (DE){sep}anna"));
        assert_eq!(target_relative_folder("bob", &r), format!("Australia (AU){sep}Bob Folder"));
        assert_eq!(target_relative_folder("zed", &r), "zed");
        assert_eq!(country_folder("zed", "zed"), NO_COUNTRY);
        assert_eq!(country_folder(&format!("Germany (DE){sep}anna"), "anna"), "Germany (DE)");
    }

    #[test]
    fn unique_names_follow_trailing_numbers() {
        let dir = temp_dir("unique");
        write(&dir.join("photo.jpg"), "x");
        assert_eq!(unique_destination_path("photo.jpg", &dir), dir.join("photo 2.jpg"));
        write(&dir.join("photo 2.jpg"), "x");
        assert_eq!(unique_destination_path("photo.jpg", &dir), dir.join("photo 3.jpg"));
        write(&dir.join("img001.jpg"), "x");
        assert_eq!(unique_destination_path("img001.jpg", &dir), dir.join("img002.jpg"));
        assert_eq!(unique_destination_path("fresh.png", &dir), dir.join("fresh.png"));
    }

    #[test]
    fn distributes_from_source_and_undoes() {
        let root = temp_dir("distribute");
        let src = root.join("На перенос");
        let dst = root.join("Исходники");
        write(&src.join("anna/1.mp4"), "a");
        write(&src.join("anna/2.mp4"), "b");
        write(&src.join("zed/9.mp4"), "c");
        write(&dst.join("Germany (DE)/anna/1.mp4"), "old");

        let result = distribute_from_source(&src.to_string_lossy(), &dst.to_string_lossy(), "anna = Germany (DE)");
        assert!(result.success, "{:?}", result.failed_items);
        assert_eq!(result.records.len(), 3);
        assert!(result.summary.starts_with("Разложено файлов: 3."), "{}", result.summary);
        // «1.mp4» занят → числовое имя увеличивается (как в SortingService.cs): 1 → 2, затем 2 → 3.
        assert_eq!(fs::read_to_string(dst.join("Germany (DE)/anna/1.mp4")).unwrap(), "old");
        assert_eq!(fs::read_to_string(dst.join("Germany (DE)/anna/2.mp4")).unwrap(), "a");
        assert_eq!(fs::read_to_string(dst.join("Germany (DE)/anna/3.mp4")).unwrap(), "b");
        assert!(dst.join("zed/9.mp4").exists());
        assert!(!src.join("anna/1.mp4").exists());
        assert_eq!(result.records.iter().find(|r| r.blogger == "zed").unwrap().country_folder, NO_COUNTRY);

        let undo = undo_distribution(&result.records);
        assert!(undo.failed_items.is_empty(), "{:?}", undo.failed_items);
        assert!(src.join("anna/1.mp4").exists() && src.join("zed/9.mp4").exists());
        assert_eq!(fs::read_to_string(dst.join("Germany (DE)/anna/1.mp4")).unwrap(), "old");
    }

    #[test]
    fn files_already_in_place_are_not_renamed() {
        let root = temp_dir("inplace");
        let file = root.join("dst/Germany (DE)/anna/1.mp4");
        write(&file, "a");
        let items = [SortItem { id: "1".into(), local_path: file.to_string_lossy().into(), source_url: String::new() }];
        let result = distribute_downloaded_items(&items, &root.join("dst").to_string_lossy(), "anna = Germany (DE)");
        assert!(file.exists());
        assert!(!root.join("dst/Germany (DE)/anna/2.mp4").exists());
        assert_eq!(result.summary, "Файлы уже лежат в нужных папках.");
    }

    #[test]
    fn reports_missing_inputs() {
        assert!(distribute_from_source("/definitely/missing", "/tmp/x", "").summary.starts_with("Папка Перенос не найдена"));
        assert_eq!(distribute_downloaded_items(&[], "/tmp/x", "").summary, "Нет файлов из последней выгрузки для раскладки.");
        let root = temp_dir("emptysrc");
        assert_eq!(distribute_from_source(&root.to_string_lossy(), "/tmp/x", "").summary, "В выбранной папке нет файлов для сортировки.");
    }

    #[test]
    fn username_comes_from_parent_folder_or_url() {
        let a = SortItem { id: "".into(), local_path: "/x/anna/1.mp4".into(), source_url: "".into() };
        let b = SortItem { id: "".into(), local_path: "1.mp4".into(), source_url: "https://www.instagram.com/bob/".into() };
        let c = SortItem::default();
        assert_eq!(source_username(&a), "anna");
        assert_eq!(source_username(&b), "bob");
        assert_eq!(source_username(&c), "Без профиля");
    }

    fn rec(blogger: &str, country: &str, target: &str, path: &str) -> SortedFileRecord {
        SortedFileRecord { id: path.into(), blogger: blogger.into(), country_folder: country.into(), target_relative_folder: target.into(), original_path: path.into(), current_path: path.into() }
    }

    #[test]
    fn digests_group_by_country_and_blogger() {
        let records = vec![rec("bob", "Germany", "Germany/bob", "b2"), rec("anna", "Germany", "Germany/anna", "a1"), rec("bob", "Germany", "Germany/bob", "b1"), rec("zed", NO_COUNTRY, "zed", "z1")];
        let expected = format!("Germany{NL}{NL}anna{NL}a1{NL}{NL}bob{NL}b1{NL}b2{NL}{NL}{NO_COUNTRY}{NL}{NL}zed{NL}z1");
        assert_eq!(build_digest(&records), expected);
        let report = build_post_processed_report(&records);
        assert_eq!(report, format!("[Germany/anna (anna)]{NL}a1{NL}{NL}[Germany/bob (bob)]{NL}b1{NL}b2{NL}{NL}[zed]{NL}z1"));
    }

    #[test]
    fn drive_digest_normalizes_links_and_marks_failures() {
        let ok = DriveOutcome { record: rec("anna", "Germany", "Germany/anna", "/d/a.mp4"), link: Some("see https://drive.google.com/open?id=AAA111 https://drive.google.com/open?id=BBB222".into()), error_message: None };
        let bad = DriveOutcome { record: rec("anna", "Germany", "Germany/anna", "/d/b.mp4"), link: None, error_message: Some("x".into()) };
        let out = build_google_drive_digest(&[bad, ok]);
        assert_eq!(out, format!("Germany{NL}{NL}anna{NL}https://drive.google.com/open?id=AAA111{NL}https://drive.google.com/open?id=BBB222{NL}# не удалось получить ссылку: b.mp4"));
    }

    #[test]
    fn merges_bloggers_by_username() {
        let old = vec![RememberedBlogger { username: "Anna".into(), country_folder: "Z".into(), ..Default::default() }];
        let fresh = vec![RememberedBlogger { username: "anna".into(), country_folder: "A".into(), ..Default::default() }, RememberedBlogger { username: "bob".into(), country_folder: "A".into(), ..Default::default() }];
        let merged = merge_bloggers(&old, fresh);
        assert_eq!(merged.iter().map(|b| (b.username.as_str(), b.country_folder.as_str())).collect::<Vec<_>>(), vec![("anna", "A"), ("bob", "A")]);
    }
}
