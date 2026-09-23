use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::Context;
use chrono::Utc;
use keepass::db::{EntryId, EntryMut, EntryRef, Times, fields};
use keepass::{Database, DatabaseKey};

fn resolve_totp(e: &EntryRef) -> String {
    if let Some(otp) = e.get_raw_otp_value() {
        if !otp.trim().is_empty() {
            return otp.to_string();
        }
    }

    let Some(seed) = e.get("TOTP Seed") else {
        return String::new();
    };
    let seed = seed.trim();
    if seed.is_empty() {
        return String::new();
    }

    let (period, digits) = e
        .get("TOTP Settings")
        .and_then(|settings| settings.split_once(';'))
        .and_then(|(p, d)| Some((p.trim().parse::<u32>().ok()?, d.trim().parse::<u32>().ok()?)))
        .unwrap_or((30, 6));

    let label = e.get_title().unwrap_or("");
    let user = e.get_username().unwrap_or("");
    let encoded_label = urlencoding_encode(&format!("{label}:{user}"));
    let encoded_issuer = urlencoding_encode(label);

    format!(
        "otpauth://totp/{encoded_label}?secret={seed}&period={period}&digits={digits}&issuer={encoded_issuer}"
    )
}

pub struct TotpCode {
    pub code: String,
    pub valid_for: std::time::Duration,
}

pub fn current_totp_code(raw: &str) -> Option<TotpCode> {
    if raw.trim().is_empty() {
        return None;
    }

    let totp: keepass::db::TOTP = raw.parse().ok()?;
    let otp_code = totp.value_now().ok()?;

    Some(TotpCode {
        code: otp_code.code,
        valid_for: otp_code.valid_for,
    })
}

fn urlencoding_encode(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for b in input.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

#[derive(Clone, Default)]
pub struct Entry {
    pub id: Option<EntryId>,
    pub name: String,
    pub user: String,
    pub password: String,
    pub url: String,
    pub totp: String,
    pub notes: String,
    pub date_last_modify: String,
    pub password_reuse_count: u32,
    pub duplicate_user_count: u32,
    pub group_id: Option<keepass::db::GroupId>,
    pub custom_fields: Vec<(String, String)>,
    pub last_copied: i64,
}

fn is_internal_field(key: &str) -> bool {
    if key.starts_with('_') {
        return true;
    }

    let lower = key.to_ascii_lowercase();

    matches!(
        lower.as_str(),
        "title"
            | "username"
            | "password"
            | "url"
            | "notes"
            | "otp"
            | "totp seed"
            | "totp settings"
            | "last copied"
    )
}

fn visible_custom_fields(e: &EntryRef<'_>) -> Vec<(String, String)> {
    let mut custom: Vec<(String, String)> = e
        .fields
        .iter()
        .map(|(key, _)| key.clone())
        .filter(|key| !is_internal_field(key))
        .map(|key| {
            let value = e.get(&key).unwrap_or_default().to_string();
            (key, value)
        })
        .collect();

    custom.sort_by(|a, b| a.0.to_lowercase().cmp(&b.0.to_lowercase()));
    custom
}

#[derive(Clone, Debug)]
pub struct Group {
    pub id: keepass::db::GroupId,
    pub name: String,
    pub parent_id: Option<keepass::db::GroupId>,
    pub children: Vec<Group>,
    #[allow(dead_code)]
    pub entry_ids: Vec<EntryId>,
}

fn parse_last_copied(e: &EntryRef<'_>) -> i64 {
    if let Some(val) = e.get("Last Copied") {
        val.trim().parse::<i64>().unwrap_or(0)
    } else {
        0
    }
}

fn format_days_ago(dt: chrono::NaiveDateTime) -> String {
    let days = (Utc::now().naive_utc() - dt).num_days();

    match days {
        d if d <= 0 => "today".to_string(),
        1 => "1 day ago".to_string(),
        d => format!("{d} days ago"),
    }
}

fn load_groups(db: &Database) -> Vec<Group> {
    let root = db.root();
    let root_id = root.id();

    fn build_group_tree(
        db: &Database,
        root_id: keepass::db::GroupId,
        group_ref: &keepass::db::GroupRef<'_>,
    ) -> Group {
        let parent_id = group_ref
            .parent()
            .map(|p| p.id())
            .filter(|pid| *pid != root_id);

        let mut group = Group {
            id: group_ref.id(),
            name: group_ref.name.clone(),
            parent_id,
            children: Vec::new(),
            entry_ids: group_ref.entry_ids().collect(),
        };

        for child_group_ref in group_ref.groups() {
            group.children.push(build_group_tree(db, root_id, &child_group_ref));
        }

        group
    }

    let mut groups = Vec::new();
    for child_group_ref in root.groups() {
        groups.push(build_group_tree(db, root_id, &child_group_ref));
    }

    groups
}

pub fn unlock_database(
    path: &Path,
    password: &str,
    keyfile_path: Option<&Path>,
) -> anyhow::Result<(Database, DatabaseKey, Vec<Entry>, Vec<Group>)> {
    let mut file =
        fs::File::open(path).with_context(|| format!("couldn't open {}", path.display()))?;

    let key = build_database_key(password, keyfile_path)?;
    let db = Database::open(&mut file, key.clone()).map_err(|err| match keyfile_path {
        Some(_) => anyhow::anyhow!("unlock failed with password + keyfile: {err}"),
        None => anyhow::anyhow!("unlock failed with password: {err}"),
    })?;

    let groups = load_groups(&db);

    let entries = db
        .iter_all_entries()
        .map(|e| {
            let date_last_modify = e
                .times
                .last_modification
                .map(format_days_ago)
                .unwrap_or_default();

            // Use keepass's own parent tracking instead of manual mapping
            let parent_gid = e.parent().id();
            let group_id = if parent_gid == db.root().id() {
                None
            } else {
                Some(parent_gid)
            };

            Entry {
                id: Some(e.id()),
                name: e.get_title().unwrap_or("(no title)").to_string(),
                user: e.get_username().unwrap_or_default().to_string(),
                password: e.get_password().unwrap_or_default().to_string(),
                url: e.get_url().unwrap_or_default().to_string(),
                totp: resolve_totp(&e),
                notes: e.get(fields::NOTES).unwrap_or_default().to_string(),
                date_last_modify,
                password_reuse_count: 0,
                duplicate_user_count: 0,
                group_id,
                custom_fields: visible_custom_fields(&e),
                last_copied: parse_last_copied(&e),
            }
        })
        .collect();

    Ok((db, key, entries, groups))
}

pub fn create_database(
    path: &Path,
    password: &str,
    keyfile_path: Option<&Path>,
) -> anyhow::Result<(Database, DatabaseKey, Vec<Entry>, Vec<Group>)> {
    if path.exists() {
        anyhow::bail!("a file already exists at {}", path.display());
    }

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("couldn't create {}", parent.display()))?;
    }

    let db = Database::new();
    let key = build_database_key(password, keyfile_path)?;

    write_to_disk(path, &key, &db)?;

    Ok((db, key, Vec::new(), Vec::new()))
}

pub fn build_database_key(
    password: &str,
    keyfile_path: Option<&Path>,
) -> anyhow::Result<DatabaseKey> {
    let mut key = DatabaseKey::new().with_password(password);

    if let Some(path) = keyfile_path {
        let mut keyfile = fs::File::open(path)
            .with_context(|| format!("couldn't open keyfile {}", path.display()))?;

        if keyfile
            .metadata()
            .with_context(|| format!("couldn't inspect keyfile {}", path.display()))?
            .len()
            == 0
        {
            anyhow::bail!("keyfile {} is empty", path.display());
        }

        key = key
            .with_keyfile(&mut keyfile)
            .with_context(|| format!("couldn't read keyfile {}", path.display()))?;
    }

    Ok(key)
}

pub fn save_database(
    path: &Path,
    key: &DatabaseKey,
    db: &mut Database,
    entries: &mut [Entry],
) -> anyhow::Result<()> {
    for entry in entries.iter_mut() {
        write_entry(db, entry)?;
    }

    write_to_disk(path, key, db)
}

fn write_to_disk(path: &Path, key: &DatabaseKey, db: &Database) -> anyhow::Result<()> {
    let tmp_path = sibling_tmp_path(path);

    crate::util::debug_log(&format!(
        "write_to_disk: path={} tmp={}",
        path.display(),
        tmp_path.display()
    ));

    let save_result = {
        let mut file = fs::File::create(&tmp_path)
            .with_context(|| format!("couldn't create {}", tmp_path.display()))?;

        let mut db_clone = db.clone();

        // The keepass 0.14.0 crate's writer rejects KDBX 3.x and KDBX 4.0.
        // It only reliably writes KDBX 4.1. We force the version to 4.1
        // in memory before saving. KeePassDX fully supports 4.1.
        db_clone.config.version = keepass::config::DatabaseVersion::KDB4(1);

        db_clone.save(&mut file, key.clone())
            .map_err(|err| anyhow::anyhow!("failed to write database: {err}"))
    };

    if let Err(err) = save_result {
        crate::util::debug_log(&format!("write_to_disk: save ERR {err:#}"));
        let _ = fs::remove_file(&tmp_path);
        return Err(err);
    }

    fs::rename(&tmp_path, path)
        .with_context(|| format!("couldn't replace {}", path.display()))?;

    crate::util::debug_log("write_to_disk: rename OK");

    Ok(())
}
fn write_entry(db: &mut Database, entry: &mut Entry) -> anyhow::Result<()> {
    match entry.id {
        Some(id) => {
            let mut e = db
                .entry_mut(id)
                .context("entry no longer exists in the database")?;

            apply_fields(&mut e, entry);
        }
        None => match entry.group_id {
            Some(gid) => {
                let mut group = db
                    .group_mut(gid)
                    .context("target group no longer exists in the database")?;

                let mut e = group.add_entry();
                apply_fields(&mut e, entry);
                entry.id = Some(e.id());
            }
            None => {
                let mut root = db.root_mut();
                let mut e = root.add_entry();
                apply_fields(&mut e, entry);
                entry.id = Some(e.id());
            }
        },
    }

    Ok(())
}

pub fn delete_entry(
    path: &Path,
    key: &DatabaseKey,
    db: &mut Database,
    id: EntryId,
) -> anyhow::Result<()> {
    db.entry_mut(id)
        .context("entry no longer exists in the database")?
        .remove();

    write_to_disk(path, key, db)
}

pub fn persist_last_copied(
    path: &Path,
    key: &DatabaseKey,
    db: &mut Database,
    id: EntryId,
    value: i64,
) -> anyhow::Result<()> {
    let mut e = db
        .entry_mut(id)
        .context("entry no longer exists in the database")?;

    e.set_unprotected("Last Copied", value.to_string());

    write_to_disk(path, key, db)
}

fn apply_fields(e: &mut EntryMut<'_>, entry: &Entry) {
    e.set_unprotected(fields::TITLE, entry.name.clone());
    e.set_unprotected(fields::USERNAME, entry.user.clone());
    e.set_unprotected(fields::PASSWORD, entry.password.clone());
    e.set_unprotected(fields::URL, entry.url.clone());
    e.set_unprotected(fields::OTP, entry.totp.clone());
    e.set_unprotected(fields::NOTES, entry.notes.clone());

    // Normalize legacy TOTP fields.
    // If the app now stores TOTP in OTP, don't let old seed/settings override it.
    e.set_unprotected("TOTP Seed", String::new());
    e.set_unprotected("TOTP Settings", String::new());

    // Persist last_copied only when it exists.
    if entry.last_copied > 0 {
        e.set_unprotected("Last Copied", entry.last_copied.to_string());
    }

    // Persist visible custom fields.
    for (key, value) in &entry.custom_fields {
        if !is_internal_field(key) {
            e.set_unprotected(key, value.clone());
        }
    }

    e.times.last_modification = Some(Times::now());
}

fn sibling_tmp_path(path: &Path) -> PathBuf {
    let file_name = path
        .file_name()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| "database".to_string());

    let pid = std::process::id();

    let counter = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);

    path.with_file_name(format!("{file_name}.{pid}.{counter}.tmp"))
}

pub fn parse_date_ago(date_str: &str) -> u64 {
    match date_str {
        "today" => 0,
        "1 day ago" => 1,
        s => s
            .strip_suffix(" days ago")
            .and_then(|n| n.parse::<u64>().ok())
            .unwrap_or(u64::MAX),
    }
}

pub fn has_totp(entry: &Entry) -> bool {
    !entry.totp.trim().is_empty()
}

pub fn has_url(entry: &Entry) -> bool {
    !entry.url.trim().is_empty()
}

pub fn calculate_warnings(entries: &mut Vec<Entry>) {
    let mut password_counts: HashMap<String, u32> = HashMap::new();
    let mut user_counts: HashMap<String, u32> = HashMap::new();

    for entry in entries.iter() {
        if !entry.password.trim().is_empty() {
            *password_counts.entry(entry.password.clone()).or_insert(0) += 1;
        }

        if !entry.user.trim().is_empty() {
            *user_counts.entry(entry.user.clone()).or_insert(0) += 1;
        }
    }

    for entry in entries.iter_mut() {
        entry.password_reuse_count = if entry.password.trim().is_empty() {
            0
        } else {
            password_counts.get(&entry.password).copied().unwrap_or(0)
        };

        entry.duplicate_user_count = if entry.user.trim().is_empty() {
            0
        } else {
            user_counts.get(&entry.user).copied().unwrap_or(0)
        };
    }
}

#[cfg(test)]
mod tests {
    use super::{build_database_key, create_database, parse_date_ago, save_database, unlock_database};
    use keepass::db::fields;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_TEST_DIR: AtomicU64 = AtomicU64::new(0);

    const XML_V1_KEYFILE: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<KeyFile>
    <Meta>
        <Version>1.00</Version>
    </Meta>
    <Key>
        <Data>NXyYiJMHg3ls+eBmjbAjWec9lcOToJiofbhNiFMTJMw=</Data>
    </Key>
</KeyFile>"#;

    struct TestDir(PathBuf);

    impl TestDir {
        fn new() -> Self {
            let id = NEXT_TEST_DIR.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!("jaiba-test-{}-{id}", std::process::id()));
            fs::create_dir_all(&path).expect("test directory should be created");
            Self(path)
        }

        fn join(&self, path: impl AsRef<Path>) -> PathBuf {
            self.0.join(path)
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn password_only_databases_still_unlock() {
        let dir = TestDir::new();
        let database_path = dir.join("password-only.kdbx");

        create_database(&database_path, "correct horse", None)
            .expect("password-only database should be created");
        unlock_database(&database_path, "correct horse", None)
            .expect("password-only database should unlock");
    }

    #[test]
    fn unlock_database_reads_entry_notes() {
        let dir = TestDir::new();
        let database_path = dir.join("notes.kdbx");
        let (mut database, key, mut entries, _) =
            create_database(&database_path, "correct horse", None)
                .expect("database should be created");

        {
            let mut root = database.root_mut();
            let mut entry = root.add_entry();
            entry.set_unprotected(fields::TITLE, "Entry with notes");
            entry.set_unprotected(fields::NOTES, "first line\nsecond line");
        }

        save_database(&database_path, &key, &mut database, &mut entries)
            .expect("database should be saved");

        let (_, _, entries, _) =
            unlock_database(&database_path, "correct horse", None).expect("database should unlock");
        let entry = entries
            .iter()
            .find(|entry| entry.name == "Entry with notes")
            .expect("entry should be loaded");

        assert_eq!(entry.notes, "first line\nsecond line");
    }

    #[test]
    fn unlock_database_defaults_missing_notes_to_empty() {
        let dir = TestDir::new();
        let database_path = dir.join("no-notes.kdbx");
        let (mut database, key, mut entries, _) =
            create_database(&database_path, "correct horse", None)
                .expect("database should be created");

        {
            let mut root = database.root_mut();
            let mut entry = root.add_entry();
            entry.set_unprotected(fields::TITLE, "Entry without notes");
        }

        save_database(&database_path, &key, &mut database, &mut entries)
            .expect("database should be saved");

        let (_, _, entries, _) =
            unlock_database(&database_path, "correct horse", None).expect("database should unlock");
        let entry = entries
            .iter()
            .find(|entry| entry.name == "Entry without notes")
            .expect("entry should be loaded");

        assert!(entry.notes.is_empty());
    }

    #[test]
    fn password_and_keyfile_databases_require_both_factors() {
        let dir = TestDir::new();
        let database_path = dir.join("composite.kdbx");
        let keyfile_path = dir.join("database.keyx");
        fs::write(&keyfile_path, XML_V1_KEYFILE).expect("XML v1 keyfile should be written");

        create_database(&database_path, "correct horse", Some(&keyfile_path))
            .expect("composite-key database should be created");
        unlock_database(&database_path, "correct horse", Some(&keyfile_path))
            .expect("database should unlock with password and keyfile");

        assert!(unlock_database(&database_path, "correct horse", None).is_err());
        assert!(unlock_database(&database_path, "wrong password", Some(&keyfile_path)).is_err());
    }

    #[test]
    fn password_change_keeps_keyfile_requirement() {
        let dir = TestDir::new();
        let database_path = dir.join("composite.kdbx");
        let keyfile_path = dir.join("database.keyx");
        fs::write(&keyfile_path, [42_u8; 32]).expect("keyfile should be written");

        let (mut database, _, mut entries, _) =
            create_database(&database_path, "old password", Some(&keyfile_path))
                .expect("composite-key database should be created");
        let new_key = build_database_key("new password", Some(&keyfile_path))
            .expect("new composite key should be built");

        save_database(&database_path, &new_key, &mut database, &mut entries)
            .expect("database should be re-encrypted");

        unlock_database(&database_path, "new password", Some(&keyfile_path))
            .expect("new password and keyfile should unlock");
        assert!(unlock_database(&database_path, "new password", None).is_err());
        assert!(unlock_database(&database_path, "old password", Some(&keyfile_path)).is_err());
    }

    #[test]
    fn missing_and_empty_keyfiles_have_clear_errors() {
        let dir = TestDir::new();
        let database_path = dir.join("placeholder.kdbx");
        let missing_keyfile = dir.join("missing.keyx");
        let empty_keyfile = dir.join("empty.keyx");
        fs::write(&database_path, []).expect("placeholder database should be written");
        fs::write(&empty_keyfile, []).expect("empty keyfile should be written");

        let missing_error = unlock_database(&database_path, "secret", Some(&missing_keyfile))
            .err()
            .expect("missing keyfile should fail")
            .to_string();
        assert!(missing_error.contains("couldn't open keyfile"));
        assert!(missing_error.contains(&missing_keyfile.display().to_string()));

        let empty_error = unlock_database(&database_path, "secret", Some(&empty_keyfile))
            .err()
            .expect("empty keyfile should fail")
            .to_string();
        assert!(empty_error.contains("keyfile"));
        assert!(empty_error.contains("is empty"));
    }

    #[test]
    fn wrong_keyfile_error_preserves_the_root_cause() {
        let dir = TestDir::new();
        let database_path = dir.join("composite.kdbx");
        let correct_keyfile = dir.join("correct.keyx");
        let wrong_keyfile = dir.join("wrong.keyx");
        fs::write(&correct_keyfile, [7_u8; 32]).expect("correct keyfile should be written");
        fs::write(&wrong_keyfile, [9_u8; 32]).expect("wrong keyfile should be written");

        create_database(&database_path, "secret", Some(&correct_keyfile))
            .expect("composite-key database should be created");

        let error = unlock_database(&database_path, "secret", Some(&wrong_keyfile))
            .err()
            .expect("wrong keyfile should fail")
            .to_string();
        assert!(error.contains("password + keyfile"));
        assert!(error.contains("Incorrect key"));
    }

#[test]
    fn parse_date_ago_handles_common_values() {
        assert_eq!(parse_date_ago("today"), 0);
        assert_eq!(parse_date_ago("1 day ago"), 1);
        assert_eq!(parse_date_ago("12 days ago"), 12);
        assert_eq!(parse_date_ago("garbage"), u64::MAX);
    }

    #[test]
    fn internal_fields_are_not_treated_as_custom() {
        assert!(super::is_internal_field("Title"));
        assert!(super::is_internal_field("UserName"));
        assert!(super::is_internal_field("Password"));
        assert!(super::is_internal_field("URL"));
        assert!(super::is_internal_field("Notes"));
        assert!(super::is_internal_field("OTP"));
        assert!(super::is_internal_field("TOTP Seed"));
        assert!(super::is_internal_field("TOTP Settings"));
        assert!(super::is_internal_field("Last Copied"));
        assert!(super::is_internal_field("_internal"));

        assert!(!super::is_internal_field("custom"));
        assert!(!super::is_internal_field("Recovery Codes"));
    }

    #[test]
    fn entry_created_inside_a_group_stays_in_that_group_after_reload() {
        let dir = TestDir::new();
        let database_path = dir.join("groups.kdbx");

        let (mut database, key, mut entries, _) =
            create_database(&database_path, "master", None)
                .expect("database should be created");

        // Create a subgroup under root.
        let mut root = database.root_mut();
        let mut group = root.add_group();
        group.name = "Work".to_string();
        let group_id = group.id();

        // Create an entry inside that group.
        {
            let mut entry = group.add_entry();
            entry.set_unprotected(fields::TITLE, "Work login");
            entry.set_unprotected(fields::USERNAME, "alice");
            entry.set_protected(fields::PASSWORD, "secret");
        }

        save_database(&database_path, &key, &mut database, &mut entries)
            .expect("database should save");

        // Reload and verify the entry is still parented to the subgroup.
        let (_, _, entries, groups) =
            unlock_database(&database_path, "master", None).expect("database should unlock");

        let work_entry = entries
            .iter()
            .find(|e| e.name == "Work login")
            .expect("entry should still exist");

        assert_eq!(work_entry.group_id, Some(group_id));

        let work_group = groups
            .iter()
            .find(|g| g.id == group_id)
            .expect("Work group should still exist");
        assert_eq!(work_group.name, "Work");
        assert_eq!(work_group.parent_id, None);
    }
}
