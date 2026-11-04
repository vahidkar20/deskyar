import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

/// Local option key remembering that the user waved the banner away.
const kOptionInstallBannerDismissed = 'nexdesk-install-banner-dismissed';

enum _Phase { idle, running, done, failed }

/// Call-to-action that promotes a portable NexDesk run into a real Windows
/// installation.
///
/// Upstream only reaches the installer through the `--install` command line
/// flag, which nobody who double-clicks a portable exe will ever find. This
/// banner surfaces the same code path (`install_install_me`) as a single,
/// obvious button on the home page, and disappears once the app is installed.
///
/// Installing moves the binary to `%ProgramFiles%`, registers an uninstaller,
/// creates start-menu / desktop shortcuts and enables the background service,
/// so NexDesk keeps accepting incoming connections after a reboot.
class NexDeskInstallBanner extends StatefulWidget {
  const NexDeskInstallBanner({Key? key}) : super(key: key);

  @override
  State<NexDeskInstallBanner> createState() => _NexDeskInstallBannerState();
}

class _NexDeskInstallBannerState extends State<NexDeskInstallBanner> {
  _Phase _phase = _Phase.idle;
  bool _eligible = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _eligible = _evaluate();
  }

  /// Only Windows portable runs have anything to promote. Installed builds,
  /// mobile, and the web client skip the banner entirely.
  bool _evaluate() {
    try {
      if (!isWindows || !isDesktop) return false;
      if (bind.mainIsInstalled()) return false;
      // Respect a policy that forbids installation entirely.
      if (bind.isDisableInstallation()) return false;
      final dismissed =
          bind.mainGetLocalOption(key: kOptionInstallBannerDismissed) == 'Y';
      return !dismissed;
    } catch (_) {
      return false;
    }
  }

  bool get _fa => Get.locale?.languageCode == 'fa';

  String _t(String fa, String en) => _fa ? fa : en;

  Future<void> _install() async {
    setState(() {
      _phase = _Phase.running;
      _error = '';
    });
    try {
      final path = bind.installInstallPath();
      await bind.installInstallMe(
        options: 'startmenu desktopicon',
        path: path,
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.done);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _error = e.toString();
      });
    }
  }

  void _dismiss() {
    bind.mainSetLocalOption(key: kOptionInstallBannerDismissed, value: 'Y');
    setState(() => _eligible = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_eligible) return const SizedBox.shrink();

    final accent = MyTheme.accent;
    final fg = Theme.of(context).textTheme.titleLarge?.color;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [accent.withOpacity(0.16), accent.withOpacity(0.03)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withOpacity(0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: loadIcon(38),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t(
                    'نکس دسک را روی این کامپیوتر نصب کنید',
                    'Install NexDesk on this computer',
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _t(
                    'نسخه‌ای که اجرا کرده‌اید موقت است. با نصب، نکس دسک در Program Files قرار می‌گیرد، '
                        'میان‌بر می‌سازد و سرویس پس‌زمینه را فعال می‌کند تا پس از ری‌استارت هم در دسترس باشد.',
                    'You are running the portable build. Installing moves NexDesk to '
                        'Program Files, adds shortcuts and enables the background '
                        'service so it stays reachable after a reboot.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: fg?.withOpacity(0.72),
                  ),
                ),
                const SizedBox(height: 12),
                _buildActions(context, accent, fg),
              ],
            ),
          ),
          if (_phase == _Phase.idle)
            IconButton(
              tooltip: _t('بستن', 'Dismiss'),
              onPressed: _dismiss,
              iconSize: 16,
              icon: Icon(Icons.close_rounded, color: fg?.withOpacity(0.55)),
            ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, Color accent, Color? fg) {
    switch (_phase) {
      case _Phase.running:
        return Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent),
            ),
            const SizedBox(width: 10),
            Text(
              _t('در حال نصب…', 'Installing…'),
              style: TextStyle(fontSize: 13, color: fg),
            ),
          ],
        );

      case _Phase.done:
        return Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _t(
                  'نصب کامل شد. نسخه نصب‌شده به‌زودی باز می‌شود.',
                  'Installed. The installed build is starting now.',
                ),
                style: TextStyle(fontSize: 13, color: fg),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => windowManager.close(),
              child: Text(_t('بستن این پنجره', 'Close this window')),
            ),
          ],
        );

      case _Phase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('نصب انجام نشد.', 'Installation failed.'),
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _error,
                  style: TextStyle(
                    fontSize: 11,
                    color: fg?.withOpacity(0.6),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _install,
              child: Text(_t('تلاش دوباره', 'Retry')),
            ),
          ],
        );

      case _Phase.idle:
        return Row(
          children: [
            ElevatedButton.icon(
              onPressed: _install,
              icon: const Icon(Icons.download_rounded, size: 17),
              label: Text(_t('نصب برنامه', 'Install NexDesk')),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: _dismiss,
              child: Text(_t('بعداً', 'Later')),
            ),
          ],
        );
    }
  }
}
