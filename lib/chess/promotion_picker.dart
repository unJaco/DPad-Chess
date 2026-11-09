import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chess_models.dart';
import 'piece_sprite.dart';

// ── Promotion picker ────────────────────────────────────────────────────────

class PromotionPicker extends StatefulWidget {
  const PromotionPicker({
    super.key,
    required this.color,
    required this.onConfirm,
    required this.onCancel,
  });

  final PieceColor color;
  final ValueChanged<PieceType> onConfirm;
  final VoidCallback onCancel;

  @override
  State<PromotionPicker> createState() => PromotionPickerState();
}

class PromotionPickerState extends State<PromotionPicker> {
  // Mapped to D-pad directions: up=queen, right=rook, down=bishop, left=knight
  static const _up = PieceType.queen;
  static const _right = PieceType.rook;
  static const _down = PieceType.bishop;
  static const _left = PieceType.knight;

  PieceType _selected = _up; // queen is default / most common
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

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    // D-pad directions select the corresponding piece
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = _up);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() => _selected = _right);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = _down);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() => _selected = _left);
      return KeyEventResult.handled;
    }
    // OK / center button confirms
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      widget.onConfirm(_selected);
      return KeyEventResult.handled;
    }
    // 0 / Escape cancels
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

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
            children: [
              Text('Promote pawn', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                _pieceName(_selected),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              // ── Cross layout ──────────────────────────────────────────────
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top: Queen (↑)
                  _PieceCard(
                    piece: Piece(widget.color, _up),
                    selected: _selected == _up,
                    colors: colors,
                    onTap: () => widget.onConfirm(_up),
                  ),
                  const SizedBox(height: 6),
                  // Middle row: Knight (←)  ·  Rook (→)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PieceCard(
                        piece: Piece(widget.color, _left),
                        selected: _selected == _left,
                        colors: colors,
                        onTap: () => widget.onConfirm(_left),
                      ),
                      // Center: OK hint
                      SizedBox(
                        width: 62,
                        height: 62,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.outlineVariant,
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'OK',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _PieceCard(
                        piece: Piece(widget.color, _right),
                        selected: _selected == _right,
                        colors: colors,
                        onTap: () => widget.onConfirm(_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Bottom: Bishop (↓)
                  _PieceCard(
                    piece: Piece(widget.color, _down),
                    selected: _selected == _down,
                    colors: colors,
                    onTap: () => widget.onConfirm(_down),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '↑↓←→ select  •  OK confirm  •  0 cancel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pieceName(PieceType type) {
    switch (type) {
      case PieceType.queen:
        return 'Queen';
      case PieceType.rook:
        return 'Rook';
      case PieceType.bishop:
        return 'Bishop';
      case PieceType.knight:
        return 'Knight';
      default:
        return '';
    }
  }
}

class _PieceCard extends StatelessWidget {
  const _PieceCard({
    required this.piece,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final Piece piece;
  final bool selected;
  final ColorScheme colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          color: selected
              ? colors.primaryContainer
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Center(child: PieceSprite(piece: piece, size: 42)),
      ),
    );
  }
}
