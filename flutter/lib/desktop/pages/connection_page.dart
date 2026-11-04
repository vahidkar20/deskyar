// main window right pane

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/widgets/connection_page_title.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/anchor_menu.dart';
import 'package:flutter_hbb/desktop/widgets/install_banner.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../models/platform_model.dart';

class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

/// State for the connection page.
class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.find<RxBool>(tag: 'stop-service');
  Timer? _updateTimer;

  double get em => 14.0;
  double? get height => bind.isIncomingOnly() ? null : em * 3;

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    startServiceWidget() => Offstage(
          offstage: !_svcStopped.value,
          child: InkWell(
                  onTap: () async {
                    await start_service(true);
                  },
                  child: Text(translate("Start service"),
                      style: TextStyle(
                          decoration: TextDecoration.underline, fontSize: em)))
              .marginStart(em),
        );

    // Upstream nags "set up your own server" here. NexDesk replaces it with a
    // permanent attribution link, shown unconditionally so it reads as branding
    // rather than as a status warning.
    setupServerWidget() => Flexible(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(', ', style: TextStyle(fontSize: em)),
              Flexible(
                child: InkWell(
                  onTap: () => launchUrlString('https://yar.one'),
                  child: Text(
                    translate('powered_by_me'),
                    style: TextStyle(
                        decoration: TextDecoration.underline, fontSize: em),
                  ),
                ),
              )
            ],
          ),
        );

    basicWidget() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 8,
              width: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _svcStopped.value ||
                        stateGlobal.svcStatus.value == SvcStatus.connecting
                    ? kColorWarn
                    : (stateGlobal.svcStatus.value == SvcStatus.ready
                        ? Color.fromARGB(255, 50, 190, 166)
                        : Color.fromARGB(255, 224, 79, 95)),
              ),
            ).marginSymmetric(horizontal: em),
            Container(
              width: isIncomingOnly ? 226 : null,
              child: _buildConnStatusMsg(),
            ),
            // stop
            if (!isIncomingOnly) startServiceWidget(),
            // ready && public
            // No need to show the guide if is custom client.
            if (!isIncomingOnly) setupServerWidget(),
          ],
        );

    return Container(
      height: height,
      child: Obx(() => isIncomingOnly
          ? Column(
              children: [
                basicWidget(),
                Align(
                        child: startServiceWidget(),
                        alignment: AlignmentDirectional.centerStart)
                    .marginOnly(top: 2.0)
                    .paddingStart(22.0),
              ],
            )
          : basicWidget()),
    ).paddingStart(isIncomingOnly ? 8 : 0);
  }

  _buildConnStatusMsg() {
    widget.onSvcStatusChanged?.call();
    return Text(
      _svcStopped.value
          ? translate("Service is not running")
          : stateGlobal.svcStatus.value == SvcStatus.connecting
              ? translate("connecting_status")
              : stateGlobal.svcStatus.value == SvcStatus.notReady
                  ? translate("not_ready_status")
                  : translate('Ready'),
      style: TextStyle(fontSize: em),
    );
  }

  updateStatus() async {
    final status =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final statusNum = status['status_num'] as int;
    if (statusNum == 0) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    } else if (statusNum == -1) {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    } else if (statusNum == 1) {
      stateGlobal.svcStatus.value = SvcStatus.ready;
    } else {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    }
    try {
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
    } catch (_) {}
  }
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin, WindowListener {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();

  final RxBool _idInputFocused = false.obs;
  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  /// Mirrors "the ID field is not empty" so the primary button can disable
  /// itself without rebuilding the whole page on every keystroke.
  final RxBool _canConnect = false.obs;

  String selectedConnectionType = 'Connect';

  bool isWindowMinimized = false;

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    _canConnect.value = _idController.id.isNotEmpty;
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (!mounted) return;
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
            _canConnect.value = _idController.id.isNotEmpty;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    Get.put<IDTextEditingController>(_idController);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _idController.dispose();
    windowManager.removeListener(this);
    _allPeersLoader.clear();
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        // windows can't update when minimized.
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    // Remove edge border by setting the value to zero.
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    // Restore edge border to default edge size.
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    _idInputFocused.value = _idFocusNode.hasFocus;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Column(
      children: [
        // Portable-only prompt: one click promotes this run into a real
        // installation. Renders nothing once installed or dismissed.
        const NexDeskInstallBanner(),
        Expanded(
            child: Column(
          children: [
            Row(
              children: [
                Flexible(child: _buildRemoteIDTextField(context)),
              ],
            ).marginOnly(top: 24),
            const SizedBox(height: 12),
            Divider().paddingStart(12),
            Expanded(child: PeerTabPage()),
          ],
        )
            // 16 on the sidebar side so the connect card and its shadow do not
            // touch the panel, 12 on the window side as before.
            .paddingStart(16.0)
            .paddingEnd(12.0)),
        if (!isOutgoingOnly) const Divider(height: 1),
        if (!isOutgoingOnly) OnlineStatusWidget()
      ],
    );
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect(
      {bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTerminal = false,
      bool isTcpTunneling = false}) {
    // `id` strips the grouping spaces and any bidi isolates that came in with
    // a pasted value. Handing the formatted text to `connect` would send
    // "205 912 679" instead of "205912679" and never match a peer.
    final id = _idController.id;
    if (id.isEmpty) {
      showToast(translate('Please enter the remote ID'));
      _idFocusNode.requestFocus();
      return;
    }
    connect(context, id,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal,
        isTcpTunneling: isTcpTunneling);
  }

  /// Put [raw] into both controllers with a valid caret.
  ///
  /// The field controller is the one RawAutocomplete listens to, so it has to be
  /// updated through `value` (text + selection together) rather than `text`,
  /// which would leave the caret at -1 and send the next keystroke to the start
  /// of the string.
  void _applyId(String raw) {
    final id = trimID(raw);
    _idController.id = id;
    final formatted = formatID(id);
    _idEditingController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _canConnect.value = id.isNotEmpty;
  }

  /// Paste an ID from the clipboard, stripping grouping spaces and any bidi
  /// marks a chat client may have added. Support staff hand IDs out over chat,
  /// so this is the fastest path from "here is my ID" to a connection.
  Future<void> _pasteId() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final id = trimID(data?.text ?? '');
      if (id.isEmpty) return;
      _applyId(id);
      _idFocusNode.requestFocus();
    } catch (_) {
      // Clipboard access can fail when another process holds it; ignore.
    }
  }

  /// UI for the remote ID TextField.
  /// Search for a peer.
  Widget _buildRemoteIDTextField(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    var w = Container(
      width: 320 + 20 * 2,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // A brand-tinted panel rather than a flat bordered box: the connect
          // field is the one thing every user looks at first, and it should
          // read as the focal point of the page. The tint stays light enough
          // that the theme's own text colours remain readable, so nothing
          // inside has to be re-coloured for light vs dark.
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: isDark
                ? [const Color(0xFF082016), const Color(0xFF0D3522)]
                : [const Color(0xFFF5FCF7), const Color(0xFFE6F6EA)],
          ),
          border: Border.all(
            color: MyTheme.accent.withOpacity(isDark ? 0.35 : 0.28),
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : MyTheme.accent)
                  .withOpacity(isDark ? 0.30 : 0.09),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ]),
      child: Ink(
        child: Column(
          children: [
            getConnectionPageTitle(context, false).marginOnly(bottom: 12),
            Row(
              children: [
                Expanded(
                    child: RawAutocomplete<Peer>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text == '') {
                      _autocompleteOpts = const Iterable<Peer>.empty();
                    } else if (_allPeersLoader.peers.isEmpty &&
                        !_allPeersLoader.isPeersLoaded) {
                      Peer emptyPeer = Peer(
                        id: '',
                        username: '',
                        hostname: '',
                        alias: '',
                        platform: '',
                        tags: [],
                        hash: '',
                        password: '',
                        forceAlwaysRelay: false,
                        rdpPort: '',
                        rdpUsername: '',
                        loginName: '',
                        device_group_name: '',
                        note: '',
                      );
                      _autocompleteOpts = [emptyPeer];
                    } else {
                      String textWithoutSpaces =
                          textEditingValue.text.replaceAll(" ", "");
                      if (int.tryParse(textWithoutSpaces) != null) {
                        textEditingValue = TextEditingValue(
                          text: textWithoutSpaces,
                          selection: textEditingValue.selection,
                        );
                      }
                      String textToFind = textEditingValue.text.toLowerCase();
                      _autocompleteOpts = _allPeersLoader.peers
                          .where((peer) =>
                              peer.id.toLowerCase().contains(textToFind) ||
                              peer.username
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.hostname
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.alias.toLowerCase().contains(textToFind))
                          .toList();
                      _allPeersLoader.queryOnlines(_autocompleteOpts);
                    }
                    return _autocompleteOpts;
                  },
                  focusNode: _idFocusNode,
                  textEditingController: _idEditingController,
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController fieldTextEditingController,
                    FocusNode fieldFocusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    updateTextAndPreserveSelection(
                        fieldTextEditingController, _idController.text);
                    // The remote ID is digits only, grouped with spaces by
                    // IDTextInputFormatter. In the Persian (RTL) UI the bidi
                    // algorithm would paint those groups right-to-left, so the
                    // user would type 519502 and watch "205 915" appear. The
                    // field is pinned to LTR in every locale - numbers read
                    // left-to-right even in an RTL page - while the alignment
                    // follows the layout direction so the card keeps its RTL
                    // reading order.
                    return Obx(() => TextField(
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          focusNode: fieldFocusNode,
                          textDirection: kNumberTextDirection,
                          textAlign:
                              isRtlLocale ? TextAlign.right : TextAlign.start,
                          style: const TextStyle(
                                    fontSize: 20,
                            height: 1.4,
                          ),
                          maxLines: 1,
                          cursorColor:
                              Theme.of(context).textTheme.titleLarge?.color,
                          decoration: InputDecoration(
                              filled: false,
                              counterText: '',
                              hintText: _idInputFocused.value
                                  ? null
                                  : translate('Enter Remote ID'),
                              suffixIcon: IconButton(
                                onPressed: _pasteId,
                                tooltip: translate('Paste'),
                                iconSize: 17,
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.content_paste_rounded,
                                  color: MyTheme.accent.withOpacity(0.8),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 13)),
                          controller: fieldTextEditingController,
                          inputFormatters: [IDTextInputFormatter()],
                          onChanged: (v) {
                            _idController.id = v;
                            final ready = _idController.id.isNotEmpty;
                            if (ready != _canConnect.value) {
                              _canConnect.value = ready;
                            }
                          },
                          onSubmitted: (_) {
                            onConnect();
                          },
                        ).workaroundFreezeLinuxMint());
                  },
                  onSelected: (option) {
                    setState(() {
                      _idController.id = option.id;
                      _canConnect.value = _idController.id.isNotEmpty;
                      FocusScope.of(context).unfocus();
                    });
                  },
                  optionsViewBuilder: (BuildContext context,
                      AutocompleteOnSelected<Peer> onSelected,
                      Iterable<Peer> options) {
                    options = _autocompleteOpts;
                    double maxHeight = options.length * 50;
                    if (options.length == 1) {
                      maxHeight = 52;
                    } else if (options.length == 3) {
                      maxHeight = 146;
                    } else if (options.length == 4) {
                      maxHeight = 193;
                    }
                    maxHeight = maxHeight.clamp(0, 200);

                    return Align(
                      // Directional so the suggestion list lines up with the
                      // field's start edge in RTL instead of hanging off the
                      // opposite side.
                      alignment: AlignmentDirectional.topStart,
                      child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 5,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: Material(
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: maxHeight,
                                    maxWidth: 319,
                                  ),
                                  child: _allPeersLoader.peers.isEmpty &&
                                          !_allPeersLoader.isPeersLoaded
                                      ? Container(
                                          height: 80,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ))
                                      : Padding(
                                          padding:
                                              const EdgeInsets.only(top: 5),
                                          child: ListView(
                                            children: options
                                                .map((peer) =>
                                                    AutocompletePeerTile(
                                                        onSelect: () =>
                                                            onSelected(peer),
                                                        peer: peer))
                                                .toList(),
                                          ),
                                        ),
                                ),
                              ))),
                    );
                  },
                )),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14.0),
              child: Row(children: [
                // Full-width primary action. Upstream used a 28px-high button
                // pinned to the end of the row, which read as a secondary
                // control even though it is the only thing most users press.
                Expanded(
                  child: SizedBox(
                    height: 44.0,
                    child: Obx(() {
                      final ready = _canConnect.value;
                      return ElevatedButton.icon(
                        onPressed: ready ? () => onConnect() : null,
                        // Direction-neutral glyph: an arrow would point the
                        // wrong way in the RTL layout.
                        icon: const Icon(Icons.link_rounded, size: 18),
                        label: Text(translate("Connect")),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MyTheme.button,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              MyTheme.button.withOpacity(0.32),
                          disabledForegroundColor:
                              Colors.white.withOpacity(0.55),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                // Secondary actions (file transfer, camera, terminal, tunnel).
                // The menu is anchored to this button rather than to the tap
                // position, so it always opens directly under it - see
                // widgets/anchor_menu.dart for why the stock showMenu call
                // landed in the middle of the window.
                AnchorMenu(
                  width: 210,
                  tooltip: translate('More'),
                  items: [
                    AnchorMenuItem(
                      label: translate('Transfer file'),
                      icon: Icons.drive_folder_upload_rounded,
                      onTap: () => onConnect(isFileTransfer: true),
                    ),
                    AnchorMenuItem(
                      label: translate('View camera'),
                      icon: Icons.videocam_outlined,
                      onTap: () => onConnect(isViewCamera: true),
                    ),
                    AnchorMenuItem(
                      label: '${translate('Terminal')} (beta)',
                      icon: Icons.terminal_rounded,
                      onTap: () => onConnect(isTerminal: true),
                    ),
                    // `connect` routes this through the desktop path only; the
                    // peer card gates it the same way.
                    if (isDesktop)
                      AnchorMenuItem(
                        label: translate('TCP tunneling'),
                        icon: Icons.cable_rounded,
                        onTap: () => onConnect(isTcpTunneling: true),
                      ),
                  ],
                  childBuilder: (context, open) => AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    height: 44.0,
                    width: 44.0,
                    decoration: BoxDecoration(
                      color: open
                          ? MyTheme.accent.withOpacity(0.14)
                          : Colors.transparent,
                      border: Border.all(
                        color: MyTheme.accent.withOpacity(open ? 0.75 : 0.45),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: MyTheme.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
    return Container(
        constraints: const BoxConstraints(maxWidth: 600), child: w);
  }
}
