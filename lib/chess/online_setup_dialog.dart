import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chess_controller.dart';
import 'chess_models.dart';

// TODO: Add seek for real opponent matchmaking

// ── Time-control option ───────────────────────────────────────────────────────

class _TimeControl {
  const _TimeControl(this.label, this.limitSeconds, this.incrementSeconds);
  final String label;
  final int limitSeconds;
  final int incrementSeconds;
}

const _timeControls = [
  _TimeControl('3+2',  180,  2),
  _TimeControl('5+0',  300,  0),
  _TimeControl('10+0', 600,  0),
  _TimeControl('15+10',900, 10),
];

// ── Dialog ────────────────────────────────────────────────────────────────────

class OnlineSetupDialog extends StatefulWidget {
  const OnlineSetupDialog({
    super.key,
    required this.controller,
    required this.onCancel,
  });

  final ChessController controller;
  final VoidCallback onCancel;

  @override
  State<OnlineSetupDialog> createState() => _OnlineSetupDialogState();
}

class _OnlineSetupDialogState extends State<OnlineSetupDialog> {
  // Row indices
  static const _rowLevel = 0;
  static const _rowColor = 1;
  static const _rowTime  = 2;
  static const _rowAct   = 3;
  static const _rowCount = 4;

  int _focusedRow = _rowLevel;
  int _level = 1;         // 1–8
  int _colorIndex = 2;    // 0=White, 1=Black, 2=Random
  int _timeIndex = 1;     // index into _timeControls

  bool _loading = false;
  String? _error;

  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // ── Input handling ──────────────────────────────────────────────────────────

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
      _stepLeft();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _stepRight();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      if (_focusedRow == _rowAct) _play();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _stepLeft() {
    setState(() {
      switch (_focusedRow) {
        case _rowLevel:
          if (_level > 1) _level--;
        case _rowColor:
          if (_colorIndex > 0) _colorIndex--;
        case _rowTime:
          if (_timeIndex > 0) _timeIndex--;
        case _rowAct:
          break; // single Play button
      }
    });
  }

  void _stepRight() {
    setState(() {
      switch (_focusedRow) {
        case _rowLevel:
          if (_level < 8) _level++;
        case _rowColor:
          if (_colorIndex < 2) _colorIndex++;
        case _rowTime:
          if (_timeIndex < _timeControls.length - 1) _timeIndex++;
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

    try {
      final tc = _timeControls[_timeIndex];
      final colorStr = ['white', 'black', 'random'][_colorIndex];

      final gameId = await widget.controller.lichessService.seekAi(
        level: _level,
        clockLimitSeconds: tc.limitSeconds,
        clockIncrementSeconds: tc.incrementSeconds,
        color: colorStr,
      );

      // Determine my color (random is resolved server-side; we find out from
      // the gameFull event, so pass white as a placeholder — it will be
      // corrected when the stream arrives).
      final myColor = _colorIndex == 0
          ? PieceColor.white
          : _colorIndex == 1
              ? PieceColor.black
              : PieceColor.white; // placeholder for random

      if (!mounted) return;
      Navigator.of(context).pop();

      await widget.controller.startOnlineGame(
        gameId: gameId,
        myColor: myColor,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Play Online', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),

              // AI Level
              _buildRowLabel('AI Level', _focusedRow == _rowLevel, colors),
              const SizedBox(height: 4),
              _buildLevelRow(colors),
              const SizedBox(height: 12),

              // Play as
              _buildRowLabel('Play as', _focusedRow == _rowColor, colors),
              const SizedBox(height: 4),
              _buildChoiceRow(
                ['White', 'Black', 'Random'],
                _colorIndex,
                _focusedRow == _rowColor,
                (i) => setState(() => _colorIndex = i),
                colors,
              ),
              const SizedBox(height: 12),

              // Time control
              _buildRowLabel('Time', _focusedRow == _rowTime, colors),
              const SizedBox(height: 4),
              _buildChoiceRow(
                _timeControls.map((t) => t.label).toList(),
                _timeIndex,
                _focusedRow == _rowTime,
                (i) => setState(() => _timeIndex = i),
                colors,
              ),
              const SizedBox(height: 16),

              // Error
              if (_error != null) ...[
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
              ],

              // Actions row
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _loading ? null : widget.onCancel,
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _loading ? null : _play,
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Play'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
              Text(
                '↑↓ select row  •  ←→ change value  •  OK confirm  •  0 cancel',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRowLabel(String label, bool focused, ColorScheme colors) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: focused ? FontWeight.bold : FontWeight.normal,
        color: focused ? colors.primary : colors.onSurfaceVariant,
      ),
    );
  }

  Widget _buildLevelRow(ColorScheme colors) {
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
              padding: const EdgeInsets.symmetric(vertical: 6),
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
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
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

  Widget _buildChoiceRow(
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
              padding: const EdgeInsets.symmetric(vertical: 6),
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
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
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
