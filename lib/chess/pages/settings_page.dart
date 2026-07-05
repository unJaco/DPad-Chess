import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../chess_controller.dart';
import '../keypad_widgets.dart';
import '../token_entry_dialog.dart';

/// Settings scaffold. A keypad-navigable list with a couple of real entries and
/// room to grow. OK activates the focused row (cycles a value or opens a
/// dialog); 0 goes back.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ChessController controller;
  final AppSettings settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _hasToken = false;

  @override
  void initState() {
    super.initState();
    _refreshToken();
  }

  Future<void> _refreshToken() async {
    final token = await widget.controller.lichessService.loadToken();
    if (mounted) setState(() => _hasToken = token != null);
  }

  void _cycleOrientation() {
    const values = BoardOrientationPref.values;
    final next =
        values[(widget.settings.orientation.index + 1) % values.length];
    setState(() => widget.settings.orientation = next);
  }

  Future<void> _setToken() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TokenEntryDialog(
        lichessService: widget.controller.lichessService,
        onSuccess: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
    await _refreshToken();
  }

  Future<void> _removeToken() async {
    await widget.controller.lichessService.deleteToken();
    await _refreshToken();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lichess account removed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeypadMenuScaffold(
      title: 'Settings',
      onBack: () => Navigator.of(context).pop(),
      items: [
        KeypadMenuItem(
          label: 'Board orientation',
          subtitle: 'Bottom side: ${widget.settings.orientation.label}',
          icon: Icons.screen_rotation_alt,
          onSelect: _cycleOrientation,
        ),
        KeypadMenuItem(
          label: _hasToken ? 'Replace Lichess account' : 'Add Lichess account',
          subtitle: _hasToken ? 'A token is saved' : 'Needed for online play',
          icon: Icons.vpn_key_outlined,
          onSelect: _setToken,
        ),
        KeypadMenuItem(
          label: 'Remove Lichess account',
          subtitle: 'Delete the saved token',
          icon: Icons.logout,
          enabled: _hasToken,
          onSelect: _removeToken,
        ),
        const KeypadMenuItem(
          label: 'Sound',
          subtitle: 'Coming soon',
          icon: Icons.volume_off_outlined,
          enabled: false,
          onSelect: _noop,
        ),
      ],
    );
  }
}

void _noop() {}
