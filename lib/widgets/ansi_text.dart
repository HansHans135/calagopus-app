import 'package:flutter/material.dart';

/// Renders a console line, interpreting basic ANSI SGR color/bold codes and
/// stripping any other escape sequences.
class AnsiText extends StatelessWidget {
  final String line;
  final TextStyle baseStyle;

  const AnsiText(this.line, {super.key, required this.baseStyle});

  static const _basicColors = <int, Color>{
    30: Color(0xFF3B4252),
    31: Color(0xFFEF5350),
    32: Color(0xFF66BB6A),
    33: Color(0xFFFFCA28),
    34: Color(0xFF42A5F5),
    35: Color(0xFFAB47BC),
    36: Color(0xFF26C6DA),
    37: Color(0xFFCFD8DC),
    90: Color(0xFF78909C),
    91: Color(0xFFFF8A80),
    92: Color(0xFFB9F6CA),
    93: Color(0xFFFFE57F),
    94: Color(0xFF82B1FF),
    95: Color(0xFFEA80FC),
    96: Color(0xFF84FFFF),
    97: Color(0xFFFFFFFF),
  };

  static final _ansiPattern = RegExp(r'\x1B\[[0-9;]*m|\x1B\[[0-9;?]*[A-Za-z]');

  List<TextSpan> _parse() {
    final spans = <TextSpan>[];
    var style = baseStyle;
    var index = 0;

    for (final match in _ansiPattern.allMatches(line)) {
      if (match.start > index) {
        spans.add(TextSpan(
            text: line.substring(index, match.start), style: style));
      }
      index = match.end;
      final seq = match.group(0)!;
      if (!seq.endsWith('m')) continue; // non-SGR sequence: strip it
      final codes = seq
          .substring(2, seq.length - 1)
          .split(';')
          .map((c) => int.tryParse(c) ?? 0)
          .toList();
      if (codes.isEmpty) codes.add(0);
      for (var i = 0; i < codes.length; i++) {
        final code = codes[i];
        if (code == 0) {
          style = baseStyle;
        } else if (code == 1) {
          style = style.copyWith(fontWeight: FontWeight.bold);
        } else if (_basicColors.containsKey(code)) {
          style = style.copyWith(color: _basicColors[code]);
        } else if (code == 38 && i + 2 < codes.length && codes[i + 1] == 5) {
          style = style.copyWith(color: _color256(codes[i + 2]));
          i += 2;
        } else if (code == 39) {
          style = style.copyWith(color: baseStyle.color);
        }
      }
    }
    if (index < line.length) {
      spans.add(TextSpan(text: line.substring(index), style: style));
    }
    return spans;
  }

  static Color _color256(int n) {
    if (n < 8) return _basicColors[30 + n]!;
    if (n < 16) return _basicColors[90 + (n - 8)]!;
    if (n >= 232) {
      final v = 8 + (n - 232) * 10;
      return Color.fromARGB(255, v, v, v);
    }
    final i = n - 16;
    const steps = [0, 95, 135, 175, 215, 255];
    return Color.fromARGB(
        255, steps[i ~/ 36], steps[(i % 36) ~/ 6], steps[i % 6]);
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(children: _parse()), softWrap: true);
  }
}
