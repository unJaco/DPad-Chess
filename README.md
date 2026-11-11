# T9 Chess

A chess app for phones with a traditional T9 keypad, played with nothing but a D-pad and the number keys. Built with Flutter for the Qin F21 Pro.

More about the project, including a live demo: [b08.io/projects/t9-chess](https://b08.io/projects/t9-chess/)

## Features

- No touch or pointer needed. Every screen and dialog is operated with the D-pad and OK. Once a piece is selected, the cursor snaps to its legal target squares.
- Chess rules written from scratch, without a chess library: castling, en passant and promotion, check, checkmate and stalemate. Draws by repetition, the 50-move rule and insufficient material are not detected locally.
- Game modes:
  - **Two Player:** pass-and-play on the same phone.
  - **Play Online:** play against the Lichess AI through the Lichess Board API. Requires a Lichess personal access token with the `board:play` scope, entered in the app. Matchmaking against real opponents is not implemented yet.
  - **Vs Computer:** play against Stockfish on the device. **Currently not working:** engine startup is commented out in `ChessController.initialize()`, so the engine makes no moves.
- Optional chess clock with increment, game review after the game, board flipping.

## Controls

During a game:

| Key | Action |
|---|---|
| D-pad | Move cursor |
| OK / Enter | Select piece or play move |
| `1` | Cancel selection |
| `*` | Undo last move (offline games only) |
| `#` | Flip board |
| `0` | Resign |
| `8` | Help |
| `9` | Main menu |

In menus, up/down move between rows, left/right change a value, OK confirms and `0` goes back. In game review, left/right step through the moves.

## Tech stack

- Flutter (Dart SDK `^3.9.2`)
- [`stockfish`](https://pub.dev/packages/stockfish) for the engine, talked to over UCI
- [`http`](https://pub.dev/packages/http) for the Lichess Board API
- [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) for the Lichess token

## Getting started

You need a Flutter SDK matching the Dart constraint above (Flutter 3.35 stable was used).

```bash
flutter pub get
flutter run
```

For online play, create a Lichess personal access token with the `board:play` scope and enter it in the app when asked.

---

Built by [B08](https://b08.io), Jacob Meilutat's software studio in Berlin.
