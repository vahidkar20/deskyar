import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/nexdesk_update_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

/// Persian-first copy, English fallback.
///
/// The app ships a Persian UI; the new update strings live here rather than in
/// the shared translation table because they are product-specific and this file
/// is the only place that renders them.
String _t(String fa, String en) => isRtlLocale ? fa : en;

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

/// Show the update prompt for the current state.
///
/// Mandatory updates are unskippable: no cancel button, no close glyph, Esc is
/// swallowed by `onCancel` and the mask does not dismiss. Optional ones can be
/// postponed for that exact version.
void showNexDeskUpdateDialog({bool forceMandatory = false, int attempt = 0}) {
  final current = nexDeskUpdate.state.value;
  if (current == null || !current.hasUpdate) return;

  final mandatory = forceMandatory || current.mandatory;
  final tag = 'nexdesk-update-${current.latest}';

  gFFI.dialogManager.show((setState, close, context) {
    return Obx(() {
      final state = nexDeskUpdate.state.value ?? current;
      return CustomAlertDialog(
        title: Row(
          children: [
            Icon(
              mandatory ? Icons.system_update_alt_rounded : Icons.new_releases_outlined,
              size: 20,
              color: mandatory ? Colors.orangeAccent : MyTheme.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mandatory
                    ? _t('به‌روزرسانی اجباری', 'Required update')
                    : _t('نسخه جدید NexDesk', 'NexDesk update'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: _UpdateBody(state: state, mandatory: mandatory),
        actions: _buildActions(context, close, state, mandatory),
        // Esc must not close a mandatory prompt.
        onCancel: mandatory ? () {} : close,
        onSubmit: state.canInstall ? () => nexDeskUpdate.install() : null,
      );
    });
  }, tag: tag).catchError((Object _) {
    // The overlay is not mounted during the first frames of startup; retry a
    // few times instead of dropping the prompt.
    if (attempt < 5) {
      Future.delayed(const Duration(seconds: 2),
          () => showNexDeskUpdateDialog(forceMandatory: forceMandatory, attempt: attempt + 1));
    }
    return null;
  });
}

List<Widget> _buildActions(
    BuildContext context, VoidCallback close, NexDeskUpdateState state, bool mandatory) {
  final actions = <Widget>[];

  if (state.isDownloading) {
    if (!mandatory) {
      actions.add(dialogButton(
        _t('انصراف', 'Cancel'),
        onPressed: () {
          nexDeskUpdate.cancel();
        },
        isOutline: true,
      ));
    }
    return actions;
  }

  if (state.isFailed) {
    if (!mandatory) {
      actions.add(dialogButton(_t('بستن', 'Close'), onPressed: close, isOutline: true));
    }
    actions.add(dialogButton(
      _t('تلاش دوباره', 'Try again'),
      onPressed: state.url.isEmpty ? null : () => nexDeskUpdate.install(),
    ));
    return actions;
  }

  if (state.canInstall) {
    if (!mandatory) {
      actions.add(dialogButton(
        _t('بعداً', 'Later'),
        onPressed: () {
          nexDeskUpdate.postpone();
          close();
        },
        isOutline: true,
      ));
    }
    actions.add(dialogButton(
      _t('دانلود و نصب', 'Download and install'),
      onPressed: () => nexDeskUpdate.install(),
    ));
  }
  return actions;
}

class _UpdateBody extends StatelessWidget {
  const _UpdateBody({required this.state, required this.mandatory});

  final NexDeskUpdateState state;
  final bool mandatory;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyMedium?.color;
    final notes = state.notes;

    return SizedBox(
      width: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                '${state.current}  →  ${state.latest}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                textDirection: TextDirection.ltr,
              ),
              const Spacer(),
              Text(
                _t('حجم ${_mb(state.size)} مگابایت', '${_mb(state.size)} MB'),
                style: TextStyle(fontSize: 11, color: textColor?.withOpacity(0.6)),
              ),
            ],
          ),
          if (mandatory)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _t(
                  'این نسخه برای ادامه کار الزامی است. تا نصب آن، برنامه قابل استفاده نیست.',
                  'This update is required. The app stays locked until it is installed.',
                ),
                style: TextStyle(fontSize: 12, height: 1.7, color: textColor?.withOpacity(0.85)),
              ),
            ),
          if (notes.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MyTheme.accent.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                notes,
                style: TextStyle(fontSize: 12, height: 1.8, color: textColor),
              ),
            ),
          const SizedBox(height: 14),
          if (state.isDownloading) _progress(context),
          if (state.isFailed && state.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                state.error,
                style: const TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
          if (state.url.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  minimumSize: const Size(0, 28),
                ),
                onPressed: () => launchUrl(Uri.parse(state.url)),
                child: Text(
                  _t('دانلود دستی', 'Download manually'),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _progress(BuildContext context) {
    final percent = (state.progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: state.isInstalling || state.size <= 0 ? null : state.progress,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          state.isInstalling
              ? _t('در حال نصب… پنجره تأیید ویندوز (UAC) را بپذیرید',
                  'Installing… accept the Windows (UAC) prompt')
              : _t(
                  '$percent٪ — ${_mb(state.downloaded)} از ${_mb(state.size)} مگابایت',
                  '$percent% — ${_mb(state.downloaded)} of ${_mb(state.size)} MB',
                ),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8),
          ),
        ),
      ],
    );
  }
}
