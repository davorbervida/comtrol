use std::collections::HashMap;
use std::env;
use std::fs;
use std::process::Command;

use crate::control::system::web_apps::{self, WebApp, WebAppSource};

/// Remove Omarchy web app desktop launchers by name.
///
/// Matches against [`web_apps::load_all`]. User apps are deleted from the home
/// directory (plus local icons). First-party apps under `/usr/share/omarchy`
/// require `sudo`. Unknown names are skipped. Prints the exact apps that will
/// be removed first.
///
/// Note: first-party removals may come back after an `omarchy-settings` update.
pub fn remove<S: AsRef<str>>(names: &[S]) {
    if names.is_empty() {
        println!("No web apps specified.");
        return;
    }

    let mut by_name: HashMap<String, Vec<WebApp>> = HashMap::new();
    for app in web_apps::load_all() {
        by_name.entry(app.name.clone()).or_default().push(app);
    }

    let mut to_remove: Vec<WebApp> = Vec::new();
    let mut skipped: Vec<&str> = Vec::new();

    for name in names {
        let name = name.as_ref();
        match by_name.remove(name) {
            Some(apps) => to_remove.extend(apps),
            None => skipped.push(name),
        }
    }

    if !skipped.is_empty() {
        println!(
            "Skipping (not an installed web app): {}",
            skipped.join(", ")
        );
    }

    if to_remove.is_empty() {
        println!("No web apps to remove.");
        return;
    }

    let has_first_party = to_remove
        .iter()
        .any(|a| a.source == WebAppSource::FirstParty);

    println!("The following web apps will be uninstalled:");
    for app in &to_remove {
        let kind = match app.source {
            WebAppSource::User => "user",
            WebAppSource::FirstParty => "preinstalled",
        };
        println!("  {} ({kind}) — {}", app.name, app.path);
    }
    if has_first_party {
        println!(
            "Note: preinstalled apps may return after an omarchy-settings package update."
        );
    }

    let home = env::var("HOME").unwrap_or_default();
    let icon_dir = format!("{home}/.local/share/icons/hicolor/256x256/apps");
    let old_icon_dir = format!("{home}/.local/share/applications/icons");
    let desktop_dir = format!("{home}/.local/share/applications");

    let mut first_party_paths: Vec<&str> = Vec::new();
    let mut removed_user = false;
    let mut ok = true;

    for app in &to_remove {
        match app.source {
            WebAppSource::User => {
                if let Err(e) = fs::remove_file(&app.path) {
                    eprintln!("Failed to remove {}: {e}", app.path);
                    ok = false;
                } else {
                    removed_user = true;
                }

                // Same sanitizing as omarchy-webapp-remove:
                // tr '[:upper:]' '[:lower:]' | sed 's/[^[:alnum:]]\+/-/g; s/^-//; s/-$//'
                let mut icon_name = String::new();
                let mut prev_dash = false;
                for c in app.name.chars() {
                    if c.is_ascii_alphanumeric() {
                        icon_name.push(c.to_ascii_lowercase());
                        prev_dash = false;
                    } else if !prev_dash {
                        icon_name.push('-');
                        prev_dash = true;
                    }
                }
                let icon_name = icon_name.trim_matches('-');

                let _ = fs::remove_file(format!("{icon_dir}/{icon_name}.png"));
                let _ = fs::remove_file(format!("{icon_dir}/{}.png", app.name));
                let _ = fs::remove_file(format!("{old_icon_dir}/{}.png", app.name));
                if !app.icon.is_empty() && app.icon != icon_name && app.icon != app.name {
                    let _ = fs::remove_file(format!("{icon_dir}/{}.png", app.icon));
                }
            }
            WebAppSource::FirstParty => {
                first_party_paths.push(&app.path);
            }
        }
    }

    if !first_party_paths.is_empty() {
        let status = Command::new("sudo")
            .arg("rm")
            .arg("-f")
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

    if removed_user {
        let _ = Command::new("update-desktop-database")
            .arg(&desktop_dir)
            .status();
    }

    if ok {
        println!("Done.");
        let mut needles: Vec<String> = Vec::new();
        for app in &to_remove {
            needles.push(app.name.clone());
            if let Some(url) = &app.url {
                needles.push(url.clone());
            }
        }
        crate::control::remove::bindings::remove_related(&needles);
    }
}
