mod control;

use control::{remove, search, system};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() || args.iter().any(|a| a == "-h" || a == "--help") {
        print_usage();
        return;
    }

    match run(&args) {
        Ok(()) => {}
        Err(err) => {
            eprintln!("error: {err}");
            eprintln!();
            print_usage();
            std::process::exit(1);
        }
    }
}

fn run(args: &[String]) -> Result<(), String> {
    let mut action: Option<Action> = None;
    let mut domain: Option<Domain> = None;
    let mut mode: Option<Mode> = None;
    let mut wallpaper_source: Option<WallpaperSource> = None;
    let mut values: Vec<String> = Vec::new();

    for arg in args {
        match arg.as_str() {
            "-s" | "--search" => set_once(&mut action, Action::Search, "action")?,
            "-r" | "--remove" => set_once(&mut action, Action::Remove, "action")?,
            "-v" | "--view" | "--system" => set_once(&mut action, Action::View, "action")?,

            "-l" | "--local" => set_once(&mut mode, Mode::Local, "mode")?,
            "-w" | "--web" => set_once(&mut mode, Mode::Web, "mode")?,

            "-current" | "--current" => {
                set_once(&mut wallpaper_source, WallpaperSource::Current, "background source")?
            }
            "-all" | "--all" => {
                set_once(&mut wallpaper_source, WallpaperSource::All, "background source")?
            }

            "-theme" | "-themes" | "--theme" | "--themes" => {
                if domain == Some(Domain::Background) {
                    set_once(&mut wallpaper_source, WallpaperSource::Themes, "background source")?;
                } else {
                    set_once(&mut domain, Domain::Themes, "domain")?;
                }
            }
            "-plugin" | "-plugins" | "--plugin" | "--plugins" => {
                set_once(&mut domain, Domain::Plugins, "domain")?
            }
            "-package" | "-packages" | "-pkg" | "--package" | "--packages" => {
                set_once(&mut domain, Domain::Packages, "domain")?
            }
            "-aur" | "-aurs" | "--aur" | "--aurs" => {
                set_once(&mut domain, Domain::Aurs, "domain")?
            }
            "-binding" | "-bindings" | "-bind" | "--binding" | "--bindings" => {
                set_once(&mut domain, Domain::Bindings, "domain")?
            }
            "-webapp" | "-webapps" | "-web-apps" | "--webapp" | "--webapps" => {
                set_once(&mut domain, Domain::WebApps, "domain")?
            }
            "-background" | "-backgrounds" | "--background" | "--backgrounds" => {
                set_once(&mut domain, Domain::Background, "domain")?
            }
            "-wallpaper" | "-wallpapers" | "--wallpaper" | "--wallpapers" => {
                set_once(
                    &mut wallpaper_source,
                    WallpaperSource::Wallpapers,
                    "background source",
                )?
            }

            "-h" | "--help" => {
                print_usage();
                return Ok(());
            }

            other if other.starts_with('-') => {
                // Allow `-momentum` style values from examples like: -r -theme -momentum
                let value = other.trim_start_matches('-');
                if value.is_empty() {
                    return Err(format!("unknown flag: {other}"));
                }
                values.push(value.to_string());
            }
            other => values.push(other.to_string()),
        }
    }

    let action = action.ok_or("missing action (-s search, -r remove, -v view)")?;
    let domain = domain.ok_or(
        "missing domain (-theme, -plugin, -package, -aur, -binding, -webapp, -background)",
    )?;

    match action {
        Action::Search => {
            let query = values.join(" ");
            let mode = mode.unwrap_or(Mode::Web);
            let json = match (domain, mode) {
                (Domain::Themes, Mode::Local) => search::themes::local(&query),
                (Domain::Themes, Mode::Web) => search::themes::web(&query),
                (Domain::Plugins, Mode::Local) => search::plugins::local(&query),
                (Domain::Plugins, Mode::Web) => search::plugins::web(&query),
                (Domain::Packages, Mode::Local) => search::packages::local(&query),
                (Domain::Packages, Mode::Web) => search::packages::web(&query),
                (Domain::Aurs, Mode::Local) => search::aurs::local(&query),
                (Domain::Aurs, Mode::Web) => search::aurs::web(&query),
                (Domain::Bindings, _) => search::bindings::search(&query),
                (Domain::WebApps, _) => {
                    return Err("search is not available for webapps (use -v -webapp)".into());
                }
                (Domain::Background, _) => {
                    return Err(
                        "search is not available for background (use -v -background -current|-themes|-wallpapers|-all)".into(),
                    );
                }
            };
            println!("{json}");
        }
        Action::View => {
            if mode.is_some() {
                return Err("view (-v) does not take -l/-w".into());
            }
            let json = match domain {
                Domain::Themes => system::themes::load_all(),
                Domain::Plugins => system::plugins::load_all(),
                Domain::Packages => system::packages::load_all(),
                Domain::Aurs => system::aurs::load_all(),
                Domain::Bindings => system::bindings::load_all(),
                Domain::WebApps => system::web_apps::load_all(),
                Domain::Background => {
                    let source = match wallpaper_source {
                        Some(source) => source,
                        None => match values.join(" ").as_str() {
                            "current" => WallpaperSource::Current,
                            "themes" => WallpaperSource::Themes,
                            "wallpapers" => WallpaperSource::Wallpapers,
                            "all" => WallpaperSource::All,
                            "" => {
                                return Err(
                                    "background view requires a source (-current, -themes, -wallpapers, -all)".into(),
                                );
                            }
                            other => {
                                return Err(format!(
                                    "unknown background source: {other} (use -current, -themes, -wallpapers, -all)"
                                ));
                            }
                        },
                    };
                    match source {
                        WallpaperSource::Current => system::backgrounds::current(),
                        WallpaperSource::Themes => system::backgrounds::themes(),
                        WallpaperSource::Wallpapers => system::backgrounds::wallpapers(),
                        WallpaperSource::All => system::backgrounds::all(),
                    }
                }
            };
            println!("{json}");
        }
        Action::Remove => {
            if mode.is_some() {
                return Err("remove (-r) does not take -l/-w".into());
            }
            if values.is_empty() {
                return Err("remove requires at least one name/id (e.g. -r -theme momentum)".into());
            }
            match domain {
                Domain::Themes => remove::themes::remove(&values),
                Domain::Plugins => remove::plugins::remove(&values),
                Domain::Packages => remove::packages::remove(&values),
                Domain::Aurs => remove::aurs::remove(&values),
                Domain::Bindings => remove::bindings::remove(&values),
                Domain::WebApps => remove::web_apps::remove(&values),
                Domain::Background => {
                    return Err("remove is not available for background".into());
                }
            }
        }
    }

    Ok(())
}

fn set_once<T>(slot: &mut Option<T>, value: T, label: &str) -> Result<(), String> {
    if slot.is_some() {
        return Err(format!("duplicate {label}"));
    }
    *slot = Some(value);
    Ok(())
}

#[derive(Clone, Copy)]
enum Action {
    Search,
    Remove,
    View,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Domain {
    Themes,
    Plugins,
    Packages,
    Aurs,
    Bindings,
    WebApps,
    Background,
}

#[derive(Clone, Copy)]
enum WallpaperSource {
    Current,
    Themes,
    Wallpapers,
    All,
}

#[derive(Clone, Copy)]
enum Mode {
    Local,
    Web,
}

fn print_usage() {
    eprintln!(
        "\
cOMtrol — Omarchy control CLI

Usage:
  cOMtrol -s <domain> [-l|-w] [query...]
  cOMtrol -v <domain>
  cOMtrol -v -background <-current|-themes|-wallpapers|-all>
  cOMtrol -r <domain> <name...>

Actions:
  -s, --search          Search (JSON stdout)
  -v, --view, --system  List installed / system state (JSON stdout)
  -r, --remove          Remove by name/id

Domains:
  -theme, -plugin, -package, -aur, -binding, -webapp, -background

Background sources (with -v -background):
  -current              Current theme backgrounds
  -themes               All theme package backgrounds
  -wallpapers           ~/Pictures/Wallpapers
  -all                  Themes + wallpapers together

Search mode:
  -l, --local           Installed / local
  -w, --web             Remote catalog (default for -s)

Examples:
  cOMtrol -s -aur -l reall good
  cOMtrol -s -theme -w
  cOMtrol -v -plugin
  cOMtrol --system -background -current
  cOMtrol -v -background -themes
  cOMtrol -v -background -wallpapers
  cOMtrol -v -background -all
  cOMtrol -r -theme momentum
  cOMtrol -r -theme -momentum"
    );
}
