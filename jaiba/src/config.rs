use std::fs;
use std::path::PathBuf;
use std::time::Duration;

use anyhow::Context;
use serde::{Deserialize, Serialize};

use crate::util::expand_tilde;

const SAMPLE_CONFIG: &str = include_str!("../jaiba_config.toml.sample");

#[derive(Clone, PartialEq, Eq, Debug)]
pub enum SortMode {
    Smart,
    Name,
    Recent,
    Reuse,
    LastCopied,
}

impl Default for SortMode {
    fn default() -> Self {
        SortMode::Smart
    }
}

impl SortMode {
    pub fn as_str(&self) -> &'static str {
        match self {
            SortMode::Smart => "smart",
            SortMode::Name => "name",
            SortMode::Recent => "recent",
            SortMode::Reuse => "reuse",
            SortMode::LastCopied => "lastcopied",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "smart" => Some(SortMode::Smart),
            "name" => Some(SortMode::Name),
            "recent" => Some(SortMode::Recent),
            "reuse" => Some(SortMode::Reuse),
            "lastcopied" => Some(SortMode::LastCopied),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub enum LogoStyle {
    #[default]
    Crab,
}

impl LogoStyle {
    pub fn as_str(&self) -> &'static str {
        "crab"
    }

    pub fn from_str(s: &str) -> Option<Self> {
        if s == "crab" {
            Some(LogoStyle::Crab)
        } else {
            None
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum GroupDisplay {
    Shown,
    Hidden,
    Bottom,
    Mixed,
}

impl Default for GroupDisplay {
    fn default() -> Self {
        GroupDisplay::Shown
    }
}

impl GroupDisplay {
    pub fn as_str(&self) -> &'static str {
        match self {
            GroupDisplay::Shown => "shown",
            GroupDisplay::Hidden => "hidden",
            GroupDisplay::Bottom => "bottom",
            GroupDisplay::Mixed => "mixed",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "shown" => Some(GroupDisplay::Shown),
            "hidden" => Some(GroupDisplay::Hidden),
            "bottom" => Some(GroupDisplay::Bottom),
            "mixed" => Some(GroupDisplay::Mixed),
            _ => None,
        }
    }
}

pub struct Config {
    pub default_database: Option<PathBuf>,
    pub keyfile: Option<PathBuf>,
    pub auto_lock: Duration,
    pub clipboard_timeout: Duration,
    pub theme: Option<String>,
    pub sort_mode: SortMode,
    pub fingerprint_enabled: bool,
    pub fingerprint_device: Option<String>,
    pub group_display: GroupDisplay,
    pub logo_style: LogoStyle,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            default_database: None,
            keyfile: None,
            auto_lock: Duration::from_secs(300),
            clipboard_timeout: Duration::from_secs(15),
            theme: None,
            sort_mode: SortMode::default(),
            fingerprint_enabled: false,
            fingerprint_device: None,
            group_display: GroupDisplay::default(),
            logo_style: LogoStyle::default(),
        }
    }
}

#[derive(Deserialize, Default)]
struct ConfigFile {
    default_database: Option<String>,
    keyfile: Option<String>,
    auto_lock: Option<u64>,
    clipboard_timeout: Option<u64>,
    theme: Option<String>,
    sort_mode: Option<String>,
    fingerprint_enabled: Option<bool>,
    fingerprint_device: Option<String>,
    group_display: Option<String>,
    logo_style: Option<String>,
}

pub fn load_config() -> anyhow::Result<Config> {
    let path = expand_tilde("~/.config/rama/jaiba_config.toml");

    if !path.is_file() {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("couldn't create {}", parent.display()))?;
        }

        fs::write(&path, SAMPLE_CONFIG)
            .with_context(|| format!("couldn't write {}", path.display()))?;
    }

    let text =
        fs::read_to_string(&path).with_context(|| format!("couldn't read {}", path.display()))?;
    parse_config(&text)
}

fn parse_config(text: &str) -> anyhow::Result<Config> {
    let raw: ConfigFile = toml::from_str(text)?;

    let defaults = Config::default();

    Ok(Config {
        default_database: raw.default_database.map(|s| expand_tilde(&s)),
        keyfile: raw.keyfile.map(|s| expand_tilde(&s)),
        auto_lock: raw
            .auto_lock
            .map(Duration::from_secs)
            .unwrap_or(defaults.auto_lock),
        clipboard_timeout: raw
            .clipboard_timeout
            .map(Duration::from_secs)
            .unwrap_or(defaults.clipboard_timeout),
        theme: raw.theme,
        sort_mode: raw
            .sort_mode
            .and_then(|s| SortMode::from_str(&s))
            .unwrap_or(defaults.sort_mode),
        fingerprint_enabled: raw
            .fingerprint_enabled
            .unwrap_or(defaults.fingerprint_enabled),
        fingerprint_device: raw.fingerprint_device,
        group_display: raw
            .group_display
            .and_then(|s| GroupDisplay::from_str(&s))
            .unwrap_or(defaults.group_display),
        logo_style: raw
            .logo_style
            .and_then(|s| LogoStyle::from_str(&s))
            .unwrap_or(defaults.logo_style),
    })
}

#[derive(Serialize)]
struct ConfigFileOut<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    default_database: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    keyfile: Option<String>,

    auto_lock: u64,
    clipboard_timeout: u64,

    #[serde(skip_serializing_if = "Option::is_none")]
    theme: Option<&'a str>,

    sort_mode: &'a str,
    fingerprint_enabled: bool,

    #[serde(skip_serializing_if = "Option::is_none")]
    fingerprint_device: Option<&'a str>,

    group_display: &'a str,
    logo_style: &'a str,
}

pub fn save_config(config: &Config) -> anyhow::Result<()> {
    let path = expand_tilde("~/.config/rama/jaiba_config.toml");

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("couldn't create {}", parent.display()))?;
    }

    let text = serialize_config(config)?;

    fs::write(&path, text).with_context(|| format!("couldn't write {}", path.display()))?;

    Ok(())
}

fn serialize_config(config: &Config) -> anyhow::Result<String> {
    let out = ConfigFileOut {
        default_database: config
            .default_database
            .as_ref()
            .map(|p| p.display().to_string()),
        keyfile: config.keyfile.as_ref().map(|p| p.display().to_string()),
        auto_lock: config.auto_lock.as_secs(),
        clipboard_timeout: config.clipboard_timeout.as_secs(),
        theme: config.theme.as_deref(),
        sort_mode: config.sort_mode.as_str(),
        fingerprint_enabled: config.fingerprint_enabled,
        fingerprint_device: config.fingerprint_device.as_deref(),
        group_display: config.group_display.as_str(),
        logo_style: config.logo_style.as_str(),
    };

    toml::to_string_pretty(&out).context("couldn't serialize config")
}

#[cfg(test)]
mod tests {
    use super::{Config, GroupDisplay, LogoStyle, SortMode, parse_config, serialize_config};
    use std::path::PathBuf;

    #[test]
    fn parses_optional_keyfile_path() {
        let config = parse_config(
            r#"
                default_database = "/tmp/passwords.kdbx"
                keyfile = "/tmp/passwords.keyx"
            "#,
        )
        .expect("config should parse");

        assert_eq!(
            config.default_database,
            Some(PathBuf::from("/tmp/passwords.kdbx"))
        );
        assert_eq!(config.keyfile, Some(PathBuf::from("/tmp/passwords.keyx")));
    }

    #[test]
    fn keyfile_remains_optional() {
        let config = parse_config("default_database = \"/tmp/passwords.kdbx\"")
            .expect("config should parse");

        assert_eq!(config.keyfile, None);

        let text = serialize_config(&config).expect("config should serialize");
        assert!(!text.contains("keyfile"));
    }

    #[test]
    fn serializes_keyfile_path() {
        let config = Config {
            keyfile: Some(PathBuf::from("/tmp/passwords.keyx")),
            ..Config::default()
        };

        let text = serialize_config(&config).expect("config should serialize");
        assert!(text.contains("keyfile = \"/tmp/passwords.keyx\""));
    }

    #[test]
    fn parses_group_display() {
        let config = parse_config("group_display = \"hidden\"")
            .expect("config should parse");
        assert_eq!(config.group_display, GroupDisplay::Hidden);
    }

    #[test]
    fn group_display_defaults_to_shown() {
        let config = parse_config("")
            .expect("config should parse");
        assert_eq!(config.group_display, GroupDisplay::Shown);
    }

    #[test]
    fn group_display_cycles_all_modes() {
        for mode in ["shown", "hidden", "bottom", "mixed"] {
            let config = parse_config(&format!("group_display = \"{}\"", mode))
                .expect(&format!("should parse mode {}", mode));
            assert_eq!(config.group_display.as_str(), mode);
        }
    }

    #[test]
    fn parses_lastcopied_sort_mode() {
        let config = parse_config("sort_mode = \"lastcopied\"")
            .expect("config should parse");
        assert_eq!(config.sort_mode, SortMode::LastCopied);
    }

    #[test]
    fn sort_mode_cycles_all_modes() {
        for mode in ["smart", "name", "recent", "reuse", "lastcopied"] {
            let config = parse_config(&format!("sort_mode = \"{}\"", mode))
                .expect(&format!("should parse mode {}", mode));
            assert_eq!(config.sort_mode.as_str(), mode);
        }
    }

    #[test]
    fn parses_crab_logo_style() {
        let config = parse_config("logo_style = \"crab\"")
            .expect("config should parse");
        assert_eq!(config.logo_style, LogoStyle::Crab);
    }

    #[test]
    fn logo_style_defaults_to_crab() {
        let config = parse_config("")
            .expect("config should parse");
        assert_eq!(config.logo_style, LogoStyle::Crab);
    }
}
