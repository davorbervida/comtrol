use std::collections::HashSet;
use std::process::Command;

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct Package {
    pub name: String,
    pub version: String,
    pub description: String,
    pub repo: String,
    pub installed: bool,
}

/// Search packages installed from pacman sync repositories (excludes AUR).
///
/// Empty `query` returns all local packages. Otherwise filters by name and
/// description.
/// Returns a JSON array.
pub fn local(query: &str) -> String {
    let tokens = query_tokens(query);
    let packages: Vec<_> = crate::control::system::packages::collect()
        .into_iter()
        .filter(|p| matches_tokens(&p.name, &p.description, &tokens))
        .collect();
    super::to_json(&packages)
}

/// Search pacman sync repositories.
///
/// An empty `query` lists packages from the `omarchy` repository.
/// A non-empty `query` searches all sync repos (name and description).
/// Returns a JSON array.
pub fn web(query: &str) -> String {
    super::to_json(&web_items(query))
}

fn web_items(query: &str) -> Vec<Package> {
    let query = query.trim();
    if query.is_empty() {
        return omarchy_repo_packages();
    }

    let tokens = query_tokens(query);
    if tokens.is_empty() {
        return Vec::new();
    }

    // pacman -Ss ANDs each argument against name+description. Passing
    // "firefox developer" as one string misses firefox-developer-edition.
    let mut args = vec!["-Ss".to_string(), "--".to_string()];
    args.extend(tokens.iter().cloned());

    let Ok(output) = Command::new("pacman").args(&args).output() else {
        return Vec::new();
    };

    let mut packages = parse_ss_output(&String::from_utf8_lossy(&output.stdout));
    packages.retain(|p| matches_tokens(&p.name, &p.description, &tokens));
    packages.sort_by(|a, b| a.name.cmp(&b.name));
    packages
}

fn omarchy_repo_packages() -> Vec<Package> {
    let Ok(installed_out) = Command::new("pacman").args(["-Qq"]).output() else {
        return Vec::new();
    };
    let installed: HashSet<&str> = std::str::from_utf8(&installed_out.stdout)
        .unwrap_or_default()
        .lines()
        .collect();

    let Ok(output) = Command::new("sh")
        .args([
            "-c",
            "zstd -d -c /var/lib/pacman/sync/omarchy.db | tar -xO --wildcards '*/desc'",
        ])
        .output()
    else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let mut packages = Vec::new();

    for chunk in text.split("%FILENAME%\n").filter(|c| !c.is_empty()) {
        let Some(name) = desc_field(chunk, "NAME") else {
            continue;
        };
        let Some(version) = desc_field(chunk, "VERSION") else {
            continue;
        };
        let description = desc_field(chunk, "DESC").unwrap_or_default().to_string();

        packages.push(Package {
            name: name.to_string(),
            version: version.to_string(),
            description,
            repo: "omarchy".to_string(),
            installed: installed.contains(name),
        });
    }

    packages.sort_by(|a, b| a.name.cmp(&b.name));
    packages
}

fn parse_ss_output(stdout: &str) -> Vec<Package> {
    let mut packages = Vec::new();
    let mut lines = stdout.lines().peekable();

    while let Some(line) = lines.next() {
        if line.is_empty() || line.starts_with(' ') || line.starts_with('\t') {
            continue;
        }

        let Some((repo_name, rest)) = line.split_once(' ') else {
            continue;
        };
        let Some((repo, name)) = repo_name.split_once('/') else {
            continue;
        };

        let rest = rest.trim();
        let installed = rest.contains("[installed");
        let version = rest
            .split_whitespace()
            .next()
            .unwrap_or_default()
            .to_string();

        let description = match lines.peek() {
            Some(next) if next.starts_with(' ') || next.starts_with('\t') => {
                lines.next().unwrap().trim().to_string()
            }
            _ => String::new(),
        };

        packages.push(Package {
            name: name.to_string(),
            version,
            description,
            repo: repo.to_string(),
            installed,
        });
    }

    packages
}

fn query_tokens(query: &str) -> Vec<String> {
    query
        .split_whitespace()
        .filter(|t| !t.is_empty())
        .map(|t| t.to_lowercase())
        .collect()
}

fn matches_tokens(name: &str, description: &str, tokens: &[String]) -> bool {
    if tokens.is_empty() {
        return true;
    }
    let hay = format!(
        "{} {}",
        normalize_pkg_text(name),
        normalize_pkg_text(description)
    );
    tokens.iter().all(|t| hay.contains(&normalize_pkg_text(t)))
}

fn normalize_pkg_text(s: &str) -> String {
    s.to_lowercase().replace(['-', '_'], " ")
}

fn desc_field<'a>(src: &'a str, key: &str) -> Option<&'a str> {
    let header = format!("%{key}%\n");
    let i = src.find(&header)?;
    let rest = &src[i + header.len()..];
    let end = rest.find('\n').unwrap_or(rest.len());
    let value = rest[..end].trim();
    (!value.is_empty()).then_some(value)
}
