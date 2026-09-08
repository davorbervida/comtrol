use std::process::Command;

use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Clone, Serialize)]
pub struct Plugin {
    pub id: String,
    pub name: String,
    pub description: String,
    pub author: String,
    pub version: String,
    pub category: String,
    pub tags: Vec<String>,
    pub repo: String,
    pub source_type: String,
    pub stars: u64,
    pub views: u64,
    pub copies: u64,
    pub hearts: u64,
    pub install_available: bool,
    pub install_command: String,
    pub preview_image: Option<String>,
}

/// Search installed (user and first-party) Omarchy plugins.
///
/// Empty `query` returns all local plugins. Otherwise filters by id, name,
/// description, and kinds.
/// Returns a JSON array.
pub fn local(query: &str) -> String {
    let q = query.trim().to_lowercase();
    let plugins: Vec<_> = crate::control::system::plugins::collect()
        .into_iter()
        .filter(|p| {
            q.is_empty()
                || p.id.to_lowercase().contains(&q)
                || p.name.to_lowercase().contains(&q)
                || p.description.to_lowercase().contains(&q)
                || p.kinds.iter().any(|k| k.to_lowercase().contains(&q))
        })
        .collect();
    super::to_json(&plugins)
}

/// Search the Omarchy plugin catalog.
///
/// Fetches `catalog.json` and install/stats data on every call.
/// An empty `query` returns the full catalog; otherwise filters by
/// id, name, description, author, category, and tags.
/// Returns a JSON array.
pub fn web(query: &str) -> String {
    super::to_json(&web_items(query))
}

fn web_items(query: &str) -> Vec<Plugin> {
    let (catalog_out, stats_out) = std::thread::scope(|scope| {
        let catalog = scope.spawn(|| {
            Command::new("curl")
                .args(["-fsSL", "https://plugins.omarchy.org/catalog.json"])
                .output()
        });
        let stats = scope.spawn(|| {
            Command::new("curl")
                .args(["-fsSL", "https://api.omarchyplugins.com/v1/stats"])
                .output()
        });
        (catalog.join().ok(), stats.join().ok())
    });

    let Some(Ok(catalog_out)) = catalog_out else {
        return Vec::new();
    };
    let Some(Ok(stats_out)) = stats_out else {
        return Vec::new();
    };
    if !catalog_out.status.success() || !stats_out.status.success() {
        return Vec::new();
    }

    let Ok(catalog) = serde_json::from_slice::<Value>(&catalog_out.stdout) else {
        return Vec::new();
    };
    let Ok(stats) = serde_json::from_slice::<Value>(&stats_out.stdout) else {
        return Vec::new();
    };

    let Some(plugins) = catalog.get("plugins").and_then(|v| v.as_array()) else {
        return Vec::new();
    };
    let stats_plugins = stats.get("plugins").cloned().unwrap_or(Value::Null);

    let q = query.trim().to_lowercase();
    let mut out = Vec::new();

    for plugin in plugins {
        let id = plugin
            .get("id")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let name = plugin
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let description = plugin
            .get("description")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let author = plugin
            .get("author")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let category = plugin
            .get("category")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let tags: Vec<String> = plugin
            .get("tags")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|t| t.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default();

        if !q.is_empty() {
            let tags_joined = tags.join(" ");
            let haystack =
                format!("{id} {name} {description} {author} {category} {tags_joined}")
                    .to_lowercase();
            if !haystack.contains(&q) {
                continue;
            }
        }

        let st = stats_plugins.get(id);
        let views = st
            .and_then(|v| v.get("views"))
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        let copies = st
            .and_then(|v| v.get("copies"))
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        let hearts = st
            .and_then(|v| v.get("hearts"))
            .and_then(|v| v.as_u64())
            .unwrap_or(0);

        out.push(Plugin {
            id: id.to_string(),
            name: name.to_string(),
            description: description.to_string(),
            author: author.to_string(),
            version: plugin
                .get("version")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            category: category.to_string(),
            tags,
            repo: plugin
                .get("repo")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            source_type: plugin
                .get("sourceType")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            stars: plugin
                .get("stars")
                .and_then(|v| v.as_u64())
                .unwrap_or(0),
            views,
            copies,
            hearts,
            install_available: plugin
                .get("installAvailable")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            install_command: plugin
                .get("installCommand")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            preview_image: plugin
                .get("previewImage")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .map(|s| {
                    if s.starts_with("http://") || s.starts_with("https://") {
                        s.to_string()
                    } else {
                        format!("https://plugins.omarchy.org/{s}")
                    }
                }),
        });
    }

    out
}
