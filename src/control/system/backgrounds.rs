use std::env;
use std::fs;
use std::path::Path;

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct Background {
    pub path: String,
}

/// List image files under the current theme's backgrounds directory as JSON.
pub fn current() -> String {
    let home = env::var("HOME").expect("Home is not set");
    let dir = format!("{home}/.local/state/omarchy/current/theme/backgrounds");

    let mut backgrounds = Vec::new();
    collect_images_from_dir(Path::new(&dir), &mut backgrounds);
    to_sorted_json(backgrounds)
}

/// List background images from all first-party and user theme packages as JSON.
pub fn themes() -> String {
    to_sorted_json(collect_theme_backgrounds())
}

/// List image files under ~/Pictures/Wallpapers as JSON.
pub fn wallpapers() -> String {
    to_sorted_json(collect_wallpaper_backgrounds())
}

/// List theme backgrounds and ~/Pictures/Wallpapers images together as JSON.
pub fn all() -> String {
    let mut backgrounds = collect_theme_backgrounds();
    backgrounds.extend(collect_wallpaper_backgrounds());
    to_sorted_json(backgrounds)
}

fn collect_theme_backgrounds() -> Vec<Background> {
    let home = env::var("HOME").expect("Home is not set");
    let omarchy = env::var("OMARCHY_PATH").unwrap_or_else(|_| "/usr/share/omarchy".to_string());

    let mut backgrounds = Vec::new();
    for root in [
        format!("{home}/.config/omarchy/themes"),
        format!("{omarchy}/themes"),
    ] {
        let Ok(entries) = fs::read_dir(&root) else {
            continue;
        };
        for entry in entries.flatten() {
            let theme_dir = entry.path();
            if !theme_dir.is_dir() {
                continue;
            }
            collect_images_from_dir(&theme_dir.join("backgrounds"), &mut backgrounds);
        }
    }
    backgrounds
}

fn collect_wallpaper_backgrounds() -> Vec<Background> {
    let home = env::var("HOME").expect("Home is not set");
    let dir = format!("{home}/Pictures/Wallpapers");

    let mut backgrounds = Vec::new();
    collect_images_from_dir(Path::new(&dir), &mut backgrounds);
    backgrounds
}

fn to_sorted_json(mut backgrounds: Vec<Background>) -> String {
    backgrounds.sort_by(|a, b| a.path.cmp(&b.path));
    super::to_json(&backgrounds)
}

fn collect_images_from_dir(dir: &Path, out: &mut Vec<Background>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() || !is_image(&path) {
            continue;
        }
        out.push(Background {
            path: path.to_string_lossy().to_string(),
        });
    }
}

fn is_image(path: &Path) -> bool {
    path.extension()
        .and_then(|e| e.to_str())
        .is_some_and(|ext| {
            matches!(
                ext.to_ascii_lowercase().as_str(),
                "jpg" | "jpeg" | "png" | "gif" | "bmp" | "webp"
            )
        })
}
