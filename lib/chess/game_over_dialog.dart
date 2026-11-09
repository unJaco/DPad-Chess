import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Game over dialog ──────────────────────────────────────────────────────────
//
// Keypad-navigable end-of-game options: ↑↓ move, OK activate.

class GameOverDialog extends StatefulWidget {
  const GameOverDialog({
    super.key,
    required this.resultText,
    required this.isOnline,
    required this.onPlayAgain,
    required this.onReview,
    required this.onMainMenu,
  });

  final String resultText;
  final bool isOnline;
  final VoidCallback onPlayAgain;
  final VoidCallback onReview;
  final VoidCallback onMainMenu;

  @override
  State<GameOverDialog> createState() => GameOverDialogState();
}

class GameOverDialogState extends State<GameOverDialog> {
  late final FocusNode _focusNode;
  late final List<({String label, IconData icon, VoidCallback action})>
  _options;
  int _focused = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _options = [
      (
        label: widget.isOnline ? 'New Game' : 'Play Again',
        icon: Icons.replay,
        action: widget.onPlayAgain,
      ),
      (label: 'Review Game', icon: Icons.history, action: widget.onReview),
      (
        label: 'Main Menu',
        icon: Icons.home_outlined,
        action: widget.onMainMenu,
      ),
    ];
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
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
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _focused = (_focused + 1) % _options.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _focused = (_focused - 1 + _options.length) % _options.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      _options[_focused].action();
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
          title: Text(widget.resultText),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List.generate(_options.length, (i) {
              final opt = _options[i];
              final focused = i == _focused;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: GestureDetector(
                  onTap: opt.action,
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
                        color: focused ? colors.primary : colors.outlineVariant,
                        width: focused ? 2.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          opt.icon,
                          size: 20,
                          color: focused
                              ? colors.onPrimaryContainer
                              : colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
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
          ),
        ),
      ),
    );
  }
}
