```python
import argparse
import httpx

args = argparse.ArgumentParser(description="Parse http endpoint")
args.add_argument('endpoint', help='Endpoint')
argument = args.parse_args()

endpoint = argument.endpoint

with httpx.Client(timeout=2) as client:
	response = client.get(endpoint)
	print(f'Status Code: {response.status_code}')
```