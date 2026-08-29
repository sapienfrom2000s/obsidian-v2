```python
import argparse
import re
from pathlib import Path

args = argparse.ArgumentParser(description="something")
args.add_argument('file', help='something')
argument = args.parse_args()

with open(Path(argument.file)) as f:
    content = f.read().lower()

reg = re.compile(r'error')
t = reg.findall(content)
print(t)
```