#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test UAFlix direct search"""

import requests
from bs4 import BeautifulSoup
import sys

if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

headers = {'User-Agent': 'Mozilla/5.0'}
base_url = 'https://uafix.net'

# Try popular page
print("Testing UAFlix popular page...")
url = f'{base_url}/?do=top&mode=now'

r = requests.get(url, headers=headers)
print(f"Status: {r.status_code}\n")

if r.status_code == 200:
    soup = BeautifulSoup(r.text, 'html.parser')
    
    # Find article elements (common for content cards)
    articles = soup.find_all('article')
    print(f"Found {len(articles)} articles")
    
    # Find divs with 'short' class (common in DLE)
    shorts = soup.find_all('div', class_='short')
    print(f"Found {len(shorts)} shorts")
    
    # Find all links
    links = soup.find_all('a', href=True)
    print(f"Found {len(links)} links total\n")
    
    # Filter for content links
    print("Analysing links...")
    for link in links[:20]:
        href = link.get('href', '')
        text = link.text.strip()[:40]
        
        if href and href.startswith(base_url) and any(c.isdigit() for c in href):
            print(f"  {text}")
            print(f"  → {href}")
            
            # Test it
            try:
                test = requests.head(href, headers=headers, timeout=5)
                if test.status_code == 200:
                    print(f"  ✓ WORKING! Use this!")
                    break
            except:
                pass
