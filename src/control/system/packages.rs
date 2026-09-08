use std::collections::HashSet;
use std::fs;
use std::path::Path;
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InstallReason {
    Explicit,
    Dependency,
}

#[derive(Debug, Clone)]
pub struct Package {
    pub name: String,
    pub version: String,
    pub description: String,
    pub reason: InstallReason,
}

/// Load packages installed from pacman sync repositories (excludes AUR/foreign).
pub fn load_all() -> Vec<Package> {
    let Ok(output) = Command::new("pacman").args(["-Qnq"]).output() else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }

    let native: HashSet<&str> = std::str::from_utf8(&output.stdout)
        .unwrap_or_default()
        .lines()
        .collect();

    let local = Path::new("/var/lib/pacman/local");
    let Ok(entries) = fs::read_dir(local) else {
        return Vec::new();
    };

    let mut packages = Vec::new();

    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }

        let Ok(src) = fs::read_to_string(path.join("desc")) else {
            continue;
        };

        let Some(name) = desc_field(&src, "NAME") else {
            continue;
        };
        if !native.contains(name) {
            continue;
        }

        let Some(version) = desc_field(&src, "VERSION") else {
            continue;
        };

        let description = desc_field(&src, "DESC")
            .unwrap_or_default()
            .to_string();

        let reason = match desc_field(&src, "REASON") {
            Some("1") => InstallReason::Dependency,
            _ => InstallReason::Explicit,
        };

        packages.push(Package {
            name: name.to_string(),
            version: version.to_string(),
            description,
            reason,
        });
    }

    packages
}

fn desc_field<'a>(src: &'a str, key: &str) -> Option<&'a str> {
    let header = format!("%{key}%\n");
    let i = src.find(&header)?;
    let rest = &src[i + header.len()..];
    let end = rest.find('\n').unwrap_or(rest.len());
    let value = rest[..end].trim();
    (!value.is_empty()).then_some(value)
}
