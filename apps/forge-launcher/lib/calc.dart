// A small calculator for the launcher: + - * / % ^, parentheses, unary
// minus, pi and e, and sqrt/sin/cos/tan/log/ln/abs/round/floor/ceil.
// Returns null for anything that isn't a complete expression, so plain words
// never turn into a result.
import 'dart:math' as math;

double? evaluate(String input) {
  final text = input.replaceAll('×', '*').replaceAll('÷', '/').replaceAll(',', '');
  // Must look like arithmetic: a digit and an operator or function, not
  // just a number on its own.
  if (!RegExp(r'\d').hasMatch(text) ||
      !RegExp(r'[-+*/%^()]|sqrt|sin|cos|tan|log|ln|abs|round|floor|ceil|pi')
          .hasMatch(text)) {
    return null;
  }
  try {
    final p = _Parser(text);
    final v = p.expression();
    p.skipSpace();
    if (!p.atEnd || v.isNaN || v.isInfinite) return null;
    return v;
  } on FormatException {
    return null;
  }
}

String formatNumber(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  var s = v.toStringAsPrecision(12);
  if (s.contains('.') && !s.contains('e')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

class _Parser {
  _Parser(this.s);

  final String s;
  int i = 0;

  bool get atEnd => i >= s.length;

  void skipSpace() {
    while (!atEnd && s[i] == ' ') {
      i++;
    }
  }

  bool eat(String c) {
    skipSpace();
    if (!atEnd && s[i] == c) {
      i++;
      return true;
    }
    return false;
  }

  // expression := term (('+' | '-') term)*
  double expression() {
    var v = term();
    while (true) {
      if (eat('+')) {
        v += term();
      } else if (eat('-')) {
        v -= term();
      } else {
        return v;
      }
    }
  }

  // term := power (('*' | '/' | '%') power)*
  double term() {
    var v = power();
    while (true) {
      if (eat('*')) {
        v *= power();
      } else if (eat('/')) {
        v /= power();
      } else if (eat('%')) {
        v %= power();
      } else {
        return v;
      }
    }
  }

  // power := unary ('^' power)?   (right-associative)
  double power() {
    final base = unary();
    if (eat('^')) return math.pow(base, power()).toDouble();
    return base;
  }

  double unary() {
    if (eat('-')) return -unary();
    if (eat('+')) return unary();
    return atom();
  }

  static final _functions = <String, double Function(double)>{
    'sqrt': math.sqrt,
    'sin': math.sin,
    'cos': math.cos,
    'tan': math.tan,
    'log': (x) => math.log(x) / math.ln10,
    'ln': math.log,
    'abs': (x) => x.abs(),
    'round': (x) => x.roundToDouble(),
    'floor': (x) => x.floorToDouble(),
    'ceil': (x) => x.ceilToDouble(),
  };

  double atom() {
    skipSpace();
    if (eat('(')) {
      final v = expression();
      if (!eat(')')) throw const FormatException('missing )');
      return v;
    }
    final word = RegExp(r'[a-z]+').matchAsPrefix(s, i);
    if (word != null) {
      final name = word.group(0)!;
      i = word.end;
      if (name == 'pi') return math.pi;
      if (name == 'e') return math.e;
      final f = _functions[name];
      if (f == null) throw FormatException('unknown $name');
      if (!eat('(')) throw const FormatException('missing (');
      final v = expression();
      if (!eat(')')) throw const FormatException('missing )');
      return f(v);
    }
    final number = RegExp(r'\d+(\.\d*)?|\.\d+').matchAsPrefix(s, i);
    if (number == null) throw const FormatException('expected a number');
    i = number.end;
    return double.parse(number.group(0)!);
  }
}
