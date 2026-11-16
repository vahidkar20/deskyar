//! Tells the controller when the host it just connected to is older than the
//! oldest build this one is meant to work with.
//!
//! The version lock was removed on purpose. Refusing a connection because of a
//! version mismatch turned a working session into "Update Required" on machines
//! that cannot update, so the decision was to accept the connection and say so
//! once. That is all this module does: it produces a short code the UI turns
//! into a dismissible bar. It never refuses a connection and never changes the
//! session.
//!
//! A code rather than a sentence, because the text has to be translated on the
//! Flutter side, where the rest of the interface strings live.

use hbb_common::get_version_number;

/// The oldest host build this controller is tested against.
///
/// 1.5.11 is the first NexDesk build; anything older is either an upstream
/// RustDesk that cannot verify this server's signatures, or a NexDesk release
/// that predates the fixes the controller now relies on.
pub const MIN_HOST_VERSION: &str = "1.5.11";

/// The code sent to the UI for an outdated host.
pub const OUTDATED_HOST: &str = "outdated_host";

/// Returns a UI code when `host_version` is older than [`MIN_HOST_VERSION`].
///
/// `None` when either side cannot be parsed as a version: a host that reports
/// nothing useful must not be labelled as outdated, because the warning would
/// then be wrong on every reconnect with no way for the user to tell.
pub fn host_advisory(host_version: &str) -> Option<&'static str> {
    // A version string starts with a digit. Without this, a prefix makes the
    // parser skip the first component and produce a plausible but wrong number:
    // "v1.5.9" comes out as 5090, which is below the floor and would raise the
    // warning for a host whose version we never actually understood.
    match host_version.trim_start().chars().next() {
        Some(c) if c.is_ascii_digit() => {}
        _ => return None,
    }
    let host = get_version_number(host_version);
    let floor = get_version_number(MIN_HOST_VERSION);
    if host <= 0 || floor <= 0 {
        return None;
    }
    if host < floor {
        Some(OUTDATED_HOST)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_older_host_is_flagged_once() {
        assert_eq!(host_advisory("1.5.9"), Some(OUTDATED_HOST));
        assert_eq!(host_advisory("1.4.1"), Some(OUTDATED_HOST));
        assert_eq!(host_advisory("1.1.9"), Some(OUTDATED_HOST));
    }

    #[test]
    fn the_floor_and_anything_newer_stay_quiet() {
        assert_eq!(host_advisory(MIN_HOST_VERSION), None);
        assert_eq!(host_advisory("1.5.11-av.1"), None);
        assert_eq!(host_advisory("1.5.12"), None);
        assert_eq!(host_advisory("2.0.0"), None);
    }

    #[test]
    fn an_unparsable_version_is_not_a_warning() {
        // Empty, whitespace, garbage and a leading zero all parse to 0. None of
        // them identify a host, so none of them may raise a warning.
        for v in ["", " ", "unknown", "dev", "0.0.0", "v1.5.9"] {
            assert_eq!(host_advisory(v), None, "version {v:?} must stay quiet");
        }
    }

    #[test]
    fn the_floor_is_the_first_nexdesk_build() {
        // If this constant is ever lowered, the warning starts firing on hosts
        // that are actually current. Keep it tied to a released version.
        assert_eq!(MIN_HOST_VERSION, "1.5.11");
        assert!(get_version_number(MIN_HOST_VERSION) > get_version_number("1.5.10"));
    }
}
