mod search;
mod system;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if !args.is_empty() {
        run_search(&args.join(" "));
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
        run_search(query);
    }
}

fn run_search(query: &str) {
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
