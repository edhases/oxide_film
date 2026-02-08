import requests

url = "https://prx4-cogent.ukrtelcdn.net/8484cd993f51bf956f920dca5f9fbdc2:2026020811:RUtMcGJKRkVQV2Z5UDZUU0RGaDFOZzRjckVQdWFFc1dHMHc3ZTc2T0RYRzVLckhod1lxZlFORDlraTlpcE1EZk5kSWdsQkpucDNjN0RiQ3lJcm8yV1NoWGVBaHB5YjlPK3ZyUUd0dE5mdmM9/1/2/6/5/0/3/6/hymer.mp4"

headers_variations = [
    {
        "name": "No Headers",
        "headers": {}
    },
    {
        "name": "Referer Only",
        "headers": {
            "Referer": "https://hdrezka-home.tv/"
        }
    },
    {
        "name": "User-Agent Only",
        "headers": {
             "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        }
    },
    {
        "name": "Referer + User-Agent",
        "headers": {
            "Referer": "https://hdrezka-home.tv/",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        }
    },
     {
        "name": "Referer + Mobile UA",
        "headers": {
            "Referer": "https://hdrezka-home.tv/",
            "User-Agent": "Mozilla/5.0 (Linux; Android 10; SM-G960F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Mobile Safari/537.36"
        }
    },
     {
        "name": "Origin + Referer + UA",
        "headers": {
            "Origin": "https://hdrezka-home.tv",
            "Referer": "https://hdrezka-home.tv/",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
        }
    }
]

print(f"Testing connectivity to: {url[:50]}...")

for variation in headers_variations:
    print(f"\nTesting {variation['name']}...")
    try:
        # Use stream=True to avoid downloading the whole file, just check headers
        response = requests.get(url, headers=variation['headers'], stream=True, timeout=10)
        print(f"Status: {response.status_code}")
        if response.status_code == 200:
            print("SUCCESS! Stream is accessible.")
            response.close()
        else:
            print(f"Failed. Headers: {response.headers}")
    except Exception as e:
        print(f"Error: {e}")
