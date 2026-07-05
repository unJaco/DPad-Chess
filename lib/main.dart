import 'package:flutter/material.dart';

import 'chess/app_settings.dart';
import 'chess/chess_controller.dart';
import 'chess/pages/start_page.dart';

void main() {
  runApp(const T9ChessApp());
}

class T9ChessApp extends StatefulWidget {
  const T9ChessApp({super.key});

  @override
  State<T9ChessApp> createState() => _T9ChessAppState();
}

class _T9ChessAppState extends State<T9ChessApp> {
  // The single source of truth, owned at the root and shared across pages.
  late final ChessController _controller;
  late final AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _controller = ChessController();
    _settings = AppSettings();
    // Initialize the engine in the background (currently a no-op until engine
    // startup is re-enabled — see ChessController.initialize).
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'T9ChessApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: StartPage(controller: _controller, settings: _settings),
    );
  }
}
