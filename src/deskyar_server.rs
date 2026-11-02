//! DeskYar server configuration.
//!
//! ## The problem this solves
//!
//! A stock RustDesk build talks to the public RustDesk infrastructure
//! (`rs-ny.rustdesk.com`) for two things that matter to a DeskYar user:
//!
//!   1. **The rendezvous (hbbs) server.** Every client registers its ID and
//!      its public key there. The server signs those registrations, and peers
//!      use the signed blob to authenticate each other. Without a rendezvous
//!      server the client cannot even *produce* an ID - `Config::gen_id()`
//!      is only reached after the connection to the server succeeds.
//!
//!   2. **The API server**, which handles address book, tags and the online
//!      peer list.
//!
//! When DeskYar was pointed at a self-hosted server by typing the address into
//! Settings, the client still reported the *same* ID as RustDesk. The reason
//! is that `Config::get_rendezvous_server()` walks a chain of sources and
//! falls back to the compiled-in `RENDEZVOUS_SERVERS` list - and the public
//! key used to verify the server's signatures comes from `RS_PUB_KEY`, which
//! upstream hard-codes. A client that talks to a self-hosted server while
//! holding the upstream public key cannot verify anything the server sends,
//! and the peer lookup silently resolves against the wrong place.
//!
//! If the public internet in Iran is throttled or filtered, a client that
//! still reaches out to `rs-ny.rustdesk.com` degrades into something that
//! looks installed but cannot connect to anything.
//!
//! ## The fix
//!
//! Bake the server into the build:
//!
//!   * `DESKYAR_SERVER` - the rendezvous host, e.g. `rd.example.com`
//!   * `DESKYAR_SERVER_KEY` - the server's Ed25519 public key, the contents of
//!     `data/id_ed25519.pub` on the server, base64-encoded
//!
//! Both can be supplied at build time (environment variable for
//! `cargo build`) or at run time (environment variable when the exe starts).
//! Run time wins, so one binary can be pointed at a different server without
//! a rebuild - useful for testing.
//!
//! [`ensure_server_defaults`] writes the values into the regular option store
//! on first run, which is what the rest of the code base already reads.

use hbb_common::config::Config;

/// Fallback used when neither the environment nor the option store carries a
/// server address. Empty means "use whatever upstream provides", which is the
/// safe default for a fork that has not been pointed at a server yet.
///
/// **To hard-code your own server, put its host here** - the DNS name or IP,
/// without `https://` and without a port. The port is filled in automatically
/// (21116 for rendezvous, 21117 for relay, 21114 for the API).
///
/// ```
/// pub const DEFAULT_SERVER: &str = "rd.yar.one";
/// ```
pub const DEFAULT_SERVER: &str = "";

/// Fallback public key of the server, base64.
///
/// **To hard-code your own server, paste the contents of
/// `data/id_ed25519.pub` from the server here**, on a single line.
///
/// ```
/// pub const DEFAULT_SERVER_KEY: &str = "abcdef...=";
/// ```
///
/// This is a *public* key. It is handed to every client by design, so it is
/// safe to commit. What must never be committed is `data/id_ed25519` - the
/// private key, with no extension.
///
/// Getting it:
///
/// ```sh
/// cat data/id_ed25519.pub
/// ```
pub const DEFAULT_SERVER_KEY: &str = "";

/// Name of the environment variable holding the rendezvous host.
pub const ENV_SERVER: &str = "DESKYAR_SERVER";

/// Name of the environment variable holding the server's public key.
pub const ENV_SERVER_KEY: &str = "DESKYAR_SERVER_KEY";

/// Option key under which the rendezvous host is stored.
pub const OPTION_SERVER: &str = "custom-rendezvous-server";

/// Option key under which the server's public key is stored.
///
/// This is upstream's own `key` option - `common::get_key` and
/// `Config::get_option("key")` both read it, and it is the value used to
/// verify the rendezvous server's signatures.
pub const OPTION_SERVER_KEY: &str = "key";

/// The configured rendezvous host, without a port.
///
/// Resolution order:
///   1. `DESKYAR_SERVER` in the environment (run time override)
///   2. the `custom-rendezvous-server` option (written on first run)
///   3. `DESKYAR_SERVER` compiled into the binary (build time)
///
/// Returns an empty string when no server is configured.
pub fn server_host() -> String {
    if let Ok(value) = std::env::var(ENV_SERVER) {
        let value = value.trim();
        if !value.is_empty() {
            return value.to_owned();
        }
    }
    let stored = Config::get_option(OPTION_SERVER);
    if !stored.is_empty() {
        return stored;
    }
    compile_time_server().unwrap_or_else(|| DEFAULT_SERVER.to_owned())
}

/// The configured server public key, base64-encoded.
///
/// Resolution order mirrors [`server_host`]:
///   1. `DESKYAR_SERVER_KEY` in the environment
///   2. the `key` option
///   3. the value compiled into the binary
///
/// Returns an empty string when no key is configured, in which case upstream's
/// `RS_PUB_KEY` is used - which only works against the public server.
pub fn server_key() -> String {
    if let Ok(value) = std::env::var(ENV_SERVER_KEY) {
        let value = value.trim();
        if !value.is_empty() {
            return value.to_owned();
        }
    }
    let stored = Config::get_option(OPTION_SERVER_KEY);
    if !stored.is_empty() {
        return stored;
    }
    compile_time_server_key().unwrap_or_else(|| DEFAULT_SERVER_KEY.to_owned())
}

/// The rendezvous host baked in at build time.
fn compile_time_server() -> Option<String> {
    option_env!("DESKYAR_SERVER")
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

/// The server public key baked in at build time.
fn compile_time_server_key() -> Option<String> {
    option_env!("DESKYAR_SERVER_KEY")
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}

/// Whether a self-hosted server has been configured at all.
pub fn is_configured() -> bool {
    !server_host().is_empty()
}

/// Point the client at the configured server, once.
///
/// Two options are written:
///
///   * `custom-rendezvous-server` - read by `Config::get_rendezvous_server()`
///     and `Config::get_rendezvous_servers()`
///   * `key` - the server's public key, read by `common::get_key()` and used
///     to verify the server's signed peer registrations
///
/// The write happens only when the option is still empty, so a user who later
/// changes the server address in Settings keeps their choice. A user who
/// *clears* the address in Settings is not overridden, because the option is
/// then empty again and this function would restore the baked-in value -
/// which is the intended behaviour for a build shipped for one specific
/// server.
pub fn ensure_server_defaults() {
    let host = server_host();
    if host.is_empty() {
        return;
    }
    // The in-memory override sits above the stored option in
    // `Config::get_rendezvous_server()`'s chain, so a build shipped for one
    // specific server keeps using it even if the option store was written by
    // an older build that pointed somewhere else.
    //
    // It is only applied when the environment supplies the address. A value
    // that was merely compiled in is written to the option store instead, so
    // the user can still change it in Settings.
    if std::env::var(ENV_SERVER).is_ok() {
        let mut guard = hbb_common::config::PROD_RENDEZVOUS_SERVER.write().unwrap();
        if guard.is_empty() {
            *guard = host.clone();
        }
    }
    if Config::get_option(OPTION_SERVER).is_empty() {
        Config::set_option(OPTION_SERVER.to_owned(), host);
    }
    let key = server_key();
    if !key.is_empty() && Config::get_option(OPTION_SERVER_KEY).is_empty() {
        Config::set_option(OPTION_SERVER_KEY.to_owned(), key);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn host_carries_no_bidi_control_characters() {
        // The host is used verbatim as a TCP address, so it must never pick up
        // the invisible isolates the UI layer uses for ID rendering. A single
        // U+2066 in the address makes DNS resolution fail with an error that
        // looks nothing like the actual cause.
        let host = server_host();
        assert!(!host.contains('\u{2066}'));
        assert!(!host.contains('\u{2069}'));
        assert!(!host.contains('\u{200f}'));
        assert_eq!(host.trim(), host);
    }

    #[test]
    fn configured_flag_tracks_the_host() {
        assert_eq!(is_configured(), !server_host().is_empty());
    }

    #[test]
    fn compile_time_values_are_trimmed_and_non_empty() {
        // `option_env!` yields whatever the build passed, including an empty
        // string when the variable is set but blank. Both helpers must fold
        // that to `None` so a blank build variable never shadows the stored
        // option with nothing.
        if let Some(server) = compile_time_server() {
            assert!(!server.is_empty());
            assert_eq!(server.trim(), server);
        }
        if let Some(key) = compile_time_server_key() {
            assert!(!key.is_empty());
            assert_eq!(key.trim(), key);
        }
    }

    #[test]
    fn hard_coded_values_are_well_formed() {
        // These are the two constants a fork is expected to edit by hand, so
        // guard against the mistakes that are easy to make there.
        if !DEFAULT_SERVER.is_empty() {
            assert_eq!(DEFAULT_SERVER.trim(), DEFAULT_SERVER);
            assert!(
                !DEFAULT_SERVER.contains("://"),
                "DEFAULT_SERVER must be a bare host, not a URL - the scheme is \
                 added by the caller"
            );
            assert!(
                !DEFAULT_SERVER.contains(':'),
                "DEFAULT_SERVER must not carry a port - 21116/21117/21114 are \
                 appended automatically"
            );
            assert!(
                !DEFAULT_SERVER.ends_with('/'),
                "DEFAULT_SERVER must not end with a slash"
            );
        }
        if !DEFAULT_SERVER_KEY.is_empty() {
            assert_eq!(DEFAULT_SERVER_KEY.trim(), DEFAULT_SERVER_KEY);
            // A real key is 44 base64 characters (32 bytes) and ends in `=`.
            assert!(
                DEFAULT_SERVER_KEY.len() >= 40,
                "DEFAULT_SERVER_KEY looks truncated - paste the whole contents \
                 of data/id_ed25519.pub"
            );
            assert!(
                !DEFAULT_SERVER_KEY.contains(' '),
                "DEFAULT_SERVER_KEY must be one line with no spaces"
            );
        }
    }
}
