use std::collections::HashSet;
use std::process::Command;

use serde::Serialize;
use serde_json::Value;

#[derive(Debug, Clone, Serialize)]
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
/// Returns a JSON array.
pub fn local(query: &str) -> String {
    let q = query.trim().to_lowercase();
    let packages: Vec<_> = crate::control::system::aurs::collect()
        .into_iter()
        .filter(|p| {
            q.is_empty()
                || p.name.to_lowercase().contains(&q)
                || p.description.to_lowercase().contains(&q)
        })
        .collect();
    super::to_json(&packages)
}

/// Search the Arch User Repository via the AUR RPC API.
///
/// An empty `query` defaults to `"omarchy"`.
/// Returns a JSON array.
pub fn web(query: &str) -> String {
    super::to_json(&web_items(query))
}

fn web_items(query: &str) -> Vec<AurPackage> {
    let raw = if query.trim().is_empty() {
        "omarchy".to_string()
    } else {
        query.trim().to_string()
    };

    let tokens: Vec<String> = raw
        .split_whitespace()
        .filter(|t| !t.is_empty())
        .map(|t| t.to_lowercase())
        .collect();
    if tokens.is_empty() {
        return Vec::new();
    }

    // "ungoogled chromium" → ungoogled-chromium (AUR names use hyphens).
    let search_arg = tokens.join("-");
    let mut results = aur_rpc_search(&search_arg);
    if results.is_empty() && tokens.len() > 1 {
        if let Some(fallback) = tokens.iter().max_by_key(|t| t.len()) {
            if *fallback != search_arg {
                results = aur_rpc_search(fallback);
            }
        }
    }

    let installed = installed_foreign();
    let mut packages = Vec::new();
    for pkg in results {
        let Some(parsed) = parse_aur_hit(&pkg, &installed) else {
            continue;
        };
        if tokens.iter().all(|t| package_matches(&parsed, t)) {
            packages.push(parsed);
        }
    }

    packages.sort_by(|a, b| a.name.cmp(&b.name));
    packages
}

fn installed_foreign() -> HashSet<String> {
    Command::new("pacman")
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
        .unwrap_or_default()
}

fn aur_rpc_search(arg: &str) -> Vec<Value> {
    if arg.chars().count() < 2 {
        return Vec::new();
    }

    let url = format!(
        "https://aur.archlinux.org/rpc/v5/search/{}?by=name-desc",
        encode_path_segment(arg)
    );
    let Ok(output) = Command::new("curl").args(["-fsSL", &url]).output() else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }

    let Ok(json) = serde_json::from_slice::<Value>(&output.stdout) else {
        return Vec::new();
    };
    json.get("results")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default()
}

fn parse_aur_hit(pkg: &Value, installed: &HashSet<String>) -> Option<AurPackage> {
    let name = pkg.get("Name").and_then(|v| v.as_str()).unwrap_or_default();
    if name.is_empty() {
        return None;
    }

    Some(AurPackage {
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
        votes: pkg.get("NumVotes").and_then(|v| v.as_u64()).unwrap_or(0),
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
    })
}

fn package_matches(pkg: &AurPackage, token: &str) -> bool {
    let needle = normalize_pkg_text(token);
    if needle.is_empty() {
        return true;
    }
    let hay = format!(
        "{} {}",
        normalize_pkg_text(&pkg.name),
        normalize_pkg_text(&pkg.description)
    );
    hay.contains(&needle)
}

fn normalize_pkg_text(s: &str) -> String {
    s.to_lowercase().replace(['-', '_'], " ")
}

fn encode_path_segment(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char)
            }
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}
