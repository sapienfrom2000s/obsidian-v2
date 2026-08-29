```python
import argparse
from pathlib import Path

args = argparse.ArgumentParser("Babab")
args.add_argument('file', help='Abba sandbox')
arguments = args.parse_args()

file_name = arguments.file

with open(Path(file_name)) as f:
    lines = f.readlines()

s = set()
for i in lines:
    if i in s:
        print("Nahhhhhhh This is already present in set")
    else:
        print("blablabla")
        s.add(i)
```
