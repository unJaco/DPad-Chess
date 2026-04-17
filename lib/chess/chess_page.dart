import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chess_controller.dart';
import 'chess_models.dart';
import 'engine_service.dart';
import 'online_setup_dialog.dart';
import 'token_entry_dialog.dart';

class ChessPage extends StatefulWidget {
  const ChessPage({super.key});

  @override
  State<ChessPage> createState() => _ChessPageState();
}

class _ChessPageState extends State<ChessPage> {
  late final ChessController _controller;
  late final FocusNode _boardFocusNode;
  late final Listenable _rebuildListenable;
  late final ScrollController _historyScrollController;
  bool _gameOverShown = false;
  bool _promotionDialogShown = false;

  @override
  void initState() {
    super.initState();
    _controller = ChessController();
    _historyScrollController = ScrollController();
    _boardFocusNode = FocusNode(debugLabel: 'chess-board');
    _rebuildListenable = Listenable.merge([_controller, _boardFocusNode]);
    _controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _boardFocusNode.requestFocus();
      // Initialize engine in background; show the dialog immediately.
      _controller.initialize();
      _showNewGameDialog();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _historyScrollController.dispose();
    _boardFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // Scroll history to show the latest move
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_historyScrollController.hasClients) {
        _historyScrollController.animateTo(
          _historyScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });

    // Promotion picker
    if (_controller.isPendingPromotion && !_promotionDialogShown) {
      _promotionDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPromotionDialog();
      });
    }
    if (!_controller.isPendingPromotion) {
      _promotionDialogShown = false;
    }

    if (!_controller.gameOver) {
      _gameOverShown = false;
      return;
    }
    if (!_gameOverShown) {
      _gameOverShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showGameOverDialog();
      });
    }
  }

  void _showPromotionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PromotionPicker(
        color: _controller.position.sideToMove,
        onConfirm: (piece) {
          Navigator.of(ctx).pop();
          _controller.confirmPromotion(piece);
          _boardFocusNode.requestFocus();
        },
        onCancel: () {
          Navigator.of(ctx).pop();
          _controller.cancelPromotion();
          _boardFocusNode.requestFocus();
        },
      ),
    );
  }

  void _showResignDialog() {
    if (_controller.gameOver) return;
    if (!_controller.isHumanTurn) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resign?'),
        content: const Text('Are you sure you want to resign?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _boardFocusNode.requestFocus();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _controller.resign();
              _boardFocusNode.requestFocus();
            },
            child: const Text('Resign'),
          ),
        ],
      ),
    );
  }

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(_controller.gameResultText ?? 'Game Over'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showNewGameDialog();
            },
            child: const Text('New Game'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Controls'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _HelpRow(key: ValueKey('nav'), icon: Icons.gamepad, label: 'D-pad', description: 'Move cursor'),
              _HelpRow(key: ValueKey('ok'), icon: Icons.check_circle_outline, label: 'OK / Enter', description: 'Select piece or execute move'),
              _HelpRow(key: ValueKey('resign'), icon: Icons.flag_outlined, label: '0', description: 'Resign'),
              _HelpRow(key: ValueKey('cancel'), icon: Icons.close, label: '1', description: 'Cancel selection'),
              _HelpRow(key: ValueKey('undo'), icon: Icons.undo, label: '*', description: 'Undo last move'),
              _HelpRow(key: ValueKey('rotate'), icon: Icons.screen_rotation_alt, label: '#', description: 'Flip board orientation'),
              Divider(height: 20),
              _HelpRow(key: ValueKey('check'), icon: Icons.warning_amber_rounded, label: 'Red king', description: 'King is in check'),
              _HelpRow(key: ValueKey('dot'), icon: Icons.circle, label: 'Dot on square', description: 'Legal move target'),
              _HelpRow(key: ValueKey('ring'), icon: Icons.radio_button_unchecked, label: 'Ring on piece', description: 'Capturable enemy piece'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showNewGameDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NewGameDialog(
        initialMode: _controller.gameMode,
        initialColor: _controller.humanColor,
        initialLevel: _controller.engineLevel,
        onConfirm: (mode, color, level) {
          Navigator.of(ctx).pop();
          if (mode == GameMode.lichess) {
            _showOnlineSetupFlow();
            return;
          }
          _controller.startNewGame(
            mode: mode,
            humanColor: color,
            level: level,
          );
          _boardFocusNode.requestFocus();
        },
        onCancel: () {
          Navigator.of(ctx).pop();
          _boardFocusNode.requestFocus();
        },
      ),
    );
  }

  Future<void> _showOnlineSetupFlow() async {
    final token = await _controller.lichessService.loadToken();
    if (!mounted) return;
    if (token == null) {
      final tokenOk = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => TokenEntryDialog(
          lichessService: _controller.lichessService,
          onSuccess: () => Navigator.of(ctx).pop(true),
          onCancel: () => Navigator.of(ctx).pop(false),
        ),
      );
      if (tokenOk != true || !mounted) return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OnlineSetupDialog(
        controller: _controller,
        onCancel: () {
          Navigator.of(ctx).pop();
          _boardFocusNode.requestFocus();
        },
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // D-pad navigation
    if (key == LogicalKeyboardKey.arrowUp) {
      _controller.moveCursor(CursorDirection.up);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _controller.moveCursor(CursorDirection.down);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _controller.moveCursor(CursorDirection.left);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _controller.moveCursor(CursorDirection.right);
      return KeyEventResult.handled;
    }

    // Center/OK button — confirm selection or execute move
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      _controller.activate();
      return KeyEventResult.handled;
    }

    // [0] — resign
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      _showResignDialog();
      return KeyEventResult.handled;
    }

    // [1] — cancel selection
    if (key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1 ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace) {
      _controller.cancelSelection();
      return KeyEventResult.handled;
    }

    // [*] — undo last move (not available in online games)
    if (key == LogicalKeyboardKey.asterisk ||
        key == LogicalKeyboardKey.numpadMultiply) {
      if (!_controller.isOnlineMode) _controller.undo();
      return KeyEventResult.handled;
    }

    // [9] — open help dialog
    if (key == LogicalKeyboardKey.digit9 ||
        key == LogicalKeyboardKey.numpad9) {
      _showHelpDialog();
      return KeyEventResult.handled;
    }

    // [#] — toggle board orientation
    if (key == LogicalKeyboardKey.numberSign) {
      _controller.toggleOrientation();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Qin Chess'),
            if (_controller.gameMode == GameMode.vsEngine)
              Text(
                'vs Engine — ${_controller.engineLevel.label}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withValues(alpha: 0.8),
                    ),
              ),
            if (_controller.gameMode == GameMode.lichess)
              Text(
                'Online — Lichess AI',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withValues(alpha: 0.8),
                    ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Undo move',
            onPressed: () {
              _controller.undo();
              _boardFocusNode.requestFocus();
            },
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Rotate board',
            onPressed: () {
              _controller.toggleOrientation();
              _boardFocusNode.requestFocus();
            },
            icon: const Icon(Icons.screen_rotation_alt),
          ),
          IconButton(
            tooltip: 'New game',
            onPressed: _showNewGameDialog,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Help',
            onPressed: _showHelpDialog,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _rebuildListenable,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Column(
                children: [
                  _buildMoveHistory(context),
                  _buildStatusText(context),
                  if (_controller.isWaitingForOpponent)
                    const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: _buildBoard(context),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMoveHistory(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final moves = _controller.moveHistory;

    return SizedBox(
      height: 26,
      child: moves.isEmpty
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No moves yet',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          : ListView.separated(
              controller: _historyScrollController,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: moves.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, index) {
                final isWhiteMove = index.isEven;
                final label = isWhiteMove
                    ? '${index ~/ 2 + 1}.\u00a0${moves[index]}'
                    : moves[index];

                return GestureDetector(
                  onTap: () {
                    // TODO: navigate to this position in the history
                  },
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: isWhiteMove
                          ? colors.surfaceContainerHighest
                          : colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: colors.outlineVariant,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusText(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isThinking = _controller.isEngineThinking;

    return SizedBox(
      height: 16,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _controller.statusText,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isThinking ? colors.primary : colors.onSurfaceVariant,
            fontStyle: isThinking ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildBoard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasFocus = _boardFocusNode.hasFocus;

    return Focus(
      focusNode: _boardFocusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _boardFocusNode.requestFocus,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasFocus ? colors.primary : colors.outlineVariant,
              width: hasFocus ? 3 : 1.5,
            ),
            boxShadow: hasFocus
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.18),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Column(
              children: List.generate(8, (displayRank) {
                return Expanded(
                  child: Row(
                    children: List.generate(8, (displayFile) {
                      final square = _squareForDisplay(displayRank, displayFile);
                      return Expanded(
                        child: _buildSquare(
                          context,
                          square: square,
                          displayRank: displayRank,
                          displayFile: displayFile,
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSquare(
    BuildContext context, {
    required Square square,
    required int displayRank,
    required int displayFile,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final piece = _controller.pieceAt(square);

    final isCursor = _controller.isCursor(square);
    final isSelected = _controller.isSelected(square);
    final isLegalTarget = _controller.isLegalTarget(square);
    final isLastMove = _controller.isLastMoveSquare(square);
    final isKingInCheck = _isKingInCheckSquare(square);

    final fileLabel = square.algebraic.substring(0, 1);
    final rankLabel = '${square.rank + 1}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleSquareTap(square),
      child: Container(
        decoration: BoxDecoration(
          color: _squareBackgroundColor(square, colors),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.08),
            width: 0.4,
          ),
        ),
        child: Stack(
          children: [
            if (displayFile == 0)
              Positioned(
                left: 3,
                top: 2,
                child: Text(
                  rankLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.black.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (displayRank == 7)
              Positioned(
                right: 3,
                bottom: 2,
                child: Text(
                  fileLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.black.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            // King in check: red background tint
            if (isKingInCheck)
              Positioned.fill(
                child: Container(
                  color: Colors.red.withValues(alpha: 0.30),
                ),
              ),
            if (isLastMove)
              Positioned.fill(
                child: Container(
                  color: Colors.amber.withValues(alpha: 0.14),
                ),
              ),
            if (isLegalTarget && piece == null)
              Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (isLegalTarget && piece != null)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colors.primary,
                      width: 2.2,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            if (piece != null)
              LayoutBuilder(
                builder: (_, constraints) => Center(
                  child: _PieceSprite(
                    piece: piece,
                    size: constraints.maxWidth * 0.82,
                  ),
                ),
              ),
            // King in check: red circle badge in top-right corner
            if (isKingInCheck)
              Positioned(
                top: 3,
                right: 3,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colors.primary,
                      width: 3,
                    ),
                  ),
                ),
              ),
            if (isCursor)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _boardFocusNode.hasFocus
                          ? colors.tertiary
                          : colors.outline,
                      width: 3,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _isKingInCheckSquare(Square square) {
    final pos = _controller.position;
    if (!pos.isInCheck(pos.sideToMove)) return false;
    final piece = _controller.pieceAt(square);
    return piece != null &&
        piece.type == PieceType.king &&
        piece.color == pos.sideToMove;
  }

  void _handleSquareTap(Square square) {
    _boardFocusNode.requestFocus();

    final selected = _controller.selectedSquare;
    final piece = _controller.pieceAt(square);

    if (selected != null) {
      if (square == selected || _controller.isLegalTarget(square)) {
        _controller.focusSquare(square);
        _controller.activate();
        return;
      }

      if (piece != null && piece.color == _controller.position.sideToMove) {
        _controller.focusSquare(square);
        _controller.activate();
        return;
      }

      _controller.focusSquare(square);
      _controller.cancelSelection();
      return;
    }

    _controller.focusSquare(square);

    if (piece != null && piece.color == _controller.position.sideToMove) {
      _controller.activate();
    }
  }

  Square _squareForDisplay(int displayRank, int displayFile) {
    if (_controller.whiteBottom) {
      return Square(displayFile, 7 - displayRank);
    }
    return Square(7 - displayFile, displayRank);
  }

  Color _squareBackgroundColor(Square square, ColorScheme colors) {
    final isLight = (square.file + square.rank).isEven;

    Color background =
        isLight ? const Color(0xFFF0D9B5) : const Color(0xFFB58863);

    if (_controller.isLastMoveSquare(square)) {
      background = Color.alphaBlend(
        Colors.amber.withValues(alpha: 0.20),
        background,
      );
    }

    if (_controller.isSelected(square)) {
      background = Color.alphaBlend(
        colors.primary.withValues(alpha: 0.28),
        background,
      );
    } else if (_controller.isCursor(square)) {
      background = Color.alphaBlend(
        colors.tertiary.withValues(alpha: 0.18),
        background,
      );
    }

    return background;
  }
}

// ── Promotion picker ────────────────────────────────────────────────────────

class _PromotionPicker extends StatefulWidget {
  const _PromotionPicker({
    required this.color,
    required this.onConfirm,
    required this.onCancel,
  });

  final PieceColor color;
  final ValueChanged<PieceType> onConfirm;
  final VoidCallback onCancel;

  @override
  State<_PromotionPicker> createState() => _PromotionPickerState();
}

class _PromotionPickerState extends State<_PromotionPicker> {
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
        child: Center(
          child: _PieceSprite(
            piece: piece,
            size: 42,
          ),
        ),
      ),
    );
  }
}

// ── Piece sprite ─────────────────────────────────────────────────────────────
//
// Renders one cell from the sprite sheet at assets/pieces.png.
// Sheet layout: 6 columns × 2 rows.
//   Columns (left→right): Queen, King, Rook, Knight, Bishop, Pawn
//   Row 0 (top):          Black pieces (filled)
//   Row 1 (bottom):       White pieces (outline)

class _PieceSprite extends StatelessWidget {
  const _PieceSprite({required this.piece, required this.size});

  final Piece piece;
  final double size;

  static const _assetPath = 'assets/pieces.png';

  static int _col(PieceType type) => switch (type) {
        PieceType.queen => 0,
        PieceType.king => 1,
        PieceType.rook => 2,
        PieceType.knight => 3,
        PieceType.bishop => 4,
        PieceType.pawn => 5,
      };

  @override
  Widget build(BuildContext context) {
    final col = _col(piece.type);
    final row = piece.color == PieceColor.black ? 0 : 1;

    // Map col 0..5 → alignment x -1..1, row 0..1 → alignment y -1..1
    final alignX = -1.0 + col * 2.0 / 5.0;
    final alignY = row == 0 ? -1.0 : 1.0;

    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          minWidth: size * 6,
          maxWidth: size * 6,
          minHeight: size * 2,
          maxHeight: size * 2,
          alignment: Alignment(alignX, alignY),
          child: Image.asset(
            _assetPath,
            width: size * 6,
            height: size * 2,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

// ── New game dialog ───────────────────────────────────────────────────────────

class _NewGameDialog extends StatefulWidget {
  const _NewGameDialog({
    required this.initialMode,
    required this.initialColor,
    required this.initialLevel,
    required this.onConfirm,
    required this.onCancel,
  });

  final GameMode initialMode;
  final PieceColor initialColor;
  final EngineLevel initialLevel;
  final void Function(GameMode, PieceColor, EngineLevel) onConfirm;
  final VoidCallback onCancel;

  @override
  State<_NewGameDialog> createState() => _NewGameDialogState();
}

class _NewGameDialogState extends State<_NewGameDialog> {
  late GameMode _mode;
  late PieceColor _color;
  late EngineLevel _level;

  int _focusedRow = 0;
  int _focusedCol = 0;

  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _color = widget.initialColor;
    _level = widget.initialLevel;
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

  // Row definitions:
  //   0: Mode       (3 cols: twoPlayer, vsEngine, online)
  //   1: Play as    (2 cols: white, black)  — vsEngine only
  //   2: Level      (N cols)               — vsEngine only
  //   last: Actions (1 col: start)

  int get _rowCount => _mode == GameMode.vsEngine ? 4 : 2;

  int _colCount(int row) {
    if (row == 0) return 3; // mode row always has 3 options
    if (_mode == GameMode.twoPlayer || _mode == GameMode.lichess) {
      return 1; // only actions row remains
    }
    return switch (row) {
      1 => 2,
      2 => EngineLevel.values.length,
      _ => 1,
    };
  }

  // Maps the logical row index to an "actions row" check.
  bool _isActionsRow(int row) => row == _rowCount - 1;

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      if (_focusedRow < _rowCount - 1) {
        setState(() {
          _focusedRow++;
          _focusedCol = _focusedCol.clamp(0, _colCount(_focusedRow) - 1);
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_focusedRow > 0) {
        setState(() {
          _focusedRow--;
          _focusedCol = _focusedCol.clamp(0, _colCount(_focusedRow) - 1);
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final max = _colCount(_focusedRow) - 1;
      if (_focusedCol < max) setState(() => _focusedCol++);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_focusedCol > 0) setState(() => _focusedCol--);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.space) {
      _activate();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _activate() {
    if (_isActionsRow(_focusedRow)) {
      if (_focusedCol == 0) {
        widget.onCancel();
      } else {
        widget.onConfirm(_mode, _color, _level);
      }
      return;
    }

    setState(() {
      if (_focusedRow == 0) {
        // Mode row
        _mode = switch (_focusedCol) {
          0 => GameMode.twoPlayer,
          1 => GameMode.vsEngine,
          _ => GameMode.lichess,
        };
        // Clamp focused row/col if rows disappear.
        _focusedRow = _focusedRow.clamp(0, _rowCount - 1);
        _focusedCol = _focusedCol.clamp(0, _colCount(_focusedRow) - 1);
      } else if (_mode == GameMode.vsEngine) {
        if (_focusedRow == 1) {
          _color =
              _focusedCol == 0 ? PieceColor.white : PieceColor.black;
        } else if (_focusedRow == 2) {
          _level = EngineLevel.values[_focusedCol];
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New Game', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),

                // Row 0: Mode
                _buildSectionLabel(theme, 'Mode'),
                const SizedBox(height: 6),
                _buildOptionRow(
                  rowIndex: 0,
                  colors: colors,
                  labels: const ['2-Player', 'vs Engine', 'Online'],
                  selectedCol: switch (_mode) {
                    GameMode.twoPlayer => 0,
                    GameMode.vsEngine  => 1,
                    GameMode.lichess   => 2,
                  },
                ),

                if (_mode == GameMode.vsEngine) ...[
                  const SizedBox(height: 12),

                  // Row 1: Play as
                  _buildSectionLabel(theme, 'Play as'),
                  const SizedBox(height: 6),
                  _buildOptionRow(
                    rowIndex: 1,
                    colors: colors,
                    labels: const ['White', 'Black'],
                    selectedCol: _color == PieceColor.white ? 0 : 1,
                  ),

                  const SizedBox(height: 12),

                  // Row 2: Strength
                  _buildSectionLabel(theme, 'Strength'),
                  const SizedBox(height: 6),
                  _buildOptionRow(
                    rowIndex: 2,
                    colors: colors,
                    labels:
                        EngineLevel.values.map((l) => l.label).toList(),
                    selectedCol: _level.index,
                  ),
                ],

                const SizedBox(height: 20),

                // Actions row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildActionButton(
                      rowIndex: _rowCount - 1,
                      colIndex: 1,
                      colors: colors,
                      label: 'Start Game',
                      filled: true,
                      onTap: () => widget.onConfirm(_mode, _color, _level),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildOptionRow({
    required int rowIndex,
    required ColorScheme colors,
    required List<String> labels,
    required int selectedCol,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(labels.length, (col) {
        final isFocused = _focusedRow == rowIndex && _focusedCol == col;
        final isSelected = selectedCol == col;
        return GestureDetector(
          onTap: () {
            setState(() {
              _focusedRow = rowIndex;
              _focusedCol = col;
            });
            _activate();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
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

  Widget _buildActionButton({
    required int rowIndex,
    required int colIndex,
    required ColorScheme colors,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final isFocused =
        _focusedRow == rowIndex && _focusedCol == colIndex;
    if (filled) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: isFocused
              ? Border.all(color: colors.primary, width: 2.5)
              : null,
        ),
        child: FilledButton(
          onPressed: onTap,
          child: Text(label),
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: isFocused
            ? Border.all(color: colors.primary, width: 2.5)
            : null,
      ),
      child: TextButton(
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}

// ── Help row ─────────────────────────────────────────────────────────────────

class _HelpRow extends StatelessWidget {
  const _HelpRow({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(description, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
