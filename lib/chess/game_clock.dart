import 'dart:async';

import 'package:flutter/foundation.dart';

import 'chess_models.dart';

/// Formats a clock time (milliseconds) for display: `M:SS` normally, and
/// `S.d` (seconds with one decimal) under 10 seconds.
String formatClockMs(int ms) {
  if (ms < 0) ms = 0;
  if (ms < 10000) {
    return (ms / 1000).toStringAsFixed(1);
  }
  final totalSeconds = ms ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// A reusable two-sided chess clock, usable across every game mode.
///
/// * Offline (2-player / vs-engine): [authoritative] is `true` — the clock
///   counts down locally, applies the increment on each move via [onMove], and
///   calls [onFlag] when a side runs out of time.
/// * Online (Lichess): [authoritative] is `false` — [sync] overwrites the times
///   from the server on each update, and the clock ticks locally between updates
///   only for a smooth display; time-out is decided by the server.
///
/// It is its own [ChangeNotifier] so clock widgets can rebuild every tick
/// without repainting the board.
class GameClock extends ChangeNotifier {
  GameClock({
    required int initialMs,
    required int incrementMs,
    this.authoritative = true,
    this.onFlag,
  }) : _incrementMs = incrementMs,
       _whiteMs = initialMs,
       _blackMs = initialMs;

  final int _incrementMs;
  final bool authoritative;

  /// Called (authoritative clocks only) when [color] runs out of time.
  final void Function(PieceColor color)? onFlag;

  int _whiteMs;
  int _blackMs;
  PieceColor? _active;
  Timer? _ticker;
  DateTime? _since;
  bool _flagged = false;

  int get whiteMs => _whiteMs;
  int get blackMs => _blackMs;

  /// The side currently counting down, or null when paused.
  PieceColor? get active => _active;

  int msFor(PieceColor color) =>
      color == PieceColor.white ? _whiteMs : _blackMs;

  static const _interval = Duration(milliseconds: 200);

  /// Starts (or resumes) counting down [side].
  void run(PieceColor side) {
    if (_flagged) return;
    _applyElapsed();
    _active = side;
    _since = DateTime.now();
    _ticker ??= Timer.periodic(_interval, (_) => _onTick());
    notifyListeners();
  }

  void pause() {
    _applyElapsed();
    _active = null;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  /// A move was played by [mover] (offline use): adds the increment to the mover
  /// and starts the opponent's clock.
  void onMove(PieceColor mover) {
    if (_flagged) return;
    _applyElapsed();
    if (mover == PieceColor.white) {
      _whiteMs += _incrementMs;
    } else {
      _blackMs += _incrementMs;
    }
    run(mover.opposite);
  }

  /// Server-authoritative update (online use).
  void sync({
    required int whiteMs,
    required int blackMs,
    required PieceColor active,
    required bool running,
  }) {
    _whiteMs = whiteMs;
    _blackMs = blackMs;
    _since = DateTime.now();
    if (running) {
      _active = active;
      _ticker ??= Timer.periodic(_interval, (_) => _onTick());
    } else {
      _active = null;
      _ticker?.cancel();
      _ticker = null;
    }
    notifyListeners();
  }

  void _onTick() {
    _applyElapsed();
    notifyListeners();
  }

  void _applyElapsed() {
    final active = _active;
    final since = _since;
    if (active == null || since == null) return;
    final now = DateTime.now();
    final elapsed = now.difference(since).inMilliseconds;
    if (elapsed <= 0) return;
    _since = now;
    if (active == PieceColor.white) {
      _whiteMs -= elapsed;
      if (_whiteMs <= 0) {
        _whiteMs = 0;
        _reachedZero(PieceColor.white);
      }
    } else {
      _blackMs -= elapsed;
      if (_blackMs <= 0) {
        _blackMs = 0;
        _reachedZero(PieceColor.black);
      }
    }
  }

  void _reachedZero(PieceColor color) {
    // Display-only clocks (online) clamp at zero and wait for the server verdict.
    if (!authoritative || _flagged) return;
    _flagged = true;
    _active = null;
    _ticker?.cancel();
    _ticker = null;
    onFlag?.call(color);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
