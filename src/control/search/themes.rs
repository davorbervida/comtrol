use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;
use serde_json::{Value, json};

const CACHE_TTL_SECS: u64 = 24 * 60 * 60;
const SEARCH_PAGES: u32 = 3;
const TOP_N: usize = 30;

#[derive(Debug, Clone, Serialize)]
pub struct Theme {
    pub name: String,
    pub full_name: String,
    pub description: String,
    pub author: String,
    pub repo: String,
    pub stars: u64,
    pub preview_image: String,
}

/// Search installed (user and first-party) Omarchy themes.
///
/// Empty `query` returns all local themes. Otherwise filters by name.
/// Returns a JSON array.
pub fn local(query: &str) -> String {
    let q = query.trim().to_lowercase();
    let themes: Vec<_> = crate::control::system::themes::collect()
        .into_iter()
        .filter(|t| q.is_empty() || t.name.to_lowercase().contains(&q))
        .collect();
    super::to_json(&themes)
}

/// Search Omarchy themes on GitHub (repos with `preview.png`).
///
/// Empty `query` returns the top 30 by stars. Non-empty filters the
/// cached catalog by name, full name, description, and author.
/// Results are cached under `~/.cache/comtrol/themes.json`.
/// Returns a JSON array.
pub fn web(query: &str) -> String {
    super::to_json(&web_items(query))
}

fn web_items(query: &str) -> Vec<Theme> {
    let mut themes = None;

    if let Some(path) = cache_path() {
        if let Ok(raw) = fs::read_to_string(&path) {
            if let Ok(value) = serde_json::from_str::<Value>(&raw) {
                let fresh = value
                    .get("fetched_at")
                    .and_then(|v| v.as_u64())
                    .and_then(|fetched_at| {
                        SystemTime::now()
                            .duration_since(UNIX_EPOCH)
                            .ok()
                            .map(|d| d.as_secs().saturating_sub(fetched_at) <= CACHE_TTL_SECS)
                    })
                    .unwrap_or(false);

                if fresh {
                    if let Some(arr) = value.get("themes").and_then(|v| v.as_array()) {
                        let mut cached = Vec::with_capacity(arr.len());
                        for item in arr {
                            let Some(name) = item.get("name").and_then(|v| v.as_str()) else {
                                continue;
                            };
                            let Some(full_name) = item.get("full_name").and_then(|v| v.as_str())
                            else {
                                continue;
                            };
                            let Some(author) = item.get("author").and_then(|v| v.as_str()) else {
                                continue;
                            };
                            let Some(repo) = item.get("repo").and_then(|v| v.as_str()) else {
                                continue;
                            };
                            let Some(stars) = item.get("stars").and_then(|v| v.as_u64()) else {
                                continue;
                            };
                            let Some(preview_image) =
                                item.get("preview_image").and_then(|v| v.as_str())
                            else {
                                continue;
                            };
                            cached.push(Theme {
                                name: name.to_string(),
                                full_name: full_name.to_string(),
                                description: item
                                    .get("description")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or_default()
                                    .to_string(),
                                author: author.to_string(),
                                repo: repo.to_string(),
                                stars,
                                preview_image: preview_image.to_string(),
                            });
                        }
                        themes = Some(cached);
                    }
                }
            }
        }
    }

    let mut themes = themes.unwrap_or_else(|| {
        let mut candidates = Vec::new();

        for page in 1..=SEARCH_PAGES {
            let url = format!(
                "https://api.github.com/search/repositories?q=omarchy-theme+in:name+fork:false&sort=stars&order=desc&per_page=100&page={page}"
            );
            let output = Command::new("curl")
                .args([
                    "-fsSL",
                    "-A",
                    "cOMtrol",
                    "-H",
                    "Accept: application/vnd.github+json",
                    &url,
                ])
                .output();

            let Ok(output) = output else {
                break;
            };
            if !output.status.success() {
                break;
            }

            let Ok(body) = serde_json::from_slice::<Value>(&output.stdout) else {
                break;
            };
            let Some(items) = body.get("items").and_then(|v| v.as_array()) else {
                break;
            };
            if items.is_empty() {
                break;
            }

            for item in items {
                let full_name = item
                    .get("full_name")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default();
                if full_name.is_empty() {
                    continue;
                }
                let default_branch = item
                    .get("default_branch")
                    .and_then(|v| v.as_str())
                    .unwrap_or("main");
                candidates.push((
                    Theme {
                        name: item
                            .get("name")
                            .and_then(|v| v.as_str())
                            .unwrap_or(full_name)
                            .to_string(),
                        full_name: full_name.to_string(),
                        description: item
                            .get("description")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        author: item
                            .get("owner")
                            .and_then(|o| o.get("login"))
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        repo: item
                            .get("clone_url")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default()
                            .to_string(),
                        stars: item
                            .get("stargazers_count")
                            .and_then(|v| v.as_u64())
                            .unwrap_or(0),
                        preview_image: String::new(),
                    },
                    default_branch.to_string(),
                ));
            }
        }

        let mut fetched = Vec::new();

        for chunk in candidates.chunks(32) {
            std::thread::scope(|scope| {
                let handles: Vec<_> = chunk
                    .iter()
                    .map(|(theme, default_branch)| {
                        scope.spawn(|| {
                            let mut branches = vec![default_branch.as_str()];
                            for b in ["main", "master"] {
                                if !branches.contains(&b) {
                                    branches.push(b);
                                }
                            }

                            for branch in branches {
                                let url = format!(
                                    "https://raw.githubusercontent.com/{}/{}/preview.png",
                                    theme.full_name, branch
                                );
                                let ok = Command::new("curl")
                                    .args(["-fsSI", "-o", "/dev/null", "-A", "cOMtrol", &url])
                                    .status()
                                    .map(|s| s.success())
                                    .unwrap_or(false);
                                if ok {
                                    let mut found = theme.clone();
                                    found.preview_image = url;
                                    return Some(found);
                                }
                            }
                            None
                        })
                    })
                    .collect();

                for handle in handles {
                    if let Ok(Some(theme)) = handle.join() {
                        fetched.push(theme);
                    }
                }
            });
        }

        fetched.sort_by(|a, b| b.stars.cmp(&a.stars));

        if let Some(path) = cache_path() {
            if let Some(parent) = path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            let items: Vec<Value> = fetched
                .iter()
                .map(|t| {
                    json!({
                        "name": t.name,
                        "full_name": t.full_name,
                        "description": t.description,
                        "author": t.author,
                        "repo": t.repo,
                        "stars": t.stars,
                        "preview_image": t.preview_image,
                    })
                })
                .collect();
            let body = json!({
                "fetched_at": now,
                "themes": items,
            });
            if let Ok(text) = serde_json::to_string_pretty(&body) {
                let _ = fs::write(path, text);
            }
        }

        fetched
    });

    themes.sort_by(|a, b| b.stars.cmp(&a.stars));

    let q = query.trim().to_lowercase();
    if q.is_empty() {
        themes.truncate(TOP_N);
        return themes;
    }

    themes
        .into_iter()
        .filter(|t| {
            let haystack =
                format!("{} {} {} {}", t.name, t.full_name, t.description, t.author).to_lowercase();
            haystack.contains(&q)
        })
        .collect()
}

fn cache_path() -> Option<PathBuf> {
    let home = env::var_os("HOME")?;
    Some(PathBuf::from(home).join(".cache/comtrol/themes.json"))
}
