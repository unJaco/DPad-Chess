// Smoke tests for the start-page navigation flow.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:t9_chess_app/main.dart';

void main() {
  testWidgets('start page shows the main menu', (tester) async {
    await tester.pumpWidget(const T9ChessApp());
    await tester.pumpAndSettle();

    expect(find.text('New Game'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
  });

  testWidgets('New Game opens the mode-select page', (tester) async {
    await tester.pumpWidget(const T9ChessApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    expect(find.text('Two Player'), findsOneWidget);
    expect(find.text('Vs Computer'), findsOneWidget);
    expect(find.text('Play Online'), findsOneWidget);
  });

  testWidgets('Two Player setup launches a game', (tester) async {
    await tester.pumpWidget(const T9ChessApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Two Player'));
    await tester.pumpAndSettle();

    // The offline setup page offers a Time picker and a Start button.
    expect(find.text('Unlimited'), findsOneWidget);
    expect(find.text('Start Game'), findsOneWidget);

    await tester.tap(find.text('Start Game'));
    await tester.pumpAndSettle();

    // The board page (untimed game) shows the turn line above the board.
    expect(find.textContaining('White to move'), findsOneWidget);
  });

  testWidgets('game-over review and back-to-menu navigation', (tester) async {
    await tester.pumpWidget(const T9ChessApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two Player'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Game'));
    await tester.pumpAndSettle();

    // Resign via the keypad (0) to reach the end-of-game options.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resign'));
    await tester.pumpAndSettle();

    // End-of-game dialog offers all three options.
    expect(find.text('Play Again'), findsOneWidget);
    expect(find.text('Review Game'), findsOneWidget);
    expect(find.text('Main Menu'), findsOneWidget);

    // Review the game, then return to the start page from review.
    await tester.tap(find.text('Review Game'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Review'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.pumpAndSettle();
    expect(find.text('New Game'), findsOneWidget);

    // The returned start page must still respond to the keypad: OK on the
    // first item (New Game) should re-open the mode-select page.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Two Player'), findsOneWidget);
  });
}
