mod control;

use control::{search, system};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();

    if args.first().is_some_and(|a| a == "themes") {
        match args.get(1).map(String::as_str) {
            Some("local") => run_theme_local_search(&args.get(2..).unwrap_or(&[]).join(" ")),
            Some("web") => run_theme_web_search(&args.get(2..).unwrap_or(&[]).join(" ")),
            _ => run_theme_web_search(&args.get(1..).unwrap_or(&[]).join(" ")),
        }
        return;
    }

    if args.first().is_some_and(|a| a == "plugins") {
        match args.get(1).map(String::as_str) {
            Some("local") => run_plugin_local_search(&args.get(2..).unwrap_or(&[]).join(" ")),
            Some("web") => run_plugin_web_search(&args.get(2..).unwrap_or(&[]).join(" ")),
            _ => run_plugin_web_search(&args.get(1..).unwrap_or(&[]).join(" ")),
        }
        return;
    }

    if args.first().is_some_and(|a| a == "packages") {
        match args.get(1).map(String::as_str) {
            Some("local") => run_package_local_search(&args.get(2..).unwrap_or(&[]).join(" ")),
            Some("web") => run_package_web_search(&args.get(2..).unwrap_or(&[]).join(" ")),
            _ => run_package_web_search(&args.get(1..).unwrap_or(&[]).join(" ")),
        }
        return;
    }

    if args.first().is_some_and(|a| a == "aurs") {
        match args.get(1).map(String::as_str) {
            Some("local") => run_aur_local_search(&args.get(2..).unwrap_or(&[]).join(" ")),
            Some("web") => run_aur_web_search(&args.get(2..).unwrap_or(&[]).join(" ")),
            _ => run_aur_web_search(&args.get(1..).unwrap_or(&[]).join(" ")),
        }
        return;
    }

    let query = args.join(" ");

    if !args.is_empty() {
        run_plugin_web_search(&query);
        return;
    }

    println!("Plugin search — type a query (empty = all, q = quit)");
    loop {
        eprint!("> ");
        let mut input = String::new();
        if std::io::stdin().read_line(&mut input).is_err() {
            break;
        }
        let query = input.trim();
        if query.eq_ignore_ascii_case("q") || query.eq_ignore_ascii_case("quit") {
            break;
        }
        run_plugin_web_search(query);
    }
}

fn run_aur_local_search(query: &str) {
    let packages = search::aurs::local(query);
    println!("{} result(s)\n", packages.len());
    for p in &packages {
        let reason = match p.reason {
            system::aurs::InstallReason::Explicit => "explicit",
            system::aurs::InstallReason::Dependency => "dependency",
        };
        println!("{}  {}  ({reason})", p.name, p.version);
        if !p.description.is_empty() {
            println!("  {}", p.description);
        }
    }
    println!();
}

fn run_aur_web_search(query: &str) {
    let packages = search::aurs::web(query);
    println!("{} result(s)\n", packages.len());
    for p in &packages {
        let flag = if p.installed { " [installed]" } else { "" };
        println!(
            "{}  {}{flag}  votes={} popularity={:.2}",
            p.name, p.version, p.votes, p.popularity
        );
        if !p.description.is_empty() {
            println!("  {}", p.description);
        }
        if !p.url.is_empty() {
            println!("  {}", p.url);
        }
    }
    println!();
}

fn run_package_local_search(query: &str) {
    let packages = search::packages::local(query);
    println!("{} result(s)\n", packages.len());
    for p in &packages {
        let reason = match p.reason {
            system::packages::InstallReason::Explicit => "explicit",
            system::packages::InstallReason::Dependency => "dependency",
        };
        println!("{}  {}  ({reason})", p.name, p.version);
        if !p.description.is_empty() {
            println!("  {}", p.description);
        }
    }
    println!();
}

fn run_package_web_search(query: &str) {
    let packages = search::packages::web(query);
    println!("{} result(s)\n", packages.len());
    for p in &packages {
        let flag = if p.installed { " [installed]" } else { "" };
        println!("{}/{}  {}{flag}", p.repo, p.name, p.version);
        if !p.description.is_empty() {
            println!("  {}", p.description);
        }
    }
    println!();
}

fn run_plugin_local_search(query: &str) {
    let plugins = search::plugins::local(query);
    println!("{} result(s)\n", plugins.len());
    for p in &plugins {
        let kind = match p.source {
            system::plugins::PluginSource::User => "user",
            system::plugins::PluginSource::FirstParty => "preinstalled",
        };
        println!("{}  —  {} ({kind})  {}", p.id, p.name, p.path);
        if !p.description.is_empty() {
            println!("  {}", p.description);
        }
        if let Some(preview) = &p.preview {
            println!("  {preview}");
        }
    }
    println!();
}

fn run_plugin_web_search(query: &str) {
    let plugins = search::plugins::web(query);
    println!("{} result(s)\n", plugins.len());
    for p in &plugins {
        println!(
            "{}  —  {}  [{}]  hearts={} views={} copies={} stars={}",
            p.id, p.name, p.category, p.hearts, p.views, p.copies, p.stars
        );
        if !p.description.is_empty() {
            println!("  {}", p.description);
        }
        if let Some(url) = &p.preview_image {
            println!("  {url}");
        }
    }
    println!();
}

fn run_theme_local_search(query: &str) {
    let themes = search::themes::local(query);
    println!("{} result(s)\n", themes.len());
    for t in &themes {
        let kind = match t.source {
            system::themes::ThemeSource::User => "user",
            system::themes::ThemeSource::FirstParty => "preinstalled",
        };
        println!("{}  —  {} ({kind})", t.name, t.path);
        if let Some(preview) = &t.preview {
            println!("  {preview}");
        }
    }
    println!();
}

fn run_theme_web_search(query: &str) {
    let themes = search::themes::web(query);
    println!("{} result(s)\n", themes.len());
    for t in &themes {
        println!("{}  —  {}  stars={}", t.full_name, t.name, t.stars);
        if !t.description.is_empty() {
            println!("  {}", t.description);
        }
        println!("  {}", t.repo);
        println!("  {}", t.preview_image);
    }
    println!();
}
