use std::collections::HashSet;
use std::process::Command;

use crate::system::packages;

/// Remove packages that were installed via pacman sync repositories.
///
/// Only names that appear in the installed native package list are
/// uninstalled. Others are skipped. Prints the exact packages that will be
/// removed before running `sudo pacman -R` (root password required).
pub fn remove<S: AsRef<str>>(packages: &[S]) {
    if packages.is_empty() {
        println!("No packages specified.");
        return;
    }

    let native: HashSet<String> = packages::load_all().into_iter().map(|p| p.name).collect();

    let mut to_remove: Vec<&str> = Vec::new();
    let mut skipped: Vec<&str> = Vec::new();

    for name in packages {
        let name = name.as_ref();
        if native.contains(name) {
            to_remove.push(name);
        } else {
            skipped.push(name);
        }
    }

    if !skipped.is_empty() {
        println!(
            "Skipping (not an installed pacman package): {}",
            skipped.join(", ")
        );
    }

    if to_remove.is_empty() {
        println!("No pacman packages to remove.");
        return;
    }

    println!("The following pacman packages will be uninstalled:");
    for name in &to_remove {
        println!("  {name}");
    }

    let status = Command::new("sudo")
        .arg("pacman")
        .arg("-R")
        .args(&to_remove)
        .status();

    match status {
        Ok(s) if s.success() => {
            println!("Done.");
            crate::remove::bindings::remove_related(&to_remove);
        }
        Ok(s) => eprintln!("pacman exited with status: {s}"),
        Err(e) => eprintln!("Failed to run sudo pacman: {e}"),
    }
}
