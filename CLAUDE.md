# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## How to work in this repo (orchestrator mode)

Claude acts as **orchestrator** for this project: break each request into concrete tasks, estimate each task's complexity, and delegate to sub-agents where that is more efficient (e.g. broad codebase sweeps, independent parallel work, larger isolated features). Trivial or tightly-coupled tasks where the context is already loaded are done directly — delegation is a tool, not a ritual. Briefly state the task breakdown and who handles what.

## What this is

A Flutter chess app whose entire interaction model is built around a **D-pad / T9 phone keypad** rather than touch or pointer. The concrete target device is the **Qin F21 Pro** (a small Android keypad phone) — that is why the whole UI is driven by arrow keys + OK + number keys and why every page/dialog reimplements manual D-pad navigation. It supports local two-player, vs-Stockfish, and online play against the Lichess AI, with optional chess clocks. The chess rules engine is hand-written (no chess library).

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

Tests: [test/widget_test.dart](test/widget_test.dart) holds navigation smoke tests (start menu → mode select → setup → board → resign → review → back to menu). There are no unit tests for the rules engine or the clock yet.

## Architecture

All application code lives in `lib/chess/`. [lib/main.dart](lib/main.dart) owns the two long-lived objects at the root — `ChessController` and `AppSettings` — and passes them down; `home` is `StartPage`.

### Navigation: full-screen pages
Flow: `StartPage` → `ModeSelectPage` → `GameSetupPage` (2-player / vs-engine) or `OnlineSetupPage` (Lichess) → `GamePage`. Plus `SettingsPage` and `HelpPage`. Pages live in [lib/chess/pages/](lib/chess/pages/); the board page `GamePage` lives in [game_page.dart](lib/chess/game_page.dart).

Reusable keypad building blocks are in [keypad_widgets.dart](lib/chess/keypad_widgets.dart): `KeypadMenuScaffold` (vertical menu), `KeypadOptionRow` (chip row for setup pages), `showKeypadChoiceDialog`. Use these for new menus/dialogs instead of hand-rolling navigation again. Help text is shared between the in-game dialog and `HelpPage` via [help_content.dart](lib/chess/help_content.dart).

### State: one controller
[chess_controller.dart](lib/chess/chess_controller.dart) — `ChessController extends ChangeNotifier` is the single source of truth for game state: position history, cursor, selection, game mode, engine state, online state, review mode, and the clock. The UI never holds game state; it rebuilds from `notifyListeners()`. `GamePage` subscribes via an `AnimatedBuilder` over a merged `Listenable` of the controller **and** the board `FocusNode` (so focus-ring changes also repaint).

[app_settings.dart](lib/chess/app_settings.dart) — `AppSettings` (in-memory only, not persisted yet) holds app-wide preferences such as board orientation.

### Rules: immutable positions, hand-rolled
[chess_models.dart](lib/chess/chess_models.dart) implements chess from scratch — there is no external chess package.
- `ChessPosition` is **immutable**; `makeMove()` returns a brand-new position. The controller keeps a `_history` stack of positions, which is what makes undo a simple `removeLast()` and review mode a simple index into `_history`.
- `Square(file, rank)` uses **0–7 for both**, with rank 0 = white's back rank (a1). UCI strings are converted at the boundaries (`EngineService.parseMoveUci`, `ChessMove.uci`).
- Move generation is **pseudo-legal then filtered**: `legalTargetsFrom` generates candidate targets, plays each on a copy, and rejects any that leave the mover's king in check (`isInCheck` → `_isAttackedBy`). Castling, en passant, and promotion are all handled inside `makeMove`. Checkmate/stalemate are derived from "in check?" + "any legal move?". Threefold-repetition / 50-move / insufficient-material draws are **not** detected locally (online, Lichess reports them as end reasons).

### Three game modes
`GameMode { twoPlayer, vsEngine, lichess }` (defined in [engine_service.dart](lib/chess/engine_service.dart)) drives move routing in the controller's `_executeMove`:
- **twoPlayer / vsEngine** → apply locally; vsEngine then triggers an async engine move when it's the engine's turn.
- **lichess** → apply **optimistically**, POST to Lichess, and roll back the last position if the POST is rejected. Incoming Lichess state is the authority: Lichess sends the *full* move list each update and the controller applies any moves it doesn't already have.

Game end states: checkmate, stalemate, resignation (`_resignedColor`), time-out (`_flaggedColor`), or an online end reason (`_onlineEndReason`). After the game ends, `GameOverDialog` ([game_over_dialog.dart](lib/chess/game_over_dialog.dart)) offers Play Again / Review Game / Main Menu.

### Chess clock
[game_clock.dart](lib/chess/game_clock.dart) — `GameClock extends ChangeNotifier`, its own notifier so the clock ticks (200 ms) without repainting the board. Created by `_setupClock` from the selected `TimeControl` ([game_config.dart](lib/chess/game_config.dart)); `null` for Unlimited.
- **Offline** (`authoritative: true`): counts down locally, `onMove` adds the increment and switches sides, `onFlag` → controller sets `_flaggedColor`. `GamePage` pauses the clock in `dispose` and resumes it on mount (leaving the board pauses the game).
- **Online** (`authoritative: false`): `sync()` overwrites times from Lichess `wtime`/`btime`; local ticking is display-only, time-out is decided by the server.
- Undo does **not** restore clock times.

[clock_bar.dart](lib/chess/clock_bar.dart) — `ClockBar` renders one side. During play, timed games show the far player's clock above and the near player's below the board; untimed games show only the status line. The move list is shown only in review mode.

### Engine integration
[engine_service.dart](lib/chess/engine_service.dart) wraps the `stockfish` package over the raw **UCI text protocol** (write to `stdin`, parse `stdout` lines). Async replies are bridged with `Completer`s — one for the `uci`/`isready` handshake, one for `bestmove`. `EngineLevel` (beginner / intermediate / hard; easy & expert are commented out) maps each difficulty to a Stockfish `Skill Level`, `movetime`, and depth cap.

> **Gotcha:** `ChessController.initialize()` currently has engine startup commented out (`// TODO: re-enable engine initialization before release`). Until that's restored, `requestMove` returns `''` because the engine is never `ready`, so **vs-Engine mode makes no moves**. Re-enable initialization to test engine play.

### Lichess integration
[lichess_service.dart](lib/chess/lichess_service.dart) is a client for the Lichess **Board API**.
- Auth is a Personal Access Token (`board:play` scope) stored via `flutter_secure_storage`, entered through `TokenEntryDialog` ([token_entry_dialog.dart](lib/chess/token_entry_dialog.dart)). `seekAi` challenges the Lichess AI (real-opponent matchmaking is a TODO).
- Game state arrives over an **NDJSON stream** (`/api/board/game/stream/{id}`) parsed line-by-line, emitted on a broadcast `Stream<LichessGameState>`. It self-heals via exponential-backoff reconnect plus a 35s heartbeat timer.
- Player color from `random` seeks is resolved server-side and corrected when the `gameFull` event arrives — the UI passes a placeholder color until then.

### Input model — read this before touching any UI
The app is **keyboard/D-pad-first** and does **not** use Flutter's normal focus traversal for navigation.

Board keys during play (`_onKeyEvent` in [game_page.dart](lib/chess/game_page.dart)): arrows = move cursor, Enter/Select/Space = activate (select piece / play move), `0` = resign, `1`/Esc/Backspace = cancel selection, `*` = undo (offline only), `#` = flip board, `8` = help, `9` = main menu. The hardware back button opens the resign dialog during a game.

Review mode (`_onReviewKey`): ←/→ step one ply, ↑ end, ↓ start, `#` flip, `1` reopen end-of-game options, `0`/Esc = main menu.

Menus/setup pages: ↑/↓ move rows, ←/→ change a row's value, OK activates, `0`/Esc goes back.

Two consequences to respect when adding UI:
1. **Every page and dialog does its own D-pad navigation** — a `FocusNode` + `onKeyEvent` + manual row/column index state (`KeypadMenuScaffold`, `GameSetupPage`, `OnlineSetupPage`, `PromotionPicker` ([promotion_picker.dart](lib/chess/promotion_picker.dart)), `GameOverDialog` all follow this pattern). Standard buttons alone won't be keyboard-reachable; prefer the widgets in `keypad_widgets.dart`.
2. **Cursor snapping:** when a piece is selected, arrow keys don't move one square — `_moveCursorToTarget` snaps the cursor to the nearest legal target in that direction using a directional score. Board orientation (`whiteBottom`) flips both the rendering (`_squareForDisplay`) and the D-pad direction vectors.

### Piece rendering
Pieces come from one sprite sheet `assets/pieces.png`, **6 columns (Q, K, R, N, B, P) × 2 rows (black top, white bottom)**. `PieceSprite` ([piece_sprite.dart](lib/chess/piece_sprite.dart)) shows a single cell by sizing the image 6× wide and clipping with `OverflowBox` alignment — keep that layout in mind if the asset is ever replaced.
