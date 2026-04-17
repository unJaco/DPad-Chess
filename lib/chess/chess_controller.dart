import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chess_models.dart';
import 'engine_service.dart';
import 'lichess_service.dart';

enum CursorDirection {
  up,
  down,
  left,
  right,
}

class ChessController extends ChangeNotifier {
  final List<ChessPosition> _history = [ChessPosition.initial()];
  final List<ChessMove> _moves = [];

  Square _cursor = const Square(4, 1);
  Square? _selectedSquare;
  List<Square> _legalTargets = const [];
  ChessMove? _pendingPromotionMove;

  bool whiteBottom = true;

  // ── Engine ─────────────────────────────────────────────────────────────────
  final EngineService _engineService = EngineService();
  GameMode _gameMode = GameMode.twoPlayer;
  PieceColor _humanColor = PieceColor.white;
  EngineLevel _engineLevel = EngineLevel.intermediate;
  bool _isEngineThinking = false;
  bool _engineMoveCancelled = false;
  PieceColor? _resignedColor;

  // ── Online / Lichess ───────────────────────────────────────────────────────
  final LichessService _lichessService = LichessService();
  StreamSubscription<LichessGameState>? _lichessStreamSub;
  bool _isWaitingForOpponent = false;
  String? _onlineEndReason;

  ChessPosition get _position => _history.last;

  ChessPosition get position => _position;
  Square get cursor => _cursor;
  Square? get selectedSquare => _selectedSquare;
  List<Square> get legalTargets => _legalTargets;
  ChessMove? get lastMove => _moves.isEmpty ? null : _moves.last;
  List<String> get moveHistory => _moves.map((m) => m.uci).toList();

  bool get gameOver =>
      _position.isCheckmate ||
      _position.isStalemate ||
      _resignedColor != null ||
      _onlineEndReason != null;

  bool get isResigned => _resignedColor != null;

  // Online-related getters
  bool get isOnlineMode => _gameMode == GameMode.lichess;
  bool get isWaitingForOpponent => _isWaitingForOpponent;
  LichessService get lichessService => _lichessService;

  // Engine-related getters
  GameMode get gameMode => _gameMode;
  PieceColor get humanColor => _humanColor;
  EngineLevel get engineLevel => _engineLevel;
  bool get isEngineThinking => _isEngineThinking;
  bool get isHumanTurn =>
      _gameMode == GameMode.twoPlayer ||
      _position.sideToMove == _humanColor;

  bool get isPendingPromotion => _pendingPromotionMove != null;

  String? get gameResultText {
    if (_onlineEndReason != null) return _onlineEndReason;
    if (_resignedColor != null) {
      return '${_resignedColor!.opposite.label} wins by resignation!';
    }
    if (_position.isCheckmate) {
      return '${_position.sideToMove.opposite.label} wins by checkmate!';
    }
    if (_position.isStalemate) {
      return 'Draw by stalemate';
    }
    return null;
  }

  String get statusText {
    if (_isWaitingForOpponent) return 'Connecting to Lichess…';
    if (_isEngineThinking) return 'Engine is thinking…';
    if (_onlineEndReason != null) return _onlineEndReason!;
    if (_resignedColor != null) {
      return '${_resignedColor!.opposite.label} wins by resignation!';
    }
    if (_position.isCheckmate) {
      return '${_position.sideToMove.opposite.label} wins by checkmate!';
    }
    if (_position.isStalemate) {
      return 'Stalemate — draw';
    }
    if (_position.isInCheck(_position.sideToMove)) {
      return '${_position.sideToMove.label} is in check!';
    }
    if (_selectedSquare != null) {
      return '${_position.sideToMove.label} to move • '
          '${_selectedSquare!.algebraic} selected • '
          '${_legalTargets.length} targets';
    }
    return '${_position.sideToMove.label} to move • '
        'cursor ${_cursor.algebraic}';
  }

  Piece? pieceAt(Square square) => _position.pieceAt(square);

  bool isCursor(Square square) => square == _cursor;

  bool isSelected(Square square) => square == _selectedSquare;

  bool isLegalTarget(Square square) => _legalTargets.contains(square);

  bool isLastMoveSquare(Square square) {
    final last = lastMove;
    return square == last?.from || square == last?.to;
  }

  void moveCursor(CursorDirection direction) {
    if (_selectedSquare != null && _legalTargets.isNotEmpty) {
      _moveCursorToTarget(direction);
    } else {
      _moveCursorFreely(direction);
    }
  }

  void _moveCursorFreely(CursorDirection direction) {
    final (df, dr) = _directionVector(direction);
    final next = _cursor.translated(df, dr);
    if (next == null) return;
    _cursor = next;
    notifyListeners();
  }

  void _moveCursorToTarget(CursorDirection direction) {
    final (df, dr) = _directionVector(direction);

    Square? best;
    int bestScore = 0x7FFFFFFF;

    for (final target in _legalTargets) {
      final deltaFile = target.file - _cursor.file;
      final deltaRank = target.rank - _cursor.rank;

      final primary = deltaFile * df + deltaRank * dr;
      if (primary <= 0) continue;

      final perp = (deltaFile * dr - deltaRank * df).abs();

      final score = primary * 8 + perp;
      if (score < bestScore) {
        bestScore = score;
        best = target;
      }
    }

    if (best != null) {
      _cursor = best;
      notifyListeners();
    }
  }

  (int, int) _directionVector(CursorDirection direction) {
    return switch (direction) {
      CursorDirection.left  => (whiteBottom ? -1 : 1,  0),
      CursorDirection.right => (whiteBottom ? 1  : -1, 0),
      CursorDirection.up    => (0, whiteBottom ? 1  : -1),
      CursorDirection.down  => (0, whiteBottom ? -1 : 1),
    };
  }

  void focusSquare(Square square) {
    _cursor = square;
    notifyListeners();
  }

  void activate() {
    if (gameOver) return;
    if (_isEngineThinking || !isHumanTurn) return;
    if (_isWaitingForOpponent) return;

    if (_selectedSquare == null) {
      _selectAtCursor();
      return;
    }

    if (_cursor == _selectedSquare) {
      cancelSelection();
      return;
    }

    if (_legalTargets.contains(_cursor)) {
      final move = ChessMove(from: _selectedSquare!, to: _cursor);
      if (_isPromotionMove(move)) {
        _pendingPromotionMove = move;
        _selectedSquare = null;
        _legalTargets = const [];
        notifyListeners();
        return;
      }
      _executeMove(move);
      return;
    }

    final piece = pieceAt(_cursor);
    if (piece != null && piece.color == _position.sideToMove) {
      _selectAtCursor();
      return;
    }

    cancelSelection();
  }

  void cancelSelection() {
    if (_selectedSquare == null && _legalTargets.isEmpty) return;

    _selectedSquare = null;
    _legalTargets = const [];
    notifyListeners();
  }

  void resign() {
    if (gameOver) return;
    if (isOnlineMode) {
      _lichessService.resign(); // stream will emit terminal state
      return;
    }
    _resignedColor = _position.sideToMove;
    _selectedSquare = null;
    _legalTargets = const [];
    notifyListeners();
  }

  void undo() {
    if (isOnlineMode) return; // undo not supported in online games
    if (_resignedColor != null) {
      _resignedColor = null;
      notifyListeners();
      return;
    }
    if (_isEngineThinking) {
      _engineMoveCancelled = true;
      _engineService.stop();
      _isEngineThinking = false;
    }
    if (_history.length <= 1) {
      notifyListeners();
      return;
    }
    if (_gameMode == GameMode.vsEngine && _history.length > 2) {
      _history.removeLast();
      _moves.removeLast();
    }
    if (_history.length > 1) {
      _history.removeLast();
      _moves.removeLast();
    }
    _selectedSquare = null;
    _legalTargets = const [];
    notifyListeners();
  }

  Future<void> initialize() async {
    // TODO: re-enable engine initialization before release
    // await _engineService.initialize();
    // _maybeStartEngineThink();
  }

  void startNewGame({
    required GameMode mode,
    required PieceColor humanColor,
    required EngineLevel level,
  }) {
    _cancelOnlineGame();
    _engineMoveCancelled = true;
    _engineService.stop();
    _isEngineThinking = false;
    _resignedColor = null;
    _onlineEndReason = null;

    _gameMode = mode;
    _humanColor = humanColor;
    _engineLevel = level;

    _history
      ..clear()
      ..add(ChessPosition.initial());
    _moves.clear();
    _cursor = const Square(4, 1);
    _selectedSquare = null;
    _legalTargets = const [];
    _pendingPromotionMove = null;

    whiteBottom = mode == GameMode.twoPlayer || humanColor == PieceColor.white;
    notifyListeners();

    if (mode == GameMode.vsEngine && humanColor == PieceColor.black) {
      _triggerEngineMove();
    }
  }

  /// Starts an online game that has already been created on Lichess.
  /// [gameId] — the Lichess game id returned by seekAi.
  /// [myColor] — which side the local player is playing.
  Future<void> startOnlineGame({
    required String gameId,
    required PieceColor myColor,
  }) async {
    _cancelOnlineGame();
    _engineMoveCancelled = true;
    _engineService.stop();
    _isEngineThinking = false;
    _resignedColor = null;
    _onlineEndReason = null;

    _gameMode = GameMode.lichess;
    _humanColor = myColor;

    _history
      ..clear()
      ..add(ChessPosition.initial());
    _moves.clear();
    _cursor = const Square(4, 1);
    _selectedSquare = null;
    _legalTargets = const [];
    _pendingPromotionMove = null;

    whiteBottom = myColor == PieceColor.white;
    _isWaitingForOpponent = true;
    notifyListeners();

    _lichessStreamSub = _lichessService.gameStates.listen(
      _onLichessState,
      onError: (_) => _onLichessConnectionError(),
      onDone: () {},
    );
    await _lichessService.connectToGame(gameId);
  }

  void _onLichessState(LichessGameState state) {
    _isWaitingForOpponent = false;

    // Update human color in case it was resolved from gameFull.
    _humanColor = state.myColor;
    whiteBottom = state.myColor == PieceColor.white;

    // Lichess sends the full move list each time; apply any moves we don't have.
    final remoteMoves =
        state.moves.isEmpty ? <String>[] : state.moves.split(' ');

    while (_moves.length < remoteMoves.length) {
      final uci = remoteMoves[_moves.length];
      _applyMoveInternal(EngineService.parseMoveUci(uci));
    }

    if (state.status != 'started' && state.status != 'created') {
      _handleOnlineGameOver(state.status);
    }

    notifyListeners();
  }

  void _handleOnlineGameOver(String status) {
    _onlineEndReason = switch (status) {
      'mate'                  => gameResultText ?? 'Checkmate!',
      'resign'                => '${_position.sideToMove.label} resigned',
      'outoftime'             => 'Time out!',
      'draw'                  => 'Draw',
      'stalemate'             => 'Draw by stalemate',
      'threefoldRepetition'   => 'Draw by repetition',
      'insufficientMaterial'  => 'Draw — insufficient material',
      'aborted'               => 'Game aborted',
      _                       => 'Game over',
    };
    // Prevent the local-checkmate branch from overwriting the online reason.
    // If it was actually a checkmate, the local isCheckmate flag will be true
    // and gameResultText will use _onlineEndReason (checked first).
  }

  void _onLichessConnectionError() {
    if (!isOnlineMode) return;
    _isWaitingForOpponent = false;
    _onlineEndReason = 'Connection lost';
    notifyListeners();
  }

  void _cancelOnlineGame() {
    _lichessStreamSub?.cancel();
    _lichessStreamSub = null;
    _lichessService.disconnect();
    _isWaitingForOpponent = false;
  }

  void reset() {
    _cancelOnlineGame();
    _resignedColor = null;
    _onlineEndReason = null;
    _history
      ..clear()
      ..add(ChessPosition.initial());
    _moves.clear();
    _cursor = const Square(4, 1);
    _selectedSquare = null;
    _legalTargets = const [];
    whiteBottom = true;
    notifyListeners();
  }

  void toggleOrientation() {
    whiteBottom = !whiteBottom;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelOnlineGame();
    _lichessService.dispose();
    _engineService.dispose();
    super.dispose();
  }

  bool _isPromotionMove(ChessMove move) {
    final piece = pieceAt(move.from);
    return piece != null &&
        piece.type == PieceType.pawn &&
        (move.to.rank == 0 || move.to.rank == 7);
  }

  /// Applies a move and, for online games, posts it to Lichess.
  void _executeMove(ChessMove move) {
    if (isOnlineMode) {
      _applyMoveInternal(move); // optimistic
      _lichessService.postMove(move.uci).then((ok) {
        if (!ok && isOnlineMode) {
          // Roll back the rejected move.
          if (_history.length > 1) {
            _history.removeLast();
            _moves.removeLast();
          }
          notifyListeners();
        }
      });
      return;
    }
    _applyMove(move);
  }

  /// Pure state update — no engine trigger, no Lichess post.
  void _applyMoveInternal(ChessMove move) {
    _history.add(_position.makeMove(move));
    _moves.add(move);
    _selectedSquare = null;
    _legalTargets = const [];
  }

  void _applyMove(ChessMove move) {
    _applyMoveInternal(move);
    notifyListeners();
    _maybeStartEngineThink();
  }

  void _maybeStartEngineThink() {
    if (_gameMode != GameMode.vsEngine) return;
    if (gameOver) return;
    if (_position.sideToMove == _humanColor) return;
    if (_isEngineThinking) return;
    _triggerEngineMove();
  }

  void _triggerEngineMove() {
    _isEngineThinking = true;
    _engineMoveCancelled = false;
    notifyListeners();

    final moves = List<String>.from(moveHistory);
    final level = _engineLevel;

    _engineService.requestMove(moveHistory: moves, level: level).then((uci) {
      if (_engineMoveCancelled) return;
      _isEngineThinking = false;

      if (uci.isEmpty || uci == '(none)' || gameOver) {
        notifyListeners();
        return;
      }
      _applyMove(EngineService.parseMoveUci(uci));
    }).catchError((_) {
      _isEngineThinking = false;
      notifyListeners();
    });
  }

  void confirmPromotion(PieceType piece) {
    final move = _pendingPromotionMove;
    if (move == null) return;
    _pendingPromotionMove = null;
    _executeMove(ChessMove(from: move.from, to: move.to, promotion: piece));
  }

  void cancelPromotion() {
    _pendingPromotionMove = null;
    notifyListeners();
  }

  void _selectAtCursor() {
    final piece = pieceAt(_cursor);
    if (piece == null || piece.color != _position.sideToMove) return;

    _selectedSquare = _cursor;
    _legalTargets = _position.legalTargetsFrom(_cursor);
    notifyListeners();
  }
}
