import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../chess_controller.dart';
import '../chess_models.dart';
import '../game_page.dart';
import '../game_config.dart';
import '../token_entry_dialog.dart';

// TODO: Add seek for real opponent matchmaking

/// Online (Lichess AI) game configuration, as a full page.
///
/// Input model: ↑/↓ move between rows, ←/→ change the focused row's value, OK
/// on the Play row starts (after ensuring a token), ↩ backs out.
class OnlineSetupPage extends StatefulWidget {
  const OnlineSetupPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ChessController controller;
  final AppSettings settings;

  @override
  State<OnlineSetupPage> createState() => _OnlineSetupPageState();
}

class _OnlineSetupPageState extends State<OnlineSetupPage> {
  static const _rowLevel = 0;
  static const _rowColor = 1;
  static const _rowTime = 2;
  static const _rowAct = 3;
  static const _rowCount = 4;

  int _focusedRow = _rowLevel;
  int _level = 1; // 1–8
  int _colorIndex = 2; // 0=White, 1=Black, 2=Random
  int _timeIndex = 1; // index into kOnlineTimeControls

  bool _loading = false;
  String? _error;

  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'online-setup');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // ── Input ───────────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _focusedRow = (_focusedRow - 1).clamp(0, _rowCount - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _focusedRow = (_focusedRow + 1).clamp(0, _rowCount - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      if (_focusedRow == _rowAct) _play();
      return KeyEventResult.handled;
    }
    /*if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      if (!_loading) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }*/
    return KeyEventResult.ignored;
  }

  void _step(int delta) {
    setState(() {
      switch (_focusedRow) {
        case _rowLevel:
          _level = (_level + delta).clamp(1, 8);
        case _rowColor:
          _colorIndex = (_colorIndex + delta).clamp(0, 2);
        case _rowTime:
          _timeIndex = (_timeIndex + delta).clamp(
            0,
            kOnlineTimeControls.length - 1,
          );
        case _rowAct:
          break;
      }
    });
  }

  // ── Play ────────────────────────────────────────────────────────────────────

  Future<void> _play() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final service = widget.controller.lichessService;
    try {
      // Ensure we have a usable token (prompt for one if missing).
      final token = await service.loadToken();
      if (!mounted) return;
      if (token == null) {
        final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => TokenEntryDialog(
            lichessService: service,
            onSuccess: () => Navigator.of(ctx).pop(true),
            onCancel: () => Navigator.of(ctx).pop(false),
          ),
        );
        if (ok != true) {
          if (mounted) setState(() => _loading = false);
          return;
        }
      }

      final tc = kOnlineTimeControls[_timeIndex];
      final colorStr = ['white', 'black', 'random'][_colorIndex];

      final gameId = await service.seekAi(
        level: _level,
        clockLimitSeconds: tc.limitSeconds,
        clockIncrementSeconds: tc.incrementSeconds,
        color: colorStr,
      );

      // Random color is resolved server-side and corrected when the gameFull
      // event arrives, so pass white as a placeholder.
      final myColor = _colorIndex == 0
          ? PieceColor.white
          : _colorIndex == 1
          ? PieceColor.black
          : PieceColor.white;

      if (!mounted) return;
      await widget.controller.startOnlineGame(
        gameId: gameId,
        myColor: myColor,
        timeControl: tc,
      );

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GamePage(
            controller: widget.controller,
            settings: widget.settings,
          ),
        ),
      );
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Play Online')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('AI Level', _focusedRow == _rowLevel, colors),
                const SizedBox(height: 6),
                _levelRow(colors),
                const SizedBox(height: 16),
                _label('Play as', _focusedRow == _rowColor, colors),
                const SizedBox(height: 6),
                _choiceRow(
                  const ['White', 'Black', 'Random'],
                  _colorIndex,
                  _focusedRow == _rowColor,
                  (i) => setState(() {
                    _focusedRow = _rowColor;
                    _colorIndex = i;
                  }),
                  colors,
                ),
                const SizedBox(height: 16),
                _label('Time', _focusedRow == _rowTime, colors),
                const SizedBox(height: 6),
                _choiceRow(
                  kOnlineTimeControls.map((t) => t.label).toList(),
                  _timeIndex,
                  _focusedRow == _rowTime,
                  (i) => setState(() {
                    _focusedRow = _rowTime;
                    _timeIndex = i;
                  }),
                  colors,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _focusedRow == _rowAct
                          ? colors.primary
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _play,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.public),
                    label: Text(_loading ? 'Connecting…' : 'Play'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '↑↓ row  •  ←→ change  •  OK play  •  ↩ back',
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

  Widget _label(String text, bool focused, ColorScheme colors) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: focused ? FontWeight.bold : FontWeight.w600,
        letterSpacing: 0.6,
        color: focused ? colors.primary : colors.onSurfaceVariant,
      ),
    );
  }

  Widget _levelRow(ColorScheme colors) {
    final focused = _focusedRow == _rowLevel;
    return Row(
      children: List.generate(8, (i) {
        final lvl = i + 1;
        final selected = lvl == _level;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _focusedRow = _rowLevel;
              _level = lvl;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected && focused
                      ? colors.primary
                      : colors.outlineVariant,
                  width: selected && focused ? 2 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  '$lvl',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _choiceRow(
    List<String> labels,
    int selectedIndex,
    bool rowFocused,
    ValueChanged<int> onTap,
    ColorScheme colors,
  ) {
    return Row(
      children: List.generate(labels.length, (i) {
        final selected = i == selectedIndex;
        return Expanded(
          child: GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected && rowFocused
                      ? colors.primary
                      : colors.outlineVariant,
                  width: selected && rowFocused ? 2 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? colors.onPrimaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
