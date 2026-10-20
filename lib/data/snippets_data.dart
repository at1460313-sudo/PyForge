/// The searchable snippet library. Tap to insert at the caret.
class CodeSnippet {
  const CodeSnippet({
    required this.title,
    required this.keywords,
    required this.code,
  });

  final String title;
  final List<String> keywords;
  final String code;
}

const List<CodeSnippet> kSnippets = <CodeSnippet>[
  CodeSnippet(
    title: 'Hello world',
    keywords: ['print', 'start', 'hello'],
    code: 'print("Hello, world!")\n',
  ),
  CodeSnippet(
    title: 'Function definition',
    keywords: ['def', 'function'],
    code: 'def my_function(param):\n'
        '    """Describe what this does."""\n'
        '    return param\n',
  ),
  CodeSnippet(
    title: 'Class definition',
    keywords: ['class', 'oop', 'object'],
    code: 'class Dog:\n'
        '    def __init__(self, name):\n'
        '        self.name = name\n\n'
        '    def bark(self):\n'
        '        print(f"{self.name} says woof!")\n',
  ),
  CodeSnippet(
    title: 'For loop with range',
    keywords: ['for', 'loop', 'range'],
    code: 'for i in range(10):\n    print(i)\n',
  ),
  CodeSnippet(
    title: 'For loop over list',
    keywords: ['for', 'loop', 'list', 'iterate'],
    code: 'items = ["a", "b", "c"]\n'
        'for item in items:\n'
        '    print(item)\n',
  ),
  CodeSnippet(
    title: 'While loop',
    keywords: ['while', 'loop'],
    code: 'count = 0\n'
        'while count < 5:\n'
        '    print(count)\n'
        '    count += 1\n',
  ),
  CodeSnippet(
    title: 'If / elif / else',
    keywords: ['if', 'elif', 'else', 'condition'],
    code: 'value = 10\n'
        'if value > 100:\n'
        '    print("big")\n'
        'elif value > 0:\n'
        '    print("small")\n'
        'else:\n'
        '    print("not positive")\n',
  ),
  CodeSnippet(
    title: 'List comprehension',
    keywords: ['list', 'comprehension', 'map'],
    code: 'squares = [x * x for x in range(10)]\n',
  ),
  CodeSnippet(
    title: 'Dictionary',
    keywords: ['dict', 'dictionary', 'map'],
    code: 'person = {\n'
        '    "name": "Ada",\n'
        '    "age": 36,\n'
        '}\n'
        'print(person["name"])\n',
  ),
  CodeSnippet(
    title: 'Try / except',
    keywords: ['try', 'except', 'error', 'exception'],
    code: 'try:\n'
        '    number = int("not a number")\n'
        'except ValueError as error:\n'
        '    print("That was not a number:", error)\n',
  ),
  CodeSnippet(
    title: 'File read',
    keywords: ['file', 'read', 'open'],
    code: 'with open("data.txt", "r") as f:\n'
        '    contents = f.read()\n'
        'print(contents)\n',
  ),
  CodeSnippet(
    title: 'File write',
    keywords: ['file', 'write', 'open'],
    code: 'with open("output.txt", "w") as f:\n'
        '    f.write("Hello from PyForge!")\n',
  ),
  CodeSnippet(
    title: 'User input',
    keywords: ['input', 'user', 'readline'],
    code: 'name = input("What is your name? ")\n'
        'print(f"Nice to meet you, {name}!")\n',
  ),
  CodeSnippet(
    title: 'F-string formatting',
    keywords: ['fstring', 'format', 'string'],
    code: 'name = "Ada"\n'
        'age = 36\n'
        'print(f"{name} is {age} years old")\n',
  ),
  CodeSnippet(
    title: 'Fetch a URL (requests)',
    keywords: ['requests', 'http', 'url', 'network'],
    code: 'import requests\n\n'
        'response = requests.get("https://api.github.com/zen")\n'
        'print(response.status_code)\n'
        'print(response.text)\n',
  ),
  CodeSnippet(
    title: 'numpy basics',
    keywords: ['numpy', 'array', 'math'],
    code: 'import numpy as np\n\n'
        'data = np.array([1, 2, 3, 4])\n'
        'print(data.mean())\n'
        'print(data * 2)\n',
  ),
  CodeSnippet(
    title: 'main() guard',
    keywords: ['main', 'script', 'entry', 'point'],
    code: 'def main():\n'
        '    print("Running")\n\n\n'
        'if __name__ == "__main__":\n'
        '    main()\n',
  ),
  CodeSnippet(
    title: 'TODO reminder',
    keywords: ['todo', 'comment', 'note'],
    code: '# TODO: finish this feature\n',
  ),
];
