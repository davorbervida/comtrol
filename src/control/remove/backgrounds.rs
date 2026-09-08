use std::fs;
use std::io::ErrorKind;
use std::path::Path;
use std::process::Command;

/// Remove a background image by absolute path.
///
/// User-writable files are deleted directly. Paths under `/usr/share` (and other
/// permission-denied cases) use `pkexec rm`. Returns JSON `{"ok":true}` or
/// `{"ok":false}`.
pub fn remove(path: &str) -> String {
    let path = path.trim();
    if path.is_empty() {
        return status_json(false);
    }

    let p = Path::new(path);
    if !p.is_absolute() || !p.is_file() {
        return status_json(false);
    }

    let ok = if is_under_usr_share(p) {
        remove_with_pkexec(path)
    } else {
        match fs::remove_file(path) {
            Ok(()) => true,
            Err(e) if e.kind() == ErrorKind::PermissionDenied => remove_with_pkexec(path),
            Err(_) => false,
        }
    };

    status_json(ok)
}

fn is_under_usr_share(path: &Path) -> bool {
    path.starts_with(Path::new("/usr/share"))
}

fn remove_with_pkexec(path: &str) -> bool {
    match Command::new("pkexec").arg("rm").arg("--").arg(path).status() {
        Ok(s) => s.success(),
        Err(_) => false,
    }
}

fn status_json(ok: bool) -> String {
    if ok {
        r#"{"ok":true}"#.to_string()
    } else {
        r#"{"ok":false}"#.to_string()
    }
}
