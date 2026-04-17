enum PieceColor {
  white,
  black,
}

extension PieceColorX on PieceColor {
  PieceColor get opposite {
    return this == PieceColor.white
        ? PieceColor.black
        : PieceColor.white;
  }

  String get label {
    return this == PieceColor.white ? 'White' : 'Black';
  }
}

enum PieceType {
  king,
  queen,
  rook,
  bishop,
  knight,
  pawn,
}

class Piece {
  const Piece(this.color, this.type);

  final PieceColor color;
  final PieceType type;

  String get symbol {
    switch (type) {
      case PieceType.king:
        return color == PieceColor.white ? '♔' : '♚';
      case PieceType.queen:
        return color == PieceColor.white ? '♕' : '♛';
      case PieceType.rook:
        return color == PieceColor.white ? '♖' : '♜';
      case PieceType.bishop:
        return color == PieceColor.white ? '♗' : '♝';
      case PieceType.knight:
        return color == PieceColor.white ? '♘' : '♞';
      case PieceType.pawn:
        return color == PieceColor.white ? '♙' : '♟';
    }
  }
}

class Square {
  const Square(this.file, this.rank)
      : assert(file >= 0 && file < 8),
        assert(rank >= 0 && rank < 8);

  final int file;
  final int rank;

  Square? translated(int df, int dr) {
    final nextFile = file + df;
    final nextRank = rank + dr;

    if (nextFile < 0 || nextFile > 7 || nextRank < 0 || nextRank > 7) {
      return null;
    }

    return Square(nextFile, nextRank);
  }

  String get algebraic {
    final fileChar = String.fromCharCode(97 + file);
    return '$fileChar${rank + 1}';
  }

  @override
  bool operator ==(Object other) {
    return other is Square && other.file == file && other.rank == rank;
  }

  @override
  int get hashCode => Object.hash(file, rank);
}

class ChessMove {
  const ChessMove({
    required this.from,
    required this.to,
    this.promotion,
  });

  final Square from;
  final Square to;

  /// The piece type to promote to when a pawn reaches the last rank.
  /// Null for non-promotion moves.
  final PieceType? promotion;

  String get uci {
    final base = '${from.algebraic}${to.algebraic}';
    return promotion != null ? '$base${_promotionLetter(promotion!)}' : base;
  }

  static String _promotionLetter(PieceType type) {
    switch (type) {
      case PieceType.queen:
        return 'q';
      case PieceType.rook:
        return 'r';
      case PieceType.bishop:
        return 'b';
      case PieceType.knight:
        return 'n';
      default:
        return '';
    }
  }
}

class CastlingRights {
  const CastlingRights({
    this.whiteKingside = true,
    this.whiteQueenside = true,
    this.blackKingside = true,
    this.blackQueenside = true,
  });

  static const none = CastlingRights(
    whiteKingside: false,
    whiteQueenside: false,
    blackKingside: false,
    blackQueenside: false,
  );

  final bool whiteKingside;
  final bool whiteQueenside;
  final bool blackKingside;
  final bool blackQueenside;

  bool canKingside(PieceColor color) =>
      color == PieceColor.white ? whiteKingside : blackKingside;

  bool canQueenside(PieceColor color) =>
      color == PieceColor.white ? whiteQueenside : blackQueenside;

  CastlingRights copyWith({
    bool? whiteKingside,
    bool? whiteQueenside,
    bool? blackKingside,
    bool? blackQueenside,
  }) {
    return CastlingRights(
      whiteKingside: whiteKingside ?? this.whiteKingside,
      whiteQueenside: whiteQueenside ?? this.whiteQueenside,
      blackKingside: blackKingside ?? this.blackKingside,
      blackQueenside: blackQueenside ?? this.blackQueenside,
    );
  }
}

class ChessPosition {
  ChessPosition({
    required Map<Square, Piece> pieces,
    required this.sideToMove,
    this.castlingRights = const CastlingRights(),
    this.enPassantTarget,
  }) : _pieces = Map.unmodifiable(pieces);

  final Map<Square, Piece> _pieces;
  final PieceColor sideToMove;
  final CastlingRights castlingRights;
  final Square? enPassantTarget;

  factory ChessPosition.initial() {
    final pieces = <Square, Piece>{};

    const backRank = <PieceType>[
      PieceType.rook,
      PieceType.knight,
      PieceType.bishop,
      PieceType.queen,
      PieceType.king,
      PieceType.bishop,
      PieceType.knight,
      PieceType.rook,
    ];

    for (var file = 0; file < 8; file++) {
      pieces[Square(file, 0)] = Piece(PieceColor.white, backRank[file]);
      pieces[Square(file, 1)] = const Piece(PieceColor.white, PieceType.pawn);
      pieces[Square(file, 6)] = const Piece(PieceColor.black, PieceType.pawn);
      pieces[Square(file, 7)] = Piece(PieceColor.black, backRank[file]);
    }

    return ChessPosition(
      pieces: pieces,
      sideToMove: PieceColor.white,
    );
  }

  Piece? pieceAt(Square square) => _pieces[square];

  bool isInCheck(PieceColor color) {
    Square? kingSquare;
    for (final entry in _pieces.entries) {
      if (entry.value.color == color && entry.value.type == PieceType.king) {
        kingSquare = entry.key;
        break;
      }
    }
    if (kingSquare == null) return false;
    return _isAttackedBy(kingSquare, color.opposite);
  }

  bool get isCheckmate {
    if (!isInCheck(sideToMove)) return false;
    return _hasNoLegalMoves();
  }

  bool get isStalemate {
    if (isInCheck(sideToMove)) return false;
    return _hasNoLegalMoves();
  }

  bool _hasNoLegalMoves() {
    for (final entry in _pieces.entries) {
      if (entry.value.color != sideToMove) continue;
      if (legalTargetsFrom(entry.key).isNotEmpty) return false;
    }
    return true;
  }

  ChessPosition makeMove(ChessMove move) {
    final movingPiece = pieceAt(move.from);
    if (movingPiece == null) return this;

    final next = Map<Square, Piece>.from(_pieces);
    next.remove(move.from);

    // Pawn promotion — use the chosen piece type from the move.
    // If promotion is null the pawn stays as a pawn; this only happens
    // transiently during the check-legality filter before the picker resolves.
    Piece placedPiece = movingPiece;
    if (movingPiece.type == PieceType.pawn &&
        (move.to.rank == 0 || move.to.rank == 7) &&
        move.promotion != null) {
      placedPiece = Piece(movingPiece.color, move.promotion!);
    }
    next[move.to] = placedPiece;

    // En passant capture: pawn moves diagonally to the en passant target square
    Square? nextEnPassantTarget;
    if (movingPiece.type == PieceType.pawn) {
      if (enPassantTarget != null && move.to == enPassantTarget) {
        final capturedRank = movingPiece.color == PieceColor.white
            ? move.to.rank - 1
            : move.to.rank + 1;
        next.remove(Square(move.to.file, capturedRank));
      }
      if ((move.to.rank - move.from.rank).abs() == 2) {
        nextEnPassantTarget =
            Square(move.from.file, (move.from.rank + move.to.rank) ~/ 2);
      }
    }

    // Castling: also move the rook
    var nextRights = castlingRights;
    if (movingPiece.type == PieceType.king) {
      final backRank = movingPiece.color == PieceColor.white ? 0 : 7;
      final fileDiff = move.to.file - move.from.file;
      if (fileDiff == 2) {
        // Kingside
        next.remove(Square(7, backRank));
        next[Square(5, backRank)] = Piece(movingPiece.color, PieceType.rook);
      } else if (fileDiff == -2) {
        // Queenside
        next.remove(Square(0, backRank));
        next[Square(3, backRank)] = Piece(movingPiece.color, PieceType.rook);
      }
      if (movingPiece.color == PieceColor.white) {
        nextRights =
            nextRights.copyWith(whiteKingside: false, whiteQueenside: false);
      } else {
        nextRights =
            nextRights.copyWith(blackKingside: false, blackQueenside: false);
      }
    }

    // Revoke rights when a rook moves
    if (movingPiece.type == PieceType.rook) {
      if (move.from == const Square(7, 0)) {
        nextRights = nextRights.copyWith(whiteKingside: false);
      }
      if (move.from == const Square(0, 0)) {
        nextRights = nextRights.copyWith(whiteQueenside: false);
      }
      if (move.from == const Square(7, 7)) {
        nextRights = nextRights.copyWith(blackKingside: false);
      }
      if (move.from == const Square(0, 7)) {
        nextRights = nextRights.copyWith(blackQueenside: false);
      }
    }

    // Revoke rights when a rook is captured
    if (move.to == const Square(7, 0)) {
      nextRights = nextRights.copyWith(whiteKingside: false);
    }
    if (move.to == const Square(0, 0)) {
      nextRights = nextRights.copyWith(whiteQueenside: false);
    }
    if (move.to == const Square(7, 7)) {
      nextRights = nextRights.copyWith(blackKingside: false);
    }
    if (move.to == const Square(0, 7)) {
      nextRights = nextRights.copyWith(blackQueenside: false);
    }

    return ChessPosition(
      pieces: next,
      sideToMove: sideToMove.opposite,
      castlingRights: nextRights,
      enPassantTarget: nextEnPassantTarget,
    );
  }

  List<Square> legalTargetsFrom(Square from) {
    final piece = pieceAt(from);
    if (piece == null || piece.color != sideToMove) return const [];

    final pseudoLegal = _pseudoLegalTargetsFrom(from, piece);
    return pseudoLegal.where((to) {
      final next = makeMove(ChessMove(from: from, to: to));
      return !next.isInCheck(piece.color);
    }).toList();
  }

  List<Square> _pseudoLegalTargetsFrom(Square from, Piece piece) {
    switch (piece.type) {
      case PieceType.pawn:
        return _pawnTargets(from, piece.color);
      case PieceType.knight:
        return _leaperTargets(from, piece.color, const [
          _Direction(1, 2),
          _Direction(2, 1),
          _Direction(2, -1),
          _Direction(1, -2),
          _Direction(-1, -2),
          _Direction(-2, -1),
          _Direction(-2, 1),
          _Direction(-1, 2),
        ]);
      case PieceType.bishop:
        return _rayTargets(from, piece.color, const [
          _Direction(1, 1),
          _Direction(1, -1),
          _Direction(-1, 1),
          _Direction(-1, -1),
        ]);
      case PieceType.rook:
        return _rayTargets(from, piece.color, const [
          _Direction(1, 0),
          _Direction(-1, 0),
          _Direction(0, 1),
          _Direction(0, -1),
        ]);
      case PieceType.queen:
        return _rayTargets(from, piece.color, const [
          _Direction(1, 0),
          _Direction(-1, 0),
          _Direction(0, 1),
          _Direction(0, -1),
          _Direction(1, 1),
          _Direction(1, -1),
          _Direction(-1, 1),
          _Direction(-1, -1),
        ]);
      case PieceType.king:
        final normal = _leaperTargets(from, piece.color, const [
          _Direction(1, 0),
          _Direction(-1, 0),
          _Direction(0, 1),
          _Direction(0, -1),
          _Direction(1, 1),
          _Direction(1, -1),
          _Direction(-1, 1),
          _Direction(-1, -1),
        ]);
        return [...normal, ..._castlingTargets(from, piece.color)];
    }
  }

  List<Square> _castlingTargets(Square from, PieceColor color) {
    final targets = <Square>[];
    final backRank = color == PieceColor.white ? 0 : 7;

    if (from != Square(4, backRank)) return targets;
    if (isInCheck(color)) return targets;

    // Kingside: king passes through f, lands on g
    if (castlingRights.canKingside(color)) {
      final f = Square(5, backRank);
      final g = Square(6, backRank);
      if (_isEmpty(f) && _isEmpty(g) && !_isAttackedBy(f, color.opposite)) {
        targets.add(g);
      }
    }

    // Queenside: king passes through d, lands on c; b must also be empty
    if (castlingRights.canQueenside(color)) {
      final d = Square(3, backRank);
      final c = Square(2, backRank);
      final b = Square(1, backRank);
      if (_isEmpty(d) &&
          _isEmpty(c) &&
          _isEmpty(b) &&
          !_isAttackedBy(d, color.opposite)) {
        targets.add(c);
      }
    }

    return targets;
  }

  List<Square> _pawnTargets(Square from, PieceColor color) {
    final targets = <Square>[];
    final forward = color == PieceColor.white ? 1 : -1;
    final startRank = color == PieceColor.white ? 1 : 6;

    final oneAhead = from.translated(0, forward);
    if (oneAhead != null && _isEmpty(oneAhead)) {
      targets.add(oneAhead);

      final twoAhead = from.translated(0, forward * 2);
      if (from.rank == startRank && twoAhead != null && _isEmpty(twoAhead)) {
        targets.add(twoAhead);
      }
    }

    final captureLeft = from.translated(-1, forward);
    final captureRight = from.translated(1, forward);

    if (captureLeft != null &&
        (_hasEnemy(captureLeft, color) || captureLeft == enPassantTarget)) {
      targets.add(captureLeft);
    }

    if (captureRight != null &&
        (_hasEnemy(captureRight, color) || captureRight == enPassantTarget)) {
      targets.add(captureRight);
    }

    return targets;
  }

  List<Square> _leaperTargets(
    Square from,
    PieceColor color,
    List<_Direction> directions,
  ) {
    final targets = <Square>[];

    for (final direction in directions) {
      final square = from.translated(direction.df, direction.dr);
      if (square == null) continue;
      if (_isEmpty(square) || _hasEnemy(square, color)) {
        targets.add(square);
      }
    }

    return targets;
  }

  List<Square> _rayTargets(
    Square from,
    PieceColor color,
    List<_Direction> directions,
  ) {
    final targets = <Square>[];

    for (final direction in directions) {
      var current = from;

      while (true) {
        final next = current.translated(direction.df, direction.dr);
        if (next == null) break;

        if (_isEmpty(next)) {
          targets.add(next);
          current = next;
          continue;
        }

        if (_hasEnemy(next, color)) {
          targets.add(next);
        }

        break;
      }
    }

    return targets;
  }

  bool _isAttackedBy(Square target, PieceColor attacker) {
    for (final entry in _pieces.entries) {
      if (entry.value.color != attacker) continue;
      if (_pieceAttacksSquare(entry.key, entry.value, target)) return true;
    }
    return false;
  }

  bool _pieceAttacksSquare(Square from, Piece piece, Square target) {
    switch (piece.type) {
      case PieceType.pawn:
        final forward = piece.color == PieceColor.white ? 1 : -1;
        return target == from.translated(-1, forward) ||
            target == from.translated(1, forward);
      case PieceType.knight:
        for (final offset in const [
          _Direction(1, 2),
          _Direction(2, 1),
          _Direction(2, -1),
          _Direction(1, -2),
          _Direction(-1, -2),
          _Direction(-2, -1),
          _Direction(-2, 1),
          _Direction(-1, 2),
        ]) {
          if (from.translated(offset.df, offset.dr) == target) return true;
        }
        return false;
      case PieceType.bishop:
        return _squareInRays(from, target, const [
          _Direction(1, 1),
          _Direction(1, -1),
          _Direction(-1, 1),
          _Direction(-1, -1),
        ]);
      case PieceType.rook:
        return _squareInRays(from, target, const [
          _Direction(1, 0),
          _Direction(-1, 0),
          _Direction(0, 1),
          _Direction(0, -1),
        ]);
      case PieceType.queen:
        return _squareInRays(from, target, const [
          _Direction(1, 0),
          _Direction(-1, 0),
          _Direction(0, 1),
          _Direction(0, -1),
          _Direction(1, 1),
          _Direction(1, -1),
          _Direction(-1, 1),
          _Direction(-1, -1),
        ]);
      case PieceType.king:
        final df = (target.file - from.file).abs();
        final dr = (target.rank - from.rank).abs();
        return df <= 1 && dr <= 1 && (df + dr) > 0;
    }
  }

  bool _squareInRays(Square from, Square target, List<_Direction> directions) {
    for (final dir in directions) {
      var current = from;
      while (true) {
        final next = current.translated(dir.df, dir.dr);
        if (next == null) break;
        if (next == target) return true;
        if (!_isEmpty(next)) break;
        current = next;
      }
    }
    return false;
  }

  bool _isEmpty(Square square) => pieceAt(square) == null;

  bool _hasEnemy(Square square, PieceColor color) {
    final piece = pieceAt(square);
    return piece != null && piece.color != color;
  }
}

class _Direction {
  const _Direction(this.df, this.dr);

  final int df;
  final int dr;
}
