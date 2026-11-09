import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_settings.dart';
import 'chess_controller.dart';
import 'chess_models.dart';
import 'clock_bar.dart';
import 'engine_service.dart';
import 'game_clock.dart';
import 'game_over_dialog.dart';
import 'help_content.dart';
import 'piece_sprite.dart';
import 'promotion_picker.dart';

/// The in-game board. The [controller] is created and configured by the setup
/// flow before this page is pushed; this page only renders it and handles the
/// in-game / review keypad input. The controller is owned by the app root, so
/// it is not disposed here.
class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.controller, required this.settings});

  final ChessController controller;
  final AppSettings settings;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final ChessController _controller;
  late final FocusNode _boardFocusNode;
  late final Listenable _rebuildListenable;
  late final ScrollController _historyScrollController;
  bool _gameOverShown = false;
  bool _promotionDialogShown = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _historyScrollController = ScrollController();
    _boardFocusNode = FocusNode(debugLabel: 'chess-board');
    _rebuildListenable = Listenable.merge([_controller, _boardFocusNode]);
    _controller.addListener(_onControllerChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _boardFocusNode.requestFocus();
      // Resume the (offline) clock now that the board is on screen again.
      _controller.resumeClock();
    });
  }

  @override
  void dispose() {
    // Pause the (offline) clock while the board is off screen.
    _controller.pauseClock();
    _controller.removeListener(_onControllerChanged);
    _historyScrollController.dispose();
    _boardFocusNode.dispose();
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
      builder: (ctx) => PromotionPicker(
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
    // Online: you can resign on any turn (Lichess resigns you). Offline vs the
    // engine, resign only on your turn — resign() ends the side to move.
    if (!_controller.isOnlineMode && !_controller.isHumanTurn) return;
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
      builder: (ctx) => GameOverDialog(
        resultText: _controller.gameResultText ?? 'Game Over',
        isOnline: _controller.isOnlineMode,
        onPlayAgain: () {
          Navigator.of(ctx).pop();
          _playAgain();
        },
        onReview: () {
          Navigator.of(ctx).pop();
          _controller.enterReview();
          _boardFocusNode.requestFocus();
        },
        onMainMenu: () {
          Navigator.of(ctx).pop();
          _goToMainMenu();
        },
      ),
    );
  }

  /// Rematch with the same settings (offline). For online games a fresh Lichess
  /// game must be created, so we drop back to the online setup page instead.
  void _playAgain() {
    if (_controller.isOnlineMode) {
      Navigator.of(context).pop();
      return;
    }
    _controller.startNewGame(
      mode: _controller.gameMode,
      humanColor: _controller.humanColor,
      level: _controller.engineLevel,
      timeControl: _controller.timeControl,
      whiteBottom: _controller.whiteBottom,
    );
    _boardFocusNode.requestFocus();
  }

  void _goToMainMenu() {
    if (_controller.isReviewing) _controller.exitReview();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Controls'),
        content: const SingleChildScrollView(child: HelpContentList()),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // While reviewing a finished game, keys step through history instead.
    if (_controller.isReviewing) {
      return _onReviewKey(key);
    }

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
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
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

    // [8] — open help dialog
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      _showHelpDialog();
      return KeyEventResult.handled;
    }

    // [9] — go to main menu
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      _goToMainMenu();
      return KeyEventResult.handled;
    }

    // [#] — toggle board orientation
    if (key == LogicalKeyboardKey.numberSign) {
      _controller.toggleOrientation();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Keypad handling while reviewing a finished game.
  /// ←/→ step one ply, ↑/↓ jump to the end/start, # flips, 1 reopens the
  /// end-of-game options, 0 returns to the start page.
  KeyEventResult _onReviewKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowLeft) {
      _controller.reviewPrev();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _controller.reviewNext();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _controller.reviewLast();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _controller.reviewFirst();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.numberSign) {
      _controller.toggleOrientation();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      _controller.exitReview();
      _showGameOverDialog();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0 ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace) {
      _goToMainMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Intercepts the system/hardware back button. During an active game we don't
  /// leave the board — we open the resign dialog instead. When the game is over
  /// or being reviewed, back returns to the start page.
  void _handleBackButton() {
    if (_controller.isReviewing || _controller.gameOver) {
      _goToMainMenu();
      return;
    }
    _showResignDialog();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackButton();
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('T9ChessApp'),
              if (_controller.gameMode == GameMode.vsEngine)
                Text(
                  'vs Engine — ${_controller.engineLevel.label}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              if (_controller.gameMode == GameMode.lichess)
                Text(
                  'Online — Lichess AI',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
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
              tooltip: 'Main menu',
              onPressed: _goToMainMenu,
              icon: const Icon(Icons.home_outlined),
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
              final reviewing = _controller.isReviewing;
              final clock = _controller.clock;
              final showClocks = !reviewing && clock != null;

              return Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Column(
                  children: [
                    // Above the board: during review show the move list + status
                    // (the "expanded" analysis info); during play show the far
                    // player's clock, or a minimal turn line for untimed games.
                    if (reviewing) ...[
                      _buildMoveHistory(context),
                      _buildStatusText(context),
                      _buildReviewBar(context),
                    ] else if (showClocks) ...[
                      _clockBar(clock, top: true),
                    ] else
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
                    if (showClocks) ...[
                      const SizedBox(height: 4),
                      _clockBar(clock, top: false),
                    ],
                  ],
                ),
              );
            },
          ),
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

                return Container(
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
                );
              },
            ),
    );
  }

  /// A clock row for the near (bottom) or far (top) side of the board. Follows
  /// the current orientation so "bottom" is always the side facing the player.
  Widget _clockBar(GameClock clock, {required bool top}) {
    final nearColor = _controller.whiteBottom
        ? PieceColor.white
        : PieceColor.black;
    final color = top ? nearColor.opposite : nearColor;
    return ClockBar(clock: clock, color: color);
  }

  Widget _buildStatusText(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isThinking = _controller.isEngineThinking;
    final reviewing = _controller.isReviewing;

    return SizedBox(
      height: 16,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          reviewing
              ? 'Review — move ${_controller.reviewPly} of ${_controller.totalPlies}'
              : _controller.statusText,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isThinking ? colors.primary : colors.onSurfaceVariant,
            fontStyle: isThinking ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildReviewBar(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 16, color: colors.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '←/→ step  •  ↑ end  •  ↓ start  •  # flip  •  1 options  •  0 menu',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
        ],
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
                      final square = _squareForDisplay(
                        displayRank,
                        displayFile,
                      );
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
                child: Container(color: Colors.red.withValues(alpha: 0.30)),
              ),
            if (isLastMove)
              Positioned.fill(
                child: Container(color: Colors.amber.withValues(alpha: 0.14)),
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
                    border: Border.all(color: colors.primary, width: 2.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            if (piece != null)
              LayoutBuilder(
                builder: (_, constraints) => Center(
                  child: PieceSprite(
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
                    border: Border.all(color: colors.primary, width: 3),
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

    Color background = isLight
        ? const Color(0xFFF0D9B5)
        : const Color(0xFFB58863);

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
