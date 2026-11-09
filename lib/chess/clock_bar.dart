import 'package:flutter/material.dart';

import 'chess_models.dart';
import 'game_clock.dart';

/// A compact, reusable clock readout for one side. It rebuilds itself on every
/// tick via the [clock] notifier, so ticking never repaints the board.
///
/// Height is kept small (34px) so it takes as little room from the board as
/// possible; two of these flank the board (top = far side, bottom = near side).
class ClockBar extends StatelessWidget {
  const ClockBar({super.key, required this.clock, required this.color});

  final GameClock clock;
  final PieceColor color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isWhite = color == PieceColor.white;

    return AnimatedBuilder(
      animation: clock,
      builder: (context, _) {
        final ms = clock.msFor(color);
        final active = clock.active == color;
        final low = ms <= 10000;

        return Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? colors.primary
                  : (low ? colors.error : colors.outlineVariant),
              width: active ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isWhite ? Colors.white : Colors.black,
                  border: Border.all(color: colors.outline, width: 1),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isWhite ? 'White' : 'Black',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: active
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                formatClockMs(ms),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.bold,
                  color: low
                      ? colors.error
                      : (active ? colors.onPrimaryContainer : colors.onSurface),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
