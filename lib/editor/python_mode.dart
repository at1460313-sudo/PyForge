import 'package:re_highlight/re_highlight.dart';

/// A hand-tuned Python grammar for re_highlight.
///
/// Beyond the stock python grammar it adds:
///  - Bracket colorization by type (rainbow brackets): () -> 'symbol',
///    [] -> 'attr', {} -> 'variable'. These classes exist in every bundled
///    syntax theme, so brackets are visually distinct from code.
///  - TODO / FIXME / XXX / HACK highlighting inside comments via 'doctag'.
const List<String> _kKeywords = <String>[
  'and', 'as', 'assert', 'async', 'await', 'break', 'case', 'class',
  'continue', 'def', 'del', 'elif', 'else', 'except', 'finally', 'for',
  'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'match',
  'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try', 'while',
  'with', 'yield',
];

const List<String> _kBuiltins = <String>[
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

const List<String> _kLiterals = <String>[
  'True', 'False', 'None', 'Ellipsis', 'NotImplemented', '__debug__',
];

const List<String> _kTypes = <String>[
  'Any', 'Callable', 'Coroutine', 'Dict', 'List', 'Literal', 'Generic',
  'Optional', 'Sequence', 'Set', 'Tuple', 'Type', 'Union',
];

final Mode _escape = Mode(match: [r'\\.'], scope: const {0: 'string'});

final Mode pyforgePythonMode = Mode(
  name: 'python',
  aliases: const <String>['py'],
  unicodeRegex: true,
  keywords: <String, dynamic>{
    r'$pattern': r'[A-Za-z]\w*|__\w+__',
    'keyword': _kKeywords,
    'built_in': _kBuiltins,
    'literal': _kLiterals,
    'type': _kTypes,
  },
  contains: <Mode>[
    // Comments with TODO/FIXME markers.
    Mode(
      className: 'comment',
      begin: '#',
      end: r'$',
      contains: <Mode>[
        Mode(
          match: [r'\b(TODO|FIXME|XXX|HACK)\b'],
          scope: const <int, String>{1: 'doctag'},
        ),
      ],
    ),
    // Triple-quoted strings (also used as docstrings).
    Mode(
      className: 'string',
      begin: "([fFrRbBuU]{0,2})'''",
      end: "'''",
      contains: <Mode>[_escape],
    ),
    Mode(
      className: 'string',
      begin: '([fFrRbBuU]{0,2})"""',
      end: '"""',
      contains: <Mode>[_escape],
    ),
    // Single-quoted strings.
    Mode(className: 'string', begin: "[fFrRbBuU]{0,2}'", end: "'"),
    Mode(className: 'string', begin: '[fFrRbBuU]{0,2}"', end: '"'),
    // Numbers (int, float, hex, oct, bin, underscores).
    Mode(
      className: 'number',
      match: [
        r'\b\d[\d_]*(\.\d+)?([eE][+-]?\d+)?[jJ]?\b',
        r'\b0[xXoObB][0-9a-fA-F_]+\b',
      ],
    ),
    // def / class names.
    Mode(
      match: [r'\b(def)\s+', r'[A-Za-z_]\w*'],
      scope: const <int, String>{1: 'keyword', 2: 'title.function'},
    ),
    Mode(
      match: [r'\b(class)\s+', r'[A-Za-z_]\w*'],
      scope: const <int, String>{1: 'keyword', 2: 'title.class'},
    ),
    // Decorators.
    Mode(className: 'meta', begin: r'^\s*@', end: '(?=#)|$'),
    // Rainbow brackets by type.
    Mode(match: [r'[()]'], scope: const <int, String>{0: 'symbol'}),
    Mode(match: [r'[\[\]]'], scope: const <int, String>{0: 'attr'}),
    Mode(match: [r'[{}]'], scope: const <int, String>{0: 'variable'}),
    // self.
    Mode(match: [r'\bself\b'], scope: const <int, String>{0: 'keyword'}),
  ],
);
