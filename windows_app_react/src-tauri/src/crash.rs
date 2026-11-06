//! Журнал падений. В релизной сборке `panic = "abort"`: без перехватчика приложение просто исчезает.
//! Перехватчик записывает причину в logs/crash-*.txt (попадает и в экспорт диагностики).

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

const KEEP_REPORTS: usize = 10;

pub fn format_report(version: &str, thread: &str, message: &str, location: Option<&str>, backtrace: &str, when: &str) -> String {
    format!(
        "SaveMe {version} упал\nВремя (UTC): {when}\nОС: {os} {arch}\nПоток: {thread}\nСообщение: {message}\nМесто: {location}\n\nСтек вызовов:\n{backtrace}\n",
        os = std::env::consts::OS,
        arch = std::env::consts::ARCH,
        location = location.unwrap_or("неизвестно"),
    )
}

/// Сохраняет отчёт и оставляет только последние `KEEP_REPORTS` файлов.
pub fn write_report(dir: &Path, report: &str, stamp: &str) -> io::Result<PathBuf> {
    fs::create_dir_all(dir)?;
    let path = dir.join(format!("crash-{stamp}.txt"));
    fs::write(&path, report)?;
    prune(dir)?;
    Ok(path)
}

fn prune(dir: &Path) -> io::Result<()> {
    let mut reports: Vec<PathBuf> = fs::read_dir(dir)?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.file_name().and_then(|n| n.to_str()).is_some_and(|n| n.starts_with("crash-") && n.ends_with(".txt")))
        .collect();
    reports.sort();
    let excess = reports.len().saturating_sub(KEEP_REPORTS);
    for old in reports.into_iter().take(excess) {
        let _ = fs::remove_file(old);
    }
    Ok(())
}

pub fn install_hook(logs_dir: PathBuf, version: &'static str) {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let message = info
            .payload()
            .downcast_ref::<&str>()
            .map(|s| (*s).to_string())
            .or_else(|| info.payload().downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "без текста".to_string());
        let location = info.location().map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()));
        let thread = std::thread::current().name().unwrap_or("без имени").to_string();
        let backtrace = std::backtrace::Backtrace::force_capture().to_string();
        let when = crate::util::iso_now();
        let report = format_report(version, &thread, &message, location.as_deref(), &backtrace, &when);
        let _ = write_report(&logs_dir, &report, &when.replace([':', '-'], ""));
        previous(info);
    }));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::temp_dir;

    #[test]
    fn report_has_the_facts_needed_to_debug() {
        let r = format_report("0.6.87", "main", "boom", Some("src/lib.rs:10:5"), "stack", "2026-11-06T10:00:00Z");
        for needle in ["SaveMe 0.6.87", "2026-11-06T10:00:00Z", "Поток: main", "Сообщение: boom", "src/lib.rs:10:5", "stack"] {
            assert!(r.contains(needle), "{needle}");
        }
        assert!(format_report("v", "t", "m", None, "b", "w").contains("Место: неизвестно"));
    }

    #[test]
    fn keeps_only_the_latest_reports() {
        let dir = temp_dir("crash");
        for i in 0..13 {
            write_report(&dir, "x", &format!("20261106T0000{i:02}Z")).unwrap();
        }
        fs::write(dir.join("worker.log"), "keep me").unwrap();
        let mut names: Vec<String> = fs::read_dir(&dir).unwrap().flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
        names.sort();
        assert_eq!(names.iter().filter(|n| n.starts_with("crash-")).count(), KEEP_REPORTS);
        assert!(names.contains(&"worker.log".to_string()), "чужие файлы не трогаем");
        assert!(!names.contains(&"crash-20261106T000000Z.txt".to_string()), "самые старые удалены");
        assert!(names.contains(&"crash-20261106T000012Z.txt".to_string()), "самые новые остались");
    }

    #[test]
    fn the_hook_writes_a_report_on_a_real_panic() {
        let dir = temp_dir("crash-hook");
        install_hook(dir.clone(), "0.0.0-test");
        let _ = std::panic::catch_unwind(|| panic!("deliberate test panic"));
        let _ = std::panic::take_hook(); // вернуть стандартный перехватчик, чтобы не влиять на другие тесты
        let found = fs::read_dir(&dir)
            .unwrap()
            .flatten()
            .filter_map(|e| fs::read_to_string(e.path()).ok())
            .any(|text| text.contains("deliberate test panic") && text.contains("SaveMe 0.0.0-test") && text.contains("crash.rs"));
        assert!(found, "отчёт о панике не записан");
    }
}
