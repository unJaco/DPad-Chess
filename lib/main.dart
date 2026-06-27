import 'package:flutter/material.dart';

import 'chess/chess_page.dart';

void main() {
  runApp(const T9ChessApp());
}

class T9ChessApp extends StatelessWidget {
  const T9ChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'T9ChessApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ChessPage(),
    );
  }
}
