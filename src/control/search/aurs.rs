use std::collections::HashSet;
use std::process::Command;

use serde_json::Value;

#[derive(Debug, Clone)]
pub struct AurPackage {
    pub name: String,
    pub version: String,
    pub description: String,
    pub votes: u64,
    pub popularity: f64,
    pub maintainer: Option<String>,
    pub url: String,
    pub installed: bool,
}

/// Search foreign packages installed from the AUR (or other non-sync sources).
///
/// Empty `query` returns all local AUR packages. Otherwise filters by name and
/// description.
pub fn local(query: &str) -> Vec<crate::control::system::aurs::AurPackage> {
    let q = query.trim().to_lowercase();
    crate::control::system::aurs::load_all()
        .into_iter()
        .filter(|p| {
            q.is_empty()
                || p.name.to_lowercase().contains(&q)
                || p.description.to_lowercase().contains(&q)
        })
        .collect()
}

/// Search the Arch User Repository via the AUR RPC API.
///
/// An empty `query` defaults to `"omarchy"`.
pub fn web(query: &str) -> Vec<AurPackage> {
    let query = if query.trim().is_empty() {
        "omarchy"
    } else {
        query.trim()
    };

    let url = format!("https://aur.archlinux.org/rpc/v5/search/{query}");
    let Ok(output) = Command::new("curl").args(["-fsSL", &url]).output() else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }

    let Ok(json) = serde_json::from_slice::<Value>(&output.stdout) else {
        return Vec::new();
    };
    let Some(results) = json.get("results").and_then(|v| v.as_array()) else {
        return Vec::new();
    };

    let installed: HashSet<String> = Command::new("pacman")
        .args(["-Qmq"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default();

    let mut packages = Vec::new();

    for pkg in results {
        let name = pkg
            .get("Name")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        if name.is_empty() {
            continue;
        }

        packages.push(AurPackage {
            name: name.to_string(),
            version: pkg
                .get("Version")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            description: pkg
                .get("Description")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            votes: pkg
                .get("NumVotes")
                .and_then(|v| v.as_u64())
                .unwrap_or(0),
            popularity: pkg
                .get("Popularity")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0),
            maintainer: pkg
                .get("Maintainer")
                .and_then(|v| v.as_str())
                .map(str::to_string),
            url: pkg
                .get("URL")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string(),
            installed: installed.contains(name),
        });
    }

    packages
}
