#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Find valid test URLs for providers"""

import requests
from bs4 import BeautifulSoup
import sys

if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

headers = {'User-Agent': 'Mozilla/5.0'}

providers = {
    'UAFlix': 'https://uafix.net',
    'UaSerials': 'https://uaserials.com',
}

print("Finding valid test URLs...\n")

for name, base_url in providers.items():
    print(f"{name} ({base_url})")
    try:
        r = requests.get(base_url, headers=headers, timeout=10)
        if r.status_code == 200:
            soup = BeautifulSoup(r.text, 'html.parser')
            
            # Find first movie/series link
            links = soup.find_all('a', href=True)
            for link in links[:50]:
                href = link.get('href', '')
                # Look for content URLs
                if any(x in href for x in ['/films', '/serial', '/movie', '/', '-']) and href.startswith(('http', '/')):
                    if href.startswith('/'):
                        full_url = base_url + href
                    else:
                        full_url = href
                    
                    # Test if it's a detail page
                    if full_url != base_url and '.html' in full_url or any(c.isdigit() for c in href):
                        print(f"  Found: {full_url}")
                        break
        else:
            print(f"  Error: {r.status_code}")
    except Exception as e:
        print(f"  Error: {e}")
    print()
