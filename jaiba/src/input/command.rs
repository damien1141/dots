use crate::app::App;
use crate::clipboard::{cp_password, cp_totp, cp_url, cp_user};
use crate::db::Entry;

pub fn handle_shortcut(app: &mut App, c: char) {
    match c {
        'u' => cp_user(app),
        'p' => cp_password(app),
        't' => cp_totp(app),
        'r' => cp_url(app),
        'o' => open_url(app),
        'a' => add_entry(app),
        'g' => crate::input::generator::open_generator(app, false),
        's' => open_settings(app),
        _ => {}
    }
}

fn add_entry(app: &mut App) {
    let mut entry = Entry::default();
    entry.group_id = app.current_group;

    app.edit_entry = Some(entry.clone());
    app.edit_original = Some(entry);
    app.edit_target = None;
    app.edit_state.select(Some(0));
    app.reveal_password = false;
    app.confirm_delete = false;
    app.confirm_exit = false;
    app.screen = crate::app::Screen::Edit;
}

pub fn preview_entry(app: &mut App) {
    let Some(entry_idx) = app.selected_entry_index() else {
        return;
    };

    let Some(entry) = app.entries.get(entry_idx) else {
        return;
    };

    app.edit_entry = Some(entry.clone());
    app.edit_original = Some(entry.clone());
    app.edit_target = Some(entry_idx);
    app.edit_state.select(Some(0));
    app.reveal_password = false;
    app.confirm_delete = false;
    app.confirm_exit = false;
    app.screen = crate::app::Screen::Edit;
}

fn open_url(app: &mut App) {
    let Some(raw_url) = app.selected_entry().map(|entry| entry.url.trim().to_string()) else {
        return;
    };

    if raw_url.is_empty() {
        app.status = Some("No URL for this entry".to_string());
        return;
    }

    let url = if raw_url.contains("://") {
        raw_url
    } else {
        format!("https://{raw_url}")
    };

    match std::process::Command::new("xdg-open")
        .arg(&url)
        .spawn()
    {
        Ok(_) => app.status = Some("Opening URL".to_string()),
        Err(err) => app.status = Some(format!("Couldn't open URL: {err}")),
    }
}

fn open_settings(app: &mut App) {
    app.status = None;
    app.available_themes = crate::theme::list_theme_names().unwrap_or_default();

    let current_idx = app.config.theme.as_deref().and_then(|current| {
        let current = crate::theme::slugify(current);
        app.available_themes
            .iter()
            .position(|name| crate::theme::slugify(name) == current)
    });

    let selected = current_idx.or(if app.available_themes.is_empty() {
        None
    } else {
        Some(0)
    });

    app.settings_state.select(selected);
    app.screen = crate::app::Screen::Settings;
}
