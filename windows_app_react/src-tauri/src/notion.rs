//! Публичные Notion-страницы: правила сортировки и список инфлюенсеров.
//! Порт NotionRoutingRulesSource.cs и NotionInfluencerSource.cs (порядок блоков важен — нужен preserve_order).

use std::collections::{HashMap, HashSet};

use regex::Regex;
use serde_json::{json, Value};

use crate::util::NL;

pub const DEFAULT_RULES_URL: &str = "https://narrow-park-cda.notion.site/366f65c3de6780e8bb03f4bdda65f5f8";
pub const DEFAULT_INFLUENCERS_URL: &str = "https://narrow-park-cda.notion.site/334f65c3de678035bfecd4b7bf2a7fa7";
const MAX_CHUNKS: usize = 10;

pub fn page_id_from_url(url: &str, what: &str) -> Result<String, String> {
    let re = Regex::new("[0-9a-fA-F]{32}").unwrap();
    let m = re.find(url).ok_or_else(|| format!("Некорректная ссылка на Notion-страницу{what}."))?;
    let c = m.as_str().to_lowercase();
    Ok(format!("{}-{}-{}-{}-{}", &c[..8], &c[8..12], &c[12..16], &c[16..20], &c[20..]))
}

pub fn api_endpoint_from_url(url: &str) -> Result<String, String> {
    let parsed = reqwest::Url::parse(url).map_err(|e| format!("Некорректная ссылка Notion: {e}"))?;
    let host = parsed.host_str().ok_or("В ссылке Notion нет адреса сервера.")?;
    Ok(format!("{}://{}/api/v3/loadCachedPageChunk", parsed.scheme(), host))
}

/// Скачивает все «куски» страницы и передаёт каждый ответ в `on_chunk`.
async fn fetch_chunks(url: &str, what: &str, user_agent: &str, mut on_chunk: impl FnMut(&Value)) -> Result<(), String> {
    let page_id = page_id_from_url(url, what)?;
    let endpoint = api_endpoint_from_url(url)?;
    let client = reqwest::Client::builder()
        .user_agent(user_agent)
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| e.to_string())?;
    let mut cursor = json!({ "stack": [] });
    for chunk_number in 0..MAX_CHUNKS {
        let payload = json!({ "pageId": page_id, "limit": 100, "cursor": cursor, "chunkNumber": chunk_number, "verticalColumns": false });
        let response: Value = client
            .post(&endpoint)
            .json(&payload)
            .send()
            .await
            .and_then(|r| r.error_for_status())
            .map_err(|e| format!("Notion недоступен: {e}"))?
            .json()
            .await
            .map_err(|e| format!("Notion вернул не JSON: {e}"))?;
        on_chunk(&response);
        match next_cursor(&response) {
            Some(next) => cursor = next,
            None => break,
        }
    }
    Ok(())
}

fn next_cursor(root: &Value) -> Option<Value> {
    let cursor = root.get("cursor")?;
    let stack = cursor.get("stack")?.as_array()?;
    if cursor.is_object() && !stack.is_empty() { Some(cursor.clone()) } else { None }
}

pub async fn fetch_rules(url: &str) -> Result<String, String> {
    let mut chunks: Vec<String> = Vec::new();
    fetch_chunks(url, " с правилами", "SaveMe-WinUI-NotionRoutingRulesSource", |root| {
        let rules = parse_rules(root);
        if !rules.trim().is_empty() {
            chunks.push(rules);
        }
    })
    .await?;
    let mut seen = HashSet::new();
    let lines: Vec<String> = chunks
        .join(NL)
        .split(NL)
        .map(str::trim)
        .filter(|l| !l.is_empty() && seen.insert(l.to_lowercase()))
        .map(str::to_string)
        .collect();
    Ok(lines.join(NL))
}

pub async fn fetch_profiles(url: &str) -> Result<Vec<String>, String> {
    let mut profiles: Vec<String> = Vec::new();
    let mut seen = HashSet::new();
    fetch_chunks(url, "", "SaveMe-WinUI-NotionInfluencerSource", |root| {
        for p in parse_profiles(root) {
            if seen.insert(p.to_lowercase()) {
                profiles.push(p);
            }
        }
    })
    .await?;
    Ok(profiles)
}

/// Текст блока Notion: `[["часть"], ["часть", [["i"]]], …]` или строка.
pub fn rich_text(value: &Value) -> String {
    match value {
        Value::String(s) => s.clone(),
        Value::Array(parts) => parts
            .iter()
            .filter_map(|fragment| match fragment {
                Value::String(s) => Some(s.as_str()),
                Value::Array(a) => a.first().and_then(Value::as_str),
                _ => None,
            })
            .collect(),
        _ => String::new(),
    }
}

fn block_value(block: &Value) -> Option<&Value> {
    block.get("value")?.get("value")
}

// ---------------------------------------------------------------- правила

pub fn parse_rules(root: &Value) -> String {
    let Some(blocks) = root.pointer("/recordMap/block").and_then(Value::as_object) else {
        return String::new();
    };
    let texts: Vec<String> = blocks
        .values()
        .filter_map(block_value)
        .filter_map(|v| v.get("properties")?.get("title"))
        .map(rich_text)
        .collect();
    normalize_rules(&texts.join(NL))
}

const TRIM_USERNAME: &[char] = &['@', '*', '/', '\\', '.', ',', ';', ':', '!', '?', '[', ']', '{', '}', '<', '>', '"', '\'', '`'];

fn instagram_username(value: &str) -> String {
    match reqwest::Url::parse(value.trim()) {
        Ok(url) if url.host_str().is_some_and(|h| h.to_lowercase().contains("instagram.com")) => {
            url.path().trim_matches('/').split('/').find(|s| !s.is_empty()).map(str::to_string).unwrap_or_else(|| value.to_string())
        }
        _ => value.to_string(),
    }
}

fn normalized_usernames(value: &str) -> Vec<String> {
    let parenthetical = Regex::new(r"\s*\([^)]*\)").unwrap();
    // «https://…» не режем по двоеточию (в оригинале на C# это давало мусорное правило «https = …»).
    const SCHEME: &str = "\u{1}";
    value
        .replace("://", SCHEME)
        .split([':', ','])
        .map(|p| p.replace(SCHEME, "://"))
        .map(|p| p.trim().to_string())
        .filter(|p| !p.is_empty())
        .map(|part| {
            let name = instagram_username(&part);
            let name = parenthetical.replace_all(&name, "");
            name.trim().trim_matches(TRIM_USERNAME).to_string()
        })
        .filter(|n| !n.is_empty())
        .collect()
}

fn looks_like_target_folder(value: &str) -> bool {
    value.to_uppercase().contains(" INF") || Regex::new(r"\([A-Z]{2}\)").unwrap().is_match(value)
}

pub fn normalize_rules(text: &str) -> String {
    let mut rules: Vec<String> = Vec::new();
    let mut current_target = String::new();
    for raw in text.split('\n') {
        let line = raw.trim().trim_start_matches('#').trim();
        if line.is_empty() || line.to_lowercase().contains("правила для сортировки") {
            continue;
        }
        if let Some(sep) = line.find('=') {
            let target = line[sep + 1..].trim();
            if target.is_empty() {
                continue;
            }
            for username in normalized_usernames(&line[..sep]) {
                rules.push(format!("{username} = {target}"));
            }
            continue;
        }
        if looks_like_target_folder(line) {
            current_target = line.to_string();
            continue;
        }
        if current_target.is_empty() {
            continue;
        }
        for username in normalized_usernames(line) {
            rules.push(format!("{username} = {current_target}"));
        }
    }
    rules.join(NL)
}

// ---------------------------------------------------------------- инфлюенсеры

pub fn parse_profiles(root: &Value) -> Vec<String> {
    let Some(blocks) = root.pointer("/recordMap/block").and_then(Value::as_object) else {
        return Vec::new();
    };
    let values: Vec<(&String, &Value)> = blocks
        .iter()
        .filter_map(|(id, b)| block_value(b).filter(|v| v.is_object()).map(|v| (id, v)))
        .collect();
    let by_id: HashMap<String, &Value> = values.iter().map(|(id, v)| (id.to_lowercase(), *v)).collect();

    struct Walk<'a> {
        by_id: &'a HashMap<String, &'a Value>,
        visited: HashSet<String>,
        seen: HashSet<String>,
        profiles: Vec<String>,
    }
    impl Walk<'_> {
        fn collect(&mut self, value: &Value) {
            let Some(title) = value.get("properties").and_then(|p| p.get("title")) else { return };
            for p in extract_profiles(&rich_text(title)) {
                if self.seen.insert(p.to_lowercase()) {
                    self.profiles.push(p);
                }
            }
        }
        fn visit(&mut self, id: &str, include_self: bool) {
            let key = id.to_lowercase();
            if !self.visited.insert(key.clone()) {
                return;
            }
            let Some(value) = self.by_id.get(&key).copied() else { return };
            if include_self {
                self.collect(value);
            }
            if let Some(children) = value.get("content").and_then(Value::as_array) {
                for child in children.iter().filter_map(Value::as_str) {
                    self.visit(child, true);
                }
            }
        }
    }

    let mut walk = Walk { by_id: &by_id, visited: HashSet::new(), seen: HashSet::new(), profiles: Vec::new() };
    for (id, v) in &values {
        if v.get("type").and_then(Value::as_str).is_some_and(|t| t.eq_ignore_ascii_case("page")) {
            walk.visit(id, false);
        }
    }
    for (id, _) in &values {
        walk.visit(id, true);
    }
    walk.profiles
}

const BLOCKED_NAMES: [&str; 8] = ["instagram", "profile", "profiles", "username", "user", "name", "link", "links"];
const TRIM_HANDLE: &[char] = &['@', '*', '/', '\\', '.', ',', ';', ':', '!', '?', '(', ')', '[', ']', '{', '}', '<', '>', '"', '\'', '`'];

fn is_username_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '.' || c == '_'
}

fn normalize_instagram_username(raw: &str) -> Option<String> {
    let name = raw.trim().trim_matches(TRIM_HANDLE);
    let valid = (1..=30).contains(&name.chars().count()) && name.chars().all(is_username_char);
    (valid && !BLOCKED_NAMES.contains(&name.to_lowercase().as_str())).then(|| name.to_string())
}

/// `@handle` — не внутри слова и не длиннее 30 символов (аналог регулярки с lookaround).
fn handles(text: &str) -> Vec<String> {
    let chars: Vec<(usize, char)> = text.char_indices().collect();
    let mut out = Vec::new();
    for (n, &(pos, c)) in chars.iter().enumerate() {
        if c != '@' || (n > 0 && is_username_char(chars[n - 1].1)) {
            continue;
        }
        let rest = &text[pos + 1..];
        let run: String = rest.chars().take_while(|&ch| is_username_char(ch)).collect();
        if (1..=30).contains(&run.chars().count()) {
            out.push(run);
        }
    }
    out
}

fn push_profile(raw: &str, profiles: &mut Vec<String>, seen: &mut HashSet<String>) {
    if let Some(name) = normalize_instagram_username(raw) {
        let url = format!("https://www.instagram.com/{name}/");
        if seen.insert(url.to_lowercase()) {
            profiles.push(url);
        }
    }
}

pub fn extract_profiles(text: &str) -> Vec<String> {
    let url_re = Regex::new(r"(?i)https?://(?:www\.)?instagram\.com/([A-Za-z0-9._]{1,30})(?:/|\b)").unwrap();
    let mut profiles: Vec<String> = Vec::new();
    let mut seen = HashSet::new();
    for cap in url_re.captures_iter(text) {
        push_profile(&cap[1], &mut profiles, &mut seen);
    }
    for handle in handles(text) {
        push_profile(&handle, &mut profiles, &mut seen);
    }
    if profiles.is_empty() {
        for token in text.split(|c: char| c.is_whitespace() || c == ',' || c == ';') {
            push_profile(token, &mut profiles, &mut seen);
        }
    }
    profiles
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn page_id_and_endpoint() {
        assert_eq!(page_id_from_url("https://x.notion.site/366f65c3de6780e8bb03f4bdda65f5f8", "").unwrap(), "366f65c3-de67-80e8-bb03-f4bdda65f5f8");
        assert!(page_id_from_url("https://x.notion.site/nope", "").is_err());
        assert_eq!(api_endpoint_from_url("https://x.notion.site/abc").unwrap(), "https://x.notion.site/api/v3/loadCachedPageChunk");
    }

    #[test]
    fn normalizes_rules_cleans_comments_and_aliases() {
        let input = "Правила для сортировки\n*nadir_bs* = Australia (AU) 🇦🇺 INF\njimisworld (без зуба) = Australia (AU) 🇦🇺 INF\nryanjslots : ryanjstewart1 = Germany (DE) 🇩🇪 INF";
        assert_eq!(
            normalize_rules(input),
            ["nadir_bs = Australia (AU) 🇦🇺 INF", "jimisworld = Australia (AU) 🇦🇺 INF", "ryanjslots = Germany (DE) 🇩🇪 INF", "ryanjstewart1 = Germany (DE) 🇩🇪 INF"].join(NL)
        );
    }

    #[test]
    fn heading_then_usernames_use_current_target() {
        let input = "Germany (DE) 🇩🇪 INF\nhttps://www.instagram.com/anna/\nbob, carl\nAustralia (AU) INF\ndan";
        assert_eq!(
            normalize_rules(input),
            ["anna = Germany (DE) 🇩🇪 INF", "bob = Germany (DE) 🇩🇪 INF", "carl = Germany (DE) 🇩🇪 INF", "dan = Australia (AU) INF"].join(NL)
        );
    }

    #[test]
    fn parses_rules_from_rich_text_blocks() {
        let payload = json!({"recordMap": {"block": {
            "page": {"value": {"value": {"properties": {"title": [["Правила для сортировки"]]}}}},
            "rule": {"value": {"value": {"properties": {"title": [["ryanjslots : "], ["ryanjstewart1", [["i"]]], [" = Germany (DE) 🇩🇪 INF"]]}}}}
        }}});
        assert_eq!(parse_rules(&payload), ["ryanjslots = Germany (DE) 🇩🇪 INF", "ryanjstewart1 = Germany (DE) 🇩🇪 INF"].join(NL));
        assert_eq!(parse_rules(&json!({})), "");
    }

    #[test]
    fn parses_profiles_in_page_order_without_annotations() {
        let payload = json!({"recordMap": {"block": {
            "page": {"value": {"value": {"type": "page", "content": ["url", "italic-handle", "plain-handle"], "properties": {"title": [["Список инфлюенсеров"]]}}}},
            "url": {"value": {"value": {"properties": {"title": [["https://www.instagram.com/brothersbonus/", [["a", "https://www.instagram.com/brothersbonus/"]]]]}}}},
            "italic-handle": {"value": {"value": {"properties": {"title": [["@"], ["berthi", [["i"]]]]}}}},
            "plain-handle": {"value": {"value": {"properties": {"title": [["@upngo____"]]}}}}
        }}});
        assert_eq!(
            parse_profiles(&payload),
            ["https://www.instagram.com/brothersbonus/", "https://www.instagram.com/berthi/", "https://www.instagram.com/upngo____/"]
        );
    }

    #[test]
    fn extract_profiles_ignores_headings_and_deduplicates() {
        assert_eq!(
            extract_profiles("Список инфлюенсеров @stake https://www.instagram.com/stake/ @stoffer__"),
            ["https://www.instagram.com/stake/", "https://www.instagram.com/stoffer__/"]
        );
    }

    #[test]
    fn extract_profiles_falls_back_to_plain_tokens_and_blocks_keywords() {
        assert_eq!(extract_profiles("anna, bob; profile link"), ["https://www.instagram.com/anna/", "https://www.instagram.com/bob/"]);
        assert!(extract_profiles("a@b.com").is_empty() || !extract_profiles("a@b.com").iter().any(|p| p.contains("b.com")));
        assert!(handles(&format!("@{}", "a".repeat(31))).is_empty());
    }
}

#[cfg(test)]
mod live {
    use super::*;

    /// Живой запрос к публичной странице Notion. Запуск: `cargo test --lib live -- --ignored --nocapture`.
    #[tokio::test]
    #[ignore]
    async fn fetches_real_pages() {
        let rules = fetch_rules(DEFAULT_RULES_URL).await;
        println!("rules: {:?}", rules.as_ref().map(|r| r.lines().count()));
        let profiles = fetch_profiles(DEFAULT_INFLUENCERS_URL).await;
        println!("profiles: {:?}", profiles.as_ref().map(|p| (p.len(), p.first().cloned())));
        assert!(rules.is_ok() || profiles.is_ok(), "{rules:?} / {profiles:?}");
    }
}
