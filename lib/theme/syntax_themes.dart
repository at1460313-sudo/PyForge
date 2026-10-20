import 'package:flutter/material.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';
import 'package:re_highlight/styles/base16/dracula.dart';
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';
import 'package:re_highlight/styles/monokai.dart';
import 'package:re_highlight/styles/nord.dart';
import 'package:re_highlight/styles/tokyo-night-dark.dart';

/// A syntax theme: a re_highlight color map plus the editor chrome colors.
class SyntaxThemeDef {
  const SyntaxThemeDef({
    required this.id,
    required this.label,
    required this.isDark,
    required this.map,
    required this.background,
    required this.text,
    this.gutterText,
  });

  final String id;
  final String label;
  final bool isDark;

  /// re_highlight class -> TextStyle map (includes a 'root' background).
  final Map<String, TextStyle> map;

  /// Editor chrome colors.
  final Color background;
  final Color text;
  final Color? gutterText;
}

class SyntaxThemes {
  static const String defaultId = 'one-dark-pro';

  static final List<SyntaxThemeDef> all = [
    SyntaxThemeDef(
      id: 'one-dark-pro',
      label: 'One Dark Pro',
      isDark: true,
      map: atomOneDarkTheme,
      background: const Color(0xFF282C34),
      text: const Color(0xFFABB2BF),
    ),
    SyntaxThemeDef(
      id: 'dracula',
      label: 'Dracula',
      isDark: true,
      map: draculaTheme,
      background: const Color(0xFF282A36),
      text: const Color(0xFFF8F8F2),
    ),
    SyntaxThemeDef(
      id: 'monokai',
      label: 'Monokai',
      isDark: true,
      map: monokaiTheme,
      background: const Color(0xFF272822),
      text: const Color(0xFFF8F8F2),
    ),
    SyntaxThemeDef(
      id: 'tokyo-night',
      label: 'Tokyo Night',
      isDark: true,
      map: tokyoNightDarkTheme,
      background: const Color(0xFF1A1B26),
      text: const Color(0xFFC0CAF5),
    ),
    SyntaxThemeDef(
      id: 'nord',
      label: 'Nord',
      isDark: true,
      map: nordTheme,
      background: const Color(0xFF2E3440),
      text: const Color(0xFFD8DEE9),
    ),
    SyntaxThemeDef(
      id: 'github-dark',
      label: 'GitHub Dark',
      isDark: true,
      map: githubDarkTheme,
      background: const Color(0xFF0D1117),
      text: const Color(0xFFC9D1D9),
    ),
    SyntaxThemeDef(
      id: 'github-light',
      label: 'GitHub Light',
      isDark: false,
      map: githubTheme,
      background: const Color(0xFFFFFFFF),
      text: const Color(0xFF24292F),
    ),
    SyntaxThemeDef(
      id: 'atom-one-light',
      label: 'Atom One Light',
      isDark: false,
      map: atomOneLightTheme,
      background: const Color(0xFFFAFAFA),
      text: const Color(0xFF383A42),
    ),
  ];

  static SyntaxThemeDef byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all.first);
}
