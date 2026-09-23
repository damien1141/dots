use std::io;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use arboard::Clipboard;
use crossterm::event::{self, Event};
use keepass::{Database, DatabaseKey};
use ratatui::{
    Terminal,
    backend::CrosstermBackend,
    style::Style,
    widgets::{Block, ListState, TableState},
};

use crate::clipboard::{ClipboardTimer, maybe_clear_clipboard};
use crate::config::{Config, GroupDisplay, load_config, SortMode};
use crate::db::{calculate_warnings, Entry, Group, parse_date_ago, has_totp, has_url, unlock_database};
use crate::fprint;
use crate::input::edit::handle_edit_input;
use crate::input::index::handle_index_input;
use crate::input::login::handle_login_input;
use crate::input::settings::handle_settings_input;
use crate::theme::{Theme, load_theme};
use crate::ui::edit::draw_edit;
use crate::ui::index::draw_index;
use crate::ui::login::draw_login;
use crate::ui::settings::draw_settings;

#[derive(PartialEq, Eq, Copy, Clone)]
pub enum Screen {
    Login,
    Index,
    Edit,
    Settings,
    Generator,
}

#[derive(PartialEq, Eq)]
pub enum PasswordChangeStep {
    CurrentPassword,
    NewPassword,
    ConfirmNewPassword,
}

#[derive(PartialEq, Eq)]
pub enum ImportStep {
    Path,
    KdbxPassword,
}

#[derive(PartialEq, Eq)]
pub enum ExportStep {
    Path,
    Confirm,
}

#[derive(Clone)]
pub enum PaletteAction {
    CopyUser,
    CopyPassword,
    CopyTotp,
    CopyUrl,
    OpenUrl,
    EditEntry,
    NewEntry,
    GeneratePassword,
    Settings,
    Lock,
    Quit,
    SetSort(SortMode),
}

#[derive(Clone, Copy)]
pub enum IndexRow {
    Group(usize),
    Entry(usize),
}

pub struct App {
    pub screen: Screen,
    pub password: String,
    pub query: String,
    pub max_len: usize,
    pub index_state: TableState,
    pub edit_state: ListState,
    pub reveal_password: bool,
    pub edit_entry: Option<Entry>,
    pub edit_original: Option<Entry>,
    pub edit_target: Option<usize>,
    pub editing_field: bool,
    pub field_buffer: String,
    pub confirm_delete: bool,
    pub confirm_exit: bool,
    pub entries: Vec<Entry>,
    pub groups: Vec<Group>,
    pub current_group: Option<keepass::db::GroupId>,
    pub filtered: Vec<usize>,
    pub kdbx: Option<Database>,
    pub db_key: Option<DatabaseKey>,
    pub theme: Theme,
    pub config: Config,

    pub creating_database: bool,
    pub confirming_new_db_password: bool,
    pub new_db_confirm: String,

    pub available_themes: Vec<String>,
    pub settings_state: ListState,
    pub choosing_theme: bool,
    pub theme_state: ListState,

    pub changing_password: bool,
    pub password_change_step: PasswordChangeStep,
    pub current_password_buffer: String,
    pub new_password_buffer: String,
    pub new_password_confirm: String,

    pub importing_database: bool,
    pub import_step: ImportStep,
    pub import_path_buffer: String,
    pub import_kdbx_password_buffer: String,
    pub pending_import_path: Option<PathBuf>,

    pub exporting_database: bool,
    pub export_step: ExportStep,
    pub export_path_buffer: String,
    pub pending_export_path: Option<PathBuf>,

    pub login_error: Option<String>,

    pub last_activity: Instant,

    pub status: Option<String>,

    pub clipboard: Option<Clipboard>,

    pub clipboard_timer: Option<ClipboardTimer>,

    pub should_quit: bool,
    pub slim_mode: bool,

    pub fingerprint_verifying: bool,
    pub fingerprint_verify_rx: Option<std::sync::mpsc::Receiver<bool>>,
    pub fingerprint_running: Option<std::sync::Arc<std::sync::atomic::AtomicBool>>,
    pub prev_screen: Screen,

    pub fprint_available: bool,
    pub fprint_enrolled: bool,

    pub entering_fprint_password: bool,
    pub fprint_password_buffer: String,

    pub palette_open: bool,
    pub palette_query: String,
    pub palette_state: ListState,
    pub detail_open: bool,

    pub generator_return: Screen,
    pub generator_into_edit_password: bool,
    pub generator_mode: crate::generator::GeneratorMode,
    pub generator_length: usize,
    pub generator_words: usize,
    pub generator_use_upper: bool,
    pub generator_use_digits: bool,
    pub generator_use_symbols: bool,
    pub generator_exclude_ambiguous: bool,
    pub generator_result: String,
}

impl App {
    fn find_group(groups: &[Group], id: keepass::db::GroupId) -> Option<&Group> {
        for group in groups {
            if group.id == id {
                return Some(group);
            }
            if let Some(found) = Self::find_group(&group.children, id) {
                return Some(found);
            }
        }
        None
    }

    pub fn current_child_groups(&self) -> Vec<&Group> {
        match self.current_group {
            None => self.groups.iter().collect(),
            Some(gid) => Self::find_group(&self.groups, gid)
                .map(|g| g.children.iter().collect())
                .unwrap_or_default(),
        }
    }

    pub fn total_display_rows(&self) -> usize {
        match self.config.group_display {
            GroupDisplay::Hidden => self.filtered.len(),
            _ => self.current_child_groups().len() + self.filtered.len(),
        }
    }

    pub fn index_rows(&self) -> Vec<IndexRow> {
        let groups = self.current_child_groups();

        match self.config.group_display {
            GroupDisplay::Hidden => self
                .filtered
                .iter()
                .copied()
                .filter(|&entry_idx| entry_idx < self.entries.len())
                .map(IndexRow::Entry)
                .collect(),

            GroupDisplay::Shown => {
                let mut rows = Vec::with_capacity(groups.len() + self.filtered.len());

                for group_idx in 0..groups.len() {
                    rows.push(IndexRow::Group(group_idx));
                }

                for &entry_idx in &self.filtered {
                    if entry_idx < self.entries.len() {
                        rows.push(IndexRow::Entry(entry_idx));
                    }
                }

                rows
            }

            GroupDisplay::Bottom => {
                let mut rows = Vec::with_capacity(groups.len() + self.filtered.len());

                for &entry_idx in &self.filtered {
                    if entry_idx < self.entries.len() {
                        rows.push(IndexRow::Entry(entry_idx));
                    }
                }

                for group_idx in 0..groups.len() {
                    rows.push(IndexRow::Group(group_idx));
                }

                rows
            }

            GroupDisplay::Mixed => {
            // Name sort gets true alphabetical mixed order.
            if matches!(self.config.sort_mode, SortMode::Name) {
                let mut items: Vec<(String, bool, IndexRow)> =
                    Vec::with_capacity(groups.len() + self.filtered.len());

                for (group_idx, group) in groups.iter().enumerate() {
                    items.push((
                        group.name.to_lowercase(),
                        false,
                        IndexRow::Group(group_idx),
                    ));
                }

                for &entry_idx in &self.filtered {
                    if let Some(entry) = self.entries.get(entry_idx) {
                        items.push((
                            entry.name.to_lowercase(),
                            true,
                            IndexRow::Entry(entry_idx),
                        ));
                    }
                }

                // false = group, true = entry.
                // groups win ties against entries with the same name.
                items.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));

                items.into_iter().map(|(_, _, row)| row).collect()
            } else {
                // For non-name sorts, keep groups pinned alphabetically,
                // then entries follow the active sort order.
                let mut group_rows: Vec<usize> = (0..groups.len()).collect();

                group_rows.sort_by(|&a, &b| {
                    groups[a]
                        .name
                        .to_lowercase()
                        .cmp(&groups[b].name.to_lowercase())
                });

                let mut rows = Vec::with_capacity(groups.len() + self.filtered.len());

                for group_idx in group_rows {
                    rows.push(IndexRow::Group(group_idx));
                }

                for &entry_idx in &self.filtered {
                    if entry_idx < self.entries.len() {
                        rows.push(IndexRow::Entry(entry_idx));
                    }
                }

                rows
            }
        }
        }
    }

    pub fn group_at_row(&self, row: usize) -> Option<keepass::db::GroupId> {
        let groups = self.current_child_groups();

        match self.index_rows().get(row)? {
            IndexRow::Group(group_idx) => groups.get(*group_idx).map(|g| g.id),
            IndexRow::Entry(_) => None,
        }
    }

    pub fn entry_at_row(&self, row: usize) -> Option<usize> {
        match self.index_rows().get(row)? {
            IndexRow::Entry(entry_idx) => Some(*entry_idx),
            IndexRow::Group(_) => None,
        }
    }

    pub fn select_entry_row(&mut self, entry_idx: usize) {
        let row = self
            .index_rows()
            .iter()
            .position(|row| matches!(row, IndexRow::Entry(i) if *i == entry_idx));

        self.index_state.select(row.or(Some(0)));
    }

    pub fn selected_group_id(&self) -> Option<keepass::db::GroupId> {
        let selected = self.index_state.selected()?;
        self.group_at_row(selected)
    }

    pub fn selected_entry_index(&self) -> Option<usize> {
        let selected = self.index_state.selected()?;
        self.entry_at_row(selected)
    }

    pub fn selected_entry(&self) -> Option<&Entry> {
        self.entries.get(self.selected_entry_index()?)
    }

    pub fn parent_group_id(&self, id: keepass::db::GroupId) -> Option<keepass::db::GroupId> {
        let group = Self::find_group(&self.groups, id)?;
        let parent = group.parent_id?;

        if Self::find_group(&self.groups, parent).is_some() {
            Some(parent)
        } else {
            None
        }
    }

    pub fn go_to_parent_group(&mut self) {
        if let Some(current) = self.current_group {
            self.current_group = self.parent_group_id(current);
            self.refresh_filter();
        }
    }

    pub fn enter_selected_group(&mut self) -> bool {
        if let Some(gid) = self.selected_group_id() {
            self.current_group = Some(gid);
            self.refresh_filter();
            true
        } else {
            false
        }
    }

    pub fn refresh_fprint_status(&mut self) {
        self.fprint_available = crate::fprint::is_available();
        self.fprint_enrolled = self.fprint_available && crate::fprint::is_enrolled();
    }

    pub fn refresh_filter(&mut self) {
        self.filtered = self.compute_filtered();
        let total = self.total_display_rows();

        self.index_state.select(if total == 0 {
            None
        } else {
            Some(0)
        });
    }

    fn compute_filtered(&self) -> Vec<usize> {
        let query = self.query.to_lowercase();

        let mut indices: Vec<usize> = self
            .entries
            .iter()
            .enumerate()
            .filter(|(_, entry)| {
                let in_current_group = self.is_entry_in_current_group(entry);

                in_current_group
                    && (query.is_empty()
                        || entry.name.to_lowercase().contains(&query)
                        || entry.user.to_lowercase().contains(&query)
                        || entry.url.to_lowercase().contains(&query))
            })
            .map(|(i, _)| i)
            .collect();

        match self.config.sort_mode {
            SortMode::Smart => {
                indices.sort_by(|&a, &b| {
                    let sa = self.sort_score(&self.entries[a]);
                    let sb = self.sort_score(&self.entries[b]);
                    sb.cmp(&sa).then_with(|| self.entries[a].name.to_lowercase().cmp(&self.entries[b].name.to_lowercase()))
                });
            }
            SortMode::Recent => {
                indices.sort_by(|&a, &b| {
                    let da = parse_date_ago(&self.entries[a].date_last_modify);
                    let db = parse_date_ago(&self.entries[b].date_last_modify);
                    da.cmp(&db).then_with(|| self.entries[a].name.to_lowercase().cmp(&self.entries[b].name.to_lowercase()))
                });
            }
            SortMode::Reuse => {
                indices.sort_by(|&a, &b| {
                    let ea = &self.entries[a];
                    let eb = &self.entries[b];
                    eb.password_reuse_count
                        .cmp(&ea.password_reuse_count)
                        .then_with(|| eb.duplicate_user_count.cmp(&ea.duplicate_user_count))
                        .then_with(|| ea.name.to_lowercase().cmp(&eb.name.to_lowercase()))
                });
            }
            SortMode::Name => {
                indices.sort_by(|&a, &b| {
                    self.entries[a].name.to_lowercase().cmp(&self.entries[b].name.to_lowercase())
                });
            }
            SortMode::LastCopied => {
                indices.sort_by(|&a, &b| {
                    let ca = self.entries[a].last_copied;
                    let cb = self.entries[b].last_copied;
                    cb.cmp(&ca).then_with(|| self.entries[a].name.to_lowercase().cmp(&self.entries[b].name.to_lowercase()))
                });
            }
        }

        indices
    }

    fn sort_score(&self, entry: &Entry) -> u64 {
        let days_ago = parse_date_ago(&entry.date_last_modify);

        let recency = match days_ago {
            0 => 1000,
            1 => 500,
            d if d <= 7 => 100 + (7 - d) * 50,
            d if d <= 30 => (30 - d) * 3,
            _ => 0,
        };

        let reuse = entry.password_reuse_count.saturating_sub(1) as u64 * 200;
        let duplicate = entry.duplicate_user_count.saturating_sub(1) as u64 * 150;
        let totp = if has_totp(entry) { 100 } else { 0 };
        let url = if has_url(entry) { 50 } else { 0 };

        recency + reuse + duplicate + totp + url
    }

    fn is_entry_in_current_group(&self, entry: &Entry) -> bool {
        match self.config.group_display {
            GroupDisplay::Hidden => true,
            _ => match (self.current_group, entry.group_id) {
                (None, None) => true,
                (Some(current_gid), Some(entry_gid)) => entry_gid == current_gid,
                _ => false,
            },
        }
    }

    fn has_unsaved_edit_changes(&self) -> bool {
        let (Some(entry), Some(original)) = (&self.edit_entry, &self.edit_original) else {
            return false;
        };

        entry.name != original.name
            || entry.user != original.user
            || entry.password != original.password
            || entry.url != original.url
            || entry.totp != original.totp
            || entry.notes != original.notes
    }
}

fn attempt_unlock_fingerprint(app: &mut App) -> bool {
    crate::util::debug_log("fprint unlock: start");

    let Some(path) = app.config.default_database.clone() else {
        app.login_error = Some("No default_database set in jaiba_config.toml".to_string());
        crate::util::debug_log("fprint unlock: no default_database");
        return false;
    };

    let password = match fprint::read_stored_password(&app.config) {
        Ok(pw) if !pw.is_empty() => pw,
        Ok(_) => {
            app.login_error = Some(
                "No stored fingerprint password — disable/re-enable fingerprint in settings to recreate it"
                    .to_string(),
            );
            crate::util::debug_log("fprint unlock: stored password is empty");
            return false;
        }
        Err(err) => {
            app.login_error = Some(format!("Couldn't read stored fingerprint password: {err}"));
            crate::util::debug_log(&format!("fprint unlock: read stored password err: {err}"));
            return false;
        }
    };

    crate::util::debug_log(&format!(
        "fprint unlock: stored password len={}",
        password.len()
    ));

    match unlock_database(&path, &password, app.config.keyfile.as_deref()) {
        Ok((db, key, mut entries, groups)) => {
            calculate_warnings(&mut entries);
            app.entries = entries;
            app.groups = groups;
            app.current_group = None;
            app.kdbx = Some(db);
            app.db_key = Some(key);
            app.password.clear();
            app.login_error = None;
            app.last_activity = Instant::now();
            app.refresh_filter();
            app.screen = Screen::Index;
            app.status = Some("Unlocked via fingerprint".to_string());
            crate::util::debug_log("fprint unlock: success");
            true
        }
        Err(err) => {
            app.login_error = Some(format!("Fingerprint unlock failed: {err}"));
            crate::util::debug_log(&format!("fprint unlock: database unlock err: {err:#}"));
            false
        }
    }
}

fn start_fingerprint_listener(app: &mut App) {
    crate::util::debug_log("fprint listener: called");

    if app.fingerprint_verifying {
        crate::util::debug_log("fprint listener: already verifying");
        return;
    }

    if !(app.config.fingerprint_enabled && app.fprint_available && app.fprint_enrolled) {
        crate::util::debug_log("fprint listener: disabled/not available/not enrolled");
        return;
    }

    if crate::input::login::database_missing(app) {
        crate::util::debug_log("fprint listener: database missing");
        return;
    }

    fprint::stop_verify(app.fingerprint_running.as_ref());
    app.fingerprint_running = None;

    match fprint::start_verify() {
        Ok((rx, running)) => {
            app.fingerprint_verifying = true;
            app.fingerprint_verify_rx = Some(rx);
            app.fingerprint_running = Some(running);
            app.login_error = None;
            app.status = Some("Scanning fingerprint...".to_string());
            crate::util::debug_log("fprint listener: started");
        }
        Err(err) => {
            app.login_error = Some(format!("Fingerprint error: {err}"));
            crate::util::debug_log(&format!("fprint listener: start err: {err}"));
        }
    }
}

impl App {
    pub fn palette_items(&self) -> Vec<(String, PaletteAction)> {
        let mut items: Vec<(String, PaletteAction)> = Vec::new();

        if self.selected_entry().is_some() {
            items.push((
                "Entry: copy username".to_string(),
                PaletteAction::CopyUser,
            ));
            items.push((
                "Entry: copy password".to_string(),
                PaletteAction::CopyPassword,
            ));
            items.push((
                "Entry: copy TOTP".to_string(),
                PaletteAction::CopyTotp,
            ));
            items.push((
                "Entry: copy URL".to_string(),
                PaletteAction::CopyUrl,
            ));
            items.push((
                "Entry: open URL".to_string(),
                PaletteAction::OpenUrl,
            ));
            items.push((
                "Entry: edit".to_string(),
                PaletteAction::EditEntry,
            ));
        }

        items.push(("New entry".to_string(), PaletteAction::NewEntry));
        items.push(("Generate password".to_string(), PaletteAction::GeneratePassword));
        items.push(("Settings".to_string(), PaletteAction::Settings));
        items.push(("Lock vault".to_string(), PaletteAction::Lock));
        items.push(("Quit".to_string(), PaletteAction::Quit));

        for mode in [
            SortMode::Smart,
            SortMode::Name,
            SortMode::Recent,
            SortMode::Reuse,
            SortMode::LastCopied,
        ] {
            let active = self.config.sort_mode == mode;
            let label = format!(
                "Sort: {}{}",
                mode.as_str(),
                if active { " ✓" } else { "" }
            );

            items.push((label, PaletteAction::SetSort(mode)));
        }

        let query = self.palette_query.trim().to_lowercase();

        if query.is_empty() {
            items
        } else {
            items
                .into_iter()
                .filter(|(label, _)| label.to_lowercase().contains(&query))
                .collect()
        }
    }

    pub fn manual_lock(&mut self) {
        if let Some(timer) = self.clipboard_timer.take() {
            if let Some(clipboard) = self.clipboard.as_mut() {
                if let Ok(current) = clipboard.get_text() {
                    if current == timer.expected {
                        let _ = clipboard.clear();
                    }
                }
            }
        }

        if self.fingerprint_verifying {
            crate::fprint::stop_verify(self.fingerprint_running.as_ref());
            self.fingerprint_verifying = false;
            self.fingerprint_verify_rx = None;
            self.fingerprint_running = None;
        }

        self.entries.clear();
        self.filtered.clear();
        self.groups.clear();
        self.current_group = None;
        self.password.clear();
        self.query.clear();
        self.kdbx = None;
        self.db_key = None;
        self.edit_entry = None;
        self.edit_original = None;
        self.edit_target = None;
        self.editing_field = false;
        self.field_buffer.clear();
        self.confirm_delete = false;
        self.confirm_exit = false;
        self.reveal_password = false;
        self.available_themes.clear();
        self.settings_state.select(None);
        self.choosing_theme = false;
        self.theme_state.select(None);
        self.creating_database = false;
        self.confirming_new_db_password = false;
        self.new_db_confirm.clear();
        self.changing_password = false;
        self.password_change_step = PasswordChangeStep::CurrentPassword;
        self.current_password_buffer.clear();
        self.new_password_buffer.clear();
        self.new_password_confirm.clear();
        self.importing_database = false;
        self.import_step = ImportStep::Path;
        self.import_path_buffer.clear();
        self.import_kdbx_password_buffer.clear();
        self.pending_import_path = None;
        self.exporting_database = false;
        self.export_step = ExportStep::Path;
        self.export_path_buffer.clear();
        self.pending_export_path = None;
        self.palette_open = false;
        self.palette_query.clear();
        self.palette_state.select(None);
        self.detail_open = false;
        self.generator_into_edit_password = false;
        self.generator_result.clear();
        self.generator_return = Screen::Index;
        self.entering_fprint_password = false;
        self.fprint_password_buffer.clear();
        self.max_len = 0;
        self.status = None;
        self.screen = Screen::Login;
        self.login_error = Some("Locked".to_string());
    }
}

fn maybe_auto_lock(app: &mut App) {
    if app.config.auto_lock.is_zero() {
        return;
    }

    if !matches!(
        app.screen,
        Screen::Index | Screen::Edit | Screen::Settings | Screen::Generator
    ) {
        return;
    }

    if app.last_activity.elapsed() < app.config.auto_lock {
        return;
    }

    if app.screen == Screen::Edit
        && (app.editing_field || app.confirm_exit || app.confirm_delete || app.has_unsaved_edit_changes())
    {
        crate::util::debug_log("maybe_auto_lock: skipped because edit state is active");
        return;
    }

    if app.screen == Screen::Settings
        && (app.editing_field
            || app.changing_password
            || app.importing_database
            || app.exporting_database
            || app.choosing_theme)
    {
        crate::util::debug_log("maybe_auto_lock: skipped because settings flow is active");
        return;
    }

    if let Some(timer) = app.clipboard_timer.take() {
        if let Some(clipboard) = app.clipboard.as_mut() {
            if let Ok(current) = clipboard.get_text() {
                if current == timer.expected {
                    let _ = clipboard.clear();
                }
            }
        }
    }

    app.entries.clear();
    app.filtered.clear();
    app.groups.clear();
    app.current_group = None;
    app.password.clear();
    app.query.clear();
    app.kdbx = None;
    app.db_key = None;
    app.edit_entry = None;
    app.edit_original = None;
    app.edit_target = None;
    app.editing_field = false;
    app.field_buffer.clear();
    app.confirm_delete = false;
    app.confirm_exit = false;
    app.reveal_password = false;
    app.available_themes.clear();
    app.settings_state.select(None);
    app.choosing_theme = false;
    app.theme_state.select(None);
    app.creating_database = false;
    app.confirming_new_db_password = false;
    app.new_db_confirm.clear();
    app.changing_password = false;
    app.password_change_step = PasswordChangeStep::CurrentPassword;
    app.current_password_buffer.clear();
    app.new_password_buffer.clear();
    app.new_password_confirm.clear();
    app.entering_fprint_password = false;
    app.fprint_password_buffer.clear();
    app.importing_database = false;
    app.import_step = ImportStep::Path;
    app.import_path_buffer.clear();
    app.import_kdbx_password_buffer.clear();
    app.pending_import_path = None;
    app.exporting_database = false;
    app.export_step = ExportStep::Path;
    app.export_path_buffer.clear();
    app.pending_export_path = None;
    app.max_len = 0;
    app.status = None;
    app.generator_into_edit_password = false;
    app.generator_result.clear();
    app.generator_return = Screen::Index;
    app.palette_open = false;
    app.palette_query.clear();
    app.palette_state.select(None);
    app.detail_open = false;
    app.screen = Screen::Login;
    app.login_error = Some("Locked after inactivity".to_string());
}

pub fn run(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    slim_mode: bool,
) -> io::Result<()> {
    let _ = crate::theme::ensure_default_themes();

    let mut config = load_config().unwrap_or_default();

    if config.default_database.is_none() {
        let default_path = crate::util::default_new_database_path();
        if default_path.is_file() {
            config.default_database = Some(default_path);
            let _ = crate::config::save_config(&config);
        }
    }

    let theme = load_theme(config.theme.as_deref()).unwrap_or_default();

    let fprint_available = fprint::is_available();
    let fprint_enrolled = fprint_available && fprint::is_enrolled();

    let mut app = App {
        screen: Screen::Login,
        password: String::new(),
        query: String::new(),
        max_len: 0,
        theme,
        config,
        available_themes: Vec::new(),
        settings_state: ListState::default(),
        choosing_theme: false,
        theme_state: ListState::default(),
        changing_password: false,
        password_change_step: PasswordChangeStep::CurrentPassword,
        current_password_buffer: String::new(),
        new_password_buffer: String::new(),
        new_password_confirm: String::new(),
        importing_database: false,
        import_step: ImportStep::Path,
        import_path_buffer: String::new(),
        import_kdbx_password_buffer: String::new(),
        pending_import_path: None,
        exporting_database: false,
        export_step: ExportStep::Path,
        export_path_buffer: String::new(),
        pending_export_path: None,
        login_error: None,
        last_activity: Instant::now(),
        index_state: TableState::default().with_selected(Some(0)),
        edit_state: ListState::default(),
        reveal_password: false,
        edit_entry: None,
        edit_original: None,
        edit_target: None,
        editing_field: false,
        field_buffer: String::new(),
        confirm_delete: false,
        confirm_exit: false,
        entries: Vec::new(),
        filtered: Vec::new(),
        kdbx: None,
        db_key: None,
        creating_database: false,
        confirming_new_db_password: false,
        new_db_confirm: String::new(),
        status: None,
        clipboard: Clipboard::new().ok(),
        clipboard_timer: None,
        should_quit: false,
        slim_mode,
        fingerprint_verifying: false,
        fingerprint_verify_rx: None,
        fingerprint_running: None,
        prev_screen: Screen::Login,
        groups: Vec::new(),
        current_group: None,
        fprint_available,
        fprint_enrolled,
        entering_fprint_password: false,
        fprint_password_buffer: String::new(),
        palette_open: false,
        palette_query: String::new(),
        palette_state: ListState::default(),
        detail_open: false,
        generator_return: Screen::Index,
        generator_into_edit_password: false,
        generator_mode: crate::generator::GeneratorMode::Random,
        generator_length: 24,
        generator_words: 6,
        generator_use_upper: true,
        generator_use_digits: true,
        generator_use_symbols: true,
        generator_exclude_ambiguous: true,
        generator_result: String::new(),
    };

    const TICK_RATE: Duration = Duration::from_millis(200);

    // Auto-start fingerprint listener on initial login screen
    if app.config.fingerprint_enabled
        && app.fprint_available
        && app.fprint_enrolled
        && !crate::input::login::database_missing(&app)
    {
        start_fingerprint_listener(&mut app);
    }

    loop {
        // Auto-start fingerprint listener when transitioning to Login screen
        if app.screen == Screen::Login && app.prev_screen != Screen::Login {
            if app.config.fingerprint_enabled
                && app.fprint_available
                && app.fprint_enrolled
                && !app.fingerprint_verifying
                && !crate::input::login::database_missing(&app)
            {
                start_fingerprint_listener(&mut app);
            }
        }
        // Stop fingerprint listener when leaving Login screen
        if app.prev_screen == Screen::Login && app.screen != Screen::Login {
            if app.fingerprint_verifying {
                fprint::stop_verify(app.fingerprint_running.as_ref());
                app.fingerprint_verifying = false;
                app.fingerprint_verify_rx = None;
                app.fingerprint_running = None;
            }
        }
        app.prev_screen = app.screen;

        terminal.draw(|frame| {
            frame.render_widget(
                Block::default().style(Style::default().bg(app.theme.background)),
                frame.area(),
            );

            match app.screen {
                Screen::Login => draw_login(frame, &mut app),
                Screen::Index => draw_index(frame, &mut app),
                Screen::Edit => draw_edit(frame, &mut app),
                Screen::Settings => draw_settings(frame, &mut app),
                Screen::Generator => crate::ui::generator::draw_generator(frame, &mut app),
            }
        })?;

        if event::poll(TICK_RATE)? {
            if let Event::Key(key) = event::read()? {
                app.last_activity = Instant::now();

                match app.screen {
                Screen::Login => handle_login_input(&mut app, key),
                Screen::Index => handle_index_input(&mut app, key),
                Screen::Edit => handle_edit_input(&mut app, key.code),
                Screen::Settings => handle_settings_input(&mut app, key.code),
                Screen::Generator => crate::input::generator::handle_generator_input(&mut app, key.code),
                }
            }
        }

        // Check for fingerprint verification result
        if app.fingerprint_verifying {
            if let Some(rx) = &app.fingerprint_verify_rx {
                if let Ok(verified) = rx.try_recv() {
                    crate::util::debug_log(&format!("fprint result: verified={verified}"));

                    app.fingerprint_verifying = false;
                    app.fingerprint_verify_rx = None;

                    fprint::stop_verify(app.fingerprint_running.as_ref());
                    app.fingerprint_running = None;

                    if verified {
                        let unlocked = attempt_unlock_fingerprint(&mut app);

                        // Do not instantly restart the listener after a failed unlock.
                        // We want the error to stay visible.
                        if !unlocked {
                            crate::util::debug_log("fprint result: unlock failed; not restarting listener");
                        }
                    } else {
                        app.login_error = Some("Fingerprint not recognized".to_string());
                        crate::util::debug_log("fprint result: not recognized; not restarting listener");
                    }
                }
            }
        }

        maybe_clear_clipboard(&mut app);
        maybe_auto_lock(&mut app);

        if app.should_quit {
            break;
        }
    }

    Ok(())
}
