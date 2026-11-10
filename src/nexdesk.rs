//! NexDesk product defaults.
//!
//! Update discovery used to live here: it resolved the newest release from the
//! GitHub API and handed a `releases/tag/<tag>` URL to `updater.rs`. That whole
//! path is gone - the app now asks `https://nexdesk.ir/api/update.php` through
//! `src/nexdesk_update.rs`, and nothing in the binary talks to GitHub.
//!
//! What remains are the defaults a fresh NexDesk install needs.

/// Whether auto-update should be considered on when the user never chose.
///
/// `allow-auto-update` is an `allow-` option, so `option2bool` only reads it as
/// enabled when it is literally `Y`. Nothing ships a default for it, which
/// leaves a fresh install with auto-update silently off. NexDesk wants new
/// installs to stay current, so "never configured" counts as enabled while an
/// explicit `N` from the settings page still wins.
pub fn auto_update_default() -> bool {
    hbb_common::config::Config::get_option(base::config::keys::OPTION_ALLOW_AUTO_UPDATE).is_empty()
}

/// Persist the auto-update preference the first time NexDesk runs.
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
pub const OPTION_DEFAULTS_APPLIED: &str = "nexdesk-defaults-applied";

/// Apply NexDesk's product defaults exactly once per installation.
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
