import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../chess_controller.dart';
import '../engine_service.dart';
import '../keypad_widgets.dart';
import 'game_setup_page.dart';
import 'online_setup_page.dart';

/// New Game → choose a mode. Each mode leads to its own setup page.
class ModeSelectPage extends StatelessWidget {
  const ModeSelectPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ChessController controller;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return KeypadMenuScaffold(
      title: 'New Game',
      subtitle: 'Choose a mode',
      onBack: () => Navigator.of(context).pop(),
      items: [
        KeypadMenuItem(
          label: 'Two Player',
          subtitle: 'Local, pass-and-play',
          icon: Icons.people_outline,
          onSelect: () => _pushOffline(context, GameMode.twoPlayer),
        ),
        KeypadMenuItem(
          label: 'Vs Computer',
          subtitle: 'Play against the engine',
          icon: Icons.smart_toy_outlined,
          onSelect: () => _pushOffline(context, GameMode.vsEngine),
        ),
        KeypadMenuItem(
          label: 'Play Online',
          subtitle: 'Lichess AI',
          icon: Icons.public,
          onSelect: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  OnlineSetupPage(controller: controller, settings: settings),
            ),
          ),
        ),
      ],
    );
  }

  void _pushOffline(BuildContext context, GameMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GameSetupPage(
          mode: mode,
          controller: controller,
          settings: settings,
        ),
      ),
    );
  }
}
