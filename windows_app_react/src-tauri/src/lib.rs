mod paths;
mod settings;
mod sleep;
mod updater;
mod worker;

use std::path::PathBuf;
use std::sync::Mutex;

use serde::Serialize;
use serde_json::Value;
use tauri::{AppHandle, Emitter, Manager, State};

use paths::AppPaths;
use settings::Settings;

struct App {
    paths: AppPaths,
    worker: worker::WorkerState,
    sleep: sleep::SleepGuard,
    installer: Mutex<Option<PathBuf>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AppInfo {
    version: &'static str,
    app_support: String,
    default_downloads: String,
    runtime_embedded: bool,
    auto_update: bool,
}

#[tauri::command]
fn app_info(app: State<'_, App>) -> AppInfo {
    AppInfo {
        version: updater::CURRENT_VERSION,
        app_support: app.paths.application_support().to_string_lossy().into_owned(),
        default_downloads: app.paths.default_downloads().to_string_lossy().into_owned(),
        runtime_embedded: app.paths.has_embedded_runtime(),
        auto_update: updater::supports_auto_install(),
    }
}

#[tauri::command]
fn settings_get(app: State<'_, App>) -> Settings {
    settings::load(&app.paths)
}

#[tauri::command]
fn settings_save(app: State<'_, App>, settings: Settings) -> Result<(), String> {
    settings::save(&app.paths, &settings)
}

#[tauri::command]
async fn worker_run(handle: AppHandle, app: State<'_, App>, request: Value) -> Result<Value, String> {
    let is_download = request.get("command").and_then(Value::as_str).is_some_and(|c| c.starts_with("download_"));
    let keep_awake = is_download && settings::load(&app.paths).prevent_sleep;
    if keep_awake {
        app.sleep.acquire();
    }
    let emitter = handle.clone();
    let result = worker::run(move |line| { let _ = emitter.emit("worker-log", line); }, &app.worker, &app.paths, request).await;
    if keep_awake {
        app.sleep.release();
    }
    result
}

#[tauri::command]
fn worker_cancel(app: State<'_, App>) -> bool {
    app.worker.cancel()
}

#[tauri::command]
fn worker_login(app: State<'_, App>, request: Value) -> Result<(), String> {
    worker::start_detached_login(&app.paths, request)
}

/// Открывает папку в Проводнике. Путь должен существовать и быть каталогом.
#[tauri::command]
fn open_path(path: String) -> Result<(), String> {
    let dir = PathBuf::from(&path);
    if !dir.is_dir() {
        return Err(format!("Папка не найдена: {path}"));
    }
    #[cfg(windows)]
    let program = "explorer";
    #[cfg(target_os = "macos")]
    let program = "open";
    #[cfg(all(not(windows), not(target_os = "macos")))]
    let program = "xdg-open";
    std::process::Command::new(program).arg(dir).spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
async fn update_check() -> Result<updater::CheckResult, String> {
    updater::check_latest().await
}

#[tauri::command]
async fn update_prepare(handle: AppHandle, app: State<'_, App>, release: Value) -> Result<(), String> {
    let info = release_from_value(&release)?;
    let installer = updater::prepare_install(&handle, &app.paths, &info).await?;
    *app.installer.lock().unwrap() = Some(installer);
    Ok(())
}

#[tauri::command]
fn update_install(app: State<'_, App>) -> Result<(), String> {
    let installer = app.installer.lock().unwrap().clone().ok_or("Сначала подготовь обновление.")?;
    if !installer.exists() {
        return Err(format!("Установщик обновления не найден: {}", installer.display()));
    }
    updater::launch_installer(&installer)
}

fn release_from_value(v: &Value) -> Result<updater::ReleaseInfo, String> {
    let s = |o: &Value, k: &str| o.get(k).and_then(Value::as_str).unwrap_or("").to_owned();
    let a = v.get("asset").ok_or("Нет данных об установщике.")?;
    Ok(updater::ReleaseInfo {
        version: s(v, "version"),
        tag: s(v, "tag"),
        title: s(v, "title"),
        notes: s(v, "notes"),
        html_url: s(v, "htmlUrl"),
        published_at: s(v, "publishedAt"),
        asset: updater::ReleaseAsset {
            name: s(a, "name"),
            url: s(a, "url"),
            size: a.get("size").and_then(Value::as_u64).unwrap_or(0),
            digest: s(a, "digest"),
            checksum_url: s(a, "checksumUrl"),
        },
    })
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .manage(App {
            paths: AppPaths::new(),
            worker: worker::WorkerState::default(),
            sleep: sleep::SleepGuard::default(),
            installer: Mutex::new(None),
        })
        .invoke_handler(tauri::generate_handler![
            app_info,
            settings_get,
            settings_save,
            worker_run,
            worker_cancel,
            worker_login,
            open_path,
            update_check,
            update_prepare,
            update_install,
        ])
        .run(tauri::generate_context!())
        .expect("failed to start SaveMe");
}
