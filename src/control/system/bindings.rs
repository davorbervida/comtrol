use std::env;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BindingType {
    Bind,
    Unbind,
    Toggle,
}

#[derive(Debug, Clone)]
pub struct Binding {
    pub keys: String,
    pub action: String,
    pub description: String,
    pub source: String,
    pub r#type: BindingType,
}

/// Load and merge bindings from all known config files.
pub fn load_all() -> Vec<Binding> {
    config_paths()
        .iter()
        .flat_map(|path| extract_bindings(path))
        .collect()
}

/// Default Omarchy + user Hyprland binding config paths.
pub fn config_paths() -> Vec<String> {
    let home = env::var("HOME").expect("Home is not set");

    vec![
        "/usr/share/omarchy/default/hypr/bindings/applications.lua".to_string(),
        "/usr/share/omarchy/default/hypr/bindings/clipboard.lua".to_string(),
        "/usr/share/omarchy/default/hypr/bindings/media.lua".to_string(),
        "/usr/share/omarchy/default/hypr/bindings/tiling.lua".to_string(),
        "/usr/share/omarchy/default/hypr/bindings/utilities.lua".to_string(),
        "/usr/share/omarchy/default/hypr/bindings/voxtype.lua".to_string(),
        format!("{home}/.config/hypr/bindings.lua"),
    ]
}

/// Extract key bindings from a single Lua bindings file.
pub fn extract_bindings(file_path: &str) -> Vec<Binding> {
    let Ok(src) = fs::read_to_string(file_path) else {
        return Vec::new();
    };

    let source = Path::new(file_path)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(file_path)
        .to_string();

    let mut out = Vec::new();

    for line in src.lines() {
        let line = line.trim();
        if line.starts_with("--") {
            continue;
        }

        let toggle = line.contains("o.bind_toggle(");
        let bind = line.contains("o.bind(");
        let unbind = line.contains("hl.unbind(");
        if !bind && !toggle && !unbind {
            continue;
        }
        // Skip concatenated keys from Lua loops, e.g. "SUPER + " .. key
        if line.contains(" .. ") {
            continue;
        }

        let Some((_, after_paren)) = line.split_once('(') else {
            continue;
        };
        let Some((keys, after_keys)) = extract_quoted(after_paren) else {
            continue;
        };

        if unbind {
            out.push(Binding {
                keys,
                action: String::new(),
                description: String::new(),
                source: source.clone(),
                r#type: BindingType::Unbind,
            });
            continue;
        }

        let after_keys = skip_comma(after_keys);
        let (description, after_desc) = if after_keys.starts_with("nil") {
            (String::new(), skip_comma(after_keys.trim_start_matches("nil")))
        } else if let Some((desc, rest)) = extract_quoted(after_keys) {
            (desc, skip_comma(rest))
        } else {
            continue;
        };

        let (action, binding_type) = if toggle {
            let name = extract_quoted(after_desc)
                .map(|(s, _)| s)
                .unwrap_or_else(|| after_desc.to_string());
            (format!("omarchy-toggle-{name}"), BindingType::Toggle)
        } else {
            (
                extract_dispatcher(after_desc, &description),
                BindingType::Bind,
            )
        };

        out.push(Binding {
            keys,
            action,
            description,
            source: source.clone(),
            r#type: binding_type,
        });
    }

    out
}

fn skip_comma(s: &str) -> &str {
    s.trim_start_matches(',').trim()
}

fn extract_quoted(s: &str) -> Option<(String, &str)> {
    let start = s.find('"')?;
    let rest = &s[start + 1..];
    let end = rest.find('"')?;
    Some((rest[..end].to_string(), &rest[end + 1..]))
}

fn extract_dispatcher(rest: &str, description: &str) -> String {
    let rest = rest.trim().trim_end_matches(')').trim();

    if let Some(s) = rest.strip_prefix('"') {
        return s.split('"').next().unwrap_or(s).to_string();
    }

    if rest.starts_with('{') {
        return action_from_table(rest, description);
    }

    if let Some((call, _)) = rest.split_once(", {") {
        return call.trim().to_string();
    }

    rest.to_string()
}

fn action_from_table(table: &str, description: &str) -> String {
    if let Some(name) = table_field(table, "omarchy") {
        return format!("omarchy-launch-{name}");
    }
    if let Some(cmd) = table_field(table, "launch") {
        if let Some(focus) = table_field(table, "focus") {
            return format!("omarchy-launch-or-focus '{focus}' 'uwsm-app -- {cmd}'");
        }
        return format!("uwsm-app -- {cmd}");
    }
    if let Some(url) = table_field(table, "webapp") {
        return if table_has(table, "focus") {
            format!("omarchy-launch-or-focus-webapp '{description}' '{url}'")
        } else {
            format!("omarchy-launch-webapp '{url}'")
        };
    }
    if let Some(tui) = table_field(table, "tui") {
        return if table_has(table, "focus") {
            format!("omarchy-launch-or-focus-tui '{tui}'")
        } else {
            format!("omarchy-launch-tui '{tui}'")
        };
    }
    table.trim().to_string()
}

fn table_field<'a>(table: &'a str, field: &str) -> Option<&'a str> {
    let pat = format!("{field} = \"");
    let i = table.find(&pat)?;
    let rest = &table[i + pat.len()..];
    let end = rest.find('"')?;
    Some(&rest[..end])
}

fn table_has(table: &str, field: &str) -> bool {
    table.contains(&format!("{field} ="))
}
