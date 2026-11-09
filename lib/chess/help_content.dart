import 'package:flutter/material.dart';

/// A single controls/legend entry, rendered by [HelpRow].
class HelpEntry {
  const HelpEntry(this.icon, this.label, this.description);

  final IconData icon;
  final String label;
  final String description;
}

const gameplayHelpEntries = <HelpEntry>[
  HelpEntry(Icons.gamepad, 'D-pad', 'Move cursor'),
  HelpEntry(
    Icons.check_circle_outline,
    'OK / Enter',
    'Select piece or execute move',
  ),
  HelpEntry(Icons.flag_outlined, '0', 'Resign'),
  HelpEntry(Icons.close, '1', 'Cancel selection'),
  HelpEntry(Icons.undo, '*', 'Undo last move'),
  HelpEntry(Icons.screen_rotation_alt, '#', 'Flip board orientation'),
  HelpEntry(Icons.help_outline, '8', 'Show this help'),
  HelpEntry(Icons.home_outlined, '9', 'Main menu'),
];

const legendHelpEntries = <HelpEntry>[
  HelpEntry(Icons.warning_amber_rounded, 'Red king', 'King is in check'),
  HelpEntry(Icons.circle, 'Dot on square', 'Legal move target'),
  HelpEntry(
    Icons.radio_button_unchecked,
    'Ring on piece',
    'Capturable enemy piece',
  ),
];

/// The shared controls + legend list used by both the in-game help dialog and
/// the standalone Help page.
class HelpContentList extends StatelessWidget {
  const HelpContentList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in gameplayHelpEntries) HelpRow(entry: e),
        const Divider(height: 20),
        for (final e in legendHelpEntries) HelpRow(entry: e),
      ],
    );
  }
}

class HelpRow extends StatelessWidget {
  const HelpRow({super.key, required this.entry});

  final HelpEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(entry.icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              entry.label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(entry.description, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
