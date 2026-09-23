use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::mpsc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use crate::config::Config;
use crate::util::expand_tilde;

pub enum FprintError {
    #[allow(dead_code)]
    NotInstalled,
    #[allow(dead_code)]
    VerificationFailed(String),
    #[allow(dead_code)]
    EnrollmentFailed(String),
    Io(String),
}

impl std::fmt::Display for FprintError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotInstalled => write!(f, "fprintd is not installed"),
            Self::VerificationFailed(msg) => write!(f, "Fingerprint verification failed: {msg}"),
            Self::EnrollmentFailed(msg) => write!(f, "Enrollment failed: {msg}"),
            Self::Io(msg) => write!(f, "{msg}"),
        }
    }
}

pub fn is_available() -> bool {
    Command::new("fprintd-verify")
        .arg("--help")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|_| true)
        .unwrap_or(false)
}

pub fn is_enrolled() -> bool {
    let mut cmd = Command::new("fprintd-list");
    if let Ok(user) = std::env::var("USER") {
        if !user.is_empty() {
            cmd.arg(user);
        }
    }
    match cmd.output() {
        Ok(output) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let lower = stdout.to_lowercase();
            !stdout.trim().is_empty()
                && !lower.contains("error")
                && !lower.contains("no fingerprints")
        }
        _ => false,
    }
}

// Instant verification. fprintd-verify blocks natively until a swipe or timeout.
// No artificial sleep loops needed.
pub fn stored_password_exists(config: &Config) -> bool {
    stored_password_path(config)
        .map(|path| path.is_file())
        .unwrap_or(false)
}

pub fn start_verify() -> Result<(mpsc::Receiver<bool>, Arc<AtomicBool>), FprintError> {
    let (tx, rx) = mpsc::channel();
    let running = Arc::new(AtomicBool::new(true));
    let running_clone = running.clone();

    thread::spawn(move || {
        crate::util::debug_log("fprint thread: started");

        while running_clone.load(Ordering::Relaxed) {
            crate::util::debug_log("fprint thread: spawning fprintd-verify");

            let output = Command::new("fprintd-verify")
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .output();

            if !running_clone.load(Ordering::Relaxed) {
                crate::util::debug_log("fprint thread: stopped after fprintd-verify returned");
                return;
            }

            match output {
                Ok(output) => {
                    crate::util::debug_log(&format!(
                        "fprint thread: fprintd-verify success={}",
                        output.status.success()
                    ));

                    if output.status.success() {
                        let _ = tx.send(true);
                        return;
                    }
                }
                Err(err) => {
                    crate::util::debug_log(&format!("fprint thread: spawn err: {err}"));
                    let _ = tx.send(false);
                    return;
                }
            }

            thread::sleep(std::time::Duration::from_millis(1500));

            if !running_clone.load(Ordering::Relaxed) {
                crate::util::debug_log("fprint thread: stopped during retry delay");
                return;
            }
        }

        crate::util::debug_log("fprint thread: exited loop");
    });

    Ok((rx, running))
}

pub fn stop_verify(running: Option<&Arc<AtomicBool>>) {
    if let Some(r) = running {
        r.store(false, Ordering::Relaxed);
    }
    let _ = Command::new("pkill")
        .arg("-x")
        .arg("fprintd-verify")
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .spawn();
}

#[allow(dead_code)]
pub fn start_enroll() -> Result<(), FprintError> {
    let status = Command::new("fprintd-enroll")
        .status()
        .map_err(|e| FprintError::Io(e.to_string()))?;
    if status.success() {
        Ok(())
    } else {
        Err(FprintError::EnrollmentFailed(
            "Enrollment was cancelled or failed".to_string(),
        ))
    }
}

fn stable_hash(input: &str) -> u64 {
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in input.bytes() {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

pub fn stored_password_path(config: &Config) -> Option<PathBuf> {
    config.default_database.as_ref().map(|path| {
        let basename = path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "database".to_string())
            .replace(|c: char| !c.is_ascii_alphanumeric(), "_");

        let hash = stable_hash(&path.display().to_string());
        expand_tilde("~/.local/share/rama").join(format!("{basename}-{hash:016x}.fprint"))
    })
}

pub fn read_stored_password(config: &Config) -> Result<String, FprintError> {
    let path = stored_password_path(config)
        .ok_or_else(|| FprintError::Io("no database configured".to_string()))?;
    
    // .trim() is critical here to prevent silent unlock failures from trailing newlines
    fs::read_to_string(&path)
        .map(|s| s.trim().to_string())
        .map_err(|e| FprintError::Io(format!("couldn't read stored password: {e}")))
}

pub fn store_password(config: &Config, password: &str) -> Result<(), FprintError> {
    let path = stored_password_path(config)
        .ok_or_else(|| FprintError::Io("no database configured".to_string()))?;

    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| FprintError::Io(format!("couldn't create dir: {e}")))?;
        
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if let Ok(mut perms) = fs::metadata(parent).map(|m| m.permissions()) {
                perms.set_mode(0o700);
                let _ = fs::set_permissions(parent, perms);
            }
        }
    }

    fs::write(&path, password)
        .map_err(|e| FprintError::Io(format!("couldn't write password: {e}")))?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Ok(mut perms) = fs::metadata(&path).map(|m| m.permissions()) {
            perms.set_mode(0o600);
            let _ = fs::set_permissions(&path, perms);
        }
    }

    Ok(())
}

pub fn delete_stored_password(config: &Config) -> Result<(), FprintError> {
    let path = stored_password_path(config)
        .ok_or_else(|| FprintError::Io("no database configured".to_string()))?;
    if path.exists() {
        fs::remove_file(&path)
            .map_err(|e| FprintError::Io(format!("couldn't delete password: {e}")))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn is_available_returns_bool() {
        let _ = is_available();
    }
}
