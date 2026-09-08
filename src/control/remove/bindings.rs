use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

use crate::control::system::bindings::{self, Binding, BindingType};

/// Remove bindings related to package names, web app names/URLs, or plugin ids.
///
/// A binding matches when its description equals a needle (case-insensitive),
/// or its action contains the needle (full URL substring, otherwise as a
/// whole token so e.g. `go` does not match `google`). Silent when nothing
/// matches. Otherwise delegates to [`remove`].
pub fn remove_related<S: AsRef<str>>(needles: &[S]) {
    let needles: Vec<&str> = needles
        .iter()
        .map(|s| s.as_ref())
        .filter(|s| !s.is_empty())
        .collect();
    if needles.is_empty() {
        return;
    }

    let mut actions = Vec::new();
    let mut seen = HashSet::new();

    for binding in bindings::collect() {
        if binding.r#type == BindingType::Unbind || binding.action.is_empty() {
            continue;
        }

        let related = needles.iter().any(|needle| {
            if binding.description.eq_ignore_ascii_case(needle) {
                return true;
            }
            let action = binding.action.to_lowercase();
            let needle = needle.to_lowercase();
            if needle.contains("://") {
                return action.contains(&needle);
            }
            let bytes = action.as_bytes();
            let n = needle.as_bytes();
            let mut start = 0;
            while let Some(rel) = action[start..].find(&needle) {
                let abs = start + rel;
                let before_ok = abs == 0 || !bytes[abs - 1].is_ascii_alphanumeric();
                let after = abs + n.len();
                let after_ok = after >= bytes.len() || !bytes[after].is_ascii_alphanumeric();
                if before_ok && after_ok {
                    return true;
                }
                start = abs + 1;
            }
            false
        });

        if related && seen.insert(binding.action.clone()) {
            actions.push(binding.action);
        }
    }

    if !actions.is_empty() {
        remove(&actions);
    }
}

/// Remove keybindings by action name.
///
/// Matches [`bindings::load_all`] Bind/Toggle entries by exact `action`, then
/// deletes the corresponding `o.bind` / `o.bind_toggle` lines from the source
/// Lua files (system defaults under `/usr/share/omarchy/...` and the user
/// `~/.config/hypr/bindings.lua`). System files require `sudo`. Multiple
/// actions can be passed.
///
/// Note: edits under `/usr/share/omarchy` may come back after a package update.
pub fn remove<S: AsRef<str>>(actions: &[S]) {
    if actions.is_empty() {
        println!("No binding actions specified.");
        return;
    }

    let mut by_action: HashMap<String, Vec<Binding>> = HashMap::new();
    for binding in bindings::collect() {
        if binding.r#type == BindingType::Unbind || binding.action.is_empty() {
            continue;
        }
        by_action
            .entry(binding.action.clone())
            .or_default()
            .push(binding);
    }

    let mut to_remove: Vec<Binding> = Vec::new();
    let mut skipped: Vec<&str> = Vec::new();

    for action in actions {
        let action = action.as_ref();
        match by_action.remove(action) {
            Some(list) => to_remove.extend(list),
            None => skipped.push(action),
        }
    }

    if !skipped.is_empty() {
        println!(
            "Skipping (no binding with that action): {}",
            skipped.join(", ")
        );
    }

    if to_remove.is_empty() {
        println!("No bindings to remove.");
        return;
    }

    let stem_to_path: HashMap<String, String> = bindings::config_paths()
        .into_iter()
        .filter_map(|path| {
            let stem = Path::new(&path)
                .file_stem()
                .and_then(|s| s.to_str())?
                .to_string();
            Some((stem, path))
        })
        .collect();

    println!("The following bindings will be deleted:");
    for binding in &to_remove {
        let desc = if binding.description.is_empty() {
            "-"
        } else {
            binding.description.as_str()
        };
        let path = stem_to_path
            .get(&binding.source)
            .map(String::as_str)
            .unwrap_or(&binding.source);
        println!(
            "  {}  —  {}  [{}]  ({path})",
            binding.keys, binding.action, desc
        );
    }

    let has_system = to_remove.iter().any(|b| {
        stem_to_path
            .get(&b.source)
            .is_some_and(|p| p.starts_with("/usr/"))
    });
    if has_system {
        println!(
            "Note: system binding files may be restored after an omarchy package update."
        );
    }

    // Per file: set of (keys, description) to delete.
    let mut by_file: HashMap<String, HashSet<(String, String)>> = HashMap::new();
    for binding in &to_remove {
        let Some(path) = stem_to_path.get(&binding.source) else {
            eprintln!(
                "Skipping {} — unknown source file '{}'",
                binding.keys, binding.source
            );
            continue;
        };
        by_file
            .entry(path.clone())
            .or_default()
            .insert((binding.keys.clone(), binding.description.clone()));
    }

    let mut ok = true;

    for (path, targets) in &by_file {
        let Ok(original) = fs::read_to_string(path) else {
            eprintln!("Failed to read {path}");
            ok = false;
            continue;
        };

        let mut kept: Vec<&str> = Vec::new();
        let mut removed = 0usize;

        for line in original.lines() {
            let trimmed = line.trim();
            let is_bind = !trimmed.starts_with("--")
                && (trimmed.contains("o.bind(") || trimmed.contains("o.bind_toggle("));

            if is_bind {
                let mut quotes = trimmed
                    .split('"')
                    .enumerate()
                    .filter_map(|(i, part)| (i % 2 == 1).then_some(part));
                let line_keys = quotes.next().unwrap_or("");
                let after_keys = trimmed
                    .split_once('"')
                    .and_then(|(_, rest)| rest.split_once('"').map(|(_, r)| r))
                    .unwrap_or("");
                let line_desc = if after_keys.trim_start().starts_with(", nil")
                    || after_keys.trim_start().starts_with(",nil")
                {
                    ""
                } else {
                    quotes.next().unwrap_or("")
                };

                if targets
                    .iter()
                    .any(|(k, d)| k == line_keys && d == line_desc)
                {
                    removed += 1;
                    continue;
                }
            }

            kept.push(line);
        }

        if removed == 0 {
            eprintln!("No matching bind lines found in {path}");
            ok = false;
            continue;
        }

        let mut output = kept.join("\n");
        if !output.is_empty() && !output.ends_with('\n') {
            output.push('\n');
        }

        let is_system = path.starts_with("/usr/");
        if is_system {
            let status = Command::new("sudo")
                .args(["tee", path])
                .stdin(Stdio::piped())
                .stdout(Stdio::null())
                .stderr(Stdio::inherit())
                .spawn()
                .and_then(|mut child| {
                    if let Some(stdin) = child.stdin.as_mut() {
                        stdin.write_all(output.as_bytes())?;
                    }
                    child.wait()
                });
            match status {
                Ok(s) if s.success() => println!("Updated {path} (−{removed} line(s))"),
                Ok(s) => {
                    eprintln!("sudo tee exited with status: {s} ({path})");
                    ok = false;
                }
                Err(e) => {
                    eprintln!("Failed to write {path}: {e}");
                    ok = false;
                }
            }
        } else if let Err(e) = fs::write(path, &output) {
            eprintln!("Failed to write {path}: {e}");
            ok = false;
        } else {
            println!("Updated {path} (−{removed} line(s))");
        }
    }

    if ok {
        println!("Done.");
    }
}
