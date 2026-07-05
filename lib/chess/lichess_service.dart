import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'chess_models.dart';

// TODO: Add OAuth 2.0 PKCE flow as alternative to PAT

// ── Model ─────────────────────────────────────────────────────────────────────

class LichessGameState {
  const LichessGameState({
    required this.moves,
    required this.status,
    required this.myColor,
    this.wtime,
    this.btime,
  });

  /// Space-separated UCI move list, e.g. "e2e4 e7e5 g1f3". Empty at game start.
  final String moves;

  /// Lichess game status: "started", "created", "mate", "resign",
  /// "outoftime", "draw", "stalemate", "aborted", etc.
  final String status;

  final PieceColor myColor;

  /// Milliseconds remaining for white.
  final int? wtime;

  /// Milliseconds remaining for black.
  final int? btime;
}

// ── Service ───────────────────────────────────────────────────────────────────

class LichessService {
  static const _base = 'https://lichess.org';
  static const _tokenKey = 'lichess_pat';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String? _token;
  String? _username;
  String? _gameId;

  final _client = http.Client();
  StreamSubscription<String>? _streamSub;
  final _gameStateController = StreamController<LichessGameState>.broadcast();
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  bool _disposed = false;

  Stream<LichessGameState> get gameStates => _gameStateController.stream;
  String? get currentGameId => _gameId;

  // ── Token management ────────────────────────────────────────────────────────

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    _token = token;
  }

  Future<String?> loadToken() async {
    _token = await _storage.read(key: _tokenKey);
    return _token;
  }

  /// Removes the stored token (used by Settings → remove account).
  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
    _token = null;
    _username = null;
  }

  /// True if a token is currently cached in memory (call [loadToken] first).
  bool get hasToken => _token != null;

  /// Ensures [_username] is populated (used to resolve our colour in
  /// real-opponent games). No-op if already known or no token is set. AI games
  /// don't need this — colour is derived from which side is the AI.
  Future<void> ensureAccountId() async {
    if (_username != null || _token == null) return;
    try {
      final response = await _client
          .get(Uri.parse('$_base/api/account'), headers: _authHeaders(_token!))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _username = data['id'] as String?;
      }
    } catch (_) {
      // Best-effort — colour resolution has other fallbacks.
    }
  }

  /// Returns true and caches the username if the token has the right scopes.
  Future<bool> validateToken(String token) async {
    try {
      final response = await _client
          .get(Uri.parse('$_base/api/account'), headers: _authHeaders(token))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _username = data['id'] as String?;
      return _username != null;
    } catch (_) {
      return false;
    }
  }

  // ── Game lifecycle ───────────────────────────────────────────────────────────

  /// Challenges the Lichess AI. Returns the gameId on success, throws on error.
  Future<String> seekAi({
    required int level,
    required int clockLimitSeconds,
    required int clockIncrementSeconds,
    required String color, // "white", "black", or "random"
  }) async {
    _assertToken();
    final response = await _client
        .post(
          Uri.parse('$_base/api/challenge/ai'),
          headers: {
            ..._authHeaders(_token!),
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'level': '$level',
            'clock.limit': '$clockLimitSeconds',
            'clock.increment': '$clockIncrementSeconds',
            'color': color,
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Lichess error ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final gameId = data['id'] as String?;
    if (gameId == null) {
      throw Exception('No game id in response: ${response.body}');
    }
    return gameId;
  }

  /// Opens the NDJSON stream for [gameId] and starts emitting [LichessGameState]
  /// events on [gameStates]. Handles reconnection automatically.
  Future<void> connectToGame(String gameId) async {
    _assertToken();
    await ensureAccountId();
    _gameId = gameId;
    _reconnectAttempts = 0;
    await _openStream(gameId);
  }

  Future<void> _openStream(String gameId) async {
    if (_disposed) return;
    _streamSub?.cancel();
    _resetHeartbeat();

    try {
      final request = http.Request(
        'GET',
        Uri.parse('$_base/api/board/game/stream/$gameId'),
      );
      request.headers.addAll(_authHeaders(_token!));
      request.headers['Accept'] = 'application/x-ndjson';

      final response = await _client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Stream error ${response.statusCode}');
      }

      final lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      _streamSub = lineStream.listen(
        _handleLine,
        onError: _handleStreamError,
        onDone: _handleStreamDone,
        cancelOnError: false,
      );
    } catch (e) {
      _scheduleReconnect(gameId);
    }
  }

  void _handleLine(String line) {
    if (_disposed) return;
    // Any received line (including keep-alive newlines) proves the connection
    // is healthy, so clear the reconnect backoff and reset the heartbeat.
    // Without this, transient drops escalate the backoff (1→2→4→8→16s) and the
    // client gives up after 5 attempts, leaving the game frozen.
    _reconnectAttempts = 0;
    _resetHeartbeat();
    if (line.trim().isEmpty) return; // keep-alive

    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final type = json['type'] as String?;

      if (type == 'gameFull') {
        _handleGameFull(json);
      } else if (type == 'gameState') {
        _handleGameState(json, _resolveMyColor(json));
      }
    } catch (_) {
      // Malformed line — ignore.
    }
  }

  void _handleGameFull(Map<String, dynamic> json) {
    final myColor = _resolveMyColorFromFull(json);
    final stateJson = json['state'] as Map<String, dynamic>?;
    if (stateJson != null) {
      _handleGameState(stateJson, myColor);
    }
  }

  PieceColor _resolveMyColorFromFull(Map<String, dynamic> json) {
    final white = json['white'] as Map<String, dynamic>?;
    final black = json['black'] as Map<String, dynamic>?;

    // In a game vs the Lichess AI, exactly one side is the AI (it carries an
    // "aiLevel" and no "id") and we are always the other side. This resolves our
    // colour reliably even when the account username isn't cached — e.g. after
    // the token was loaded from storage without re-validating.
    final whiteIsAi = white?['aiLevel'] != null;
    final blackIsAi = black?['aiLevel'] != null;
    if (whiteIsAi && !blackIsAi) return PieceColor.black;
    if (blackIsAi && !whiteIsAi) return PieceColor.white;

    // Real-opponent games: match our own account id.
    if (_username != null) {
      if ((white?['id'] as String?) == _username) return PieceColor.white;
      if ((black?['id'] as String?) == _username) return PieceColor.black;
    }

    // Unknown — keep the colour we already have rather than forcing black.
    return _lastMyColor;
  }

  // For gameState events we rely on the cached color from gameFull.
  // _lastMyColor is set during gameFull processing.
  PieceColor _lastMyColor = PieceColor.white;

  PieceColor _resolveMyColor(Map<String, dynamic> _) => _lastMyColor;

  void _handleGameState(Map<String, dynamic> json, PieceColor myColor) {
    _lastMyColor = myColor;
    _gameStateController.add(
      LichessGameState(
        moves: (json['moves'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'started',
        myColor: myColor,
        wtime: json['wtime'] as int?,
        btime: json['btime'] as int?,
      ),
    );
  }

  void _handleStreamError(Object error) {
    if (_disposed) return;
    if (_gameId != null) _scheduleReconnect(_gameId!);
  }

  void _handleStreamDone() {
    if (_disposed) return;
    // Stream closed cleanly — game may be over or network dropped.
    // The controller will have already received a terminal status if the game
    // ended normally. If not, attempt a reconnect.
    if (_gameId != null) _scheduleReconnect(_gameId!);
  }

  void _scheduleReconnect(String gameId) {
    if (_disposed || _reconnectAttempts >= 5) return;
    final delay = Duration(seconds: (1 << _reconnectAttempts).clamp(1, 60));
    _reconnectAttempts++;
    Future.delayed(delay, () => _openStream(gameId));
  }

  void _resetHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(const Duration(seconds: 35), () {
      // No event for 35s — connection may have silently dropped.
      if (_gameId != null && !_disposed) {
        _reconnectAttempts = 0;
        _openStream(_gameId!);
      }
    });
  }

  // ── Move / game actions ──────────────────────────────────────────────────────

  /// Posts a move. Returns true on success.
  Future<bool> postMove(String uci) async {
    if (_token == null || _gameId == null) return false;
    try {
      final response = await _client
          .post(
            Uri.parse('$_base/api/board/game/$_gameId/move/$uci'),
            headers: _authHeaders(_token!),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> resign() async {
    if (_token == null || _gameId == null) return;
    try {
      await _client
          .post(
            Uri.parse('$_base/api/board/game/$_gameId/resign'),
            headers: _authHeaders(_token!),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> abort() async {
    if (_token == null || _gameId == null) return;
    try {
      await _client
          .post(
            Uri.parse('$_base/api/board/game/$_gameId/abort'),
            headers: _authHeaders(_token!),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _streamSub?.cancel();
    _streamSub = null;
    _gameId = null;
    _reconnectAttempts = 0;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    disconnect();
    _gameStateController.close();
    _client.close();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Map<String, String> _authHeaders(String token) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  void _assertToken() {
    if (_token == null) throw StateError('No Lichess token set.');
  }

  /// Utility: paste text from clipboard into a [TextEditingController].
  static Future<String?> pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }
}
