use std::env;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WebAppSource {
    FirstParty,
    User,
}

#[derive(Debug, Clone)]
pub struct WebApp {
    pub name: String,
    pub url: Option<String>,
    pub icon: String,
    pub path: String,
    pub source: WebAppSource,
}

/// Load user-installed and first-party Omarchy web apps.
pub fn load_all() -> Vec<WebApp> {
    let home = env::var("HOME").expect("Home is not set");
    let omarchy = env::var("OMARCHY_PATH").unwrap_or_else(|_| "/usr/share/omarchy".to_string());

    let mut apps = collect_from(
        &PathBuf::from(format!("{home}/.local/share/applications")),
        true,
        WebAppSource::User,
    );
    apps.extend(collect_from(
        &PathBuf::from(format!("{omarchy}/applications")),
        false,
        WebAppSource::FirstParty,
    ));
    apps
}

fn collect_from(dir: &Path, recursive: bool, source: WebAppSource) -> Vec<WebApp> {
    let mut apps = Vec::new();
    let mut stack = vec![dir.to_path_buf()];

    while let Some(current) = stack.pop() {
        let Ok(entries) = fs::read_dir(&current) else {
            continue;
        };

        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                if recursive {
                    stack.push(path);
                }
                continue;
            }

            let is_desktop = path
                .extension()
                .and_then(|s| s.to_str())
                .is_some_and(|ext| ext == "desktop");
            if !is_desktop {
                continue;
            }

            let Ok(src) = fs::read_to_string(&path) else {
                continue;
            };

            let Some(exec) = desktop_field(&src, "Exec") else {
                continue;
            };
            if !exec.contains("omarchy-launch-webapp") && !exec.contains("omarchy-webapp-handler")
            {
                continue;
            }

            let name = desktop_field(&src, "Name")
                .map(str::to_string)
                .unwrap_or_else(|| {
                    path.file_stem()
                        .and_then(|s| s.to_str())
                        .unwrap_or("unknown")
                        .to_string()
                });

            let icon = desktop_field(&src, "Icon")
                .unwrap_or_default()
                .to_string();

            let url = exec
                .strip_prefix("omarchy-launch-webapp")
                .map(|rest| {
                    let rest = rest.trim();
                    if let Some(rest) = rest.strip_prefix('"') {
                        rest.split('"').next().unwrap_or(rest).to_string()
                    } else {
                        rest.split_whitespace()
                            .next()
                            .unwrap_or(rest)
                            .to_string()
                    }
                })
                .filter(|u| !u.is_empty());

            apps.push(WebApp {
                name,
                url,
                icon,
                path: path.to_string_lossy().to_string(),
                source,
            });
        }
    }

    apps
}

fn desktop_field<'a>(src: &'a str, key: &str) -> Option<&'a str> {
    for line in src.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((k, value)) = line.split_once('=') else {
            continue;
        };
        if k == key {
            return Some(value.trim());
        }
    }
    None
}
