import 'package:flutter/material.dart';

import 'chess_models.dart';

// ── Piece sprite ─────────────────────────────────────────────────────────────
//
// Renders one cell from the sprite sheet at assets/pieces.png.
// Sheet layout: 6 columns × 2 rows.
//   Columns (left→right): Queen, King, Rook, Knight, Bishop, Pawn
//   Row 0 (top):          Black pieces (filled)
//   Row 1 (bottom):       White pieces (outline)

class PieceSprite extends StatelessWidget {
  const PieceSprite({super.key, required this.piece, required this.size});

  final Piece piece;
  final double size;

  static const _assetPath = 'assets/pieces.png';

  static int _col(PieceType type) => switch (type) {
    PieceType.queen => 0,
    PieceType.king => 1,
    PieceType.rook => 2,
    PieceType.knight => 3,
    PieceType.bishop => 4,
    PieceType.pawn => 5,
  };

  @override
  Widget build(BuildContext context) {
    final col = _col(piece.type);
    final row = piece.color == PieceColor.black ? 0 : 1;

    // Map col 0..5 → alignment x -1..1, row 0..1 → alignment y -1..1
    final alignX = -1.0 + col * 2.0 / 5.0;
    final alignY = row == 0 ? -1.0 : 1.0;

    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          minWidth: size * 6,
          maxWidth: size * 6,
          minHeight: size * 2,
          maxHeight: size * 2,
          alignment: Alignment(alignX, alignY),
          child: Image.asset(
            _assetPath,
            width: size * 6,
            height: size * 2,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
