import 'package:flutter_test/flutter_test.dart';
import 'package:pyforge/editor/python_mode.dart';
import 'package:re_highlight/re_highlight.dart';

/// Regression: the custom Python grammar used to throw
/// "beginScope must be Map<int, String>" while compiling, so the editor never
/// showed any syntax colors. Scope keys in a `match:` list are also 1-based.
String _html(String code) {
  final Highlight h = Highlight()..registerLanguage('python', pyforgePythonMode);
  final HighlightResult r = h.highlight(code: code, language: 'python');
  return r.toHtml();
}

void main() {
  test('grammar compiles and highlights keywords, strings and numbers', () {
    final String html = _html('def f(x):\n    return "a" + str(12)  # note\n');
    expect(html, contains('hljs-keyword'));
    expect(html, contains('hljs-string'));
    expect(html, contains('hljs-number'));
    expect(html, contains('hljs-comment'));
  });

  test('numbers: int, float, hex, exponent, underscore, complex', () {
    for (final String n in <String>['42', '3.14', '0xFF', '1e-3', '1_000', '2j']) {
      expect(_html('x = $n\n'), contains('hljs-number">$n<'), reason: n);
    }
  });

  test('def / class names, TODO markers, brackets and self are scoped', () {
    final String html = _html(
        'class A:\n    def go(self):  # TODO fix\n        return [1, {2: (3)}]\n');
    expect(html, contains('hljs-title class_'));
    expect(html, contains('hljs-title function_'));
    expect(html, contains('hljs-doctag'));
    expect(html, contains('hljs-symbol'));
    expect(html, contains('hljs-attr'));
    expect(html, contains('hljs-variable'));
  });
}
