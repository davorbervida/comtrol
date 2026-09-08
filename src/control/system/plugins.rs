use std::env;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PluginSource {
    FirstParty,
    User,
}

#[derive(Debug, Clone)]
pub struct Plugin {
    pub id: String,
    pub name: String,
    pub version: String,
    pub description: String,
    pub path: String,
    pub preview: Option<String>,
    pub kinds: Vec<String>,
    pub source: PluginSource,
}

/// Load user-installed and first-party Omarchy plugins.
pub fn load_all() -> Vec<Plugin> {
    let mut plugins = load_user();
    plugins.extend(load_first_party());
    plugins
}

fn load_user() -> Vec<Plugin> {
    let home = env::var("HOME").expect("Home is not set");
    let plugins_dir = PathBuf::from(format!("{home}/.config/omarchy/plugins"));

    let Ok(entries) = fs::read_dir(&plugins_dir) else {
        return Vec::new();
    };

    let mut plugins = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let manifest = path.join("manifest.json");
        if !manifest.is_file() {
            continue;
        }
        if let Some(plugin) = parse_plugin(&manifest, PluginSource::User) {
            plugins.push(plugin);
        }
    }
    plugins
}

fn load_first_party() -> Vec<Plugin> {
    let omarchy = env::var("OMARCHY_PATH").unwrap_or_else(|_| "/usr/share/omarchy".to_string());
    let root = PathBuf::from(format!("{omarchy}/shell/plugins"));

    let mut plugins = Vec::new();
    for manifest in find_manifests(&root, 2, 3) {
        if let Some(plugin) = parse_plugin(&manifest, PluginSource::FirstParty) {
            plugins.push(plugin);
        }
    }
    plugins
}

fn parse_plugin(manifest_path: &Path, source: PluginSource) -> Option<Plugin> {
    let src = fs::read_to_string(manifest_path).ok()?;

    let id = json_string(&src, "id")?;
    let name = json_string(&src, "name").unwrap_or_else(|| id.clone());
    let version = json_string(&src, "version").unwrap_or_default();
    let description = json_string(&src, "description").unwrap_or_default();

    let plugin_dir = manifest_path.parent()?;
    let path = plugin_dir.to_string_lossy().to_string();

    let preview_path = plugin_dir.join("preview.png");
    let preview = preview_path
        .is_file()
        .then(|| preview_path.to_string_lossy().to_string());

    let kinds = json_string_array(&src, "kinds");

    Some(Plugin {
        id,
        name,
        version,
        description,
        path,
        preview,
        kinds,
        source,
    })
}

/// Match Omarchy PluginRegistry: find manifests at relative depth min..=max.
fn find_manifests(root: &Path, min_depth: usize, max_depth: usize) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let mut stack = vec![(root.to_path_buf(), 0usize)];

    while let Some((dir, depth)) = stack.pop() {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };

        for entry in entries.flatten() {
            let path = entry.path();
            let next = depth + 1;

            if path.is_dir() {
                if next < max_depth {
                    stack.push((path, next));
                }
                continue;
            }

            if next < min_depth || next > max_depth {
                continue;
            }

            let name = path
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or_default();
            if name == "manifest.json" || name.ends_with(".manifest.json") {
                out.push(path);
            }
        }
    }

    out
}

fn json_string(src: &str, key: &str) -> Option<String> {
    let pat = format!("\"{key}\"");
    let i = src.find(&pat)?;
    let after_key = &src[i + pat.len()..];
    let after_colon = after_key.split_once(':')?.1.trim_start();
    let rest = after_colon.strip_prefix('"')?;
    let mut value = String::new();
    let mut chars = rest.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            if let Some(next) = chars.next() {
                value.push(next);
            }
            continue;
        }
        if c == '"' {
            break;
        }
        value.push(c);
    }
    Some(value)
}

fn json_string_array(src: &str, key: &str) -> Vec<String> {
    let pat = format!("\"{key}\"");
    let Some(i) = src.find(&pat) else {
        return Vec::new();
    };
    let after_key = &src[i + pat.len()..];
    let Some((_, after_colon)) = after_key.split_once(':') else {
        return Vec::new();
    };
    let Some(start) = after_colon.find('[') else {
        return Vec::new();
    };
    let Some(end) = after_colon[start..].find(']') else {
        return Vec::new();
    };
    let body = &after_colon[start + 1..start + end];

    let mut values = Vec::new();
    let mut rest = body;
    while let Some(q) = rest.find('"') {
        rest = &rest[q + 1..];
        let Some(end) = rest.find('"') else {
            break;
        };
        values.push(rest[..end].to_string());
        rest = &rest[end + 1..];
    }
    values
}
