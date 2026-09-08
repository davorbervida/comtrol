use crate::control::system::bindings::{self, BindingType};

/// Search installed Hyprland/Omarchy keybindings.
///
/// An empty `query` returns all bind/toggle entries. Otherwise matches against
/// keys, action, and description (case-insensitive; spaces ignored; `_` and
/// `-` treated the same), so both `"SUPER + SPACE"` and `"omarchy_menu"` work.
/// Returns a JSON array.
pub fn search(query: &str) -> String {
    let q = normalize(query);

    let bindings: Vec<_> = bindings::collect()
        .into_iter()
        .filter(|b| b.r#type != BindingType::Unbind)
        .filter(|b| {
            q.is_empty()
                || normalize(&b.keys).contains(&q)
                || normalize(&b.action).contains(&q)
                || normalize(&b.description).contains(&q)
        })
        .collect();
    super::to_json(&bindings)
}

fn normalize(s: &str) -> String {
    s.chars()
        .filter(|c| !c.is_whitespace())
        .map(|c| match c {
            '_' => '-',
            c => c.to_ascii_lowercase(),
        })
        .collect()
}
