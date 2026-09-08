use std::collections::HashMap;
use std::fs;
use std::process::Command;

use crate::system::plugins::{self, Plugin, PluginSource};

/// Remove Omarchy shell plugins by id.
///
/// Matches [`plugins::load_all`]. User plugins under `~/.config/omarchy/plugins`
/// are deleted directly. First-party plugins under `/usr/share/omarchy/shell/plugins`
/// require `sudo`. Unknown ids are skipped. Prints the exact plugins that will
/// be removed first, disables them in omarchy-shell when possible, then rescans.
///
/// Note: first-party removals may come back after an `omarchy` package update.
pub fn remove<S: AsRef<str>>(ids: &[S]) {
    if ids.is_empty() {
        println!("No plugins specified.");
        return;
    }

    let mut by_id: HashMap<String, Plugin> = HashMap::new();
    for plugin in plugins::load_all() {
        by_id.insert(plugin.id.clone(), plugin);
    }

    let mut to_remove: Vec<Plugin> = Vec::new();
    let mut skipped: Vec<&str> = Vec::new();

    for id in ids {
        let id = id.as_ref();
        match by_id.remove(id) {
            Some(plugin) => to_remove.push(plugin),
            None => skipped.push(id),
        }
    }

    if !skipped.is_empty() {
        println!("Skipping (not an installed plugin): {}", skipped.join(", "));
    }

    if to_remove.is_empty() {
        println!("No plugins to remove.");
        return;
    }

    let has_first_party = to_remove
        .iter()
        .any(|p| p.source == PluginSource::FirstParty);

    println!("The following plugins will be uninstalled:");
    for plugin in &to_remove {
        let kind = match plugin.source {
            PluginSource::User => "user",
            PluginSource::FirstParty => "preinstalled",
        };
        println!(
            "  {} ({kind}) — {} — {}",
            plugin.id, plugin.name, plugin.path
        );
    }
    if has_first_party {
        println!(
            "Note: preinstalled plugins may return after an omarchy package update."
        );
    }

    let mut first_party_paths: Vec<&str> = Vec::new();
    let mut ok = true;

    for plugin in &to_remove {
        let _ = Command::new("omarchy-shell")
            .args(["shell", "setPluginEnabled", &plugin.id, "false"])
            .output();

        match plugin.source {
            PluginSource::User => {
                if let Err(e) = fs::remove_dir_all(&plugin.path) {
                    eprintln!("Failed to remove {}: {e}", plugin.path);
                    ok = false;
                }
            }
            PluginSource::FirstParty => {
                first_party_paths.push(&plugin.path);
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

    let _ = Command::new("omarchy-shell")
        .args(["shell", "rescanPlugins"])
        .output();

    if ok {
        println!("Done.");
        let needles: Vec<&str> = to_remove
            .iter()
            .flat_map(|p| [p.id.as_str(), p.name.as_str()])
            .collect();
        crate::remove::bindings::remove_related(&needles);
    }
}
