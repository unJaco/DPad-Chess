/// A chess time control (clock) selection.
///
/// NOTE: the selection is currently only *stored*, not enforced — no countdown
/// clock is implemented yet. Online games forward [limitSeconds]/[incrementSeconds]
/// to Lichess via `seekAi`; offline (2-player / vs-engine) games simply remember
/// the choice on [ChessController.timeControl] for a future clock feature.
class TimeControl {
  const TimeControl({
    required this.label,
    required this.limitSeconds,
    required this.incrementSeconds,
  });

  /// Display label, e.g. "5+0" or "Unlimited".
  final String label;

  /// Base time in seconds. 0 means no clock (unlimited).
  final int limitSeconds;

  /// Increment added per move, in seconds.
  final int incrementSeconds;

  bool get isUnlimited => limitSeconds == 0;

  static const unlimited = TimeControl(
    label: 'Unlimited',
    limitSeconds: 0,
    incrementSeconds: 0,
  );

  @override
  bool operator ==(Object other) =>
      other is TimeControl &&
      other.label == label &&
      other.limitSeconds == limitSeconds &&
      other.incrementSeconds == incrementSeconds;

  @override
  int get hashCode => Object.hash(label, limitSeconds, incrementSeconds);
}

/// Presets offered for offline (2-player & vs-engine) games. Includes Unlimited.
const kOfflineTimeControls = <TimeControl>[
  TimeControl.unlimited,
  TimeControl(label: '3+2', limitSeconds: 180, incrementSeconds: 2),
  TimeControl(label: '5+0', limitSeconds: 300, incrementSeconds: 0),
  TimeControl(label: '10+0', limitSeconds: 600, incrementSeconds: 0),
  TimeControl(label: '15+10', limitSeconds: 900, incrementSeconds: 10),
];

/// Presets offered for online (Lichess AI) games. No Unlimited — the Board API
/// AI challenge used here expects a real-time clock.
const kOnlineTimeControls = <TimeControl>[
  TimeControl(label: '3+2', limitSeconds: 180, incrementSeconds: 2),
  TimeControl(label: '5+0', limitSeconds: 300, incrementSeconds: 0),
  TimeControl(label: '10+0', limitSeconds: 600, incrementSeconds: 0),
  TimeControl(label: '15+10', limitSeconds: 900, incrementSeconds: 10),
];
