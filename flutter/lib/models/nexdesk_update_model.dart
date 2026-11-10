import 'dart:async';
import 'dart:convert';

import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';

/// Event pushed by `src/nexdesk_update.rs` on every phase change.
///
/// The payload is `{"name": "nexdesk-update", "state": {...}}`; `state` is the
/// same snapshot `nexdeskUpdateState()` returns, so the UI has one parser.
const kEventNexDeskUpdate = 'nexdesk-update';

/// Immutable snapshot of the Rust `UpdateState`.
///
/// Kept deliberately flat: the dialog only needs to know which phase it is in,
/// how far the download got, and whether the publisher marked this release as
/// mandatory.
class NexDeskUpdateState {
  const NexDeskUpdateState({
    required this.phase,
    required this.current,
    required this.latest,
    required this.mandatory,
    required this.postponed,
    required this.minSupported,
    required this.retiredCurrent,
    required this.message,
    required this.notesFa,
    required this.notesEn,
    required this.url,
    required this.size,
    required this.downloaded,
    required this.error,
    required this.installKind,
    required this.canInstall,
  });

  final String phase;
  final String current;
  final String latest;
  final bool mandatory;
  final bool postponed;
  final String minSupported;

  /// The panel retired the running build, so updating is not optional.
  final bool retiredCurrent;

  /// Publisher's own wording for a retirement / forced update.
  final String message;
  final String notesFa;
  final String notesEn;
  final String url;
  final int size;
  final int downloaded;
  final String error;
  final String installKind;
  final bool canInstall;

  factory NexDeskUpdateState.fromJson(Map<String, dynamic> json) {
    int asInt(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;
    String asString(Object? value) => value is String ? value : '';
    bool asBool(Object? value) => value == true || value == 'true';

    return NexDeskUpdateState(
      phase: asString(json['phase']),
      current: asString(json['current']),
      latest: asString(json['latest']),
      mandatory: asBool(json['mandatory']),
      postponed: asBool(json['postponed']),
      minSupported: asString(json['min_supported']),
      retiredCurrent: asBool(json['retired_current']),
      message: asString(json['message']),
      notesFa: asString(json['notes_fa']),
      notesEn: asString(json['notes_en']),
      url: asString(json['url']),
      size: asInt(json['size']),
      downloaded: asInt(json['downloaded']),
      error: asString(json['error']),
      installKind: asString(json['install_kind']),
      canInstall: asBool(json['can_install']),
    );
  }

  bool get hasUpdate => latest.isNotEmpty && latest != current;

  bool get isDownloading =>
      phase == 'downloading' || phase == 'verifying' || phase == 'installing';

  bool get isInstalling => phase == 'verifying' || phase == 'installing';

  bool get isFailed => phase == 'failed';

  /// 0.0 - 1.0. Zero while the size is unknown (indeterminate bar).
  double get progress {
    if (size <= 0) return 0;
    final value = downloaded / size;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  String get notes => notesFa.isNotEmpty ? notesFa : notesEn;
}

/// Single owner of the update state for the whole app.
///
/// The Rust side owns the truth; this controller mirrors it and polls only
/// while a transfer is in flight, so an idle app costs nothing.
class NexDeskUpdateController extends GetxController {
  final state = Rxn<NexDeskUpdateState>();

  Timer? _poll;
  bool _started = false;

  /// Set by the UI: fired once per version when an update becomes installable.
  /// Kept as a callback so the model does not import the dialog layer.
  void Function()? onAvailable;

  /// Fired when a new session is attempted while a mandatory update is pending.
  void Function()? onBlockedConnection;

  String? _promptedVersion;

  /// True while a mandatory update is pending: the main window is blocked and
  /// new remote sessions must not start.
  bool get blocksNewConnections {
    final current = state.value;
    if (current == null || !current.mandatory) return false;
    return current.phase == 'available' ||
        current.phase == 'downloading' ||
        current.phase == 'failed';
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    platformFFI.registerEventHandler(
        kEventNexDeskUpdate, kEventNexDeskUpdate, _onEvent,
        replace: true);
    try {
      bind.nexdeskUpdateStart();
    } catch (_) {
      // Older builds without the new bridge simply have no updater.
    }
    await refresh();
  }

  Future<void> _onEvent(Map<String, dynamic> event) async {
    final payload = event['state'];
    if (payload is Map) {
      _apply(Map<String, dynamic>.from(payload));
    }
  }

  Future<void> refresh() async {
    try {
      final raw = bind.nexdeskUpdateState();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _apply(decoded);
      }
    } catch (_) {
      // Bridge missing or Rust side not ready; keep the last known state.
    }
  }

  void _apply(Map<String, dynamic> json) {
    final next = NexDeskUpdateState.fromJson(json);
    state.value = next;
    if (next.isDownloading) {
      _startPolling();
    } else {
      _stopPolling();
    }
    final shouldPrompt = next.phase == 'available' &&
        !next.postponed &&
        _promptedVersion != next.latest;
    if (shouldPrompt) {
      _promptedVersion = next.latest;
      onAvailable?.call();
    }
  }

  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(milliseconds: 500), (_) async {
      await refresh();
      if (state.value?.isDownloading != true) {
        _stopPolling();
      }
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  void checkNow() {
    try {
      bind.nexdeskUpdateCheck();
    } catch (_) {
      return;
    }
    // The Rust check runs on its own thread; a couple of polls is enough to
    // pick up the result without keeping a timer alive.
    Future.delayed(const Duration(seconds: 2), refresh);
    Future.delayed(const Duration(seconds: 6), refresh);
  }

  void install() {
    try {
      bind.nexdeskUpdateInstall();
    } catch (_) {
      return;
    }
    _startPolling();
  }

  void cancel() {
    try {
      bind.nexdeskUpdateCancel();
    } catch (_) {
      return;
    }
    refresh();
  }

  bool postpone() {
    try {
      final accepted = bind.nexdeskUpdatePostpone();
      refresh();
      return accepted;
    } catch (_) {
      return false;
    }
  }

  @override
  void onClose() {
    _stopPolling();
    super.onClose();
  }
}

final nexDeskUpdate = NexDeskUpdateController();
