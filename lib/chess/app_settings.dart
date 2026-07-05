import 'package:flutter/foundation.dart';

import 'chess_models.dart';
import 'engine_service.dart';

/// How the board is oriented when a new game starts.
enum BoardOrientationPref {
  /// White always at the bottom.
  whiteBottom,

  /// Black always at the bottom.
  blackBottom,

  /// Orient so the local player is at the bottom — white for 2-player or when
  /// you play white, black when you play black vs the engine. This mirrors the
  /// app's historical default.
  auto,
}

extension BoardOrientationPrefX on BoardOrientationPref {
  String get label => switch (this) {
    BoardOrientationPref.whiteBottom => 'White',
    BoardOrientationPref.blackBottom => 'Black',
    BoardOrientationPref.auto => 'Auto',
  };
}

/// App-wide, in-memory settings.
///
/// Scaffold for future growth — not persisted to disk yet (the Lichess token
/// continues to live in secure storage via `LichessService`). Add
/// `shared_preferences` later to persist these across launches.
class AppSettings extends ChangeNotifier {
  BoardOrientationPref _orientation = BoardOrientationPref.auto;

  BoardOrientationPref get orientation => _orientation;
  set orientation(BoardOrientationPref value) {
    if (_orientation == value) return;
    _orientation = value;
    notifyListeners();
  }

  /// Resolves the concrete `whiteBottom` flag for a new game given the chosen
  /// [mode] and the local player's [humanColor].
  bool resolveWhiteBottom(GameMode mode, PieceColor humanColor) {
    return switch (_orientation) {
      BoardOrientationPref.whiteBottom => true,
      BoardOrientationPref.blackBottom => false,
      BoardOrientationPref.auto =>
        mode == GameMode.twoPlayer || humanColor == PieceColor.white,
    };
  }
}
