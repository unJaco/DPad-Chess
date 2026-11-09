import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../chess_controller.dart';
import '../game_page.dart';
import '../keypad_widgets.dart';
import 'help_page.dart';
import 'mode_select_page.dart';
import 'settings_page.dart';

/// The app's home screen. Action-first menu: New Game / Settings / Help.
class StartPage extends StatelessWidget {
  const StartPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ChessController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return KeypadMenuScaffold(
      title: 'T9ChessApp',
      //subtitle: 'D-pad chess',
      footerHint: '↑↓ move  •  OK select',
      // Home screen — nothing to go back to.
      onBack: null,
      items: [
        KeypadMenuItem(
          label: 'New Game',
          subtitle: 'Online or offline',
          icon: Icons.play_arrow,
          onSelect: () => _onNewGame(context),
        ),
        KeypadMenuItem(
          label: 'Settings',
          subtitle: 'Board, account, and more',
          icon: Icons.settings_outlined,
          onSelect: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  SettingsPage(controller: controller, settings: settings),
            ),
          ),
        ),
        KeypadMenuItem(
          label: 'Help',
          subtitle: 'Controls and legend',
          icon: Icons.help_outline,
          onSelect: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const HelpPage())),
        ),
      ],
    );
  }

  /// If a game is already in progress, offer to resume it rather than silently
  /// discarding it; otherwise go straight to mode selection.
  void _onNewGame(BuildContext context) {
    if (controller.hasActiveGame) {
      showKeypadChoiceDialog(
        context,
        title: 'Game in progress',
        message:
            'You already have a game running. Resume it, or start a new '
            'one (this abandons the current game)?',
        options: [
          KeypadDialogOption(
            label: 'Resume game',
            icon: Icons.play_arrow,
            onSelect: () {
              Navigator.of(context).pop();
              _openGame(context);
            },
          ),
          KeypadDialogOption(
            label: 'New game',
            icon: Icons.add,
            onSelect: () {
              Navigator.of(context).pop();
              _openModeSelect(context);
            },
          ),
        ],
      );
      return;
    }
    _openModeSelect(context);
  }

  void _openModeSelect(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ModeSelectPage(controller: controller, settings: settings),
      ),
    );
  }

  void _openGame(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GamePage(controller: controller, settings: settings),
      ),
    );
  }
}
