use std::time::{SystemTime, UNIX_EPOCH, Instant};

use arboard::Clipboard;

use crate::app::App;

fn current_epoch_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn mark_copied(app: &mut App) {
    let Some(selected) = app.index_state.selected() else {
        return;
    };

    let Some(idx) = app.entry_at_row(selected) else {
        return;
    };

    let entry_id = app.entries.get(idx).and_then(|e| e.id);
    let now = current_epoch_secs();

    if let Some(entry) = app.entries.get_mut(idx) {
        entry.last_copied = now;
    }

    let mut persist_error: Option<String> = None;

    if let Some(id) = entry_id {
        let path = app.config.default_database.clone();
        let key = app.db_key.clone();

        if let (Some(path), Some(key), Some(db)) = (path, key, app.kdbx.as_mut()) {
            if let Err(err) = crate::db::persist_last_copied(&path, &key, db, id, now) {
                persist_error = Some(format!("{err:#}"));
            }
        }
    }

    if let Some(err) = persist_error {
        app.status = Some(format!("copied, but couldn't save last-copied: {err}"));
    }

    if app.config.sort_mode == crate::config::SortMode::LastCopied {
        app.refresh_filter();
        app.select_entry_row(idx);
    }
}

pub struct ClipboardTimer {
    pub label: String,
    pub expected: String,
    pub clear_at: Instant,
}

fn copy_and_report(app: &mut App, label: &str, text: &str) -> bool {
    let result = match app.clipboard.as_mut() {
        Some(clipboard) => clipboard.set_text(text),
        None => match Clipboard::new() {
            Ok(mut clipboard) => {
                let result = clipboard.set_text(text);
                app.clipboard = Some(clipboard);
                result
            }
            Err(err) => Err(err),
        },
    };

    match result {
        Ok(()) => {
            app.clipboard_timer = Some(ClipboardTimer {
                label: label.to_string(),
                expected: text.to_string(),
                clear_at: Instant::now() + app.config.clipboard_timeout,
            });
            app.status = None;
            true
        }
        Err(err) => {
            app.clipboard_timer = None;
            app.status = Some(format!("Failed to copy {label}: {err}"));
            false
        }
    }
}

pub fn maybe_clear_clipboard(app: &mut App) {
    let clear_at = match app.clipboard_timer.as_ref() {
        Some(timer) => timer.clear_at,
        None => return,
    };

    if Instant::now() < clear_at {
        return;
    }

    let Some(timer) = app.clipboard_timer.take() else {
        return;
    };

    let Some(clipboard) = app.clipboard.as_mut() else {
        app.status = Some("Clipboard unavailable".to_string());
        return;
    };

    match clipboard.get_text() {
        Ok(current) if current == timer.expected => {
            if let Err(err) = clipboard.clear() {
                app.clipboard_timer = Some(timer);
                app.status = Some(format!("Couldn't clear clipboard: {err}"));
            } else {
                app.status = Some("Clipboard cleared".to_string());
            }
        }
        _ => {
            app.status = Some("Clipboard left unchanged".to_string());
        }
    }
}

pub fn cp_user(app: &mut App) {
    let Some(user) = app.selected_entry().map(|entry| entry.user.clone()) else {
        return;
    };

    if copy_and_report(app, "user", &user) {
        mark_copied(app);
    }
}

pub fn cp_password(app: &mut App) {
    let Some(password) = app.selected_entry().map(|entry| entry.password.clone()) else {
        return;
    };

    if copy_and_report(app, "password", &password) {
        mark_copied(app);
    }
}

pub fn cp_totp(app: &mut App) {
    let Some(totp_raw) = app.selected_entry().map(|entry| entry.totp.clone()) else {
        return;
    };

    match crate::db::current_totp_code(&totp_raw) {
        Some(code) => {
            if copy_and_report(app, "TOTP code", &code.code) {
                mark_copied(app);
            }
        }
        None => {
            app.clipboard_timer = None;
            app.status = Some("No valid TOTP configured for this entry".to_string());
        }
    }
}

pub fn cp_url(app: &mut App) {
    let Some(url) = app.selected_entry().map(|entry| entry.url.clone()) else {
        return;
    };

    if copy_and_report(app, "URL", &url) {
        mark_copied(app);
    }
}

pub fn copy_text(app: &mut App, label: &str, text: &str) -> bool {
    copy_and_report(app, label, text)
}
