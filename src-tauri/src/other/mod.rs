#[cfg(feature = "telemetry")]
pub mod telemetry;

pub mod rss;

/// Returns true when `url` is a web or mail link that is safe to hand to the
/// system opener. Anything else (file paths, custom schemes) could launch a
/// local program from renderer-controlled input.
pub fn is_openable_link(url: &str) -> bool {
    url::Url::parse(url)
        .map(|parsed| matches!(parsed.scheme(), "http" | "https" | "mailto"))
        .unwrap_or(false)
}

#[tauri::command]
pub fn open_link(url: String) -> Result<(), tauri::Error> {
    if !is_openable_link(&url) {
        return Err(tauri::Error::Anyhow(anyhow::anyhow!(
            "Refusing to open non-web link"
        )));
    }
    open::that_detached(url).map_err(tauri::Error::from)
}

#[cfg(test)]
mod tests {
    use super::is_openable_link;

    #[test]
    fn open_link_accepts_only_web_and_mail_schemes() {
        assert!(is_openable_link("https://modrinth.com/mod/sodium"));
        assert!(is_openable_link("http://127.0.0.1:1420/"));
        assert!(is_openable_link("mailto:hello@example.invalid"));
        assert!(!is_openable_link("file:///etc/passwd"));
        assert!(!is_openable_link("C:\\Windows\\System32\\cmd.exe"));
        assert!(!is_openable_link("/usr/bin/env"));
        assert!(!is_openable_link("javascript:alert(1)"));
        assert!(!is_openable_link(""));
    }
}
