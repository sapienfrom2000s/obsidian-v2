```
import subprocess
import argparse

k = argparse.ArgumentParser(description="Lmaoooojj")
k.add_argument('command', help='lmao')
args = k.parse_args()

command = args.command.split(' ')

gym = subprocess.run(command, capture_output=True, text=True)
print(gym.stdout)
```