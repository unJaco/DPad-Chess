import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../chess_controller.dart';
import '../chess_models.dart';
import '../game_page.dart';
import '../engine_service.dart';
import '../game_config.dart';
import '../keypad_widgets.dart';

/// Offline game configuration (2-player or vs-engine).
///
/// Input model (consistent with [OnlineSetupPage]): ↑/↓ move between rows,
/// ←/→ change the focused row's value, OK on the Start row launches, ↩ backs out.
///
/// Rows:
///   vs-engine : Play as · Strength · Time · Start
///   2-player  : Time · Start
class GameSetupPage extends StatefulWidget {
  const GameSetupPage({
    super.key,
    required this.mode,
    required this.controller,
    required this.settings,
  });

  final GameMode mode;
  final ChessController controller;
  final AppSettings settings;

  @override
  State<GameSetupPage> createState() => _GameSetupPageState();
}

class _GameSetupPageState extends State<GameSetupPage> {
  late final FocusNode _focusNode;

  PieceColor _color = PieceColor.white;
  EngineLevel _level = EngineLevel.intermediate;
  int _timeIndex = 0; // index into kOfflineTimeControls (0 = Unlimited)

  int _focusedRow = 0;

  bool get _isEngine => widget.mode == GameMode.vsEngine;

  int get _rowCount => _isEngine ? 4 : 2;
  int get _startRow => _rowCount - 1;
  int get _colorRow => _isEngine ? 0 : -1;
  int get _levelRow => _isEngine ? 1 : -1;
  int get _timeRow => _isEngine ? 2 : 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'game-setup');
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
      if (_focusedRow == _startRow) _startGame();
      return KeyEventResult.handled;
    }
    /*if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.goBack) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }*/
    return KeyEventResult.ignored;
  }

  void _step(int delta) {
    setState(() {
      if (_focusedRow == _colorRow) {
        _color = _color == PieceColor.white
            ? PieceColor.black
            : PieceColor.white;
      } else if (_focusedRow == _levelRow) {
        final next = (_level.index + delta).clamp(
          0,
          EngineLevel.values.length - 1,
        );
        _level = EngineLevel.values[next];
      } else if (_focusedRow == _timeRow) {
        _timeIndex = (_timeIndex + delta).clamp(
          0,
          kOfflineTimeControls.length - 1,
        );
      }
    });
  }

  void _startGame() {
    final tc = kOfflineTimeControls[_timeIndex];
    final color = _isEngine ? _color : PieceColor.white;
    widget.controller.startNewGame(
      mode: widget.mode,
      humanColor: color,
      level: _level,
      timeControl: tc,
      whiteBottom: widget.settings.resolveWhiteBottom(widget.mode, color),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            GamePage(controller: widget.controller, settings: widget.settings),
      ),
    );
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
        appBar: AppBar(title: Text(_isEngine ? 'Vs Computer' : 'Two Player')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isEngine) ...[
                  _label('Play as', _focusedRow == _colorRow, colors),
                  const SizedBox(height: 6),
                  KeypadOptionRow(
                    labels: const ['White', 'Black'],
                    selectedIndex: _color == PieceColor.white ? 0 : 1,
                    focusedIndex: _focusedRow == _colorRow
                        ? (_color == PieceColor.white ? 0 : 1)
                        : -1,
                    onTapIndex: (i) => setState(() {
                      _focusedRow = _colorRow;
                      _color = i == 0 ? PieceColor.white : PieceColor.black;
                    }),
                  ),
                  const SizedBox(height: 16),
                  _label('Strength', _focusedRow == _levelRow, colors),
                  const SizedBox(height: 6),
                  KeypadOptionRow(
                    labels: EngineLevel.values.map((l) => l.label).toList(),
                    selectedIndex: _level.index,
                    focusedIndex: _focusedRow == _levelRow ? _level.index : -1,
                    onTapIndex: (i) => setState(() {
                      _focusedRow = _levelRow;
                      _level = EngineLevel.values[i];
                    }),
                  ),
                  const SizedBox(height: 16),
                ],
                _label('Time', _focusedRow == _timeRow, colors),
                const SizedBox(height: 6),
                KeypadOptionRow(
                  labels: kOfflineTimeControls.map((t) => t.label).toList(),
                  selectedIndex: _timeIndex,
                  focusedIndex: _focusedRow == _timeRow ? _timeIndex : -1,
                  onTapIndex: (i) => setState(() {
                    _focusedRow = _timeRow;
                    _timeIndex = i;
                  }),
                ),
                const Spacer(),
                _StartButton(
                  focused: _focusedRow == _startRow,
                  onTap: _startGame,
                ),
                const SizedBox(height: 12),
                Text(
                  '↑↓ row  •  ←→ change  •  OK start  •  ↩ back',
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
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.focused, required this.onTap});

  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: focused ? colors.primary : Colors.transparent,
          width: 2.5,
        ),
      ),
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start Game'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }
}
