//! Удаление пустых подпапок. Порт EmptyFolderCleanupService.cs: «пустой» значит без файлов,
//! кроме .DS_Store / desktop.ini / Thumbs.db; папки с компонентом «На перенос» не трогаются.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf, MAIN_SEPARATOR};

use serde::Serialize;

#[derive(Clone, Debug, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CleanupResult {
    pub removed: Vec<String>,
    pub failed: Vec<String>,
}

pub fn is_ignorable_entry(path: &Path) -> bool {
    path.file_name()
        .map(|n| n.to_string_lossy().to_lowercase())
        .is_some_and(|n| matches!(n.as_str(), ".ds_store" | "desktop.ini" | "thumbs.db"))
}

fn is_protected(path: &Path) -> bool {
    path.components().any(|c| c.as_os_str().to_string_lossy().eq_ignore_ascii_case("На перенос"))
}

fn depth(path: &Path) -> usize {
    path.to_string_lossy().split(['/', '\\']).count()
}

fn all_subdirectories(root: &Path, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    for entry in fs::read_dir(root)? {
        let path = entry?.path();
        // Символические ссылки не обходим: удалять по ним нельзя.
        if path.is_dir() && !fs::symlink_metadata(&path)?.file_type().is_symlink() {
            out.push(path.clone());
            all_subdirectories(&path, out)?;
        }
    }
    Ok(())
}

fn key(path: &Path) -> String {
    path.to_string_lossy().replace(['/', '\\'], &MAIN_SEPARATOR.to_string()).trim_end_matches(MAIN_SEPARATOR).to_lowercase()
}

fn is_effectively_empty(dir: &Path, known_empty: &HashSet<String>) -> bool {
    let Ok(entries) = fs::read_dir(dir) else { return false };
    for entry in entries {
        let Ok(entry) = entry else { return false };
        let path = entry.path();
        if is_ignorable_entry(&path) {
            continue;
        }
        if path.is_dir() && known_empty.contains(&key(&path)) {
            continue;
        }
        return false;
    }
    true
}

pub fn find_deletable_empty_folders(root: &str) -> Vec<String> {
    let root = Path::new(root);
    if root.as_os_str().is_empty() || !root.is_dir() {
        return Vec::new();
    }
    let mut candidates = Vec::new();
    if all_subdirectories(root, &mut candidates).is_err() {
        return Vec::new();
    }
    candidates.retain(|p| !is_protected(p));
    candidates.sort_by_key(|p| std::cmp::Reverse(depth(p)));

    let mut deletable: HashSet<String> = HashSet::new();
    for folder in &candidates {
        if is_effectively_empty(folder, &deletable) {
            deletable.insert(key(folder));
        }
    }
    candidates.iter().filter(|f| deletable.contains(&key(f))).map(|f| f.to_string_lossy().into_owned()).collect()
}

pub fn delete_empty_folders(folders: &[String]) -> CleanupResult {
    let mut result = CleanupResult::default();
    let mut list: Vec<PathBuf> = folders.iter().map(PathBuf::from).filter(|p| !is_protected(p)).collect();
    list.sort_by_key(|p| std::cmp::Reverse(depth(p)));
    let none = HashSet::new();
    for folder in list {
        if !folder.is_dir() {
            continue;
        }
        // Повторная проверка перед удалением: за время диалога в папке мог появиться файл.
        if !is_effectively_empty_deep(&folder, &none) {
            continue;
        }
        match fs::remove_dir_all(&folder) {
            Ok(()) => result.removed.push(folder.to_string_lossy().into_owned()),
            Err(_) => result.failed.push(folder.to_string_lossy().into_owned()),
        }
    }
    result
}

/// Папка пуста (допускаются только игнорируемые файлы и вложенные пустые папки).
fn is_effectively_empty_deep(dir: &Path, none: &HashSet<String>) -> bool {
    let Ok(entries) = fs::read_dir(dir) else { return false };
    entries.flatten().all(|e| {
        let p = e.path();
        is_ignorable_entry(&p) || (p.is_dir() && is_effectively_empty_deep(&p, none))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::util::temp_dir;

    fn names(list: &[String]) -> Vec<String> {
        let mut v: Vec<String> = list.iter().map(|p| Path::new(p).file_name().unwrap().to_string_lossy().into_owned()).collect();
        v.sort();
        v
    }

    #[test]
    fn finds_nested_empty_folders_and_keeps_folders_with_files() {
        let root = temp_dir("cleanup-find");
        fs::create_dir_all(root.join("a/b/c")).unwrap();
        fs::create_dir_all(root.join("keep/inner")).unwrap();
        fs::write(root.join("keep/file.mp4"), "x").unwrap();
        fs::create_dir_all(root.join("thumbs")).unwrap();
        fs::write(root.join("thumbs/Thumbs.db"), "x").unwrap();
        fs::create_dir_all(root.join("На перенос/empty")).unwrap();

        let found = find_deletable_empty_folders(&root.to_string_lossy());
        assert_eq!(names(&found), ["a", "b", "c", "inner", "thumbs"]);
    }

    #[test]
    fn deletes_only_what_is_still_empty() {
        let root = temp_dir("cleanup-delete");
        fs::create_dir_all(root.join("a/b")).unwrap();
        fs::create_dir_all(root.join("late")).unwrap();
        let found = find_deletable_empty_folders(&root.to_string_lossy());
        fs::write(root.join("late/new.mp4"), "x").unwrap(); // файл появился после поиска
        let result = delete_empty_folders(&found);
        assert!(result.failed.is_empty());
        assert!(!root.join("a").exists());
        assert!(root.join("late/new.mp4").exists());
    }

    #[test]
    fn protected_and_missing_roots_are_ignored() {
        assert!(find_deletable_empty_folders("").is_empty());
        assert!(find_deletable_empty_folders("/definitely/missing").is_empty());
        let root = temp_dir("cleanup-protected");
        fs::create_dir_all(root.join("На перенос/x")).unwrap();
        let result = delete_empty_folders(&[root.join("На перенос/x").to_string_lossy().into_owned()]);
        assert!(result.removed.is_empty() && root.join("На перенос/x").exists());
    }
}
