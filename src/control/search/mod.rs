pub mod aurs;
pub mod bindings;
pub mod packages;
pub mod plugins;
pub mod themes;

pub(crate) fn to_json<T: serde::Serialize>(value: &T) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| "[]".to_string())
}
