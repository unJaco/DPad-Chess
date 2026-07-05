import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One row in a [KeypadMenuScaffold].
class KeypadMenuItem {
  const KeypadMenuItem({
    required this.label,
    required this.onSelect,
    this.subtitle,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback onSelect;
  final bool enabled;
}

/// A full-screen, keypad-navigable vertical menu.
///
/// ↑/↓ move between (enabled) items, OK/Enter/Select/Space activates, and
/// 0/Esc triggers [onBack] (pass null on a home screen with nowhere to go
/// back to). Mirrors the manual D-pad pattern used by the in-game dialogs.
class KeypadMenuScaffold extends StatefulWidget {
  const KeypadMenuScaffold({
    super.key,
    required this.title,
    required this.items,
    this.subtitle,
    this.header,
    this.footerHint = '↑↓ move  •  OK select  •  ↩ back',
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final Widget? header;
  final String footerHint;
  final List<KeypadMenuItem> items;
  final VoidCallback? onBack;

  @override
  State<KeypadMenuScaffold> createState() => _KeypadMenuScaffoldState();
}

class _KeypadMenuScaffoldState extends State<KeypadMenuScaffold> {
  late final FocusNode _focusNode;
  int _focused = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'keypad-menu');
    _focused = _firstEnabled();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  int _firstEnabled() {
    for (var i = 0; i < widget.items.length; i++) {
      if (widget.items[i].enabled) return i;
    }
    return 0;
  }

  void _move(int delta) {
    final n = widget.items.length;
    if (n == 0) return;
    var i = _focused;
    for (var step = 0; step < n; step++) {
      i = (i + delta) % n;
      if (i < 0) i += n;
      if (widget.items[i].enabled) {
        setState(() => _focused = i);
        return;
      }
    }
  }

  void _activate() {
    if (_focused < 0 || _focused >= widget.items.length) return;
    final item = widget.items[_focused];
    if (item.enabled) item.onSelect();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      _activate();
      return KeyEventResult.handled;
    }
    /*if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.goBack) {
      widget.onBack?.call();
      return KeyEventResult.handled;
    }*/
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title, style: theme.textTheme.headlineSmall),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (widget.header != null) ...[
                  const SizedBox(height: 12),
                  widget.header!,
                ],
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: widget.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _MenuTile(
                      item: widget.items[i],
                      focused: i == _focused,
                      onTap: () {
                        setState(() => _focused = i);
                        if (widget.items[i].enabled) widget.items[i].onSelect();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.footerHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
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

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.item,
    required this.focused,
    required this.onTap,
  });

  final KeypadMenuItem item;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = item.enabled;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: focused
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused ? colors.primary : colors.outlineVariant,
            width: focused ? 2.5 : 1,
          ),
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  color: focused
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: focused ? FontWeight.bold : FontWeight.w500,
                        color: focused
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                    if (item.subtitle != null)
                      Text(
                        item.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: focused
                              ? colors.onPrimaryContainer.withValues(alpha: 0.8)
                              : colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (focused)
                Icon(Icons.chevron_right, color: colors.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// A horizontal row of selectable chips, used by the setup pages.
///
/// [selectedIndex] is the chosen value; [focusedIndex] is the column under the
/// D-pad cursor (or -1 when this row isn't the focused row).
class KeypadOptionRow extends StatelessWidget {
  const KeypadOptionRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    this.focusedIndex = -1,
    this.onTapIndex,
  });

  final List<String> labels;
  final int selectedIndex;
  final int focusedIndex;
  final ValueChanged<int>? onTapIndex;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(labels.length, (col) {
        final isFocused = focusedIndex == col;
        final isSelected = selectedIndex == col;
        return GestureDetector(
          onTap: onTapIndex == null ? null : () => onTapIndex!(col),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isFocused
                    ? colors.primary
                    : isSelected
                    ? colors.primary.withValues(alpha: 0.4)
                    : colors.outlineVariant,
                width: isFocused ? 2.5 : 1,
              ),
            ),
            child: Text(
              labels[col],
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? colors.onPrimaryContainer
                    : colors.onSurface,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ── Keypad choice dialog ──────────────────────────────────────────────────────

/// One option in a [showKeypadChoiceDialog].
class KeypadDialogOption {
  const KeypadDialogOption({
    required this.label,
    required this.onSelect,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onSelect;
}

/// Shows a modal, keypad-navigable choice dialog: ↑/↓ move, OK activates the
/// focused option. The dialog itself does not pop — each option's [onSelect] is
/// responsible for dismissing it (typically `Navigator.pop(ctx)` first).
Future<void> showKeypadChoiceDialog(
  BuildContext context, {
  required String title,
  String? message,
  required List<KeypadDialogOption> options,
  bool barrierDismissible = false,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) =>
        _KeypadChoiceDialog(title: title, message: message, options: options),
  );
}

class _KeypadChoiceDialog extends StatefulWidget {
  const _KeypadChoiceDialog({
    required this.title,
    required this.options,
    this.message,
  });

  final String title;
  final String? message;
  final List<KeypadDialogOption> options;

  @override
  State<_KeypadChoiceDialog> createState() => _KeypadChoiceDialogState();
}

class _KeypadChoiceDialogState extends State<_KeypadChoiceDialog> {
  late final FocusNode _focusNode;
  int _focused = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final n = widget.options.length;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _focused = (_focused + 1) % n);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _focused = (_focused - 1 + n) % n);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      widget.options[_focused].onSelect();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: AlertDialog(
          title: Text(widget.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.message != null) ...[
                Text(widget.message!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
              ],
              ...List.generate(widget.options.length, (i) {
                final opt = widget.options[i];
                final focused = i == _focused;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: GestureDetector(
                    onTap: opt.onSelect,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: focused
                            ? colors.primaryContainer
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: focused
                              ? colors.primary
                              : colors.outlineVariant,
                          width: focused ? 2.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (opt.icon != null) ...[
                            Icon(
                              opt.icon,
                              size: 20,
                              color: focused
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                          ],
                          Text(
                            opt.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: focused
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: focused
                                  ? colors.onPrimaryContainer
                                  : colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
