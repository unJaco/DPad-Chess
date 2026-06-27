# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Flutter chess app whose entire interaction model is built around a **D-pad / T9 phone keypad** rather than touch or pointer. The concrete target device is the **Qin F21 Pro** (a small Android keypad phone) — that is why the whole UI is driven by arrow keys + OK + number keys (`0/1/*/#/9`) and why every dialog reimplements manual D-pad navigation. It supports local two-player, vs-Stockfish, and online play against the Lichess AI. The chess rules engine is hand-written (no chess library).

The app is named **T9ChessApp** everywhere user-facing (window/app title, AppBar, web title/manifest, root widget class). The Dart **package identifier** is `t9_chess_app` (`pubspec.yaml` `name:` and `package:t9_chess_app/...` imports) — pub requires lowercase snake_case, so the identifier uses the snake_case form. Note the native platform projects still use `dpad_chess` / `com.example.dpad_chess` for product/binary names and the Android `applicationId`/`namespace`; those are independent of the Dart package and were intentionally left as-is. Keep new display strings as "T9ChessApp".

## Commands

```bash
flutter pub get                              # install dependencies
flutter run -d <device>                       # run (e.g. -d chrome, -d macos, -d <android-id>)
flutter analyze                               # static analysis / lints (flutter_lints + analysis_options.yaml)
dart format lib test                          # format
flutter test                                  # run all tests
flutter test --plain-name "<substring>"       # run a single test by name
flutter build apk    # / appbundle / ios / macos / web / windows / linux
```

Toolchain: Flutter 3.35.x stable, Dart SDK `^3.9.2`.

> `test/widget_test.dart` is still the stale default counter template and **does not match this app — it fails**. Replace or delete it before relying on `flutter test`.

## Architecture

All application code lives in `lib/chess/`. `lib/main.dart` is just the `MaterialApp` shell pointing at `ChessPage`.

### State: one controller
[chess_controller.dart](lib/chess/chess_controller.dart) — `ChessController extends ChangeNotifier` is the single source of truth for everything: position history, cursor, selection, game mode, engine state, and online state. The UI never holds game state; it rebuilds from `notifyListeners()`. [chess_page.dart](lib/chess/chess_page.dart) subscribes via an `AnimatedBuilder` over a merged `Listenable` of the controller **and** the board `FocusNode` (so focus-ring changes also repaint).

### Rules: immutable positions, hand-rolled
[chess_models.dart](lib/chess/chess_models.dart) implements chess from scratch — there is no external chess package.
- `ChessPosition` is **immutable**; `makeMove()` returns a brand-new position. The controller keeps a `_history` stack of positions, which is what makes undo a simple `removeLast()`.
- `Square(file, rank)` uses **0–7 for both**, with rank 0 = white's back rank (a1). UCI strings are converted at the boundaries (`EngineService.parseMoveUci`, `ChessMove.uci`).
- Move generation is **pseudo-legal then filtered**: `legalTargetsFrom` generates candidate targets, plays each on a copy, and rejects any that leave the mover's king in check (`isInCheck` → `_isAttackedBy`). Castling, en passant, and promotion are all handled inside `makeMove`. Checkmate/stalemate are derived from "in check?" + "any legal move?".

### Three game modes
`GameMode { twoPlayer, vsEngine, lichess }` (defined in [engine_service.dart](lib/chess/engine_service.dart)) drives move routing in the controller's `_executeMove`:
- **twoPlayer / vsEngine** → apply locally; vsEngine then triggers an async engine move when it's the engine's turn.
- **lichess** → apply **optimistically**, POST to Lichess, and roll back the last position if the POST is rejected. Incoming Lichess state is the authority: Lichess sends the *full* move list each update and the controller applies any moves it doesn't already have.

### Engine integration
[engine_service.dart](lib/chess/engine_service.dart) wraps the `stockfish` package over the raw **UCI text protocol** (write to `stdin`, parse `stdout` lines). Async replies are bridged with `Completer`s — one for the `uci`/`isready` handshake, one for `bestmove`. `EngineLevel` maps each difficulty to a Stockfish `Skill Level`, `movetime`, and depth cap.

> **Gotcha:** `ChessController.initialize()` currently has engine startup commented out (`// TODO: re-enable engine initialization before release`). Until that's restored, `requestMove` returns `''` because the engine is never `ready`, so **vs-Engine mode makes no moves**. Re-enable initialization to test engine play.

### Lichess integration
[lichess_service.dart](lib/chess/lichess_service.dart) is a client for the Lichess **Board API**.
- Auth is a Personal Access Token (`board:play` scope) stored via `flutter_secure_storage`. `seekAi` challenges the Lichess AI (real-opponent matchmaking is a TODO).
- Game state arrives over an **NDJSON stream** (`/api/board/game/stream/{id}`) parsed line-by-line, emitted on a broadcast `Stream<LichessGameState>`. It self-heals via exponential-backoff reconnect plus a 35s heartbeat timer.
- Player color from `random` seeks is resolved server-side and corrected when the `gameFull` event arrives — the UI passes a placeholder color until then.

### Input model — read this before touching any UI
The app is **keyboard/D-pad-first** and does **not** use Flutter's normal focus traversal for navigation. The board's `_onKeyEvent` ([chess_page.dart](lib/chess/chess_page.dart)) maps: arrows = move cursor, Enter/Select/Space = activate (select piece / play move), `0` = resign, `1` = cancel selection, `*` = undo, `#` = flip board, `9` = help.

Two consequences to respect when adding UI:
1. **Every dialog reimplements its own D-pad navigation** by hand — a `FocusNode` + `onKeyEvent` + manual row/column index state (`_NewGameDialog`, `OnlineSetupDialog`, `_PromotionPicker` all follow this pattern). New dialogs must do the same; standard buttons alone won't be keyboard-reachable.
2. **Cursor snapping:** when a piece is selected, arrow keys don't move one square — `_moveCursorToTarget` snaps the cursor to the nearest legal target in that direction using a directional score. Board orientation (`whiteBottom`) flips both the rendering (`_squareForDisplay`) and the D-pad direction vectors.

### Piece rendering
Pieces come from one sprite sheet `assets/pieces.png`, **6 columns (Q, K, R, N, B, P) × 2 rows (black top, white bottom)**. `_PieceSprite` shows a single cell by sizing the image 6× wide and clipping with `OverflowBox` alignment — keep that layout in mind if the asset is ever replaced.
