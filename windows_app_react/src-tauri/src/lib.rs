mod cleanup;
mod crash;
mod gdrive;
mod memory;
mod notion;
mod pathguard;
mod paths;
mod queue;
mod runtime;
mod settings;
mod sleep;
mod sorting;
mod updater;
mod util;
mod worker;

use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

use serde::Serialize;
use serde_json::Value;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, State, Theme, WebviewWindow, WebviewWindowBuilder};
use tauri_plugin_notification::NotificationExt;
use tauri_plugin_window_state::StateFlags;

use paths::AppPaths;
use settings::Settings;
use sorting::{DriveOutcome, RememberedBlogger, SortItem, SortedFileRecord};

/// Удалось ли включить нативный материал окна (Mica). Если нет — интерфейс рисует свой непрозрачный фон.
struct NativeGlass(bool);

struct App {
    paths: AppPaths,
    worker: worker::WorkerState,
    sleep: sleep::SleepGuard,
    installer: Mutex<Option<PathBuf>>,
    installing: Mutex<bool>,
}

// ------------------------------------------------------------------ приложение

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AppInfo {
    version: &'static str,
    app_support: String,
    default_downloads: String,
    runtime_embedded: bool,
    auto_update: bool,
    native_glass: bool,
}

#[tauri::command]
fn app_info(app: State<'_, App>, glass: State<'_, NativeGlass>) -> AppInfo {
    AppInfo {
        native_glass: glass.0,
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

/// Показывает окно после первой отрисовки интерфейса (окно создаётся скрытым).
#[tauri::command]
fn app_ready(window: WebviewWindow) {
    let _ = window.show();
}

/// Тема окна (рамка и материал Mica) должна совпадать с темой интерфейса, а не только с системной.
#[tauri::command]
fn window_set_theme(window: WebviewWindow, theme: String) {
    let theme = match theme.as_str() {
        "dark" => Some(Theme::Dark),
        "light" => Some(Theme::Light),
        _ => None,
    };
    let _ = window.set_theme(theme);
}

/// Mica есть только в Windows 11 и дёшево рисуется системой (в отличие от размытия в CSS).
#[cfg(windows)]
fn apply_native_glass(window: &WebviewWindow) -> bool {
    use tauri::window::{Effect, EffectsBuilder};
    window.set_effects(EffectsBuilder::new().effect(Effect::Mica).build()).is_ok()
}

#[cfg(not(windows))]
fn apply_native_glass(_window: &WebviewWindow) -> bool {
    false
}

#[tauri::command]
fn queue_load(app: State<'_, App>) -> Vec<queue::QueueEntry> {
    queue::load(&app.paths)
}

#[tauri::command]
fn queue_save(app: State<'_, App>, entries: Vec<queue::QueueEntry>) -> Result<(), String> {
    queue::save(&app.paths, entries)
}

/// Папки, которые интерфейс вправе открыть: данные приложения и папки, выбранные пользователем.
fn openable_roots(paths: &AppPaths, s: &Settings) -> Vec<PathBuf> {
    let mut roots = vec![paths.application_support(), paths.playwright_browsers(), paths.default_downloads()];
    for chosen in [&s.save_directory, &s.sorting_source_directory, &s.sorting_destination_directory, &s.empty_folder_cleanup_directory, &s.unik_output_directory] {
        if !chosen.trim().is_empty() {
            roots.push(PathBuf::from(chosen));
        }
    }
    roots
}

/// Открывает папку в Проводнике (создаёт её, если нет — как ShellFolderService.OpenFolder).
/// Только внутри папок приложения и выбранных пользователем: иначе интерфейс мог бы открыть любой путь, включая сетевой.
#[tauri::command]
fn open_path(app: State<'_, App>, path: String) -> Result<(), String> {
    if path.trim().is_empty() {
        return Err("Папка не выбрана.".into());
    }
    let roots = openable_roots(&app.paths, &settings::load(&app.paths));
    let dir = pathguard::allowed(&path, &roots)
        .ok_or("Эту папку открыть нельзя: она не входит в папки приложения и выбранные вами папки.")?;
    std::fs::create_dir_all(&dir).map_err(|e| format!("Не удалось создать папку: {e}"))?;
    #[cfg(windows)]
    let program = "explorer";
    #[cfg(target_os = "macos")]
    let program = "open";
    #[cfg(all(not(windows), not(target_os = "macos")))]
    let program = "xdg-open";
    std::process::Command::new(program).arg(dir).spawn().map(|_| ()).map_err(|e| e.to_string())
}

// ------------------------------------------------------------------ воркер

#[tauri::command]
async fn worker_run(handle: AppHandle, app: State<'_, App>, request: Value, timeout_secs: Option<u64>) -> Result<Value, String> {
    // Выгрузка и обработка видео идут долго: на это время компьютер не должен засыпать.
    let is_download = request.get("command").and_then(Value::as_str).is_some_and(|c| c.starts_with("download_") || c == "unik_process");
    let keep_awake = is_download && settings::load(&app.paths).prevent_sleep;
    if keep_awake {
        app.sleep.acquire();
    }
    let emitter = handle.clone();
    let result = worker::run(
        move |line| {
            let _ = emitter.emit("worker-log", line);
        },
        &app.worker,
        &app.paths,
        request,
        timeout_secs.map(Duration::from_secs),
    )
    .await;
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

// ------------------------------------------------------------------ сортировка

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RulesParsed {
    count: usize,
    remembered: Vec<RememberedBlogger>,
}

#[tauri::command]
fn sorting_parse_rules(rules: String, remembered: Vec<RememberedBlogger>) -> RulesParsed {
    let parsed = sorting::parse_rules(&rules);
    let fresh = sorting::bloggers_from_rules(&parsed, &util::iso_now());
    RulesParsed { count: parsed.len(), remembered: sorting::merge_bloggers(&remembered, fresh) }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SortingOutcome {
    success: bool,
    summary: String,
    records: Vec<SortedFileRecord>,
    failed_items: Vec<String>,
    /// Локальный список «[папка (блогер)] файлы…» для копирования.
    report: String,
    remembered: Vec<RememberedBlogger>,
}

fn outcome(result: sorting::SortingResult, remembered: &[RememberedBlogger]) -> SortingOutcome {
    let fresh = sorting::bloggers_from_records(&result.records, &util::iso_now());
    SortingOutcome {
        report: sorting::build_post_processed_report(&result.records),
        remembered: if fresh.is_empty() { remembered.to_vec() } else { sorting::merge_bloggers(remembered, fresh) },
        success: result.success,
        summary: result.summary,
        records: result.records,
        failed_items: result.failed_items,
    }
}

#[tauri::command]
async fn sorting_run_source(source: String, destination: String, rules: String, remembered: Vec<RememberedBlogger>) -> Result<SortingOutcome, String> {
    tauri::async_runtime::spawn_blocking(move || outcome(sorting::distribute_from_source(&source, &destination, &rules), &remembered))
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn sorting_run_items(items: Vec<SortItem>, destination: String, rules: String, remembered: Vec<RememberedBlogger>) -> Result<SortingOutcome, String> {
    tauri::async_runtime::spawn_blocking(move || outcome(sorting::distribute_downloaded_items(&items, &destination, &rules), &remembered))
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
async fn sorting_undo(records: Vec<SortedFileRecord>) -> Result<sorting::UndoResult, String> {
    tauri::async_runtime::spawn_blocking(move || sorting::undo_distribution(&records)).await.map_err(|e| e.to_string())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DriveExport {
    digest: String,
    success_count: usize,
    failure_count: usize,
    outcomes: Vec<DriveOutcome>,
}

#[tauri::command]
async fn drive_export(records: Vec<SortedFileRecord>) -> Result<DriveExport, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let outcomes = gdrive::export_links(&records, gdrive::RETRY_COUNT, Duration::from_secs(gdrive::RETRY_DELAY_SECS));
        let success = outcomes.iter().filter(|o| o.link.as_deref().is_some_and(|l| !l.trim().is_empty())).count();
        DriveExport { digest: sorting::build_google_drive_digest(&outcomes), success_count: success, failure_count: outcomes.len() - success, outcomes }
    })
    .await
    .map_err(|e| e.to_string())
}

// ------------------------------------------------------------------ Notion и очистка

// Адреса страниц зашиты в приложение: интерфейс не может заставить бэкенд ходить по произвольным ссылкам.
#[tauri::command]
async fn notion_fetch_rules() -> Result<String, String> {
    notion::fetch_rules(notion::DEFAULT_RULES_URL).await
}

#[tauri::command]
async fn notion_fetch_profiles() -> Result<Vec<String>, String> {
    notion::fetch_profiles(notion::DEFAULT_INFLUENCERS_URL).await
}

#[tauri::command]
async fn cleanup_find(root: String) -> Result<Vec<String>, String> {
    tauri::async_runtime::spawn_blocking(move || cleanup::find_deletable_empty_folders(&root)).await.map_err(|e| e.to_string())
}

#[tauri::command]
async fn cleanup_delete(folders: Vec<String>) -> Result<cleanup::CleanupResult, String> {
    tauri::async_runtime::spawn_blocking(move || cleanup::delete_empty_folders(&folders)).await.map_err(|e| e.to_string())
}

#[derive(Serialize)]
struct Snapshot {
    files: usize,
    folders: usize,
}

const MEDIA_EXTENSIONS: [&str; 7] = ["jpg", "jpeg", "png", "webp", "mp4", "mov", "m4v"];

fn count_media(dir: &Path, files: &mut usize) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            count_media(&path, files);
        } else if !cleanup::is_ignorable_entry(&path)
            && path.extension().is_some_and(|e| MEDIA_EXTENSIONS.contains(&e.to_string_lossy().to_lowercase().as_str()))
        {
            *files += 1;
        }
    }
}

/// Живая статистика выгрузки: медиафайлы во всей папке и подпапки первого уровня.
#[tauri::command]
fn dir_snapshot(root: String) -> Snapshot {
    let dir = Path::new(&root);
    if root.trim().is_empty() || !dir.is_dir() {
        return Snapshot { files: 0, folders: 0 };
    }
    let folders = std::fs::read_dir(dir)
        .map(|rd| rd.flatten().filter(|e| e.path().is_dir() && !cleanup::is_ignorable_entry(&e.path())).count())
        .unwrap_or(0);
    let mut files = 0;
    count_media(dir, &mut files);
    Snapshot { files, folders }
}

// ------------------------------------------------------------------ среда и диагностика

#[tauri::command]
fn runtime_status(app: State<'_, App>) -> runtime::RuntimeStatus {
    runtime::status(&app.paths)
}

#[tauri::command]
async fn runtime_install_chromium(handle: AppHandle, app: State<'_, App>) -> Result<String, String> {
    {
        let mut busy = app.installing.lock().unwrap();
        if *busy {
            return Err("Установка уже идёт.".into());
        }
        *busy = true;
    }
    let emitter = handle.clone();
    let result = runtime::install_chromium(&app.paths, move |line| {
        let _ = emitter.emit("bootstrap-log", line);
    })
    .await;
    *app.installing.lock().unwrap() = false;
    result
}

#[tauri::command]
fn preflight(app: State<'_, App>) -> runtime::Preflight {
    let s = settings::load(&app.paths);
    runtime::preflight(&app.paths, Path::new(&s.save_directory))
}

#[tauri::command]
fn export_diagnostics(app: State<'_, App>) -> Result<String, String> {
    let s = settings::load(&app.paths);
    runtime::export_diagnostics(&app.paths, updater::CURRENT_VERSION, Path::new(&s.save_directory)).map(|p| p.to_string_lossy().into_owned())
}

// ------------------------------------------------------------------ обновления

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
fn update_install(handle: AppHandle, app: State<'_, App>) -> Result<(), String> {
    if app.sleep.is_active() {
        return Err("Идёт выгрузка. Дождись её окончания или останови, потом установи обновление.".into());
    }
    let installer = app.installer.lock().unwrap().clone().ok_or("Сначала подготовь обновление.")?;
    if !installer.exists() {
        return Err(format!("Установщик обновления не найден: {}", installer.display()));
    }
    updater::launch_installer(&installer)?;
    // Установщик заменяет файлы приложения: закрываемся сами, не дожидаясь принудительного закрытия.
    // Очередь уже сохранена на диск; установщик запустит приложение снова (/RELAUNCH).
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(1500));
        handle.exit(0);
    });
    Ok(())
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

/// Окно на виду и в фокусе: тогда уведомление не нужно, результат и так перед глазами.
fn window_in_front(app: &AppHandle) -> bool {
    app.get_webview_window("main")
        .map(|w| w.is_visible().unwrap_or(false) && !w.is_minimized().unwrap_or(false) && w.is_focused().unwrap_or(false))
        .unwrap_or(false)
}

/// Системное уведомление о конце выгрузки или обработки. Показывается только когда окно свёрнуто или не в фокусе.
#[tauri::command]
fn notify(app: AppHandle, title: String, body: String) -> Result<bool, String> {
    if window_in_front(&app) {
        return Ok(false);
    }
    app.notification().builder().title(title).body(body).show().map_err(|e| e.to_string())?;
    Ok(true)
}

/// Подсказка у значка в трее: что происходит сейчас («Выгрузка: 58 из 122»).
#[tauri::command]
fn set_tray_status(app: AppHandle, text: String) {
    if let Some(tray) = app.tray_by_id("main") {
        let _ = tray.set_tooltip(Some(text));
    }
}

/// Пункты меню у значка в трее: нужны, чтобы интерфейс мог сменить подписи при другом языке.
struct TrayLabels {
    show: MenuItem<tauri::Wry>,
    quit: MenuItem<tauri::Wry>,
}

#[tauri::command]
fn set_tray_labels(app: AppHandle, show: String, quit: String) {
    if let Some(labels) = app.try_state::<TrayLabels>() {
        let _ = labels.show.set_text(show);
        let _ = labels.quit.set_text(quit);
    }
}

fn show_main_window(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn build_tray(app: &tauri::App) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "Открыть SaveMe", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Выйти", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&show, &quit])?;
    let mut builder = TrayIconBuilder::with_id("main")
        .tooltip("SaveMe")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "show" => show_main_window(app),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                show_main_window(tray.app_handle());
            }
        });
    if let Some(icon) = app.default_window_icon() {
        builder = builder.icon(icon.clone());
    }
    builder.build(app)?;
    app.manage(TrayLabels { show, quit });
    Ok(())
}

pub fn run() {
    let paths = AppPaths::new();
    crash::install_hook(paths.logs_directory(), updater::CURRENT_VERSION);
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        // Размер и положение окна запоминаются. Видимость не восстанавливаем: окно показывает app_ready после отрисовки.
        .plugin(
            tauri_plugin_window_state::Builder::default()
                .with_state_flags(StateFlags::SIZE | StateFlags::POSITION | StateFlags::MAXIMIZED)
                .build(),
        )
        .setup(|app| {
            let mut glass = false;
            // Окно создаём сами (а не из конфигурации), чтобы проверочный запуск в CI мог открыть порт отладки WebView2.
            // Порт включается только переменной SAVEME_CDP_PORT; у обычного пользователя её нет.
            let config = app.config().app.windows.iter().find(|w| w.label == "main").cloned();
            if let Some(config) = config {
                #[allow(unused_mut)]
                let mut builder = WebviewWindowBuilder::from_config(app.handle(), &config)?;
                #[cfg(windows)]
                if let Some(port) = std::env::var("SAVEME_CDP_PORT").ok().and_then(|v| v.trim().parse::<u16>().ok()) {
                    builder = builder.additional_browser_args(&format!(
                        "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection --remote-debugging-port={port}"
                    ));
                }
                builder.build()?;
            }
            if let Some(window) = app.get_webview_window("main") {
                glass = apply_native_glass(&window);
                // Страховка: если интерфейс по какой-то причине не сообщил о готовности, окно всё равно появится.
                let fallback = window.clone();
                std::thread::spawn(move || {
                    std::thread::sleep(Duration::from_secs(4));
                    let _ = fallback.show();
                });
            }
            app.manage(NativeGlass(glass));
            // Значок в трее не обязателен для работы: если система его не дала, просто идём дальше.
            if let Err(error) = build_tray(app) {
                eprintln!("tray: {error}");
            }
            if let Some(window) = app.get_webview_window("main") {
                let saver = std::sync::Arc::new(memory::MemorySaver::default());
                let target = window.clone();
                let handle = app.handle().clone();
                window.on_window_event(move |event| {
                    if matches!(event, tauri::WindowEvent::Resized(_) | tauri::WindowEvent::Focused(_)) {
                        let busy_handle = handle.clone();
                        let is_busy: std::sync::Arc<dyn Fn() -> bool + Send + Sync> =
                            std::sync::Arc::new(move || busy_handle.state::<App>().sleep.is_active());
                        saver.on_window_changed(&target, is_busy);
                    }
                });
            }
            Ok(())
        })
        .manage(App {
            paths,
            worker: worker::WorkerState::default(),
            sleep: sleep::SleepGuard::default(),
            installer: Mutex::new(None),
            installing: Mutex::new(false),
        })
        .invoke_handler(tauri::generate_handler![
            app_info,
            app_ready,
            window_set_theme,
            notify,
            set_tray_status,
            set_tray_labels,
            settings_get,
            settings_save,
            queue_load,
            queue_save,
            open_path,
            worker_run,
            worker_cancel,
            worker_login,
            sorting_parse_rules,
            sorting_run_source,
            sorting_run_items,
            sorting_undo,
            drive_export,
            notion_fetch_rules,
            notion_fetch_profiles,
            cleanup_find,
            cleanup_delete,
            dir_snapshot,
            runtime_status,
            runtime_install_chromium,
            preflight,
            export_diagnostics,
            update_check,
            update_prepare,
            update_install,
        ])
        .run(tauri::generate_context!())
        .expect("failed to start SaveMe");
}
