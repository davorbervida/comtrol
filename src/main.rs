mod remove;
mod search;
mod system;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let themes_mode = args.first().is_some_and(|a| a == "themes");
    let query = if themes_mode {
        args.get(1..).unwrap_or(&[]).join(" ")
    } else {
        args.join(" ")
    };

    if themes_mode {
        run_theme_search(&query);
        return;
    }

    if !args.is_empty() {
        run_plugin_search(&query);
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
        run_plugin_search(query);
    }
}

fn run_plugin_search(query: &str) {
    let plugins = search::plugins::search(query);
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

fn run_theme_search(query: &str) {
    let themes = search::themes::search(query);
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
