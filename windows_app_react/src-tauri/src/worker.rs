//! Запуск node_worker/bridge.mjs. Протокол тот же, что у Python-клиента:
//! один JSON-запрос в stdin, один JSON-ответ в stdout, прогресс строками в stderr.

use std::process::Stdio;
use std::sync::{Arc, Mutex};

use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;
use tokio::sync::Notify;

use crate::paths::AppPaths;

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
#[cfg(windows)]
const DETACHED_PROCESS: u32 = 0x0000_0008;
#[cfg(windows)]
const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;

#[derive(Default)]
pub struct WorkerState {
    cancel: Mutex<Option<Arc<Notify>>>,
}

impl WorkerState {
    pub fn cancel(&self) -> bool {
        match self.cancel.lock().unwrap().as_ref() {
            Some(notify) => {
                notify.notify_one();
                true
            }
            None => false,
        }
    }
}

pub fn process_failure(message: impl Into<String>) -> Value {
    json!({ "ok": false, "status": "process_error", "message": message.into(), "data": {}, "items": [], "logs": [] })
}

fn cancelled() -> Value {
    json!({ "ok": false, "status": "cancelled", "message": "Остановлено пользователем.", "data": {}, "items": [], "logs": [] })
}

/// Первый JSON-объект из stdout и «хвост» после него (как `_load_first_json_object` в Python).
pub fn parse_first_json(text: &str) -> Result<(Value, String), String> {
    let start = text.find('{').ok_or("Worker stdout does not contain a JSON object.")?;
    let slice = &text[start..];
    let mut stream = serde_json::Deserializer::from_str(slice).into_iter::<Value>();
    let value = stream.next().ok_or("Worker returned no JSON.")?.map_err(|e| e.to_string())?;
    if !value.is_object() {
        return Err("Worker JSON response must be an object.".into());
    }
    let tail = slice[stream.byte_offset()..].trim().to_string();
    Ok((value, tail))
}

fn worker_command(paths: &AppPaths, runtime: &str) -> Result<std::process::Command, String> {
    let (program, script) = paths.node_command()?;
    let mut cmd = std::process::Command::new(program);
    cmd.arg(script)
        .env("SAVESTORIES_APP_SUPPORT", paths.application_support())
        .env("SAVESTORIES_BROWSER_PROFILE", paths.browser_profile())
        .env("SAVESTORIES_MANIFESTS", paths.manifests_directory())
        .env("SAVESTORIES_PLAYWRIGHT_BROWSERS", paths.playwright_browsers())
        // Воркер уважает уже заданную PLAYWRIGHT_BROWSERS_PATH, поэтому закрепляем свою папку Chromium явно.
        .env("PLAYWRIGHT_BROWSERS_PATH", paths.playwright_browsers())
        .env("SAVESTORIES_DEFAULT_DOWNLOADS", paths.default_downloads())
        .env("SAVESTORIES_LOGS", paths.logs_directory())
        .env("SAVESTORIES_WORKER_RUNTIME", runtime);
    Ok(cmd)
}

pub async fn run<F>(on_log: F, state: &WorkerState, paths: &AppPaths, request: Value, timeout: Option<std::time::Duration>) -> Result<Value, String>
where
    F: Fn(&str) + Send + 'static,
{
    let cancel = {
        let mut slot = state.cancel.lock().unwrap();
        if slot.is_some() {
            return Err("Воркер уже выполняет другую команду.".into());
        }
        let notify = Arc::new(Notify::new());
        *slot = Some(notify.clone());
        notify
    };
    let result = run_inner(on_log, paths, request, cancel, timeout).await;
    *state.cancel.lock().unwrap() = None;
    result
}

async fn run_inner<F>(on_log: F, paths: &AppPaths, request: Value, cancel: Arc<Notify>, timeout: Option<std::time::Duration>) -> Result<Value, String>
where
    F: Fn(&str) + Send + 'static,
{
    paths.ensure_directories().map_err(|e| format!("Не удалось подготовить папки приложения: {e}"))?;
    #[allow(unused_mut)]
    let mut std_cmd = worker_command(paths, "node")?;
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        std_cmd.creation_flags(CREATE_NO_WINDOW);
    }
    let mut cmd = Command::from(std_cmd);
    cmd.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).kill_on_drop(true);

    let mut child = cmd.spawn().map_err(|e| format!("Не удалось запустить Node worker: {e}"))?;
    let pid = child.id();

    let mut stdin = child.stdin.take().ok_or("Нет stdin у воркера.")?;
    stdin
        .write_all(format!("{request}\n").as_bytes())
        .await
        .map_err(|e| format!("Не удалось отправить запрос воркеру: {e}"))?;
    drop(stdin);

    let mut stdout = child.stdout.take().ok_or("Нет stdout у воркера.")?;
    let stderr = child.stderr.take().ok_or("Нет stderr у воркера.")?;
    let out_task = tokio::spawn(async move {
        let mut buf = Vec::new();
        let _ = stdout.read_to_end(&mut buf).await;
        buf
    });
    let err_task = tokio::spawn(async move {
        let mut lines = BufReader::new(stderr).lines();
        let mut all = Vec::new();
        while let Ok(Some(line)) = lines.next_line().await {
            on_log(&line);
            all.push(line);
        }
        all
    });

    let status = tokio::select! {
        status = child.wait() => status.map_err(|e| e.to_string())?,
        _ = cancel.notified() => {
            kill_tree(pid);
            let _ = child.kill().await;
            out_task.abort();
            err_task.abort();
            return Ok(cancelled());
        }
        _ = async {
            match timeout {
                Some(limit) => tokio::time::sleep(limit).await,
                None => std::future::pending::<()>().await,
            }
        } => {
            kill_tree(pid);
            let _ = child.kill().await;
            out_task.abort();
            err_task.abort();
            let minutes = timeout.map(|t| t.as_secs() / 60).unwrap_or(0);
            return Ok(process_failure(format!("Команда worker превысила таймаут {minutes} мин.")));
        }
    };

    let stdout_text = String::from_utf8_lossy(&out_task.await.unwrap_or_default()).into_owned();
    let stderr_lines = err_task.await.unwrap_or_default();

    if stdout_text.trim().is_empty() {
        let tail = stderr_lines.join("\n");
        let message = if tail.trim().is_empty() {
            match status.code() {
                Some(code) if code != 0 => format!("Worker process failed with exit status {code}."),
                _ => "Worker returned no output.".to_string(),
            }
        } else {
            tail
        };
        return Ok(process_failure(message));
    }

    match parse_first_json(&stdout_text) {
        Ok((mut value, tail)) => {
            if !tail.is_empty() {
                if let Some(logs) = value.get_mut("logs").and_then(Value::as_array_mut) {
                    logs.push(Value::String(format!("worker_stdout_tail={tail}")));
                }
            }
            Ok(value)
        }
        Err(_) => Ok(process_failure(format!("Worker returned invalid JSON.\n{stdout_text}"))),
    }
}

/// Убивает воркер вместе с дочерним Chromium (на Windows `terminate` оставляет браузер сиротой).
fn kill_tree(pid: Option<u32>) {
    let Some(pid) = pid else { return };
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        let _ = std::process::Command::new("taskkill")
            .args(["/PID", &pid.to_string(), "/T", "/F"])
            .creation_flags(CREATE_NO_WINDOW)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
    #[cfg(not(windows))]
    {
        let _ = pid;
    }
}

/// Вход в Instagram: отдельное окно браузера, которое живёт независимо от приложения.
pub fn start_detached_login(paths: &AppPaths, request: Value) -> Result<(), String> {
    use std::io::Write;
    paths.ensure_directories().map_err(|e| e.to_string())?;
    let mut cmd = worker_command(paths, "node")?;
    cmd.stdin(Stdio::piped()).stdout(Stdio::null()).stderr(Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW | DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP);
    }
    let mut child = cmd.spawn().map_err(|e| format!("Не удалось запустить браузер для входа: {e}"))?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(format!("{request}\n").as_bytes()).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    #[test]
    fn parses_first_object_and_keeps_tail() {
        let (value, tail) = parse_first_json("noise {\"ok\":true,\"n\":{\"a\":1}} trailing").unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["n"]["a"], 1);
        assert_eq!(tail, "trailing");
    }

    #[test]
    fn rejects_text_without_json() {
        assert!(parse_first_json("nothing here").is_err());
    }

    #[test]
    fn process_failure_has_error_status() {
        let v = process_failure("boom");
        assert_eq!(v["ok"], false);
        assert_eq!(v["status"], "process_error");
        assert_eq!(v["message"], "boom");
    }

    fn fake_root(name: &str, script: &str) -> PathBuf {
        let root = std::env::temp_dir().join(format!("saveme-worker-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("node_worker")).unwrap();
        fs::write(root.join("node_worker/bridge.mjs"), script).unwrap();
        root
    }

    fn have_node() -> bool {
        std::process::Command::new("node").arg("--version").output().map(|o| o.status.success()).unwrap_or(false)
    }

    #[tokio::test]
    async fn round_trips_request_and_streams_stderr() {
        if !have_node() { return; }
        let script = "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const r=JSON.parse(d);process.stderr.write('step one\\n');process.stdout.write(JSON.stringify({ok:true,status:'ok',message:r.command,items:[]}));});";
        let root = fake_root("roundtrip", script);
        std::env::set_var("SAVESTORIES_APP_SUPPORT", root.join("data"));
        let paths = AppPaths::with_root(root);
        let logs = Arc::new(Mutex::new(Vec::<String>::new()));
        let sink = logs.clone();
        let state = WorkerState::default();
        let out = run(move |l| sink.lock().unwrap().push(l.to_string()), &state, &paths, json!({"command":"ping"}), None).await.unwrap();
        assert_eq!(out["ok"], true);
        assert_eq!(out["message"], "ping");
        assert_eq!(logs.lock().unwrap().as_slice(), ["step one"]);
    }

    #[tokio::test]
    async fn cancel_stops_a_long_running_worker() {
        if !have_node() { return; }
        let root = fake_root("cancel", "process.stdin.resume(); setInterval(()=>{}, 1000);");
        std::env::set_var("SAVESTORIES_APP_SUPPORT", root.join("data"));
        let paths = AppPaths::with_root(root);
        let state = Arc::new(WorkerState::default());
        let canceller = state.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(600)).await;
            assert!(canceller.cancel());
        });
        let out = run(|_| {}, &state, &paths, json!({"command":"x"}), None).await.unwrap();
        assert_eq!(out["status"], "cancelled");
        assert!(!state.cancel());
    }

    #[tokio::test]
    async fn timeout_kills_a_stuck_worker() {
        if !have_node() { return; }
        let root = fake_root("timeout", "process.stdin.resume(); setInterval(()=>{}, 1000);");
        std::env::set_var("SAVESTORIES_APP_SUPPORT", root.join("data"));
        let paths = AppPaths::with_root(root);
        let started = std::time::Instant::now();
        let out = run(|_| {}, &WorkerState::default(), &paths, json!({"command":"x"}), Some(std::time::Duration::from_millis(500))).await.unwrap();
        assert_eq!(out["status"], "process_error");
        assert!(out["message"].as_str().unwrap().contains("таймаут"));
        assert!(started.elapsed() < std::time::Duration::from_secs(5));
    }

    #[tokio::test]
    async fn crash_without_output_reports_process_error() {
        if !have_node() { return; }
        let root = fake_root("crash", "process.stdin.resume(); process.stderr.write('kaboom\\n'); process.exit(3);");
        std::env::set_var("SAVESTORIES_APP_SUPPORT", root.join("data"));
        let paths = AppPaths::with_root(root);
        let out = run(|_| {}, &WorkerState::default(), &paths, json!({"command":"x"}), None).await.unwrap();
        assert_eq!(out["status"], "process_error");
        assert_eq!(out["message"], "kaboom");
    }
}
