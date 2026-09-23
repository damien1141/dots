use std::time::Instant;

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

use crate::app::{App, Screen};
use crate::config::save_config;
use crate::db::{calculate_warnings, create_database, unlock_database};
use crate::fprint;
use crate::util::default_new_database_path;

pub fn handle_login_input(app: &mut App, key: KeyEvent) {
    let key_code = key.code;

    if app.creating_database {
        handle_create_database_input(app, key_code);
        return;
    }

    if database_missing(app) {
        handle_missing_database_input(app, key_code);
        return;
    }

    if app.config.fingerprint_enabled
        && app.fprint_available
        && app.fprint_enrolled
        && !app.fingerprint_verifying
    {
        if let KeyCode::Char('f') = key_code {
            if key.modifiers.contains(KeyModifiers::CONTROL) {
                start_fingerprint_verify(app);
                return;
            }
        }
    }

    match key_code {
        KeyCode::Char(c) => {
            app.login_error = None;

            if app.password.len() < app.max_len {
                app.password.push(c);
            }
        }

        KeyCode::Backspace => {
            app.login_error = None;
            app.password.pop();
        }

        KeyCode::Enter => {
            attempt_unlock(app);
        }

        KeyCode::Esc => {
            app.should_quit = true;
        }

        _ => {}
    }
}

pub fn database_missing(app: &App) -> bool {
    match &app.config.default_database {
        None => true,
        Some(path) => !path.is_file(),
    }
}

fn handle_missing_database_input(app: &mut App, key: KeyCode) {
    match crate::input::normalize_shortcut(key) {
        KeyCode::Char('n') => start_create_database(app),

        KeyCode::Esc => {
            app.should_quit = true;
        }

        _ => {}
    }
}

fn start_create_database(app: &mut App) {
    app.creating_database = true;
    app.confirming_new_db_password = false;
    app.password.clear();
    app.new_db_confirm.clear();
    app.login_error = None;
}

fn cancel_create_database(app: &mut App) {
    app.creating_database = false;
    app.confirming_new_db_password = false;
    app.password.clear();
    app.new_db_confirm.clear();
    app.login_error = None;
}

fn handle_create_database_input(app: &mut App, key: KeyCode) {
    match key {
        KeyCode::Char(c) => {
            app.login_error = None;
            let limit = app.max_len;

            if app.confirming_new_db_password {
                if app.new_db_confirm.len() < limit {
                    app.new_db_confirm.push(c);
                }
            } else if app.password.len() < limit {
                app.password.push(c);
            }
        }

        KeyCode::Backspace => {
            app.login_error = None;

            if app.confirming_new_db_password {
                app.new_db_confirm.pop();
            } else {
                app.password.pop();
            }
        }

        KeyCode::Enter => {
            if app.confirming_new_db_password {
                finish_create_database(app);
            } else if app.password.is_empty() {
                app.login_error = Some("Master password can't be empty".to_string());
            } else {
                app.confirming_new_db_password = true;
            }
        }

        KeyCode::Esc => cancel_create_database(app),

        _ => {}
    }
}

fn finish_create_database(app: &mut App) {
    if app.new_db_confirm != app.password {
        app.login_error = Some("Passwords don't match".to_string());
        app.new_db_confirm.clear();
        app.confirming_new_db_password = false;
        return;
    }

    let path = app
        .config
        .default_database
        .clone()
        .unwrap_or_else(default_new_database_path);

    if path.is_file() {
        app.config.default_database = Some(path.clone());
        let _ = save_config(&app.config);

        app.new_db_confirm.clear();
        app.creating_database = false;
        app.confirming_new_db_password = false;
        app.login_error = Some(format!(
            "A vault already exists at {}. Press Enter to try unlocking it with this password.",
            path.display()
        ));
        return;
    }

    match create_database(&path, &app.password, app.config.keyfile.as_deref()) {
        Ok((db, key, entries, groups)) => {
            app.config.default_database = Some(path.clone());
            let save_result = save_config(&app.config);

            if app.config.fingerprint_enabled {
                if let Err(err) = fprint::store_password(&app.config, &app.password) {
                    app.status = Some(format!("Fingerprint password storage failed: {err}"));
                }
            }

            app.kdbx = Some(db);
            app.db_key = Some(key);
            app.entries = entries;
            app.groups = groups;
            app.current_group = None;
            app.password.clear();
            app.new_db_confirm.clear();
            app.creating_database = false;
            app.confirming_new_db_password = false;
            app.login_error = None;
            app.last_activity = Instant::now();
            app.refresh_filter();
            app.screen = Screen::Index;

            app.status = Some(match save_result {
                Ok(()) => format!("Created new database at {}", path.display()),
                Err(err) => format!("Database created, but couldn't save config: {err}"),
            });
        }

        Err(err) => {
            app.login_error = Some(format!("Couldn't create database: {err:#}"));
            app.password.clear();
            app.new_db_confirm.clear();
            app.confirming_new_db_password = false;
        }
    }
}

fn attempt_unlock(app: &mut App) {
    let Some(path) = app.config.default_database.clone() else {
        app.login_error = Some("No default_database set in jaiba_config.toml".to_string());
        return;
    };

    // Kill background fingerprint listener so it doesn't overwrite manual unlock
    if app.fingerprint_verifying {
        crate::fprint::stop_verify(app.fingerprint_running.as_ref());
        app.fingerprint_verifying = false;
        app.fingerprint_verify_rx = None;
        app.fingerprint_running = None;
    }

    let password = app.password.clone();
    match unlock_database(&path, &password, app.config.keyfile.as_deref()) {
        Ok((db, key, mut entries, groups)) => {
            calculate_warnings(&mut entries);
            app.entries = entries;
            app.groups = groups;
            app.current_group = None; // Start at root
            app.kdbx = Some(db);
            app.db_key = Some(key);

            if app.config.fingerprint_enabled {
                if let Err(err) = fprint::store_password(&app.config, &password) {
                    app.status = Some(format!("Fingerprint password storage failed: {err}"));
                }
            }

            app.password.clear();
            app.login_error = None;
            app.last_activity = Instant::now();
            app.refresh_filter();
            app.screen = Screen::Index;
        }
        Err(err) => {
            app.password.clear();
            app.login_error = Some(format!("{err}"));
        }
    }
}

fn start_fingerprint_verify(app: &mut App) {
    if app.fingerprint_verifying {
        return;
    }

    // Stop any ongoing verification first
    fprint::stop_verify(app.fingerprint_running.as_ref());

    match fprint::start_verify() {
        Ok((rx, running)) => {
            app.fingerprint_verifying = true;
            app.fingerprint_verify_rx = Some(rx);
            app.fingerprint_running = Some(running);
            app.login_error = None;
            app.status = Some("Scanning fingerprint...".to_string());
        }
        Err(err) => {
            app.login_error = Some(format!("Fingerprint error: {err}"));
        }
    }
}
