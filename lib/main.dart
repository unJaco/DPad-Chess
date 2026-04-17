import 'package:flutter/material.dart';

import 'chess/chess_page.dart';

void main() {
  runApp(const QinChessApp());
}

class QinChessApp extends StatelessWidget {
  const QinChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DPad Chess',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ChessPage(),
    );
  }
}
