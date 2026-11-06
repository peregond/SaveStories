//! Не даёт Windows засыпать на время выгрузки. ES_CONTINUOUS действует на поток,
//! поэтому состояние держит отдельный поток, а не пул async-задач.

use std::sync::mpsc::{channel, Sender};
use std::sync::Mutex;

#[derive(Default)]
pub struct SleepGuard {
    stop: Mutex<Option<Sender<()>>>,
}

impl SleepGuard {
    pub fn acquire(&self) {
        let mut slot = self.stop.lock().unwrap();
        if slot.is_some() {
            return;
        }
        let (tx, rx) = channel::<()>();
        std::thread::spawn(move || {
            set_awake(true);
            let _ = rx.recv();
            set_awake(false);
        });
        *slot = Some(tx);
    }

    /// Идёт ли выгрузка (держится ли блокировка сна).
    pub fn is_active(&self) -> bool {
        self.stop.lock().unwrap().is_some()
    }

    pub fn release(&self) {
        if let Some(tx) = self.stop.lock().unwrap().take() {
            let _ = tx.send(());
        }
    }
}

#[cfg(windows)]
fn set_awake(on: bool) {
    use windows_sys::Win32::System::Power::{SetThreadExecutionState, ES_CONTINUOUS, ES_SYSTEM_REQUIRED};
    unsafe {
        SetThreadExecutionState(if on { ES_CONTINUOUS | ES_SYSTEM_REQUIRED } else { ES_CONTINUOUS });
    }
}

#[cfg(not(windows))]
fn set_awake(_on: bool) {}
