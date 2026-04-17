import 'package:flutter/material.dart';

import 'lichess_service.dart';

class TokenEntryDialog extends StatefulWidget {
  const TokenEntryDialog({
    super.key,
    required this.lichessService,
    required this.onSuccess,
    required this.onCancel,
  });

  final LichessService lichessService;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  @override
  State<TokenEntryDialog> createState() => _TokenEntryDialogState();
}

class _TokenEntryDialogState extends State<TokenEntryDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = await LichessService.pasteFromClipboard();
    if (text != null && text.isNotEmpty) {
      _controller.text = text.trim();
      setState(() => _error = null);
    }
  }

  Future<void> _validate() async {
    final token = _controller.text.trim();
    if (token.isEmpty) {
      setState(() => _error = 'Please enter a token.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final ok = await widget.lichessService.validateToken(token);

    if (!mounted) return;
    if (ok) {
      await widget.lichessService.saveToken(token);
      widget.onSuccess();
    } else {
      setState(() {
        _loading = false;
        _error = 'Invalid token or missing board:play scope.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AlertDialog(
      title: const Text('Lichess Account'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          /*Text(
            'Generate a Personal Access Token at lichess.org/account/oauth/token '
            'with the board:play scope, then paste or type it below.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),*/
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'API token',
              hintText: 'lip_…',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _validate(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : _paste,
            icon: const Icon(Icons.paste, size: 18),
            label: const Text('Paste from clipboard'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _validate,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Validate & Save'),
        ),
      ],
    );
  }
}
