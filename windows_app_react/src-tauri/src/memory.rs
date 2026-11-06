//! Экономия памяти WebView2, пока окно свёрнуто.
//!
//! Свёрнутое окно: сразу просим WebView2 отдать кэши (MemoryUsageTargetLevel = Low). Если выгрузка не идёт и окно
//! остаётся свёрнутым дольше паузы, страницу замораживаем (TrySuspend). При разворачивании всё возвращается.
//! Во время выгрузки страницу не замораживаем: интерфейс получает события журнала и не должен их пропускать.
//! Любая ошибка WebView2 игнорируется — в худшем случае память просто не освобождается.

use std::sync::atomic::{AtomicU64, AtomicU8, Ordering};
use std::sync::Arc;
use std::time::Duration;

use tauri::WebviewWindow;

const NORMAL: u8 = 0;
const LOW: u8 = 1;
const SUSPENDED: u8 = 2;

/// Через сколько свёрнутое окно замораживается (если выгрузки нет).
const SUSPEND_AFTER: Duration = Duration::from_secs(20);

#[derive(Default)]
pub struct MemorySaver {
    state: AtomicU8,
    generation: AtomicU64,
}

impl MemorySaver {
    /// Вызывается при каждом изменении размера окна или фокуса.
    pub fn on_window_changed(self: &Arc<Self>, window: &WebviewWindow, is_busy: Arc<dyn Fn() -> bool + Send + Sync>) {
        let minimized = window.is_minimized().unwrap_or(false);
        if minimized {
            if self.state.load(Ordering::SeqCst) != NORMAL {
                return;
            }
            self.state.store(LOW, Ordering::SeqCst);
            let generation = self.generation.fetch_add(1, Ordering::SeqCst) + 1;
            platform::set_low(window, true);
            let me = Arc::clone(self);
            let window = window.clone();
            std::thread::spawn(move || {
                std::thread::sleep(SUSPEND_AFTER);
                let still_minimized = window.is_minimized().unwrap_or(false);
                if me.generation.load(Ordering::SeqCst) == generation && still_minimized && !is_busy() {
                    platform::suspend(&window);
                    me.state.store(SUSPENDED, Ordering::SeqCst);
                }
            });
        } else {
            self.generation.fetch_add(1, Ordering::SeqCst);
            let previous = self.state.swap(NORMAL, Ordering::SeqCst);
            if previous == SUSPENDED {
                platform::resume(window);
            }
            if previous != NORMAL {
                platform::set_low(window, false);
            }
        }
    }
}

#[cfg(windows)]
mod platform {
    use tauri::WebviewWindow;
    use webview2_com::Microsoft::Web::WebView2::Win32::{
        ICoreWebView2_19, ICoreWebView2_3, COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_LOW,
        COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_NORMAL,
    };
    use webview2_com::TrySuspendCompletedHandler;
    use windows_core::Interface;

    pub fn set_low(window: &WebviewWindow, low: bool) {
        let _ = window.with_webview(move |webview| unsafe {
            let Ok(core) = webview.controller().CoreWebView2() else { return };
            let Ok(core19) = core.cast::<ICoreWebView2_19>() else { return };
            let level = if low {
                COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_LOW
            } else {
                COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_NORMAL
            };
            let _ = core19.SetMemoryUsageTargetLevel(level);
        });
    }

    pub fn suspend(window: &WebviewWindow) {
        let _ = window.with_webview(move |webview| unsafe {
            let controller = webview.controller();
            // TrySuspend работает только с невидимым WebView.
            let _ = controller.SetIsVisible(false);
            let Ok(core) = controller.CoreWebView2() else { return };
            let Ok(core3) = core.cast::<ICoreWebView2_3>() else { return };
            let handler = TrySuspendCompletedHandler::create(Box::new(|_, _| Ok(())));
            let _ = core3.TrySuspend(&handler);
        });
    }

    pub fn resume(window: &WebviewWindow) {
        let _ = window.with_webview(move |webview| unsafe {
            let controller = webview.controller();
            if let Ok(core) = controller.CoreWebView2() {
                if let Ok(core3) = core.cast::<ICoreWebView2_3>() {
                    let _ = core3.Resume();
                }
            }
            let _ = controller.SetIsVisible(true);
        });
    }
}

#[cfg(not(windows))]
mod platform {
    use tauri::WebviewWindow;
    pub fn set_low(_window: &WebviewWindow, _low: bool) {}
    pub fn suspend(_window: &WebviewWindow) {}
    pub fn resume(_window: &WebviewWindow) {}
}
