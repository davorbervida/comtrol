use std::env;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeSource {
    FirstParty,
    User,
}

#[derive(Debug, Clone)]
pub struct Theme {
    pub name: String,
    pub path: String,
    pub preview: Option<String>,
    pub ansi_colors: [Option<String>; 16],
    pub source: ThemeSource,
}

/// Load user-installed and first-party Omarchy themes.
pub fn load_all() -> Vec<Theme> {
    let home = env::var("HOME").expect("Home is not set");
    let omarchy = env::var("OMARCHY_PATH").unwrap_or_else(|_| "/usr/share/omarchy".to_string());

    let mut themes = collect_from(
        &PathBuf::from(format!("{home}/.config/omarchy/themes")),
        ThemeSource::User,
    );
    themes.extend(collect_from(
        &PathBuf::from(format!("{omarchy}/themes")),
        ThemeSource::FirstParty,
    ));
    themes
}

fn collect_from(dir: &Path, source: ThemeSource) -> Vec<Theme> {
    let Ok(entries) = fs::read_dir(dir) else {
        return Vec::new();
    };

    let mut themes = Vec::new();

    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }

        let name = entry.file_name().to_string_lossy().to_string();
        let path_str = path.to_string_lossy().to_string();

        let preview_path = path.join("preview.png");
        let preview = preview_path
            .is_file()
            .then(|| preview_path.to_string_lossy().to_string());

        let mut ansi_colors = std::array::from_fn(|_| None);
        if let Ok(src) = fs::read_to_string(path.join("colors.toml")) {
            for line in src.lines() {
                let line = line.trim();
                if line.is_empty() || line.starts_with('#') {
                    continue;
                }

                let Some((key, value)) = line.split_once('=') else {
                    continue;
                };

                let key = key.trim();
                let hex = value.trim().trim_matches('"').to_string();
                if !hex.starts_with('#') {
                    continue;
                }

                let index = if let Some(n) = key.strip_prefix("color") {
                    n.parse::<usize>().ok()
                } else {
                    match key {
                        "black" => Some(0),
                        "red" => Some(1),
                        "green" => Some(2),
                        "yellow" => Some(3),
                        "blue" => Some(4),
                        "magenta" | "purple" => Some(5),
                        "cyan" => Some(6),
                        "white" => Some(7),
                        "bright_black" => Some(8),
                        "bright_red" => Some(9),
                        "bright_green" => Some(10),
                        "bright_yellow" => Some(11),
                        "bright_blue" => Some(12),
                        "bright_magenta" | "bright_purple" => Some(13),
                        "bright_cyan" => Some(14),
                        "bright_white" => Some(15),
                        _ => None,
                    }
                };

                let Some(index) = index else {
                    continue;
                };
                if index > 15 {
                    continue;
                }

                // Prefer explicit colorN over named aliases.
                if key.starts_with("color") || ansi_colors[index].is_none() {
                    ansi_colors[index] = Some(hex);
                }
            }
        }

        themes.push(Theme {
            name,
            path: path_str,
            preview,
            ansi_colors,
            source,
        });
    }

    themes
}
