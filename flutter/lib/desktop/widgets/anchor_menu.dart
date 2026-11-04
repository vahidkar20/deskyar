// A small dropdown that is anchored to the widget that opens it.
//
// The material `showMenu` API takes a `RelativeRect` describing the anchor as
// *insets from the four edges of the overlay*, not as a point. Passing a global
// tap position as both `left` and `right` - which is easy to do and looks
// plausible - makes the menu land nowhere near the button, and the error is
// worse in RTL because the layout delegate mirrors the anchor. This widget
// computes the position from the trigger's own render box, so it stays attached
// to the button in either direction and is clamped to the window.
//
// It also gives the menu a look that matches the rest of NexDesk (rounded card,
// brand border, icon per row, hover highlight) instead of the stock Material
// popup, which is what the connection page needs.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../common.dart';

/// One row of an [AnchorMenu].
class AnchorMenuItem {
  const AnchorMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
}

/// A button that opens a menu anchored to its own bounds.
///
/// [childBuilder] receives the open state so the trigger can animate (rotate a
/// chevron, tint its background) without the caller having to own the menu.
class AnchorMenu extends StatefulWidget {
  const AnchorMenu({
    Key? key,
    required this.items,
    required this.childBuilder,
    this.tooltip,
    this.width = 216,
    this.rowHeight = 40,
    this.alignment = AnchorMenuAlignment.start,
  }) : super(key: key);

  final List<AnchorMenuItem> items;
  final Widget Function(BuildContext context, bool open) childBuilder;
  final String? tooltip;

  /// Fixed menu width. A fixed width keeps the card from resizing between
  /// openings and makes the edge clamping deterministic.
  final double width;
  final double rowHeight;

  /// Which edge of the trigger the menu is aligned to.
  final AnchorMenuAlignment alignment;

  @override
  State<AnchorMenu> createState() => _AnchorMenuState();
}

/// Horizontal alignment of a menu relative to its trigger.
enum AnchorMenuAlignment {
  /// Align the menu's reading-start edge with the trigger's start edge.
  start,

  /// Align the menu's reading-end edge with the trigger's end edge.
  end,
}

class _AnchorMenuState extends State<AnchorMenu> {
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _entry;
  bool _open = false;

  @override
  void dispose() {
    _removeEntry();
    super.dispose();
  }

  void _removeEntry() {
    final entry = _entry;
    _entry = null;
    _open = false;
    // `mounted` is false once the overlay itself is being torn down (window
    // closing), and removing an entry that is no longer inserted asserts.
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }

  void _close() {
    if (_entry == null) return;
    _removeEntry();
    if (mounted) setState(() {});
  }

  void _toggle() => _open ? _close() : _show();

  void _show() {
    if (_entry != null) return;
    final anchorContext = _anchorKey.currentContext;
    if (anchorContext == null) return;
    final anchorBox = anchorContext.findRenderObject();
    if (anchorBox is! RenderBox || !anchorBox.hasSize) return;

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject();
    if (overlayBox is! RenderBox) return;

    final overlaySize = overlayBox.size;
    final anchorTopLeft =
        anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final anchorRect = anchorTopLeft & anchorBox.size;

    final rtl = Directionality.of(context) == TextDirection.rtl;
    final menuWidth = math.min(widget.width, overlaySize.width - 16);
    final menuHeight = widget.items.length * widget.rowHeight + 12;

    // Horizontal: attach to the requested edge of the trigger, then keep the
    // whole card inside the window.
    final bool alignToEnd = widget.alignment == AnchorMenuAlignment.end;
    double left = alignToEnd
        ? (rtl ? anchorRect.left : anchorRect.right - menuWidth)
        : (rtl ? anchorRect.right - menuWidth : anchorRect.left);
    left = left
        .clamp(8.0, math.max(8.0, overlaySize.width - menuWidth - 8.0))
        .toDouble();

    // Vertical: below the trigger, flipping above when there is no room.
    double top = anchorRect.bottom + 6;
    if (top + menuHeight > overlaySize.height - 8) {
      top = anchorRect.top - menuHeight - 6;
    }
    top = top
        .clamp(8.0, math.max(8.0, overlaySize.height - menuHeight - 8.0))
        .toDouble();

    _entry = OverlayEntry(
      builder: (overlayContext) => _MenuOverlay(
        left: left,
        top: top,
        width: menuWidth,
        rowHeight: widget.rowHeight,
        rtl: rtl,
        items: widget.items,
        onDismiss: _close,
      ),
    );
    overlay.insert(_entry!);
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final trigger = GestureDetector(
      key: _anchorKey,
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: widget.childBuilder(context, _open),
    );
    if (widget.tooltip == null) return trigger;
    return Tooltip(message: widget.tooltip!, waitDuration: const Duration(milliseconds: 400), child: trigger);
  }
}

class _MenuOverlay extends StatefulWidget {
  const _MenuOverlay({
    required this.left,
    required this.top,
    required this.width,
    required this.rowHeight,
    required this.rtl,
    required this.items,
    required this.onDismiss,
  });

  final double left;
  final double top;
  final double width;
  final double rowHeight;
  final bool rtl;
  final List<AnchorMenuItem> items;
  final VoidCallback onDismiss;

  @override
  State<_MenuOverlay> createState() => _MenuOverlayState();
}

class _MenuOverlayState extends State<_MenuOverlay> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'anchor-menu');

  @override
  void initState() {
    super.initState();
    // Take focus so Escape closes the menu and so a click anywhere else is
    // reported as a focus loss even if it lands on a widget that swallows taps.
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && mounted) widget.onDismiss();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = MyTheme.accent;
    final surface = isDark ? const Color(0xFF0E2317) : Colors.white;
    final border = isDark
        ? const Color(0xFF1C4529)
        : accent.withOpacity(0.22);

    return Directionality(
      textDirection: widget.rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Stack(
        children: [
          // Full-window barrier: a click anywhere outside dismisses. The
          // trigger itself is covered too, so it cannot reopen the menu in the
          // same gesture.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onDismiss,
              onSecondaryTap: widget.onDismiss,
            ),
          ),
          Positioned(
            left: widget.left,
            top: widget.top,
            width: widget.width,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(
                  scale: 0.96 + 0.04 * t,
                  alignment: widget.rtl
                      ? Alignment.topRight
                      : Alignment.topLeft,
                  child: child,
                ),
              ),
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.escape):
                      widget.onDismiss,
                },
                child: Focus(
                  focusNode: _focusNode,
                  child: Material(
                    color: surface,
                    elevation: 14,
                    shadowColor: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final item in widget.items)
                            _MenuRow(
                              item: item,
                              height: widget.rowHeight,
                              onSelected: () {
                                widget.onDismiss();
                                item.onTap();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.item,
    required this.height,
    required this.onSelected,
  });

  final AnchorMenuItem item;
  final double height;
  final VoidCallback onSelected;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.item.enabled;
    final accent = MyTheme.accent;
    final textColor = Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).textTheme.titleLarge?.color;
    final color = enabled
        ? (_hover ? accent : textColor)
        : (textColor?.withOpacity(0.38) ?? Colors.grey);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? widget.onSelected : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: widget.height,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover && enabled
                ? accent.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.item.icon, size: 17, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
