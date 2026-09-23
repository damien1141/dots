use crossterm::event::KeyCode;
use crate::app::{App, Screen};
use crate::generator::{GeneratorMode, GeneratorOptions};

pub fn open_generator(app: &mut App, into_edit_password: bool) {
    if app.screen == Screen::Generator {
        return;
    }

    app.generator_return = app.screen;
    app.generator_into_edit_password = into_edit_password;
    app.screen = Screen::Generator;

    regenerate(app);
}

pub fn handle_generator_input(app: &mut App, key: KeyCode) {
    match crate::input::normalize_shortcut(key) {
        KeyCode::Esc => close_generator(app),
        KeyCode::Enter => use_generated_password(app),
        KeyCode::Tab => cycle_mode(app),
        KeyCode::Up => increase_size(app),
        KeyCode::Down => decrease_size(app),
        KeyCode::Char('g') => regenerate(app),
        KeyCode::Char('y') => copy_generated_password(app),
        KeyCode::Char('u') => toggle_upper(app),
        KeyCode::Char('d') => toggle_digits(app),
        KeyCode::Char('s') => toggle_symbols(app),
        KeyCode::Char('a') => toggle_ambiguous(app),
        _ => {}
    }
}

fn close_generator(app: &mut App) {
    app.screen = app.generator_return;
    app.generator_into_edit_password = false;
    app.generator_result.clear();
}

fn use_generated_password(app: &mut App) {
    let result = app.generator_result.clone();
    let into_edit = app.generator_into_edit_password;
    let target = app.generator_return;

    app.generator_result.clear();
    app.generator_into_edit_password = false;
    app.screen = target;

    if into_edit && target == Screen::Edit {
        if let Some(entry) = app.edit_entry.as_mut() {
            entry.password = result;
            app.reveal_password = true;
            app.status = Some("Password field updated".to_string());
            return;
        }
    }

    crate::clipboard::copy_text(app, "generated password", &result);
}

fn copy_generated_password(app: &mut App) {
    let result = app.generator_result.clone();
    crate::clipboard::copy_text(app, "generated password", &result);
}

fn cycle_mode(app: &mut App) {
    app.generator_mode = match app.generator_mode {
        GeneratorMode::Random => GeneratorMode::Passphrase,
        GeneratorMode::Passphrase => GeneratorMode::Pin,
        GeneratorMode::Pin => GeneratorMode::Hex,
        GeneratorMode::Hex => GeneratorMode::Random,
    };

    regenerate(app);
}

fn increase_size(app: &mut App) {
    match app.generator_mode {
        GeneratorMode::Passphrase => {
            app.generator_words = (app.generator_words + 1).min(20);
        }
        GeneratorMode::Pin => {
            app.generator_length = (app.generator_length + 2).min(32);
        }
        _ => {
            app.generator_length = (app.generator_length + 2).min(128);
        }
    }

    regenerate(app);
}

fn decrease_size(app: &mut App) {
    match app.generator_mode {
        GeneratorMode::Passphrase => {
            app.generator_words = app.generator_words.saturating_sub(1).max(1);
        }
        GeneratorMode::Pin => {
            app.generator_length = app.generator_length.saturating_sub(2).max(4);
        }
        _ => {
            app.generator_length = app.generator_length.saturating_sub(2).max(4);
        }
    }

    regenerate(app);
}

fn toggle_upper(app: &mut App) {
    if app.generator_mode != GeneratorMode::Random {
        return;
    }

    app.generator_use_upper = !app.generator_use_upper;
    regenerate(app);
}

fn toggle_digits(app: &mut App) {
    if app.generator_mode != GeneratorMode::Random {
        return;
    }

    app.generator_use_digits = !app.generator_use_digits;
    regenerate(app);
}

fn toggle_symbols(app: &mut App) {
    if app.generator_mode != GeneratorMode::Random {
        return;
    }

    app.generator_use_symbols = !app.generator_use_symbols;
    regenerate(app);
}

fn toggle_ambiguous(app: &mut App) {
    if app.generator_mode != GeneratorMode::Random {
        return;
    }

    app.generator_exclude_ambiguous = !app.generator_exclude_ambiguous;
    regenerate(app);
}

fn regenerate(app: &mut App) {
    let opts = GeneratorOptions {
        mode: app.generator_mode,
        length: app.generator_length,
        words: app.generator_words,
        use_upper: app.generator_use_upper,
        use_digits: app.generator_use_digits,
        use_symbols: app.generator_use_symbols,
        exclude_ambiguous: app.generator_exclude_ambiguous,
    };

    app.generator_result = crate::generator::generate(&opts);
}
