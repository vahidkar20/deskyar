//! DeskYar release feed.
//!
//! RustDesk's updater asks `api.rustdesk.com` for the newest release and then
//! rebuilds the asset name as `rustdesk-<version>-<arch>.exe`. Two things make
//! that unusable for a rebrand:
//!
//!   1. `common::check_software_update` returns immediately when
//!      `is_custom_client()` is true — i.e. for every build whose `APP_NAME`
//!      is not literally "RustDesk". Rebranded clients therefore never update.
//!   2. The asset naming and the release host are hard-wired to upstream.
//!
//! This module supplies the missing piece: it resolves the newest DeskYar
//! release from GitHub and reports it in the shape `updater.rs` already
//! understands (a `releases/tag/<tag>` URL). Everything downstream — download,
//! staging directory, `--update` handoff, service restart — is reused as-is.
//!
//! The repository is configurable so a fork can point at its own releases:
//!
//!   1. `DESKYAR_UPDATE_REPO` environment variable at runtime (useful for
//!      testing against a scratch repo), else
//!   2. `DESKYAR_UPDATE_REPO` at compile time (the release workflow sets it), else
//!   3. [`DEFAULT_REPO`].

use serde_json::Value;

/// Fallback when neither build-time nor runtime configuration is present.
/// Replace with the real `owner/repo` before publishing.
pub const DEFAULT_REPO: &str = "deskyar/deskyar";

/// GitHub rejects API requests that do not identify a client.
pub const USER_AGENT: &str = concat!("DeskYar/", env!("CARGO_PKG_VERSION"));

/// Resolve the `owner/repo` whose releases we track.
pub fn update_repo() -> String {
    if let Ok(value) = std::env::var("DESKYAR_UPDATE_REPO") {
        let value = value.trim().to_string();
        if !value.is_empty() {
            return value;
        }
    }
    option_env!("DESKYAR_UPDATE_REPO")
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| DEFAULT_REPO.to_string())
}

/// GitHub API endpoint for the newest published release.
pub fn api_url(repo: &str) -> String {
    format!("https://api.github.com/repos/{repo}/releases/latest")
}

/// Human-facing release page, used by the "download" action.
pub fn release_page(repo: &str, tag: &str) -> String {
    format!("https://github.com/{repo}/releases/tag/{tag}")
}

/// Strip the optional `v` prefix so `get_version_number` can parse the tag.
///
/// `get_version_number` splits on `.` and parses each part as an integer, so a
/// leading `v` would silently degrade to `0.0.0` and every release would look
/// older than the installed build.
pub fn normalize_version(tag: &str) -> String {
    tag.trim()
        .trim_start_matches('v')
        .trim_start_matches('V')
        .to_string()
}

/// Filename of the self-installing exe published with a release.
///
/// Must stay in sync with `updater.rs`, which builds the download URL from the
/// same parts, and with the release workflow that uploads the asset.
pub fn asset_name(version: &str) -> String {
    #[cfg(target_os = "windows")]
    let arch = crate::platform::windows::release_arch_suffix().unwrap_or("x86_64");
    #[cfg(not(target_os = "windows"))]
    let arch = "x86_64";
    format!("{}-{}-{}.exe", crate::get_app_name(), version, arch)
}

/// Whether auto-update should be considered on when the user never chose.
///
/// `allow-auto-update` is an `allow-` option, so `option2bool` only reads it as
/// enabled when it is literally `Y`. Nothing ships a default for it, which
/// leaves a fresh install with auto-update silently off. DeskYar wants new
/// installs to stay current, so "never configured" counts as enabled while an
/// explicit `N` from the settings page still wins.
pub fn auto_update_default() -> bool {
    hbb_common::config::Config::get_option(base::config::keys::OPTION_ALLOW_AUTO_UPDATE).is_empty()
}

/// Persist the auto-update preference the first time DeskYar runs.
///
/// `check_update` already treats "unset" as enabled, but the settings checkbox
/// renders the raw option value, so an unset key would show as "off" while
/// updates still happened. Writing the default once keeps the UI honest.
pub fn ensure_update_defaults() {
    if auto_update_default() {
        hbb_common::config::Config::set_option(
            base::config::keys::OPTION_ALLOW_AUTO_UPDATE.to_owned(),
            "Y".to_owned(),
        );
    }
}

/// Marker option recording that the product defaults below were applied.
///
/// Without it, every start would rewrite the options and silently undo a
/// deliberate change the user made in Settings.
pub const OPTION_DEFAULTS_APPLIED: &str = "deskyar-defaults-applied";

/// Apply DeskYar's product defaults exactly once per installation.
///
/// ## Why this exists
///
/// File transfer is the single most requested capability in a remote-support
/// tool, and the default here was fragile in two ways:
///
///   1. `enable-file-copy-paste` is stored in a *separate* `_default` config
///      file and defaults to `Y` only through a fallback in
///      `UserDefaultConfig::get`. If that file ever held `N` or `""` - for
///      example because an older build wrote it - the connecting client stops
///      sending `enable_file_transfer = Yes` in its `LoginRequest`, and the
///      remote side silently refuses the transfer with no visible reason.
///
///   2. `enable-file-transfer` is the *incoming* permission. It reads as
///      enabled when unset, but the settings checkbox shows the raw value, so
///      an empty value renders as an unticked box that does nothing when
///      clicked the first time.
///
/// Writing both explicitly on first run removes the ambiguity: the checkboxes
/// render ticked, and the client always asks for transfer permission.
///
/// The write happens once, guarded by [`OPTION_DEFAULTS_APPLIED`], so a user
/// who later unticks either box keeps that choice across restarts.
pub fn ensure_product_defaults() {
    use hbb_common::config::Config;
    // Runs outside the one-shot guard below: a machine can be upgraded from a
    // build that predates the salt long after the guard was written, and the
    // migration is idempotent (it no-ops once the ID is already salted).
    Config::migrate_auto_id();
    if Config::get_option(OPTION_DEFAULTS_APPLIED) == "Y" {
        return;
    }
    // Literal option names on purpose: `enable-file-transfer` lives in
    // `base::config::keys` while `enable-file-copy-paste` lives in
    // `hbb_common::config::keys`, and the two are easy to confuse. These
    // strings are the wire format and never change.
    for key in [
        // Incoming: this device accepts file transfers.
        "enable-file-transfer",
        // Outgoing: this client offers to transfer files.
        "enable-file-copy-paste",
    ] {
        if Config::get_option(key).is_empty() {
            Config::set_option(key.to_owned(), "Y".to_owned());
        }
    }
    Config::set_option(OPTION_DEFAULTS_APPLIED.to_owned(), "Y".to_owned());
}

/// A release as advertised by the GitHub API.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LatestRelease {
    /// Raw tag, e.g. `v1.5.1`. Needed verbatim for the download path.
    pub tag: String,
    /// Normalised version, e.g. `1.5.1`. Used for comparisons and filenames.
    pub version: String,
    /// Asset filenames attached to the release.
    pub assets: Vec<String>,
}

impl LatestRelease {
    /// True when the release carries the exe we know how to install.
    ///
    /// Checking this before advertising an update avoids the worst case: the
    /// client tells the user a new version exists, downloads a 404, and leaves
    /// a broken file behind.
    pub fn has_installable_asset(&self) -> bool {
        let expected = asset_name(&self.version);
        self.assets.iter().any(|name| name == &expected)
    }
}

/// Parse a `GET /repos/{owner}/{repo}/releases/latest` body.
pub fn parse_latest_release(body: &str) -> Option<LatestRelease> {
    let root: Value = serde_json::from_str(body).ok()?;
    let tag = root.get("tag_name")?.as_str()?.trim().to_string();
    if tag.is_empty() {
        return None;
    }
    let version = normalize_version(&tag);
    if version.is_empty() {
        return None;
    }
    let assets = root
        .get("assets")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.get("name").and_then(Value::as_str))
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default();
    Some(LatestRelease {
        tag,
        version,
        assets,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"{
        "tag_name": "v1.5.1",
        "name": "DeskYar 1.5.1",
        "assets": [
            {"name": "DeskYar-1.5.1-x86_64.exe", "size": 25900000},
            {"name": "DeskYar-1.5.1-aarch64.exe", "size": 24000000}
        ]
    }"#;

    #[test]
    fn strips_v_prefix() {
        assert_eq!(normalize_version("v1.5.1"), "1.5.1");
        assert_eq!(normalize_version("V1.5.1"), "1.5.1");
        assert_eq!(normalize_version(" 1.5.1 "), "1.5.1");
        assert_eq!(normalize_version("v"), "");
    }

    #[test]
    fn parses_tag_version_and_assets() {
        let release = parse_latest_release(SAMPLE).expect("should parse");
        assert_eq!(release.tag, "v1.5.1");
        assert_eq!(release.version, "1.5.1");
        assert_eq!(release.assets.len(), 2);
    }

    #[test]
    fn rejects_payloads_without_a_tag() {
        assert!(parse_latest_release(r#"{"assets": []}"#).is_none());
        assert!(parse_latest_release(r#"{"tag_name": "  "}"#).is_none());
        assert!(parse_latest_release("not json").is_none());
        assert!(parse_latest_release("").is_none());
    }

    #[test]
    fn tolerates_missing_assets() {
        let release = parse_latest_release(r#"{"tag_name": "1.2.3"}"#).expect("should parse");
        assert!(release.assets.is_empty());
        assert!(!release.has_installable_asset());
    }

    #[test]
    fn version_comparison_is_monotonic() {
        // Mirrors how common.rs decides whether to advertise an update.
        assert!(hbb_common::get_version_number("1.5.1") > hbb_common::get_version_number("1.5.0"));
        assert!(hbb_common::get_version_number("1.6.0") > hbb_common::get_version_number("1.5.9"));
        assert_eq!(
            hbb_common::get_version_number("1.5.1"),
            hbb_common::get_version_number("1.5.1")
        );
    }

    #[test]
    fn urls_are_well_formed() {
        assert_eq!(
            api_url("acme/deskyar"),
            "https://api.github.com/repos/acme/deskyar/releases/latest"
        );
        assert_eq!(
            release_page("acme/deskyar", "v1.5.1"),
            "https://github.com/acme/deskyar/releases/tag/v1.5.1"
        );
    }
}
