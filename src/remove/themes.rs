use std::collections::HashMap;
use std::fs;
use std::process::Command;

use crate::system::themes::{self, Theme, ThemeSource};

/// Remove Omarchy themes by directory name.
///
/// Matches [`themes::load_all`]. User themes are deleted directly; first-party
/// themes under `/usr/share/omarchy/themes` require `sudo`. Unknown names are
/// skipped. Prints the exact themes that will be removed first.
///
/// Note: first-party removals may come back after an `omarchy` package update.
pub fn remove<S: AsRef<str>>(names: &[S]) {
    if names.is_empty() {
        println!("No themes specified.");
        return;
    }

    let mut by_name: HashMap<String, Theme> = HashMap::new();
    for theme in themes::load_all() {
        // Prefer the user copy when the same name exists in both places.
        if theme.source == ThemeSource::User || !by_name.contains_key(&theme.name) {
            by_name.insert(theme.name.clone(), theme);
        }
    }

    let mut to_remove: Vec<Theme> = Vec::new();
    let mut skipped: Vec<&str> = Vec::new();

    for name in names {
        let name = name.as_ref();
        if name.is_empty() || name == "." || name == ".." || name.contains('/') {
            skipped.push(name);
            continue;
        }
        match by_name.remove(name) {
            Some(theme) => to_remove.push(theme),
            None => skipped.push(name),
        }
    }

    if !skipped.is_empty() {
        println!("Skipping (not an installed theme): {}", skipped.join(", "));
    }

    if to_remove.is_empty() {
        println!("No themes to remove.");
        return;
    }

    let has_first_party = to_remove
        .iter()
        .any(|t| t.source == ThemeSource::FirstParty);

    println!("The following themes will be uninstalled:");
    for theme in &to_remove {
        let kind = match theme.source {
            ThemeSource::User => "user",
            ThemeSource::FirstParty => "preinstalled",
        };
        println!("  {} ({kind}) — {}", theme.name, theme.path);
    }
    if has_first_party {
        println!(
            "Note: preinstalled themes may return after an omarchy package update."
        );
    }

    let mut first_party_paths: Vec<&str> = Vec::new();
    let mut ok = true;

    for theme in &to_remove {
        match theme.source {
            ThemeSource::User => {
                let meta = fs::symlink_metadata(&theme.path);
                let result = match meta {
                    Ok(m) if m.file_type().is_symlink() => fs::remove_file(&theme.path),
                    _ => fs::remove_dir_all(&theme.path),
                };
                if let Err(e) = result {
                    eprintln!("Failed to remove {}: {e}", theme.path);
                    ok = false;
                }
            }
            ThemeSource::FirstParty => {
                first_party_paths.push(&theme.path);
            }
        }
    }

    if !first_party_paths.is_empty() {
        let status = Command::new("sudo")
            .arg("rm")
            .arg("-rf")
            .args(&first_party_paths)
            .status();
        match status {
            Ok(s) if s.success() => {}
            Ok(s) => {
                eprintln!("sudo rm exited with status: {s}");
                ok = false;
            }
            Err(e) => {
                eprintln!("Failed to run sudo rm: {e}");
                ok = false;
            }
        }
    }

    if ok {
        println!("Done.");
    }
}
