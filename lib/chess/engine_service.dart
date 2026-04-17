import 'dart:async';

import 'package:stockfish/stockfish.dart';

import 'chess_models.dart';

// ── Game / engine configuration enums ────────────────────────────────────────

enum GameMode { twoPlayer, vsEngine, lichess }

enum EngineLevel { beginner, intermediate, hard }

extension EngineLevelX on EngineLevel {
  String get label => switch (this) {
        EngineLevel.beginner => 'Beginner',
        //EngineLevel.easy => 'Easy',
        EngineLevel.intermediate => 'Middle',
        EngineLevel.hard => 'Hard',
        //EngineLevel.expert => 'Expert',
      };

  /// Stockfish UCI "Skill Level" option value (0–20).
  int get skillLevel => switch (this) {
        EngineLevel.beginner => 0,
        //EngineLevel.easy => 5,
        EngineLevel.intermediate => 10,
        EngineLevel.hard => 16,
        //EngineLevel.expert => 20,
      };

  /// Maximum wall-clock search time sent to "go movetime".
  int get moveTimeMs => switch (this) {
        EngineLevel.beginner => 100,
        //EngineLevel.easy => 250,
        EngineLevel.intermediate => 500,
        EngineLevel.hard => 1000,
        //EngineLevel.expert => 2000,
      };

  /// Hard depth cap (null = unlimited).
  int? get maxDepth => switch (this) {
        EngineLevel.beginner => 1,
        //EngineLevel.easy => 3,
        EngineLevel.intermediate => 5,
        EngineLevel.hard => 10,
        //EngineLevel.expert => null,
      };
}

// ── EngineService ─────────────────────────────────────────────────────────────

class EngineService {
  Stockfish? _stockfish;
  StreamSubscription<String>? _stdoutSub;

  // Handshake completer: resolves when the expected keyword arrives.
  Completer<void>? _handshakeCompleter;
  String? _waitingForKeyword;

  // Move-request completer: resolves with the "bestmove" UCI string.
  Completer<String>? _bestmoveCompleter;

  bool _ready = false;
  bool _disposed = false;

  bool get isReady => _ready;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      _stockfish = await stockfishAsync()
          .timeout(const Duration(seconds: 15));
      _stdoutSub = _stockfish!.stdout.listen(_handleLine);

      await _handshake('uci', 'uciok');
      await _handshake('isready', 'readyok');

      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> _handshake(String command, String expectedKeyword) async {
    _handshakeCompleter = Completer<void>();
    _waitingForKeyword = expectedKeyword;
    _stockfish!.stdin = command;
    await _handshakeCompleter!.future.timeout(const Duration(seconds: 30));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    _stdoutSub?.cancel();
    _stdoutSub = null;
    // Unblock any waiting futures before quitting.
    _handshakeCompleter?.complete();
    _handshakeCompleter = null;
    _bestmoveCompleter?.complete('');
    _bestmoveCompleter = null;
    _stockfish?.dispose(); // sends "quit"
    _stockfish = null;
  }

  // ── Stdout handler ─────────────────────────────────────────────────────────

  void _handleLine(String line) {
    final trimmed = line.trim();
    // Handshake keywords ("uciok", "readyok").
    if (_waitingForKeyword != null && trimmed == _waitingForKeyword) {
      _waitingForKeyword = null;
      _handshakeCompleter?.complete();
      _handshakeCompleter = null;
      return;
    }

    // Engine best move.
    if (trimmed.startsWith('bestmove') && _bestmoveCompleter != null) {
      final parts = trimmed.split(' ');
      final uci = parts.length > 1 ? parts[1] : '';
      _bestmoveCompleter!.complete(uci);
      _bestmoveCompleter = null;
    }
  }

  // ── Move request ───────────────────────────────────────────────────────────

  /// Sends the current position to Stockfish and returns the best UCI move.
  ///
  /// Returns an empty string if the engine is unavailable or was stopped.
  Future<String> requestMove({
    required List<String> moveHistory,
    required EngineLevel level,
  }) async {
    if (!_ready || _disposed || _stockfish == null) return '';

    _bestmoveCompleter = Completer<String>();

    _stockfish!.stdin = 'setoption name Skill Level value ${level.skillLevel}';

    if (moveHistory.isEmpty) {
      _stockfish!.stdin = 'position startpos';
    } else {
      _stockfish!.stdin = 'position startpos moves ${moveHistory.join(' ')}';
    }

    final depth = level.maxDepth;
    if (depth != null) {
      _stockfish!.stdin = 'go movetime ${level.moveTimeMs} depth $depth';
    } else {
      _stockfish!.stdin = 'go movetime ${level.moveTimeMs}';
    }

    // Timeout = movetime + generous overhead for slow devices.
    final timeoutMs = level.moveTimeMs + 10000;
    return _bestmoveCompleter!.future
        .timeout(Duration(milliseconds: timeoutMs), onTimeout: () => '');
  }

  /// Interrupts an ongoing search. Stockfish will emit a final "bestmove"
  /// line which unblocks the pending completer.
  void stop() {
    if (_stockfish == null || !_ready) return;
    _stockfish!.stdin = 'stop';
  }

  // ── UCI move parser ────────────────────────────────────────────────────────

  /// Parses a UCI move string like `"e2e4"` or `"e7e8q"` into a [ChessMove].
  static ChessMove parseMoveUci(String uci) {
    final fromFile = uci.codeUnitAt(0) - 97; // 'a' = 0
    final fromRank = int.parse(uci[1]) - 1;
    final toFile = uci.codeUnitAt(2) - 97;
    final toRank = int.parse(uci[3]) - 1;

    PieceType? promotion;
    if (uci.length == 5) {
      promotion = switch (uci[4]) {
        'q' => PieceType.queen,
        'r' => PieceType.rook,
        'b' => PieceType.bishop,
        'n' => PieceType.knight,
        _ => null,
      };
    }

    return ChessMove(
      from: Square(fromFile, fromRank),
      to: Square(toFile, toRank),
      promotion: promotion,
    );
  }
}
