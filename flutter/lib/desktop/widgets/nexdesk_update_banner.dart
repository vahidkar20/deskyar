import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/models/nexdesk_update_model.dart';
import 'package:get/get.dart';

/// Persian-first copy, English fallback - same convention as the dialog.
String _t(String fa, String en) => isRtlLocale ? fa : en;

/// The app-wide update surface.
///
/// Two different jobs, deliberately kept apart:
///
///   * an **optional** update is a quiet card in the bottom-left corner - it
///     never steals focus and can be postponed for that exact version;
///   * a **mandatory** one covers the whole window, so the app cannot be used
///     until the download has been started. Nothing behind it is reachable:
///     the overlay is opaque and swallows every pointer event.
///
/// It is mounted through `MaterialApp.builder`, so it sits above every route,
/// dialog and snackbar rather than inside one page.
class NexDeskUpdateOverlay extends StatelessWidget {
  const NexDeskUpdateOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.maybeOf(context) ?? TextDirection.rtl;
    return Directionality(
      textDirection: direction,
      child: Stack(
        children: [
          child,
          Obx(() {
            final state = nexDeskUpdate.state.value;
            if (state == null || !state.hasUpdate) {
              return const SizedBox.shrink();
            }
            if (state.mandatory) {
              return _MandatoryBlocker(state: state);
            }
            if (state.postponed) {
              return const SizedBox.shrink();
            }
            return _AvailableBanner(state: state);
          }),
        ],
      ),
    );
  }
}

class _AvailableBanner extends StatelessWidget {
  const _AvailableBanner({required this.state});

  final NexDeskUpdateState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 16,
      bottom: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: scheme.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.system_update_alt_rounded,
                    size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('نسخه جدید برنامه در دسترس است',
                            'A new version is available'),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${state.current} → ${state.latest}',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => nexDeskUpdate.install(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              minimumSize: const Size(0, 32),
                            ),
                            child: Text(_t('دانلود', 'Download')),
                          ),
                          TextButton(
                            onPressed: () => nexDeskUpdate.postpone(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              minimumSize: const Size(0, 32),
                              foregroundColor: scheme.onSurfaceVariant,
                            ),
                            child: Text(_t('بعداً', 'Later')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MandatoryBlocker extends StatelessWidget {
  const _MandatoryBlocker({required this.state});

  final NexDeskUpdateState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final downloading = state.isDownloading;
    final message = state.message.isNotEmpty
        ? state.message
        : (state.retiredCurrent
            ? _t('پشتیبانی از این نسخه متوقف شده است.',
                'This version is no longer supported.')
            : _t('برای ادامه کار با برنامه باید نرم‌افزار را بروزرسانی کنید.',
                'You must update the app to keep using it.'));

    return Positioned.fill(
      child: ColoredBox(
        color: scheme.surface,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.gpp_maybe_rounded,
                      size: 56, color: scheme.error),
                  const SizedBox(height: 18),
                  Text(
                    _t('به‌روزرسانی اجباری', 'Required update'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, height: 1.7, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${state.current} → ${state.latest}',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  if (downloading) ...[
                    const SizedBox(height: 22),
                    LinearProgressIndicator(
                      value: state.size > 0 ? state.progress : null,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.size > 0
                          ? '${(state.progress * 100).toStringAsFixed(0)}%'
                          : _t('در حال آماده‌سازی…', 'Preparing…'),
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                  if (state.isFailed) ...[
                    const SizedBox(height: 14),
                    Text(
                      state.error,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: scheme.error),
                    ),
                  ],
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      onPressed: downloading ? null : () => nexDeskUpdate.install(),
                      icon: downloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded, size: 20),
                      label: Text(
                        downloading
                            ? _t('در حال دانلود…', 'Downloading…')
                            : _t('دانلود و به‌روزرسانی', 'Download and update'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
