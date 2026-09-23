use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use crate::app::{App, PaletteAction};
use crate::config::{save_config, GroupDisplay};
use crate::input::command::{handle_shortcut, preview_entry};

pub fn handle_index_input(app: &mut App, key: KeyEvent) {
    if app.palette_open {
        handle_palette_input(app, key);
        return;
    }

    if key.modifiers.contains(KeyModifiers::CONTROL) {
        if let KeyCode::Char(c) = key.code {
            if c == 'k' || c == 'K' {
                open_palette(app);
                return;
            }

            app.status = None;
            handle_shortcut(app, c.to_ascii_lowercase());
        }
        return;
    }

    let total_rows = app.total_display_rows();

    match key.code {
        KeyCode::Char(c) => {
            app.status = None;

            if app.query.len() < app.max_len {
                app.query.push(c);
                app.refresh_filter();
            }
        }

        KeyCode::Backspace => {
            app.status = None;
            app.query.pop();
            app.refresh_filter();
        }

        KeyCode::Enter => {
            app.status = None;

            if app.enter_selected_group() {
                return;
            }

            preview_entry(app);
        }

        KeyCode::Esc => {
            if !app.query.is_empty() {
                app.query.clear();
                app.refresh_filter();
            } else {
                app.should_quit = true;
            }
        }

        KeyCode::Tab => {
            app.detail_open = !app.detail_open;
            app.status = None;
        }

        KeyCode::Left => {
            if app.config.group_display != GroupDisplay::Hidden && app.current_group.is_some() {
                app.status = None;
                app.go_to_parent_group();
            }
        }

        KeyCode::Right => {
            if app.enter_selected_group() {
                app.status = None;
            }
        }

        KeyCode::Down => {
            if total_rows == 0 {
                return;
            }

            app.status = None;

            let selected = app.index_state.selected().unwrap_or(0);
            let next = if selected >= total_rows - 1 {
                0
            } else {
                selected + 1
            };

            app.index_state.select(Some(next));
        }

        KeyCode::Up => {
            if total_rows == 0 {
                return;
            }

            app.status = None;

            let selected = app.index_state.selected().unwrap_or(0);
            let prev = if selected == 0 {
                total_rows - 1
            } else {
                selected - 1
            };

            app.index_state.select(Some(prev));
        }

        _ => {}
    }
}

fn open_palette(app: &mut App) {
    app.palette_open = true;
    app.palette_query.clear();
    refresh_palette_selection(app);
    app.status = None;
}

fn close_palette(app: &mut App) {
    app.palette_open = false;
    app.palette_query.clear();
    app.palette_state.select(None);
}

fn refresh_palette_selection(app: &mut App) {
    let count = app.palette_items().len();

    app.palette_state.select(if count == 0 {
        None
    } else {
        Some(0)
    });
}

fn move_palette_selection(app: &mut App, delta: i32) {
    let count = app.palette_items().len();

    if count == 0 {
        return;
    }

    let current = app.palette_state.selected().unwrap_or(0) as i32;
    let next = (current + delta).rem_euclid(count as i32) as usize;

    app.palette_state.select(Some(next));
}

fn handle_palette_input(app: &mut App, key: KeyEvent) {
    if key.modifiers.contains(KeyModifiers::CONTROL) {
        if let KeyCode::Char(c) = key.code {
            if c == 'k' || c == 'K' {
                close_palette(app);
            }
        }
        return;
    }

    match key.code {
        KeyCode::Esc => {
            close_palette(app);
        }

        KeyCode::Backspace => {
            app.palette_query.pop();
            refresh_palette_selection(app);
        }

        KeyCode::Char(c) => {
            if app.palette_query.len() < 80 {
                app.palette_query.push(c);
                refresh_palette_selection(app);
            }
        }

        KeyCode::Down => {
            move_palette_selection(app, 1);
        }

        KeyCode::Up => {
            move_palette_selection(app, -1);
        }

        KeyCode::Enter => {
            let items = app.palette_items();

            let Some(selected) = app.palette_state.selected() else {
                close_palette(app);
                return;
            };

            let Some((_, action)) = items.get(selected) else {
                close_palette(app);
                return;
            };

            let action = action.clone();
            run_palette_action(app, action);
        }

        _ => {}
    }
}

fn run_palette_action(app: &mut App, action: PaletteAction) {
    app.palette_open = false;
    app.palette_query.clear();
    app.palette_state.select(None);

    match action {
        PaletteAction::CopyUser => {
            crate::clipboard::cp_user(app);
        }
        PaletteAction::CopyPassword => {
            crate::clipboard::cp_password(app);
        }
        PaletteAction::CopyTotp => {
            crate::clipboard::cp_totp(app);
        }
        PaletteAction::CopyUrl => {
            crate::clipboard::cp_url(app);
        }
        PaletteAction::OpenUrl => {
            handle_shortcut(app, 'o');
        }
        PaletteAction::EditEntry => {
            preview_entry(app);
        }
        PaletteAction::NewEntry => {
            handle_shortcut(app, 'a');
        }
        PaletteAction::GeneratePassword => {
            crate::input::generator::open_generator(app, false);
        }
        PaletteAction::Settings => {
            handle_shortcut(app, 's');
        }
        PaletteAction::Lock => {
            app.manual_lock();
        }
        PaletteAction::Quit => {
            app.should_quit = true;
        }
        PaletteAction::SetSort(mode) => {
            app.config.sort_mode = mode.clone();
            app.refresh_filter();

            app.status = Some(match save_config(&app.config) {
                Ok(()) => format!("sort mode: {}", mode.as_str()),
                Err(err) => {
                    format!("sort mode changed, but couldn't save config: {err}")
                }
            });
        }
    }
}
