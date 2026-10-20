import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

/// Signatures for the most common builtins (shown as parameter hints).
const Map<String, Map<String, String>> _kBuiltinSignatures = {
  'print': {'values': 'object', 'sep': 'str', 'end': 'str'},
  'range': {'start': 'int', 'stop': 'int', 'step': 'int'},
  'len': {'obj': 'object'},
  'enumerate': {'iterable': 'iterable', 'start': 'int'},
  'isinstance': {'obj': 'object', 'class_or_tuple': 'type'},
  'open': {'file': 'str', 'mode': 'str'},
};

const List<String> _kKeywords = [
  'and', 'as', 'assert', 'async', 'await', 'break', 'case', 'class',
  'continue', 'def', 'del', 'elif', 'else', 'except', 'finally', 'for',
  'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'match',
  'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try', 'while',
  'with', 'yield',
];

const List<String> _kBuiltinNames = [
  'abs', 'all', 'any', 'ascii', 'bin', 'bool', 'breakpoint', 'bytearray',
  'bytes', 'callable', 'chr', 'classmethod', 'compile', 'complex',
  'delattr', 'dict', 'dir', 'divmod', 'enumerate', 'eval', 'exec',
  'filter', 'float', 'format', 'frozenset', 'getattr', 'globals',
  'hasattr', 'hash', 'help', 'hex', 'id', 'input', 'int', 'isinstance',
  'issubclass', 'iter', 'len', 'list', 'locals', 'map', 'max',
  'memoryview', 'min', 'next', 'object', 'oct', 'open', 'ord', 'pow',
  'print', 'property', 'range', 'repr', 'reversed', 'round', 'set',
  'setattr', 'slice', 'sorted', 'staticmethod', 'str', 'sum', 'super',
  'tuple', 'type', 'vars', 'zip',
];

/// IntelliSense for Python: keywords, builtins (with parameter hints) and
/// every symbol defined anywhere in the current document.
class PythonPromptsBuilder implements CodeAutocompletePromptsBuilder {
  PythonPromptsBuilder({required this.documentProvider});

  /// Returns the full text of the document being edited (live).
  final String Function() documentProvider;

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    final String lineText = codeLine.text;
    final int offset = selection.extentOffset;
    if (offset < 0 || offset > lineText.length) return null;

    final String before = lineText.substring(0, offset);
    final RegExpMatch? wordMatch =
        RegExp(r'([A-Za-z_]\w*)$').firstMatch(before);
    if (wordMatch == null) return null;
    final String input = wordMatch.group(1)!;
    if (input.isEmpty) return null;

    final List<CodePrompt> prompts = <CodePrompt>[
      for (final String kw in _kKeywords) CodeKeywordPrompt(word: kw),
      for (final String name in _kBuiltinNames)
        _builtinPrompt(name),
      ..._documentSymbols(documentProvider()),
    ];

    final List<CodePrompt> matched =
        prompts.where((CodePrompt p) => p.match(input)).toList();
    // Keywords first, then builtins, then document symbols — already
    // ordered by construction; dedupe exact words.
    final List<CodePrompt> deduped = <CodePrompt>[];
    final Set<String> seen = <String>{};
    for (final CodePrompt p in matched) {
      if (seen.add(p.word)) deduped.add(p);
    }
    if (deduped.isEmpty) return null;
    return CodeAutocompleteEditingValue(
      input: input,
      prompts: deduped,
      index: 0,
    );
  }

  static CodePrompt _builtinPrompt(String name) {
    final Map<String, String>? params = _kBuiltinSignatures[name];
    if (params == null) {
      return CodeFieldPrompt(word: name, type: 'builtin');
    }
    return CodeFunctionPrompt(
      word: name,
      type: 'builtin',
      parameters: params,
    );
  }

  static List<CodePrompt> _documentSymbols(String document) {
    final Set<String> names = <String>{};
    for (final RegExpMatch m
        in RegExp(r'\b(?:def|class)\s+([A-Za-z_]\w*)').allMatches(document)) {
      names.add(m.group(1)!);
    }
    for (final RegExpMatch m
        in RegExp(r'^\s*([A-Za-z_]\w*)\s*(?::[^=\n]+)?=')
            .allMatches(document)) {
      names.add(m.group(1)!);
    }
    for (final RegExpMatch m
        in RegExp(r'\b(?:import|from)\s+([A-Za-z_][\w.]*)')
            .allMatches(document)) {
      names.add(m.group(1)!.split('.').first);
    }
    return <CodePrompt>[
      for (final String name in names)
        CodeFieldPrompt(word: name, type: 'in this file'),
    ];
  }
}

/// The autocomplete overlay list, themed for the current app theme.
class PythonAutocompleteView extends StatefulWidget
    implements PreferredSizeWidget {
  const PythonAutocompleteView({
    super.key,
    required this.notifier,
    required this.onSelected,
  });

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  static const double itemHeight = 40;

  @override
  Size get preferredSize => Size(
        280,
        (itemHeight * notifier.value.prompts.length).clamp(0.0, 200.0) + 2,
      );

  @override
  State<PythonAutocompleteView> createState() => _PythonAutocompleteViewState();
}

class _PythonAutocompleteViewState extends State<PythonAutocompleteView> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final CodeAutocompleteEditingValue value = widget.notifier.value;
    if (value.prompts.isEmpty) return const SizedBox.shrink();

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        width: 280,
        height: (PythonAutocompleteView.itemHeight * value.prompts.length)
                .clamp(0.0, 200.0) +
            2,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 2),
          itemCount: value.prompts.length,
          itemBuilder: (BuildContext context, int index) {
            final CodePrompt prompt = value.prompts[index];
            final bool selected = index == value.index;
            return InkWell(
              onTap: () => widget.onSelected(
                value.copyWith(index: index).autocomplete,
              ),
              child: Container(
                height: PythonAutocompleteView.itemHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                color: selected
                    ? scheme.primary.withValues(alpha: 0.15)
                    : null,
                child: _promptRow(prompt, scheme),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _promptRow(CodePrompt prompt, ColorScheme scheme) {
    final String input = widget.notifier.value.input;
    String detail = '';
    if (prompt is CodeFieldPrompt) detail = prompt.type;
    if (prompt is CodeFunctionPrompt) {
      detail = '(${prompt.parameters.keys.join(', ')})';
    }
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: input.isEmpty
                ? prompt.word
                : prompt.word.substring(0, input.length),
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          TextSpan(
            text: input.isEmpty
                ? ''
                : prompt.word.substring(input.length),
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          TextSpan(
            text: '  $detail',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
