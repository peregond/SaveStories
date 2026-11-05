//! Ссылки на файлы Google Drive (Drive для компьютера хранит id файла в альтернативных потоках NTFS).
//! Порт GoogleDriveLinkExporter.cs. Чтение потоков работает только в Windows, разбор метаданных — везде.

use regex::Regex;

use crate::sorting::{DriveOutcome, SortedFileRecord};

pub const RETRY_COUNT: usize = 15;
pub const RETRY_DELAY_SECS: u64 = 2;

pub fn is_drive_item_id(value: &str) -> bool {
    (10..=128).contains(&value.chars().count()) && value.chars().all(|c| c.is_alphanumeric() || c == '_' || c == '-')
}

#[cfg_attr(not(windows), allow(dead_code))]
pub fn link_from_metadata(stream_name: &str, metadata: &str) -> Option<String> {
    if metadata.trim().is_empty() {
        return None;
    }
    let url = Regex::new(r#"(?i)https://drive\.google\.com/[^\s"'<>]+"#).unwrap();
    if let Some(m) = url.find(metadata) {
        return Some(m.as_str().to_string());
    }
    let open_id = Regex::new(r"(?i)(?:open\?id=|/file/d/|/folders/)([A-Za-z0-9_-]+)").unwrap();
    if let Some(c) = open_id.captures(metadata) {
        return Some(format!("https://drive.google.com/open?id={}", &c[1]));
    }
    let stream = stream_name.to_lowercase();
    if stream.contains("user.drive.itemprotostr") {
        let proto = Regex::new(r#"(?i)(?:id|item_id|drive_id)["'\s:=]+([A-Za-z0-9_-]{10,128})"#).unwrap();
        if let Some(c) = proto.captures(metadata) {
            if is_drive_item_id(&c[1]) {
                return Some(format!("https://drive.google.com/open?id={}", &c[1]));
            }
        }
    }
    if stream.contains("com.google.drivefs.item-id") || stream.contains("user.drive.id") {
        let id = metadata
            .split(['\r', '\n', '\0'])
            .map(str::trim)
            .filter(|v| !v.is_empty())
            .find(|v| !v.to_lowercase().starts_with("local") && is_drive_item_id(v));
        if let Some(id) = id {
            return Some(format!("https://drive.google.com/open?id={id}"));
        }
    }
    None
}

#[cfg(windows)]
mod ntfs {
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Foundation::INVALID_HANDLE_VALUE;
    use windows_sys::Win32::Storage::FileSystem::{FindClose, FindFirstStreamW, FindNextStreamW, FindStreamInfoStandard, WIN32_FIND_STREAM_DATA};

    pub fn stream_names(path: &str) -> Vec<String> {
        let wide: Vec<u16> = std::ffi::OsStr::new(path).encode_wide().chain(Some(0)).collect();
        let mut data: WIN32_FIND_STREAM_DATA = unsafe { std::mem::zeroed() };
        let handle = unsafe { FindFirstStreamW(wide.as_ptr(), FindStreamInfoStandard, &mut data as *mut _ as *mut _, 0) };
        let mut names = Vec::new();
        if handle == INVALID_HANDLE_VALUE {
            return names;
        }
        let mut add = |d: &WIN32_FIND_STREAM_DATA| {
            let len = d.cStreamName.iter().position(|&c| c == 0).unwrap_or(d.cStreamName.len());
            let name = String::from_utf16_lossy(&d.cStreamName[..len]);
            if !name.is_empty() && !name.eq_ignore_ascii_case("::$DATA") {
                names.push(name);
            }
        };
        add(&data);
        while unsafe { FindNextStreamW(handle, &mut data as *mut _ as *mut _) } != 0 {
            add(&data);
        }
        unsafe { FindClose(handle) };
        names
    }
}

fn read_stream(path: &str, stream: &str) -> Option<String> {
    let suffix = stream.strip_suffix(":$DATA").unwrap_or(stream);
    let suffix = if suffix.starts_with(':') { suffix.to_string() } else { format!(":{suffix}") };
    let bytes = std::fs::read(format!("{path}{suffix}")).ok()?;
    Some(String::from_utf8_lossy(&bytes).trim_matches(['\0', '\r', '\n', '\t', ' ']).to_string())
}

/// Ссылка для одного файла: сначала виртуальный поток `user.drive.id`, затем все потоки Drive.
fn metadata_link(path: &str) -> Option<String> {
    if path.trim().is_empty() || !std::path::Path::new(path).is_file() {
        return None;
    }
    if let Some(id) = read_stream(path, "user.drive.id") {
        if !id.is_empty() && !id.to_lowercase().starts_with("local") && is_drive_item_id(&id) {
            return Some(format!("https://drive.google.com/open?id={id}"));
        }
    }
    #[cfg(windows)]
    for stream in ntfs::stream_names(path) {
        let lower = stream.to_lowercase();
        if !["com.google.drivefs.item-id", "com.google.drivefs.url", "user.drive.id", "user.drive.itemprotostr"].iter().any(|k| lower.contains(k)) {
            continue;
        }
        if let Some(link) = read_stream(path, &stream).and_then(|meta| link_from_metadata(&stream, &meta)) {
            return Some(link);
        }
    }
    None
}

/// Опрашивает файлы, пока Drive не проставит метаданные (до `retries` повторов с паузой).
pub fn export_links(records: &[SortedFileRecord], retries: usize, delay: std::time::Duration) -> Vec<DriveOutcome> {
    use std::collections::HashMap;
    let mut links: HashMap<String, Option<String>> = HashMap::new();
    let mut errors: HashMap<String, Option<String>> = HashMap::new();
    let mut pending: Vec<&SortedFileRecord> = records.iter().collect();
    for attempt in 0..=retries {
        if pending.is_empty() {
            break;
        }
        pending.retain(|record| {
            let link = metadata_link(&record.current_path);
            let found = link.as_deref().is_some_and(|l| !l.trim().is_empty());
            errors.insert(record.current_path.clone(), link.is_none().then(|| "Google Drive metadata не найдена.".to_string()));
            links.insert(record.current_path.clone(), link);
            !found
        });
        if !pending.is_empty() && attempt < retries {
            std::thread::sleep(delay);
        }
    }
    records
        .iter()
        .map(|r| DriveOutcome {
            record: r.clone(),
            link: links.get(&r.current_path).cloned().flatten(),
            error_message: errors.get(&r.current_path).cloned().flatten().or_else(|| Some("Google Drive metadata не найдена.".into())),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_links_from_metadata() {
        assert_eq!(link_from_metadata("x", "see https://drive.google.com/file/d/AAA111BBB222/view?usp=sharing ok").unwrap(), "https://drive.google.com/file/d/AAA111BBB222/view?usp=sharing");
        assert_eq!(link_from_metadata("x", "open?id=ABCDEFGHIJ123").unwrap(), "https://drive.google.com/open?id=ABCDEFGHIJ123");
        assert_eq!(link_from_metadata(":user.drive.id:$DATA", "local-123\nABCDEFGHIJ123\n").unwrap(), "https://drive.google.com/open?id=ABCDEFGHIJ123");
        assert_eq!(link_from_metadata("user.drive.itemprotostr", "item_id: \"ZZZZZZZZZZ999\"").unwrap(), "https://drive.google.com/open?id=ZZZZZZZZZZ999");
        assert!(link_from_metadata("user.drive.id", "local-only").is_none());
        assert!(link_from_metadata("x", "   ").is_none());
    }

    #[test]
    fn validates_item_ids() {
        assert!(is_drive_item_id("abc_DEF-123456"));
        assert!(!is_drive_item_id("short"));
        assert!(!is_drive_item_id("has space 12345"));
    }

    #[test]
    fn missing_files_report_an_error_after_retries() {
        let record = SortedFileRecord { current_path: "/definitely/missing.mp4".into(), ..Default::default() };
        let out = export_links(&[record], 1, std::time::Duration::from_millis(1));
        assert_eq!(out.len(), 1);
        assert!(out[0].link.is_none());
        assert_eq!(out[0].error_message.as_deref(), Some("Google Drive metadata не найдена."));
    }
}
