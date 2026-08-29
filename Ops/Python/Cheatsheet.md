# Python Cheatsheet

## Operators

- Most operators are like other languages: `**`, `%`, `+`, etc.
- **`//` is integer division** (Python-specific).

```python
print("The following is integer division.", f"5 divided by 2 is \"{5//2}\"", sep="\n", end="\nHigh Five!!")
```

- `printf` is invalid → use `print(f"...")` for formatting.
- `sep=` separates arguments passed to `print`.
- `end=` triggered once, at the end of print.

**Augmented assignment** — "augmented" = made larger by adding to it; here we augment `=`:

```python
k = 4
k += 5  # instead of k = k + 5
```

**Replication** works on sequences:

```python
print("alpha " * 3)  # alpha alpha alpha
```

## Data Types

- Normal: `int`, `float`, `str`, `bool`, `list`, `dict`, `set`
- Extra: `NoneType`, `tuple`
- `NoneType` — like `nil` in Ruby: `k = None`
- **Tuple** — like a list, but fixed size + immutable → fast element access.

```python
t = (1, 2, 3)
# t[0] = 9  # TypeError! tuples are immutable
```

**Input** (blocking operation):

```python
# my_name = input('What is your name?\n')
# print(f'Hi, {my_name}')
```

## Truthiness (Pythonic checks)

```python
a = [1, 2, 3, 4]
b = '90'
c = ('something')

# Non-Pythonic
if len(a) > 0:
    print('a is Non Empty')

# Pythonic
if a:
    print('a is Non Empty')
```

## Typecasting

```python
str(99)      # '99'
int('55')    # 55
float(55)    # 55.0
bool('9')    # True
bool('')     # False
bool(0)      # False
bool('0')    # True (non-empty string!)
```

Converting between containers:

```python
list('bla')                     # ['b', 'l', 'a']
set(['1', '2', '3', '3'])       # {'1', '2', '3'} — dedupes
dict(name="Alice", age=25)      # {'name': 'Alice', 'age': 25}
tuple((3, 4, 5))                # (3, 4, 5)
# All 4 can be converted into one another in some situations
```

## Built-ins & Generators

```python
# range(start, stop, step)
for i in range(5, 10, 2):
    print(i)

abs(-490)  # 490
```

**Generator expression** — a one-line formula that generates a sequence of data on demand:
`(output for variable in iterable)`

```python
my_gen = (x * x for x in [1, 2, 3])
print(my_gen)        # iterator object
print(next(my_gen))  # 1

b = all(x * x for x in [0, 1, 2, 3])  # False
# any(...) — same idea, True if ANY match
```

## Conditionals

- `or` instead of `||`, `and` instead of `&&`, `not` instead of `!`.

```python
age = 19
if age > 18:
    print('can vote')
elif age < 9:
    pass
else:
    print('went to else condition')
```

**Ternary** (and chained):

```python
age = 9
print('kid' if age < 18 else 'adult')
print('teen' if age < 13 else 'kid' if age < 18 else 'adult')
```

**Switch case** (`match`):

```python
code = 200
match code:
    case 200 | 201:
        print('Status 200 or 201')
    case 204 | 205:
        pass
    case _:          # default case
        print('Went to default case')
```

## Loops

```python
num = 5
while num > 0:
    num -= 1
    print(num)
    if num == 2:
        break
    else:
        continue

for i in [77777, 8, 9, 2]:
    print(i)
```

## Functions

```python
def say_hi(name, greeting):
    print(f"{name}{greeting}")

say_hi(greeting="Hi", name="Buddy")  # keyword args, order doesn't matter

def sum(a, b):
    return a + b
```

**Lambdas:**

```python
pk = lambda x, y: x + y
print(pk(5, 9))  # 14
```

## Lists

```python
furniture = ['table', 'chair']
furniture[-1]     # 'chair'
# furniture[3]    # IndexError — will crash
furniture[0:1]    # ['table']
fur = furniture[:]  # slicing the complete list = copying
```

- `.append()` — add to list
- `len()` — length
- `.index()`, `.pop()`, `.sort()`
- list ↔ tuple interconvertible; remember one is mutable and the other isn't.

**enumerate** when you need the index; **zip** to pair (or more) sequences:

```python
for i, item in enumerate(furniture):
    print(f"{i} with {item}")

price = [10, 5]
for price, item in zip(price, furniture):  # n can be more than 2
    print(f"{price} for {item}")
```

**`in` / `not in`** → boolean:

```python
"bed" in furniture       # False
"chair" not in furniture # False
```

**Multi-assignment:**

```python
i, j = furniture  # i='table', j='chair'
```

## Dictionaries

```python
my_cat = {
    'size': 'fat',
    'color': 'gray',
    'disposition': 'loud',
}
my_cat['age'] = 2   # adding a key
my_cat.values()
my_cat.keys()
# .pop('key')    → deletes that key
# .popitem()     → deletes last key-value pair
```

**Merging with `**`:**

```python
dict_1 = {'a': 1, 'b': 2}
dict_2 = {'c': 3, 'd': 4}
merged_dict = {**dict_1, **dict_2}
```

## Sets

```python
s = {1, 2, 3}
t = set([1, 2, 3, 4])

# Unordered → s[0] throws an error
# Methods: .add, .remove, .discard
```

## Strings

Same indexing/slicing as lists:

```python
s = 'hello'
s[0]      # 'h'
s[:]      # copy
'h' in s  # True
```

Helpers: `.upper`, `.lower`, `.title`, `.islower`, `.startswith('world')`, `.endswith('world')`, `.join`, `.split`.

## Regex

```python
import re

phone_num_regex = re.compile(r'\d\d\d-\d\d\d-\d\d\d')
mo = phone_num_regex.search('My number is 980-345-234.')
print(mo.group(0))  # .group() = entire match (0 is reserved for it)
```

**Groups:**

```python
phone_num_regex = re.compile(r'(\d\d\d)-(\d\d\d)-(\d\d\d)')
mo = phone_num_regex.search('My number is 080-245-234.')
mo.group(0)    # entire match
mo.group(1)    # first group
mo.groups()    # tuple of all groups
```

**search vs findall** — `search` finds only the *first* match (returns match object); `findall` finds all (returns a list):

```python
hero_regex = re.compile(r'Batman|Tina Fey')
k = hero_regex.search('I am Batman and Tina Fey')
p = hero_regex.findall('I am Batman and Tina Fey')
```

**Pattern repetition:**

| Pattern | Meaning |
|---|---|
| `Hey\|Bla` | or |
| `(m)?` / `(wom)?` | optional — 0 or 1 of preceding group |
| `*` | 0 or more |
| `+` | 1 or more |
| `Ha{3}` | exactly 3; `{m, n}` range works too |

**Character classes:**

```python
vowel_regex = re.compile(r'[aeiouAEIOU]')   # match any single char from set
const_regex = re.compile(r'[^aeiouAEIOU]')  # ^ inside [] inverts the class
```

**Anchors:** `^` = start of string (`^` inside `[]` = inverse); `$` = end of string.

**Wildcards:** `.` matches any character; `.*` greedy; `.*?` non-greedy.

**Case-insensitive:** pass `re.I` as the second argument:

```python
robocop = re.compile(r'robocop', re.I)
```

## pathlib — Cross-Platform Paths

Handles Linux, Windows, etc.:

```python
from pathlib import Path

# both do the same thing
print(Path('usr').joinpath('bin'))
print(Path('usr') / 'bin')

print(Path.home())           # user's home directory
print(Path.cwd())            # current working directory
```

Combine home with filenames:

```python
my_files = ['accounts.txt', 'details.csv', 'invite.docx']
home = Path.home()
for filename in my_files:
    print(home / filename)
```

```python
import os.path
print(os.path.expanduser('~/Documents'))

# (cwd / 'alpha' / 'beta' / 'gamma').mkdir(parents=True)
Path('/').is_absolute()
Path('..').is_absolute()
Path('..').resolve()                       # absolute version of relative path
Path('/etc/passwd').relative_to('/')       # 'etc/passwd'
(Path('..') / 'bla').exists()
Path('bla').is_file()
Path('kla').is_dir()

for f in Path('.').iterdir():
    print(f)
```

## File Operations

**Copying / moving / deleting** (`shutil`):

```python
import shutil
# shutil.copy('path1/file', 'path2/file')
# shutil.copytree('dir1', 'dir2')
# shutil.move('path1', 'path2')
# Path.unlink()    → delete file
# Path.rmdir()     → delete folder (must be empty) — useless, lol
# shutil.rmtree()  → delete folder + everything inside
```

**Recursively walking a directory** (`rglob` takes a glob pattern like `*.png`):

```python
p = Path('.')
for i in p.rglob('*'):
    print(i)
```

**Reading:**

```python
with open(Path('.') / 'test.txt') as file:
    content = file.read()
print(content)
```

> [!note] Why does `content` still exist outside the `with` block?
> Blocks like `with`, `if`, `for`, `while`, or `try/except` do **not** create their own variable scope. Any variable defined inside a `with` block remains accessible throughout the entire enclosing function or module.

**Writing / appending:**

```python
with open(Path('.') / 'test.txt', 'w') as file:
    file.write('Hello')

with open(Path('.') / 'test.txt', 'a') as f:
    f.write('\nappending to hello')
```

**Line-by-line:**

```python
# readlines(): returns a list of strings, one per line
with open('test.txt') as sonnet_file:
    sonnet_file.readlines()

# Iterating the file object — memory efficient for large files
with open('test.txt') as sonnet_file:
    for line in sonnet_file:
        print(line, end='')  # no extra newline
```

## JSON

```python
import json

with open(Path('.') / 'bla.json', 'r') as f:
    content = json.load(f)   # file → object

with open(Path('bla_v2.json'), 'w') as file:
    json.dump(content, file) # object → file
```

## Exception Handling

```python
try:
    1 / 0
except ZeroDivisionError:
    print('You can not divide by 0')
finally:
    print('This will always run no matter what')
```

**Custom exceptions** — inherit from `Exception`; `pass` = empty body, just a distinctly named type:

```python
class MyCustomException(Exception):
    pass

try:
    raise MyCustomException
except MyCustomException:
    print('Caught custom exception')
```

## `*args` vs `**kwargs`

```python
# *args collects positional arguments into a tuple
def some_function(*args):
    print(f'Arguments passed: {args} as {type(args)}')

some_function('arg1', 'arg2', 'arg3')
# ('arg1', 'arg2', 'arg3') as <class 'tuple'>

# **kwargs collects keyword arguments into a dictionary
def some_function(**kwargs):
    print(f'keywords: {kwargs} as {type(kwargs)}')

some_function(key1='arg1', key2='arg2')
# {'key1': 'arg1', 'key2': 'arg2'} as <class 'dict'>
```

## Decorators

```python
def my_decorator(func):
    def wrapper():
        print("Before")
        func()
        print("After")
    return wrapper

@my_decorator
def say_hi():
    print("Hi!")

say_hi()
```

**What `@my_decorator` actually does:**

```text
@my_decorator
def say_hi(): ...   ---->   say_hi = my_decorator(say_hi)

- original say_hi  ---> passed in as `func`
- my_decorator returns `wrapper`
- say_hi (the name) ===> now points to `wrapper`
```

**Calling `say_hi()`:**

```text
say_hi()
  |
  v
actually runs wrapper()
  |
  +-- print("Before")
  +-- func() ----> runs ORIGINAL say_hi()
  |     |
  |     v
  |     print("Hi!")
  +-- print("After")
```

**Output:**

```text
Before
Hi!
After
```

## Related

- [[Ops/Python/Easy/Questions|Python practice questions]]
- [[Ops/Checklist|Ops Checklist]]
