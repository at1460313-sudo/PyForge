/// The built-in learning hub: lessons, challenges and cheat sheets.
/// Everything works offline; challenges are graded on-device.
class Lesson {
  const Lesson({
    required this.id,
    required this.title,
    required this.minutes,
    required this.summary,
    required this.content,
    required this.challengeId,
  });

  final String id;
  final String title;
  final int minutes;
  final String summary;
  final String content; // markdown-lite
  final String challengeId;
}

class Challenge {
  const Challenge({
    required this.id,
    required this.title,
    required this.description,
    required this.starterCode,
    required this.testCode,
    this.hint = '',
  });

  final String id;
  final String title;
  final String description;
  final String starterCode;
  final String testCode;
  final String hint;
}

class CheatSheet {
  const CheatSheet({required this.title, required this.rows});
  final String title;
  final List<List<String>> rows; // [code, meaning]
}

const List<Lesson> kLessons = <Lesson>[
  Lesson(
    id: 'lesson-variables',
    title: 'Variables & Types',
    minutes: 6,
    summary: 'Store values in names; meet int, float, str and bool.',
    challengeId: 'challenge-variables',
    content: '''
# Variables & Types

A variable is a **name for a value**. You create one with `=`:

```python
age = 12          # int (whole number)
height = 1.52     # float (decimal)
nickname = "Byte" # str (text)
is_coder = True   # bool (True / False)
```

## The rules
- Names are lowercase with underscores: `my_score`.
- A value's **type** can change: `x = 5` then `x = "five"` is fine.
- See a value's type with `type(x)`.

## Converting between types
```python
int("42")    # 42
str(42)      # "42"
float("1.5") # 1.5
```

## Try it
Create a variable for your age, print it, then print its type.
''',
  ),
  Lesson(
    id: 'lesson-strings',
    title: 'Strings & f-strings',
    minutes: 7,
    summary: 'Text in Python: slicing, methods and formatted output.',
    challengeId: 'challenge-strings',
    content: '''
# Strings & f-strings

Strings are text inside quotes. Single or double, both work.

## f-strings (the modern way to format)
```python
name = "Ada"
age = 36
print(f"{name} is {age} years old")
```

## Useful string methods
```python
"hello".upper()        # "HELLO"
"hello".capitalize()   # "Hello"
"  hi  ".strip()       # "hi"
"hello world".replace("o", "0")  # "hell0 w0rld"
"a,b,c".split(",")    # ["a", "b", "c"]
"-".join(["a", "b"])   # "a-b"
```

## Slicing
```python
text = "Python"
text[0]      # "P"
text[-1]     # "n"
text[0:3]    # "Pyt"
```

## Try it
Build a greeting with an f-string using your name.
''',
  ),
  Lesson(
    id: 'lesson-conditionals',
    title: 'If / Elif / Else',
    minutes: 6,
    summary: 'Make decisions with comparisons and logic.',
    challengeId: 'challenge-conditionals',
    content: '''
# If / Elif / Else

Code can **choose** what to run:

```python
temperature = 30

if temperature > 25:
    print("It's warm!")
elif temperature > 15:
    print("It's mild.")
else:
    print("It's cold.")
```

## Comparisons
`==` equal, `!=` not equal, `<` `>` `<=` `>=`

## Combining conditions
```python
age = 20
has_ticket = True
if age >= 18 and has_ticket:
    print("You may enter")
```

## Indentation matters
The 4 spaces after `if ...:` are **required** — they mark what belongs
inside the branch.
''',
  ),
  Lesson(
    id: 'lesson-loops',
    title: 'Loops',
    minutes: 8,
    summary: 'Repeat work with for and while.',
    challengeId: 'challenge-loops',
    content: '''
# Loops

## for loops — over a sequence
```python
for i in range(5):        # 0 1 2 3 4
    print(i)

for name in ["Ada", "Alan"]:
    print(name)
```

## while loops — while a condition holds
```python
count = 0
while count < 3:
    print(count)
    count += 1
```

## break and continue
```python
for i in range(100):
    if i == 5:
        break        # stop the loop
    if i % 2 == 0:
        continue     # skip to next iteration
    print(i)
```

## Looping with index and value
```python
for i, name in enumerate(["Ada", "Alan"]):
    print(i, name)
```
''',
  ),
  Lesson(
    id: 'lesson-functions',
    title: 'Functions',
    minutes: 9,
    summary: 'Package logic into reusable, named blocks.',
    challengeId: 'challenge-functions',
    content: '''
# Functions

Functions let you reuse logic:

```python
def greet(name):
    """Return a greeting for the given name."""
    return f"Hello, {name}!"

print(greet("Ada"))      # Hello, Ada!
```

## Parameters with defaults
```python
def power(base, exponent=2):
    return base ** exponent

power(3)       # 9
power(3, 3)     # 27
```

## Returning multiple values
```python
def min_max(numbers):
    return min(numbers), max(numbers)

low, high = min_max([3, 1, 4, 1, 5])
```

## Why functions?
- Name your ideas (readability)
- Reuse instead of copy-paste
- Test one thing at a time
''',
  ),
  Lesson(
    id: 'lesson-lists-dicts',
    title: 'Lists & Dictionaries',
    minutes: 8,
    summary: 'Collections: many values in one name.',
    challengeId: 'challenge-lists',
    content: '''
# Lists & Dictionaries

## Lists — ordered collections
```python
scores = [90, 85, 77]

scores[0]        # 90 (first)
scores[-1]       # 77 (last)
scores.append(100)
len(scores)      # 4
sorted(scores)   # [77, 85, 90, 100]
```

## Dictionaries — key → value
```python
person = {"name": "Ada", "age": 36}

person["name"]          # "Ada"
person["job"] = "engineer"
for key, value in person.items():
    print(key, "=", value)
```

## List comprehensions — transform lists
```python
squares = [x * x for x in range(5)]        # [0, 1, 4, 9, 16]
evens = [x for x in range(10) if x % 2 == 0]
```
''',
  ),
];

const List<Challenge> kChallenges = <Challenge>[
  Challenge(
    id: 'challenge-variables',
    title: 'Two variables',
    description: 'Create a variable `city` set to "Amsterdam" and a variable '
        '`year` set to 2026, then print them.',
    starterCode: '# Create city and year, then print them\n',
    testCode: '''
def test_variables_exist():
    assert "city" in globals(), "Create a variable named city"
    assert "year" in globals(), "Create a variable named year"

def test_values():
    assert city == "Amsterdam", "city should be the string Amsterdam"
    assert year == 2026, "year should be 2026"
''',
    hint: 'city = "Amsterdam" and year = 2026',
  ),
  Challenge(
    id: 'challenge-strings',
    title: 'Greeting builder',
    description: 'Write a function `greet(name)` that returns the string '
        '"Hello, NAME!" where NAME is the given name (e.g. '
        'greet("Ada") returns "Hello, Ada!").',
    starterCode: 'def greet(name):\n    # your code here\n',
    testCode: '''
def test_greet():
    assert greet("Ada") == "Hello, Ada!"

def test_greet_other():
    assert greet("Linus") == "Hello, Linus!"
''',
    hint: 'return f"Hello, {name}!"',
  ),
  Challenge(
    id: 'challenge-conditionals',
    title: 'Sign of a number',
    description: 'Write a function `sign(n)` that returns "positive", '
        '"negative" or "zero" depending on the number.',
    starterCode: 'def sign(n):\n    # your code here\n',
    testCode: '''
def test_positive():
    assert sign(10) == "positive"

def test_negative():
    assert sign(-3) == "negative"

def test_zero():
    assert sign(0) == "zero"
''',
    hint: 'Use if / elif / else',
  ),
  Challenge(
    id: 'challenge-loops',
    title: 'Sum of squares',
    description: 'Write a function `sum_of_squares(n)` that returns the sum '
        'of the squares of all numbers from 1 to n. '
        'sum_of_squares(3) should be 1 + 4 + 9 = 14.',
    starterCode: 'def sum_of_squares(n):\n    total = 0\n    # your code here\n',
    testCode: '''
def test_small():
    assert sum_of_squares(3) == 14

def test_one():
    assert sum_of_squares(1) == 1

def test_ten():
    assert sum_of_squares(10) == 385
''',
    hint: 'for i in range(1, n + 1): total += i * i',
  ),
  Challenge(
    id: 'challenge-functions',
    title: 'Temperature convert',
    description: 'Write a function `to_fahrenheit(celsius)` that converts '
        'Celsius to Fahrenheit. Formula: c * 9 / 5 + 32.',
    starterCode: 'def to_fahrenheit(celsius):\n    # your code here\n',
    testCode: '''
def test_boiling():
    assert to_fahrenheit(100) == 212

def test_freezing():
    assert to_fahrenheit(0) == 32

def test_body_temp():
    assert abs(to_fahrenheit(37) - 98.6) < 0.01
''',
    hint: 'return celsius * 9 / 5 + 32',
  ),
  Challenge(
    id: 'challenge-lists',
    title: 'Word lengths',
    description: 'Write a function `word_lengths(sentence)` that returns a '
        'list with the length of each word in the sentence.',
    starterCode: 'def word_lengths(sentence):\n    # your code here\n',
    testCode: '''
def test_basic():
    assert word_lengths("hello world") == [5, 5]

def test_single():
    assert word_lengths("python") == [6]

def test_empty():
    assert word_lengths("") == []
''',
    hint: '[len(word) for word in sentence.split()]',
  ),
];

const List<CheatSheet> kCheatSheets = <CheatSheet>[
  CheatSheet(
    title: 'Strings',
    rows: [
      ['f"{name}"', 'format a string'],
      ['s.upper() / s.lower()', 'change case'],
      ['s.strip()', 'trim whitespace'],
      ['s.split(",")', 'string → list'],
      ['"-".join(list)', 'list → string'],
      ['s[0] / s[-1] / s[0:3]', 'index / slice'],
      ['len(s)', 'length'],
      ['"a" in s', 'contains'],
    ],
  ),
  CheatSheet(
    title: 'Lists',
    rows: [
      ['items.append(x)', 'add to end'],
      ['items[0] / items[-1]', 'first / last'],
      ['items[1:3]', 'slice'],
      ['len(items)', 'length'],
      ['sorted(items)', 'sorted copy'],
      ['sum(items)', 'sum of numbers'],
      ['[x * 2 for x in items]', 'transform (comprehension)'],
      ['[x for x in items if x > 0]', 'filter'],
    ],
  ),
  CheatSheet(
    title: 'Dictionaries',
    rows: [
      ['d["key"]', 'read value'],
      ['d["key"] = value', 'write value'],
      ['"key" in d', 'key exists'],
      ['d.get("key", default)', 'safe read'],
      ['d.keys() / d.values()', 'all keys / values'],
      ['d.items()', '(key, value) pairs'],
      ['for k, v in d.items():', 'iterate pairs'],
    ],
  ),
  CheatSheet(
    title: 'Control flow',
    rows: [
      ['if / elif / else', 'decisions'],
      ['for x in items:', 'iterate'],
      ['for i in range(10):', 'count 0..9'],
      ['while condition:', 'loop while true'],
      ['break / continue', 'exit / skip iteration'],
      ['try: ... except ValueError:', 'handle errors'],
      ['def name(args):', 'define function'],
      ['return value', 'give back a result'],
    ],
  ),
  CheatSheet(
    title: 'Common errors',
    rows: [
      ['SyntaxError', 'the code cannot be parsed (often a missing :)'],
      ['IndentationError', 'wrong number of spaces'],
      ['NameError', 'using a name that does not exist (typo?)'],
      ['TypeError', 'mixing wrong types, e.g. "a" + 1'],
      ['IndexError', 'list index out of range'],
      ['KeyError', 'dictionary key does not exist'],
      ['ValueError', 'right type, wrong value, e.g. int("abc")'],
    ],
  ),
];
