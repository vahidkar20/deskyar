//! NexDesk auto-update.
//!
//! ## Why this exists
//!
//! The upstream updater (`updater.rs`) can only download from
//! `https://github.com/rustdesk/rustdesk/releases/...`: its URL parser rejects
//! every other host, so a rebranded build can never update itself. It also
//! buffers the whole file in memory, shows no progress, has no notion of a
//! mandatory update, and verifies nothing about what it downloaded.
//!
//! This module owns the NexDesk update path end to end:
//!
//!   1. **Discover** - fetch a small JSON manifest from our own site.
//!   2. **Verify** - Ed25519 signature over a canonical field list, then
//!      SHA-256 of the downloaded binary. A manifest that fails either check is
//!      discarded; there is no "skip verification" path.
//!   3. **Download** - reuse `hbbs_http::downloader`, which streams to disk and
//!      exposes `downloaded_size`, so the UI can show a real percentage.
//!   4. **Install** - hand the verified file to the existing
//!      `platform::update_to` (installed copy) or to the portable packer.
//!
//! ## Manifest
//!
//! ```json
//! {
//!   "schema": 1,
//!   "channel": "stable",
//!   "platform": "windows-x86_64",
//!   "version": "1.5.4",
//!   "url": "https://nexdesk.ir/updates/NexDesk-1.5.4-x86_64.exe",
//!   "sha256": "<64 hex>",
//!   "size": 26064384,
//!   "mandatory": false,
//!   "min_supported": "1.5.0",
//!   "published_at": "2026-11-07T12:00:00Z",
//!   "notes_fa": "...",
//!   "notes_en": "...",
//!   "signatures": [{ "key_id": "2026-11", "sig": "<128 hex>" }]
//! }
//! ```
//!
//! The signature covers [`canonical_payload`], not the raw JSON: whitespace,
//! key order and a CDN's re-serialisation all change raw bytes, so signing the
//! body would break the moment anyone prettified the file.
//!
//! ## Mandatory updates
//!
//! `mandatory: true` blocks the main window. `min_supported` is a version
//! floor: a client older than it is forced to update even when the publisher
//! forgot to set the flag. Both are publisher-controlled.
//!
//! The login gate is a *version*, not a boolean (`set_server_gate`), so it
//! clears itself once `crate::VERSION` reaches the floor - a stale flag can
//! never lock a machine out permanently.

use std::path::PathBuf;
use std::sync::{Mutex, Once};
use std::time::{Duration, Instant};

use hbb_common::{bail, log, ResultType};
use serde_derive::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::hbbs_http::create_http_client_with_url_strict;
use crate::hbbs_http::downloader::{
    cancel as cancel_download, download_file, get_download_data, remove as remove_download,
};

/// Only schema 1 is understood. A future security-relevant field bumps this
/// and the canonical prefix together, so an old client cannot silently ignore
/// it.
pub const SCHEMA: u32 = 1;
pub const MANIFEST_PREFIX: &str = "nexdesk-manifest-v1";

/// A manifest larger than this is rejected before parsing.
const MAX_MANIFEST_BYTES: u64 = 64 * 1024;
const MIN_BINARY_BYTES: u64 = 1024 * 1024;
const MAX_BINARY_BYTES: u64 = 300 * 1024 * 1024;

const FIRST_CHECK_DELAY: Duration = Duration::from_secs(20);
const CHECK_INTERVAL: Duration = Duration::from_secs(6 * 60 * 60);
const RETRY_INTERVAL: Duration = Duration::from_secs(20 * 60);
const MIN_CHECK_INTERVAL: Duration = Duration::from_secs(5 * 60);
const DOWNLOAD_POLL: Duration = Duration::from_millis(250);
const DOWNLOAD_TIMEOUT: Duration = Duration::from_secs(30 * 60);

/// Only this exact version may be postponed; a newer release re-prompts.
const OPTION_POSTPONED_VERSION: &str = "nexdesk-postponed-version";
const OPTION_LAST_VERSION: &str = "nexdesk-last-manifest-version";
const OPTION_LAST_PUBLISHED: &str = "nexdesk-last-manifest-published";
const OPTION_INSTALL_ATTEMPT: &str = "nexdesk-update-install-attempt";
const OPTION_LOGIN_GATE: &str = "nexdesk-block-below-version";

// ---------------------------------------------------------------------------
// Manifest
// ---------------------------------------------------------------------------

#[derive(Deserialize, Clone, Debug, Default)]
pub struct ManifestSignature {
    #[serde(default)]
    pub key_id: String,
    /// Hex-encoded 64-byte Ed25519 signature.
    #[serde(default)]
    pub sig: String,
}

#[derive(Deserialize, Clone, Debug, Default)]
pub struct Manifest {
    #[serde(default)]
    pub schema: u32,
    #[serde(default)]
    pub channel: String,
    #[serde(default)]
    pub platform: String,
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub url: String,
    #[serde(default)]
    pub sha256: String,
    #[serde(default)]
    pub size: u64,
    #[serde(default)]
    pub mandatory: bool,
    #[serde(default)]
    pub min_supported: String,
    #[serde(default)]
    pub published_at: String,
    #[serde(default)]
    pub notes_fa: String,
    #[serde(default)]
    pub notes_en: String,
    #[serde(default)]
    pub signatures: Vec<ManifestSignature>,
    /// The running build has been retired in the panel: update is mandatory.
    #[serde(default)]
    pub retired_current: bool,
    /// Publisher's floor. Anything below it must update.
    #[serde(default)]
    pub minimum_version: String,
    /// Publisher's message, shown verbatim (retirement / forced update copy).
    #[serde(default)]
    pub message: String,
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

#[derive(Serialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    Idle,
    Checking,
    UpToDate,
    Available,
    Downloading,
    Verifying,
    Installing,
    Done,
    Failed,
}

#[derive(Serialize, Clone, Debug)]
pub struct UpdateState {
    pub phase: Phase,
    pub current: String,
    pub latest: String,
    pub mandatory: bool,
    pub postponed: bool,
    pub min_supported: String,
    pub retired_current: bool,
    pub message: String,
    pub notes_fa: String,
    pub notes_en: String,
    pub url: String,
    pub size: u64,
    pub downloaded: u64,
    pub error: String,
    /// "installed" or "portable"; the UI wording differs.
    pub install_kind: String,
    pub can_install: bool,
}

impl UpdateState {
    fn new() -> Self {
        Self {
            phase: Phase::Idle,
            current: crate::VERSION.to_owned(),
            latest: String::new(),
            mandatory: false,
            postponed: false,
            min_supported: String::new(),
            retired_current: false,
            message: String::new(),
            notes_fa: String::new(),
            notes_en: String::new(),
            url: String::new(),
            size: 0,
            downloaded: 0,
            error: String::new(),
            install_kind: if is_installed_copy() {
                "installed"
            } else {
                "portable"
            }
            .to_owned(),
            can_install: false,
        }
    }
}

static STATE: Mutex<Option<UpdateState>> = Mutex::new(None);
static PENDING: Mutex<Option<Manifest>> = Mutex::new(None);
static DOWNLOAD_ID: Mutex<Option<String>> = Mutex::new(None);
static LAST_CHECK: Mutex<Option<Instant>> = Mutex::new(None);
static STARTED: Once = Once::new();
static LOGIN_GATE: Mutex<Option<String>> = Mutex::new(None);

fn with_state<F: FnOnce(&mut UpdateState)>(f: F) {
    let mut guard = STATE.lock().unwrap();
    let state = guard.get_or_insert_with(UpdateState::new);
    f(state);
}

/// Snapshot used by the FFI layer and by the poller.
pub fn state_json() -> String {
    let guard = STATE.lock().unwrap();
    let state = guard.clone().unwrap_or_else(UpdateState::new);
    serde_json::to_string(&state).unwrap_or_else(|_| "{}".to_owned())
}

fn current_phase() -> Phase {
    STATE
        .lock()
        .unwrap()
        .as_ref()
        .map(|s| s.phase)
        .unwrap_or(Phase::Idle)
}

fn emit() {
    // `crate::flutter` only exists in UI builds (see src/lib.rs); the server and
    // CLI builds compile this module without it.
    #[cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
    {
        let payload = state_json();
        let event = serde_json::json!({
            "name": "nexdesk-update",
            "state": serde_json::from_str::<serde_json::Value>(&payload)
                .unwrap_or(serde_json::Value::Null),
        });
        let _ = crate::flutter::push_global_event(
            crate::flutter::APP_TYPE_MAIN,
            serde_json::ser::to_string(&event).unwrap_or_default(),
        );
    }
}

fn set_phase(phase: Phase) {
    with_state(|s| s.phase = phase);
    emit();
}

fn set_failed(error: impl Into<String>) {
    let error = error.into();
    log::warn!("nexdesk update: {}", error);
    with_state(|s| {
        s.phase = Phase::Failed;
        s.error = error;
        s.can_install = false;
    });
    emit();
}

fn is_installed_copy() -> bool {
    #[cfg(target_os = "windows")]
    {
        crate::platform::is_installed()
    }
    #[cfg(not(target_os = "windows"))]
    {
        false
    }
}

// ---------------------------------------------------------------------------
// Configuration (baked at build time, overridable at runtime for testing)
// ---------------------------------------------------------------------------

fn env_or_baked(name: &str, baked: Option<&'static str>, fallback: &str) -> String {
    if let Ok(value) = std::env::var(name) {
        let value = value.trim().to_string();
        if !value.is_empty() {
            return value;
        }
    }
    baked
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| fallback.to_owned())
}

/// Base of the update API. The whole update path is served from here; nothing
/// in this module talks to GitHub any more.
pub fn api_base() -> String {
    env_or_baked(
        "NEXDESK_UPDATE_API",
        option_env!("NEXDESK_UPDATE_API"),
        "https://nexdesk.ir",
    )
}

/// `GET /api/update.php?platform=<p>&current=<v>` - the contract implemented by
/// the site (see docs/nexdesk-update-api.md).
///
/// `current` is sent so the server decides whether an update exists; the answer
/// is authoritative and is not second-guessed here.
pub fn manifest_url() -> String {
    format!(
        "{}/api/update.php?platform={}&current={}",
        api_base().trim_end_matches('/'),
        api_platform(),
        crate::VERSION
    )
}

fn api_platform() -> &'static str {
    #[cfg(target_os = "windows")]
    {
        "windows"
    }
    #[cfg(target_os = "android")]
    {
        "android"
    }
    #[cfg(not(any(target_os = "windows", target_os = "android")))]
    {
        "windows"
    }
}

/// Identifies the client to the update endpoint.
pub const USER_AGENT: &str = concat!("NexDesk/", env!("CARGO_PKG_VERSION"));

pub fn channel() -> String {
    env_or_baked(
        "NEXDESK_UPDATE_CHANNEL",
        option_env!("NEXDESK_UPDATE_CHANNEL"),
        "stable",
    )
}

pub fn platform_tag() -> &'static str {
    #[cfg(all(target_os = "windows", target_arch = "aarch64"))]
    {
        "windows-aarch64"
    }
    #[cfg(all(target_os = "windows", not(target_arch = "aarch64")))]
    {
        "windows-x86_64"
    }
    #[cfg(not(target_os = "windows"))]
    {
        "unsupported"
    }
}

/// Hosts an update may be downloaded from. Sub-domains are accepted, so
/// `dl.nexdesk.ir` works without a rebuild.
pub fn allowed_hosts() -> Vec<String> {
    env_or_baked(
        "NEXDESK_UPDATE_HOSTS",
        option_env!("NEXDESK_UPDATE_HOSTS"),
        "nexdesk.ir",
    )
    .split(',')
    .map(|h| h.trim().to_ascii_lowercase())
    .filter(|h| !h.is_empty())
    .collect()
}

/// Baked Ed25519 public keys as `(key_id, 32 bytes)`.
///
/// Format of `NEXDESK_UPDATE_PUBKEY`: `key_id:hex[,key_id2:hex]`. More than one
/// entry is how a key rotation is rolled out: sign with both for two releases,
/// then drop the old one.
pub fn public_keys() -> Vec<(String, [u8; 32])> {
    let raw = env_or_baked(
        "NEXDESK_UPDATE_PUBKEY",
        option_env!("NEXDESK_UPDATE_PUBKEY"),
        "",
    );
    let mut keys = Vec::new();
    for entry in raw.split(',') {
        let entry = entry.trim();
        if entry.is_empty() {
            continue;
        }
        let Some((id, hex_key)) = entry.split_once(':') else {
            log::warn!("nexdesk update: ignoring malformed public key entry");
            continue;
        };
        let Ok(bytes) = hex::decode(hex_key.trim()) else {
            log::warn!("nexdesk update: public key {id} is not valid hex");
            continue;
        };
        let Ok(key) = <[u8; 32]>::try_from(bytes.as_slice()) else {
            log::warn!("nexdesk update: public key {id} is not 32 bytes");
            continue;
        };
        keys.push((id.trim().to_owned(), key));
    }
    keys
}

/// The update path is always on for the platforms it can install on.
///
/// It used to require a baked Ed25519 key, which left the updater silently
/// disabled in every build that did not carry one - and the legacy GitHub check
/// then took over. Integrity now comes from the SHA-256 the API returns, which
/// is checked before anything is executed.
pub fn is_enabled() -> bool {
    // Windows installs the downloaded exe itself. Android needs the
    // FileProvider + ACTION_VIEW hand-off on the Dart side, which is not wired
    // yet, so the check stays off there rather than offering an update it
    // cannot install.
    cfg!(target_os = "windows")
}

fn cache_dir() -> PathBuf {
    hbb_common::config::Config::path("updates")
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

fn has_control_chars(value: &str) -> bool {
    value.contains('\n') || value.contains('\r') || value.contains('\0')
}

fn is_plain_version(value: &str) -> bool {
    let parts: Vec<&str> = value.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.len() <= 4 && p.chars().all(|c| c.is_ascii_digit()))
}

fn is_hex_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .chars()
            .all(|c| c.is_ascii_digit() || ('a'..='f').contains(&c))
}

fn validate_url(url: &str) -> ResultType<()> {
    if !url.is_ascii() {
        bail!("update url must be ascii");
    }
    let Some(rest) = url.strip_prefix("https://") else {
        bail!("update url must use https");
    };
    if rest.contains('@') || rest.contains(' ') || rest.contains('\t') {
        bail!("update url must not carry credentials or whitespace");
    }
    let host_end = rest.find('/').unwrap_or(rest.len());
    let host = rest[..host_end].to_ascii_lowercase();
    if host.is_empty() || host.contains(':') {
        bail!("update url must carry a plain host without a port");
    }
    if !allowed_hosts()
        .iter()
        .any(|allowed| host == *allowed || host.ends_with(&format!(".{allowed}")))
    {
        bail!("update host {host} is not in the allowlist");
    }
    let path = &rest[host_end..];
    if path.contains('?') || path.contains('#') {
        bail!("update url must not carry a query or fragment");
    }
    if !path.to_ascii_lowercase().ends_with(".exe") {
        bail!("update url must point at an .exe");
    }
    Ok(())
}

/// Validate everything that can be checked without touching the network.
pub fn validate(m: &Manifest) -> ResultType<()> {
    if m.schema != SCHEMA {
        bail!("unsupported manifest schema {}", m.schema);
    }
    if m.channel != channel() {
        bail!(
            "manifest channel {} does not match {}",
            m.channel,
            channel()
        );
    }
    if m.platform != platform_tag() {
        bail!(
            "manifest platform {} does not match {}",
            m.platform,
            platform_tag()
        );
    }
    if !is_plain_version(&m.version) {
        bail!("manifest version {} is not a plain x.y.z", m.version);
    }
    if !is_plain_version(&m.min_supported) && !m.min_supported.is_empty() {
        bail!("manifest min_supported is not a plain x.y.z");
    }
    if !is_hex_sha256(&m.sha256) {
        bail!("manifest sha256 must be 64 lowercase hex characters");
    }
    if m.size < MIN_BINARY_BYTES || m.size > MAX_BINARY_BYTES {
        bail!("manifest size {} is out of range", m.size);
    }
    if m.published_at.len() != 20
        || !m.published_at.ends_with('Z')
        || m.published_at.as_bytes().get(4) != Some(&b'-')
        || m.published_at.as_bytes().get(10) != Some(&b'T')
    {
        bail!("manifest published_at must be YYYY-MM-DDTHH:MM:SSZ");
    }
    if m.notes_fa.len() > 4096 || m.notes_en.len() > 4096 {
        bail!("manifest notes are too long");
    }
    for value in [
        &m.channel,
        &m.platform,
        &m.version,
        &m.url,
        &m.sha256,
        &m.min_supported,
        &m.published_at,
    ] {
        if has_control_chars(value) {
            bail!("manifest field contains a control character");
        }
    }
    validate_url(&m.url)?;
    Ok(())
}

/// The exact bytes the publisher signs.
///
/// Fixed field order, LF separators, one trailing newline, no spaces around
/// `=`. Notes are hashed rather than embedded so their newlines and quotes
/// cannot break the framing.
pub fn canonical_payload(m: &Manifest) -> ResultType<String> {
    let sha = |text: &str| -> String {
        let mut hasher = Sha256::new();
        hasher.update(text.as_bytes());
        hex::encode(hasher.finalize())
    };
    Ok(format!(
        "{prefix}\nschema={schema}\nchannel={channel}\nplatform={platform}\nversion={version}\nurl={url}\nsha256={sha256}\nsize={size}\nmandatory={mandatory}\nmin_supported={min_supported}\npublished_at={published_at}\nnotes_fa_sha256={fa}\nnotes_en_sha256={en}\n",
        prefix = MANIFEST_PREFIX,
        schema = m.schema,
        channel = m.channel,
        platform = m.platform,
        version = m.version,
        url = m.url,
        sha256 = m.sha256,
        size = m.size,
        mandatory = m.mandatory,
        min_supported = m.min_supported,
        published_at = m.published_at,
        fa = sha(&m.notes_fa),
        en = sha(&m.notes_en),
    ))
}

/// True when at least one signature verifies with a baked key.
pub fn verify_signatures(m: &Manifest, payload: &str) -> ResultType<()> {
    use hbb_common::sodiumoxide::crypto::sign;

    let keys = public_keys();
    if keys.is_empty() {
        bail!("no update public key is baked into this build");
    }
    if m.signatures.is_empty() {
        bail!("manifest carries no signature");
    }
    let mut tried = 0usize;
    for entry in &m.signatures {
        let Some((_, raw_key)) = keys.iter().find(|(id, _)| id == &entry.key_id) else {
            continue;
        };
        tried += 1;
        let Ok(raw_sig) = hex::decode(entry.sig.trim()) else {
            continue;
        };
        let Ok(sig_bytes) = <[u8; 64]>::try_from(raw_sig.as_slice()) else {
            continue;
        };
        // sodiumoxide keeps the tuple fields private: construct through the
        // checked constructors instead of `Signature(bytes)`.
        let public_key = sign::PublicKey(*raw_key);
        let Ok(signature) = sign::Signature::from_bytes(&sig_bytes) else {
            continue;
        };
        if sign::verify_detached(&signature, payload.as_bytes(), &public_key) {
            return Ok(());
        }
    }
    bail!(
        "manifest signature did not verify ({} known key(s) tried)",
        tried
    )
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

/// The response wrapper documented in `docs/nexdesk-update-api.md`.
#[derive(Deserialize, Default)]
struct ApiEnvelope {
    #[serde(default)]
    ok: bool,
    #[serde(default)]
    update_available: bool,
    #[serde(default)]
    latest: Option<ApiLatest>,
    #[serde(default)]
    mandatory: bool,
    #[serde(default)]
    retired_current: bool,
    #[serde(default)]
    minimum_version: String,
    #[serde(default)]
    message: String,
}

#[derive(Deserialize, Default)]
struct ApiLatest {
    #[serde(default)]
    version: String,
    #[serde(default)]
    url: String,
    #[serde(default)]
    size: u64,
    #[serde(default)]
    sha256: String,
    #[serde(default)]
    mandatory: bool,
    #[serde(default)]
    notes: String,
    #[serde(default)]
    published_at: String,
}

/// `2026-11-10T10:15:00+03:30` -> `2026-11-10T10:15:00Z`.
///
/// The local offset is dropped on purpose: the value is only used for the
/// "older than the last one seen" guard, which compares manifests of the same
/// publisher, and a wrong-by-hours value can only ever reject, never accept.
fn normalize_published_at(raw: &str) -> String {
    let raw = raw.trim();
    if raw.len() >= 19
        && raw.as_bytes().get(4) == Some(&b'-')
        && raw.as_bytes().get(10) == Some(&b'T')
    {
        format!("{}Z", &raw[..19])
    } else {
        "1970-01-01T00:00:00Z".to_owned()
    }
}

fn fetch_manifest() -> ResultType<Option<Manifest>> {
    let url = manifest_url();
    let client = create_http_client_with_url_strict(&url)?;
    let resp = client
        .get(&url)
        .header("User-Agent", USER_AGENT)
        .header("Cache-Control", "no-cache")
        .header("Pragma", "no-cache")
        .timeout(Duration::from_secs(20))
        .send()?;
    if !resp.status().is_success() {
        bail!("manifest request failed with HTTP {}", resp.status());
    }
    if let Some(len) = resp.content_length() {
        if len > MAX_MANIFEST_BYTES {
            bail!("manifest is larger than {} bytes", MAX_MANIFEST_BYTES);
        }
    }
    let body = resp.bytes()?;
    if body.len() as u64 > MAX_MANIFEST_BYTES {
        bail!("manifest is larger than {} bytes", MAX_MANIFEST_BYTES);
    }
    let envelope: ApiEnvelope = serde_json::from_slice(&body)?;
    if !envelope.ok {
        bail!("update api reported ok=false");
    }
    // `update_available: false` is the server's decision. Mirror it by
    // reporting the running version, which `check_now` turns into "up to date"
    // without a second comparison of its own.
    if !envelope.update_available {
        return Ok(None);
    }
    let Some(latest) = envelope.latest else {
        bail!("update api reported an update but sent no latest block");
    };
    Ok(Some(Manifest {
        schema: SCHEMA,
        channel: channel(),
        platform: platform_tag().to_owned(),
        version: latest.version.trim().trim_start_matches('v').to_owned(),
        url: latest.url.trim().to_owned(),
        sha256: latest.sha256.trim().to_ascii_lowercase(),
        size: latest.size,
        mandatory: latest.mandatory || envelope.mandatory,
        min_supported: String::new(),
        published_at: normalize_published_at(&latest.published_at),
        notes_fa: latest.notes,
        notes_en: String::new(),
        signatures: Vec::new(),
        retired_current: envelope.retired_current,
        minimum_version: envelope.minimum_version.trim().to_owned(),
        message: envelope.message.trim().to_owned(),
    }))
}

fn persist(key: &str, value: &str) {
    hbb_common::config::Config::set_option(key.to_owned(), value.to_owned());
}

fn read_option(key: &str) -> String {
    hbb_common::config::Config::get_option(key)
}

/// One check: fetch, validate, verify, compare, publish state.
pub fn check_now(manual: bool) -> ResultType<()> {
    if !is_enabled() {
        return Ok(());
    }
    {
        let mut last = LAST_CHECK.lock().unwrap();
        if let Some(previous) = *last {
            let minimum = if manual {
                Duration::from_secs(5)
            } else {
                MIN_CHECK_INTERVAL
            };
            if previous.elapsed() < minimum {
                return Ok(());
            }
        }
        *last = Some(Instant::now());
    }

    set_phase(Phase::Checking);

    let manifest = match fetch_manifest().and_then(|m| match m {
        Some(m) => {
            validate(&m)?;
            Ok(Some(m))
        }
        None => Ok(None),
    }) {
        Ok(Some(manifest)) => manifest,
        Ok(None) => {
            // The server says this build is current.
            *PENDING.lock().unwrap() = None;
            with_state(|s| {
                s.phase = Phase::UpToDate;
                s.latest = crate::VERSION.to_owned();
                s.mandatory = false;
                s.can_install = false;
                s.error.clear();
            });
            emit();
            return Ok(());
        }
        Err(err) => {
            set_failed(format!("{err}"));
            return Err(err);
        }
    };

    let current = hbb_common::get_version_number(crate::VERSION);
    let latest = hbb_common::get_version_number(&manifest.version);

    // A manifest older than the running build is either a rollback attempt or
    // a stale CDN copy; either way it must not be offered.
    if latest < current {
        set_failed(format!(
            "manifest version {} is older than {}",
            manifest.version,
            crate::VERSION
        ));
        return Ok(());
    }

    // Replay protection that does not depend on the local clock.
    let previous_published = read_option(OPTION_LAST_PUBLISHED);
    if !previous_published.is_empty() && manifest.published_at < previous_published {
        set_failed("manifest is older than the last one seen".to_owned());
        return Ok(());
    }

    if latest == current {
        *PENDING.lock().unwrap() = None;
        with_state(|s| {
            s.phase = Phase::UpToDate;
            s.latest = manifest.version.clone();
            s.mandatory = false;
            s.retired_current = false;
            s.message.clear();
            s.can_install = false;
            s.error.clear();
        });
        emit();
        return Ok(());
    }

    let floor = if manifest.minimum_version.is_empty() {
        manifest.min_supported.clone()
    } else {
        manifest.minimum_version.clone()
    };
    let below_floor = !floor.is_empty() && current < hbb_common::get_version_number(&floor);
    // Three independent reasons to force the update, all publisher-controlled:
    // the release is flagged, the running build was retired, or it sits below
    // the minimum version the panel still supports.
    let mandatory = manifest.mandatory || below_floor || manifest.retired_current;
    let postponed = read_option(OPTION_POSTPONED_VERSION) == manifest.version;

    persist(OPTION_LAST_VERSION, &manifest.version);
    persist(OPTION_LAST_PUBLISHED, &manifest.published_at);

    with_state(|s| {
        s.phase = Phase::Available;
        s.latest = manifest.version.clone();
        s.mandatory = mandatory;
        s.postponed = postponed && !mandatory;
        s.min_supported = floor.clone();
        s.retired_current = manifest.retired_current;
        s.message = manifest.message.clone();
        s.notes_fa = manifest.notes_fa.clone();
        s.notes_en = manifest.notes_en.clone();
        s.url = manifest.url.clone();
        s.size = manifest.size;
        s.downloaded = 0;
        s.error.clear();
        s.can_install = true;
        s.install_kind = if is_installed_copy() {
            "installed"
        } else {
            "portable"
        }
        .to_owned();
    });
    *PENDING.lock().unwrap() = Some(manifest);
    apply_login_gate();
    emit();
    Ok(())
}

/// Background poller. Idempotent.
pub fn start() {
    if !is_enabled() {
        log::warn!("nexdesk update: disabled on this platform");
        return;
    }
    STARTED.call_once(|| {
        std::thread::spawn(|| {
            std::thread::sleep(FIRST_CHECK_DELAY);
            loop {
                let _ = check_now(false);
                let delay = if current_phase() == Phase::Failed {
                    RETRY_INTERVAL
                } else {
                    CHECK_INTERVAL
                };
                std::thread::sleep(delay);
            }
        });
    });
}

// ---------------------------------------------------------------------------
// Download + install
// ---------------------------------------------------------------------------

fn sha256_file(path: &PathBuf) -> ResultType<String> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hex::encode(hasher.finalize()))
}

fn update_progress(downloaded: u64, total: u64) {
    with_state(|s| {
        s.downloaded = downloaded;
        if total > 0 {
            s.size = total;
        }
    });
}

/// Start downloading and installing the pending manifest.
pub fn install() {
    let Some(manifest) = PENDING.lock().unwrap().clone() else {
        log::warn!("nexdesk update: install requested with no pending manifest");
        return;
    };
    if current_phase() == Phase::Downloading || current_phase() == Phase::Installing {
        return;
    }
    std::thread::spawn(move || {
        if let Err(err) = download_and_install(manifest) {
            set_failed(format!("{err}"));
        }
    });
}

fn download_and_install(manifest: Manifest) -> ResultType<()> {
    let dir = cache_dir();
    std::fs::create_dir_all(&dir)?;
    let file_name = manifest
        .url
        .rsplit('/')
        .next()
        .filter(|name| !name.is_empty())
        .unwrap_or("NexDesk-update.exe")
        .to_owned();
    if !file_name.to_ascii_lowercase().ends_with(".exe") {
        bail!("unexpected update filename");
    }
    let path = dir.join(&file_name);

    // The downloader refuses to overwrite, so a retry must start clean.
    let _ = std::fs::remove_file(&path);

    with_state(|s| {
        s.phase = Phase::Downloading;
        s.downloaded = 0;
        s.size = manifest.size;
        s.error.clear();
        s.can_install = false;
    });
    emit();

    let id = download_file(manifest.url.clone(), Some(path.clone()), None)?;
    *DOWNLOAD_ID.lock().unwrap() = Some(id.clone());

    let started = Instant::now();
    let mut last_reported = 0u64;
    loop {
        if started.elapsed() > DOWNLOAD_TIMEOUT {
            cancel_download(&id);
            remove_download(&id);
            *DOWNLOAD_ID.lock().unwrap() = None;
            bail!("download timed out");
        }
        std::thread::sleep(DOWNLOAD_POLL);
        match get_download_data(&id) {
            Ok(data) => {
                if data.downloaded_size != last_reported {
                    last_reported = data.downloaded_size;
                    update_progress(data.downloaded_size, manifest.size);
                    emit();
                }
                if let Some(error) = data.error {
                    remove_download(&id);
                    *DOWNLOAD_ID.lock().unwrap() = None;
                    bail!("download failed: {error}");
                }
                if data.downloaded_size >= manifest.size {
                    break;
                }
            }
            Err(err) => {
                remove_download(&id);
                *DOWNLOAD_ID.lock().unwrap() = None;
                bail!("download state lost: {err}");
            }
        }
    }
    remove_download(&id);
    *DOWNLOAD_ID.lock().unwrap() = None;

    set_phase(Phase::Verifying);

    let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
    if size != manifest.size {
        let _ = std::fs::remove_file(&path);
        bail!("downloaded {size} bytes, expected {}", manifest.size);
    }
    let digest = sha256_file(&path)?;
    if digest != manifest.sha256 {
        let _ = std::fs::remove_file(&path);
        bail!("checksum mismatch");
    }

    persist(OPTION_INSTALL_ATTEMPT, &manifest.version);

    with_state(|s| {
        s.phase = Phase::Installing;
        s.downloaded = s.size;
    });
    emit();

    install_file(&path, &manifest)?;
    Ok(())
}

#[cfg(target_os = "windows")]
fn install_file(path: &PathBuf, manifest: &Manifest) -> ResultType<()> {
    if crate::platform::is_installed() {
        // Elevates through UAC, hands over to `--update`, then `update_me`
        // kills the running app and copies the payload into Program Files.
        crate::platform::update_to(&path.to_string_lossy())?;
        log::info!(
            "nexdesk update: handed {} over to the installer",
            manifest.version
        );
        Ok(())
    } else {
        install_portable(path, manifest)
    }
}

#[cfg(target_os = "windows")]
fn install_portable(path: &PathBuf, manifest: &Manifest) -> ResultType<()> {
    use std::process::Command;

    let exe_name = format!("{}.exe", crate::get_app_name());
    // The packer waits for the running app to exit, then re-extracts into
    // %LOCALAPPDATA%\nexdesk and relaunches. Without `--wait-exe` it would
    // write into a locked directory and fail silently.
    Command::new(path)
        .arg("--wait-exe")
        .arg(&exe_name)
        .arg("--from-update")
        .spawn()?;
    log::info!(
        "nexdesk update: portable packer started for {}",
        manifest.version
    );

    std::thread::sleep(Duration::from_millis(800));
    // Kill every instance (window, tray, sessions). This process is included;
    // the packer is already waiting and takes over.
    let _ = Command::new("taskkill")
        .args(["/F", "/IM", &exe_name])
        .status();
    std::process::exit(0);
}

#[cfg(not(target_os = "windows"))]
fn install_file(_path: &PathBuf, _manifest: &Manifest) -> ResultType<()> {
    bail!("self-update is only implemented for Windows")
}

// ---------------------------------------------------------------------------
// Postpone / cancel / gate
// ---------------------------------------------------------------------------

/// Suppress the prompt for this exact version. Mandatory updates ignore it.
pub fn postpone() -> bool {
    let guard = STATE.lock().unwrap();
    let Some(state) = guard.as_ref() else {
        return false;
    };
    if state.mandatory || state.latest.is_empty() {
        return false;
    }
    let version = state.latest.clone();
    drop(guard);
    persist(OPTION_POSTPONED_VERSION, &version);
    with_state(|s| s.postponed = true);
    emit();
    true
}

pub fn cancel() {
    let id = DOWNLOAD_ID.lock().unwrap().clone();
    if let Some(id) = id {
        cancel_download(&id);
        remove_download(&id);
    }
    *DOWNLOAD_ID.lock().unwrap() = None;
    set_phase(Phase::Available);
    with_state(|s| {
        s.downloaded = 0;
        s.can_install = true;
    });
    emit();
}

/// Publish the version floor to the server process so new logins are refused
/// while a mandatory update is pending. The gate is a version, so it clears
/// itself once the app is updated.
fn apply_login_gate() {
    let floor = {
        let guard = STATE.lock().unwrap();
        match guard.as_ref() {
            Some(state) if state.mandatory => state.min_supported.clone(),
            _ => String::new(),
        }
    };
    // Without a publisher floor, block anything below the offered version.
    let floor = if floor.is_empty() {
        STATE
            .lock()
            .unwrap()
            .as_ref()
            .filter(|s| s.mandatory)
            .map(|s| s.latest.clone())
            .unwrap_or_default()
    } else {
        floor
    };
    *LOGIN_GATE.lock().unwrap() = if floor.is_empty() {
        None
    } else {
        Some(floor.clone())
    };
    if floor.is_empty() {
        persist(OPTION_LOGIN_GATE, "");
    } else {
        persist(OPTION_LOGIN_GATE, &floor);
    }
}

/// True when this build is below the published floor and must not accept new
/// logins. Read by the server on every login request.
pub fn login_blocked() -> bool {
    let gate = LOGIN_GATE.lock().unwrap().clone().or_else(|| {
        let stored = read_option(OPTION_LOGIN_GATE);
        if stored.is_empty() {
            None
        } else {
            Some(stored)
        }
    });
    match gate {
        Some(version) if !version.is_empty() => {
            hbb_common::get_version_number(crate::VERSION)
                < hbb_common::get_version_number(&version)
        }
        _ => false,
    }
}

/// Restore the persisted gate at process start (the server process does not
/// run the updater).
pub fn load_login_gate() {
    let stored = read_option(OPTION_LOGIN_GATE);
    if !stored.is_empty() {
        *LOGIN_GATE.lock().unwrap() = Some(stored);
    }
}

pub fn mandatory_pending() -> bool {
    STATE
        .lock()
        .unwrap()
        .as_ref()
        .map(|s| {
            s.mandatory
                && matches!(
                    s.phase,
                    Phase::Available | Phase::Downloading | Phase::Failed
                )
        })
        .unwrap_or(false)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Manifest {
        Manifest {
            schema: 1,
            channel: channel(),
            platform: platform_tag().to_owned(),
            version: "9.9.9".to_owned(),
            url: "https://nexdesk.ir/updates/NexDesk-9.9.9-x86_64.exe".to_owned(),
            sha256: "a".repeat(64),
            size: 26_000_000,
            mandatory: false,
            min_supported: "1.0.0".to_owned(),
            published_at: "2026-11-07T12:00:00Z".to_owned(),
            notes_fa: "سلام\nدنیا".to_owned(),
            notes_en: "hello\nworld".to_owned(),
            signatures: vec![],
        }
    }

    #[test]
    fn canonical_payload_is_stable_and_hashes_notes() {
        let manifest = sample();
        let payload = canonical_payload(&manifest).unwrap();
        assert!(payload.starts_with(MANIFEST_PREFIX));
        assert!(payload.ends_with('\n'));
        assert!(payload.contains("size=26000000\n"));
        assert!(payload.contains("mandatory=false\n"));
        // The notes themselves never appear; only their hashes do.
        assert!(!payload.contains("hello"));
        assert_eq!(payload.matches("notes_fa_sha256=").count(), 1);
        assert_eq!(payload, canonical_payload(&manifest).unwrap());
    }

    #[test]
    fn validate_rejects_bad_fields() {
        assert!(validate(&sample()).is_ok());

        let mut bad = sample();
        bad.schema = 2;
        assert!(validate(&bad).is_err());

        let mut bad = sample();
        bad.version = "1.5".to_owned();
        assert!(validate(&bad).is_err());

        let mut bad = sample();
        bad.sha256 = "xyz".to_owned();
        assert!(validate(&bad).is_err());

        let mut bad = sample();
        bad.url = "http://nexdesk.ir/updates/a.exe".to_owned();
        assert!(validate(&bad).is_err());

        let mut bad = sample();
        bad.url = "https://evil.example.com/a.exe".to_owned();
        assert!(validate(&bad).is_err());

        let mut bad = sample();
        bad.url = "https://nexdesk.ir/updates/a.exe?x=1".to_owned();
        assert!(validate(&bad).is_err());

        let mut bad = sample();
        bad.size = 10;
        assert!(validate(&bad).is_err());
    }

    #[test]
    fn validate_rejects_control_characters() {
        let mut bad = sample();
        bad.version = "1.5.4\nschema=2".to_owned();
        assert!(validate(&bad).is_err());
    }
}
