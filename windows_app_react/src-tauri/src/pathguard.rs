//! Какие папки интерфейс вправе просить открыть. Раньше команда принимала любой путь (в том числе сетевой
//! `\\сервер\папка`); теперь — только папки приложения и папки, выбранные пользователем в настройках.
//! Проверка лексическая (без обращения к диску): `..` отвергаются, сравнение по компонентам пути.

use std::path::{Component, Path, PathBuf};

/// Абсолютный путь без `.`; `None`, если путь пустой, относительный или содержит `..`.
pub fn normalize(path: &str) -> Option<PathBuf> {
    let path = path.trim();
    if path.is_empty() {
        return None;
    }
    let p = Path::new(path);
    if !p.is_absolute() {
        return None;
    }
    let mut out = PathBuf::new();
    for component in p.components() {
        match component {
            Component::ParentDir => return None,
            Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }
    Some(out)
}

fn key(component: Component<'_>) -> String {
    let s = component.as_os_str().to_string_lossy().into_owned();
    // В Windows пути не различают регистр.
    if cfg!(windows) { s.to_lowercase() } else { s }
}

/// Лежит ли `path` внутри `root` (или совпадает с ним): по целым компонентам, а не по префиксу строки.
pub fn is_within(path: &Path, root: &Path) -> bool {
    let mut p = path.components();
    for r in root.components() {
        match p.next() {
            Some(c) if key(c) == key(r) => {}
            _ => return false,
        }
    }
    true
}

/// Нормализованный путь, если он входит в одну из разрешённых папок.
pub fn allowed(path: &str, roots: &[PathBuf]) -> Option<PathBuf> {
    let candidate = normalize(path)?;
    roots
        .iter()
        .filter_map(|r| normalize(&r.to_string_lossy()))
        .any(|root| is_within(&candidate, &root))
        .then_some(candidate)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn root(p: &str) -> PathBuf {
        PathBuf::from(p)
    }

    #[cfg(not(windows))]
    const BASE: &str = "/home/u/Downloads/SaveMe";
    #[cfg(windows)]
    const BASE: &str = r"C:\Users\u\Downloads\SaveMe";

    fn join(rel: &str) -> String {
        format!("{BASE}{}{rel}", std::path::MAIN_SEPARATOR)
    }

    #[test]
    fn allows_the_root_and_its_children() {
        let roots = [root(BASE)];
        assert!(allowed(BASE, &roots).is_some());
        assert!(allowed(&join("anna"), &roots).is_some());
        assert!(allowed(&join("anna/stories"), &roots).is_some());
    }

    #[test]
    fn rejects_siblings_that_only_share_a_prefix() {
        let roots = [root(BASE)];
        assert!(allowed(&format!("{BASE}2"), &roots).is_none(), "SaveMe2 — не SaveMe");
        assert!(allowed(&format!("{BASE}-old"), &roots).is_none());
    }

    #[test]
    fn rejects_parent_traversal_relative_and_empty() {
        let roots = [root(BASE)];
        assert!(allowed(&join("../../secret"), &roots).is_none());
        assert!(allowed("relative/path", &roots).is_none());
        assert!(allowed("", &roots).is_none());
        assert!(allowed("   ", &roots).is_none());
        assert!(normalize(&join("a/../b")).is_none());
    }

    #[test]
    fn rejects_everything_when_no_roots() {
        assert!(allowed(BASE, &[]).is_none());
    }

    #[cfg(not(windows))]
    #[test]
    fn rejects_other_absolute_paths() {
        assert!(allowed("/etc", &[root(BASE)]).is_none());
        assert!(allowed("/home/u/Downloads", &[root(BASE)]).is_none(), "родитель разрешённой папки — нельзя");
    }

    #[cfg(windows)]
    #[test]
    fn windows_paths_ignore_case_and_reject_unc() {
        let roots = [root(r"C:\Users\u\Downloads\SaveMe")];
        assert!(allowed(r"c:\users\U\downloads\saveme\Anna", &roots).is_some());
        assert!(allowed(r"\\attacker\share", &roots).is_none());
        assert!(allowed(r"C:\Users\u\Downloads", &roots).is_none());
    }
}
