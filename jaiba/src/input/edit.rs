use crossterm::event::KeyCode;

use crate::app::{App, Screen};
use crate::db::{calculate_warnings, delete_entry, save_database};

const BASE_FIELD_COUNT: usize = 7;
const LAST_MODIFIED_INDEX: usize = 6;

fn field_count(app: &App) -> usize {
    BASE_FIELD_COUNT
        + app
            .edit_entry
            .as_ref()
            .map(|entry| entry.custom_fields.len())
            .unwrap_or(0)
}

pub fn handle_edit_input(app: &mut App, key: KeyCode) {
    if app.editing_field {
        handle_field_input(app, key);
        return;
    }

    if app.confirm_exit {
        handle_exit_confirmation(app, key);
        return;
    }

    if app.confirm_delete {
        handle_delete_confirmation(app, key);
        return;
    }

    match crate::input::normalize_shortcut(key) {
        KeyCode::Esc => request_close_edit(app),

        KeyCode::Enter => start_editing_field(app),

        KeyCode::Char('v') => {
            app.reveal_password = !app.reveal_password;
        }

        KeyCode::Char('g') => {
            if app.edit_state.selected() == Some(2) {
                crate::input::generator::open_generator(app, true);
            } else {
                app.status = Some("select the password field to generate into it".to_string());
            }
        }

        KeyCode::Char('d') => start_delete_confirmation(app),

        KeyCode::Down => move_selection(app, 1),
        KeyCode::Up => move_selection(app, -1),

        _ => {}
    }
}

fn handle_field_input(app: &mut App, key: KeyCode) {
    match key {
        KeyCode::Esc => {
            app.editing_field = false;
            app.field_buffer.clear();
        }

        KeyCode::Enter => commit_field(app),

        KeyCode::Char(c) => app.field_buffer.push(c),

        KeyCode::Backspace => {
            app.field_buffer.pop();
        }

        _ => {}
    }
}

fn move_selection(app: &mut App, delta: i32) {
    let count = field_count(app);

    if count == 0 {
        return;
    }

    let current = app.edit_state.selected().unwrap_or(0) as i32;
    let next = (current + delta).rem_euclid(count as i32) as usize;

    app.edit_state.select(Some(next));
}

fn start_editing_field(app: &mut App) {
    let selected = app.edit_state.selected().unwrap_or(0);

    if selected == LAST_MODIFIED_INDEX {
        app.status = Some("Last modified is set automatically".to_string());
        return;
    }

    if selected >= BASE_FIELD_COUNT {
        let Some(entry) = app.edit_entry.as_ref() else {
            return;
        };

        let Some(custom_index) = selected.checked_sub(BASE_FIELD_COUNT) else {
            return;
        };

        let Some((key, value)) = entry.custom_fields.get(custom_index).cloned() else {
            return;
        };

        crate::clipboard::copy_text(app, &format!("custom field {key}"), &value);
        return;
    }

    let Some(entry) = app.edit_entry.as_ref() else {
        return;
    };

    app.field_buffer = match selected {
        0 => entry.name.clone(),
        1 => entry.user.clone(),
        2 => entry.password.clone(),
        3 => entry.url.clone(),
        4 => entry.totp.clone(),
        5 => entry.notes.clone(),
        _ => return,
    };

    app.editing_field = true;
    app.status = None;

    if selected == 2 {
        app.reveal_password = true;
    }
}

fn commit_field(app: &mut App) {
    let selected = app.edit_state.selected().unwrap_or(0);
    let value = std::mem::take(&mut app.field_buffer);

    if let Some(entry) = app.edit_entry.as_mut() {
        match selected {
            0 => entry.name = value,
            1 => entry.user = value,
            2 => entry.password = value,
            3 => entry.url = value,
            4 => entry.totp = value,
            5 => entry.notes = value,
            _ => {}
        }
    }

    app.editing_field = false;
}

fn request_close_edit(app: &mut App) {
    if has_unsaved_changes(app) {
        app.confirm_exit = true;
        app.status = Some("Save changes? [y] yes  [n] no".to_string());
    } else {
        reset_edit_state(app);
    }
}

fn has_unsaved_changes(app: &App) -> bool {
    let (Some(entry), Some(original)) = (app.edit_entry.as_ref(), app.edit_original.as_ref())
    else {
        return false;
    };

    entry.name != original.name
        || entry.user != original.user
        || entry.password != original.password
        || entry.url != original.url
        || entry.totp != original.totp
        || entry.notes != original.notes
}

fn handle_exit_confirmation(app: &mut App, key: KeyCode) {
    match crate::input::normalize_shortcut(key) {
        KeyCode::Char('y') => {
            app.confirm_exit = false;
            close_edit(app);
        }

        KeyCode::Char('n') => {
            app.confirm_exit = false;
            reset_edit_state(app);
            app.status = Some("Changes discarded".to_string());
        }

        KeyCode::Esc => {
            app.confirm_exit = false;
            app.status = None;
        }

        _ => {}
    }
}

fn close_edit(app: &mut App) {
    save_edit(app);
    reset_edit_state(app);
}

fn reset_edit_state(app: &mut App) {
    app.edit_entry = None;
    app.edit_original = None;
    app.edit_target = None;
    app.editing_field = false;
    app.field_buffer.clear();
    app.confirm_delete = false;
    app.confirm_exit = false;
    app.reveal_password = false;
    app.edit_state.select(None);
    app.screen = Screen::Index;
}

fn save_edit(app: &mut App) {
    let Some(entry) = app.edit_entry.take() else {
        crate::util::debug_log("save_edit: no edit_entry");
        return;
    };

    crate::util::debug_log(&format!(
        "save_edit: name=\"{}\" target={:?}",
        entry.name, app.edit_target
    ));

    let saved_idx = match app.edit_target {
        Some(idx) => {
            if idx >= app.entries.len() {
                crate::util::debug_log(&format!(
                    "save_edit: target idx {idx} out of range (entries.len={})",
                    app.entries.len()
                ));
                app.status = Some("Not saved: target entry disappeared".to_string());
                return;
            }

            if let Some(slot) = app.entries.get_mut(idx) {
                *slot = entry;
            }

            Some(idx)
        }
        None => {
            if entry.name.trim().is_empty() {
                crate::util::debug_log("save_edit: new entry has empty name; not saving");
                app.status = Some("Not saved: new entry needs a Name".to_string());
                return;
            }

            app.entries.push(entry);
            Some(app.entries.len() - 1)
        }
    };

    calculate_warnings(&mut app.entries);

    if let Some(idx) = saved_idx {
        persist_entry(app, idx);
    }

    app.refresh_filter();
}

fn persist_entry(app: &mut App, idx: usize) {
    let Some(path) = app.config.default_database.clone() else {
        crate::util::debug_log("persist_entry: no default_database");
        app.status = Some("Not saved: no default_database configured".to_string());
        return;
    };

    let Some(key) = app.db_key.clone() else {
        crate::util::debug_log("persist_entry: no db_key");
        app.status = Some("Not saved: database key missing".to_string());
        return;
    };

    let Some(db) = app.kdbx.as_mut() else {
        crate::util::debug_log("persist_entry: kdbx locked");
        app.status = Some("Not saved: database is locked".to_string());
        return;
    };

    let Some(target) = app.entries.get_mut(idx) else {
        crate::util::debug_log(&format!("persist_entry: idx {idx} out of range"));
        app.status = Some("Not saved: entry disappeared".to_string());
        return;
    };

    let label = if target.name.trim().is_empty() {
        "(no title)".to_string()
    } else {
        target.name.clone()
    };

    crate::util::debug_log(&format!(
        "persist_entry: saving \"{label}\" idx={idx} id_present={} path={}",
        target.id.is_some(),
        path.display()
    ));

    match save_database(&path, &key, db, std::slice::from_mut(target)) {
        Ok(()) => {
            crate::util::debug_log("persist_entry: OK");
            app.status = Some(format!("Saved \"{label}\" to {}", path.display()));
        }
        Err(err) => {
            crate::util::debug_log(&format!("persist_entry: ERR {err:#}"));
            app.status = Some(format!(
                "Failed to save \"{label}\" to {}: {err:#}",
                path.display()
            ));
        }
    }
}

fn start_delete_confirmation(app: &mut App) {
    if app.edit_entry.is_none() {
        return;
    }

    app.confirm_delete = true;
    app.status = Some("Delete this entry? [y] confirm  [any other key] cancel".to_string());
}

fn handle_delete_confirmation(app: &mut App, key: KeyCode) {
    app.confirm_delete = false;
    app.status = None;

    if let KeyCode::Char('y') = crate::input::normalize_shortcut(key) {
        delete_current_entry(app);
    }
}

fn delete_current_entry(app: &mut App) {
    let Some(entry) = app.edit_entry.take() else {
        reset_edit_state(app);
        return;
    };

    if let Some(id) = entry.id {
        let (Some(db), Some(key), Some(path)) = (
            app.kdbx.as_mut(),
            app.db_key.as_ref(),
            app.config.default_database.as_ref(),
        ) else {
            app.status = Some("Not deleted: database is locked".to_string());
            app.edit_entry = Some(entry);
            return;
        };

        if let Err(err) = delete_entry(path, key, db, id) {
            app.status = Some(format!("Failed to delete: {err:#}"));
            app.edit_entry = Some(entry);
            return;
        }
    }

    if let Some(idx) = app.edit_target {
        if idx < app.entries.len() {
            app.entries.remove(idx);
        }
    }

    calculate_warnings(&mut app.entries);
    app.refresh_filter();

    reset_edit_state(app);
    app.status = Some("Entry deleted".to_string());
}
