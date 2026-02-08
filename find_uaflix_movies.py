#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Find actual movie URLs on UAFlix (not categories)"""

import requests
from bs4 import BeautifulSoup
import re
import sys

if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

headers = {'User-Agent': 'Mozilla/5.0'}
base_url = 'https://uafix.net'

print("Searching for actual movie pages on UAFlix...\n")

# Strategy 1: Try from homepage
print("Strategy 1: Homepage")
try:
    r = requests.get(base_url, headers=headers, timeout=10)
    soup = BeautifulSoup(r.text, 'html.parser')
    
    # Look for movie cards - common patterns
    movie_links = []
    
    # Find all links and filter
    for link in soup.find_all('a', href=True):
        href = link.get('href', '')
        
        # Movie detail pages usually have pattern: /number-title.html or /number-title/
        if re.match(r'^/?\d+-[\w\-]+(?:\.html)?/?$', href):
            full_url = base_url + href if href.startswith('/') else href
            title = link.text.strip()[:60]
            
            if full_url not in [m[0] for m in movie_links]:
                movie_links.append((full_url, title))
    
    print(f"Found {len(movie_links)} potential movie URLs\n")
    
    # Test first 3
    for i, (url, title) in enumerate(movie_links[:3], 1):
        print(f"{i}. Testing: {url}")
        print(f"   Title: {title}")
        
        try:
            test_r = requests.get(url, headers=headers, timeout=5)
            print(f"   Status: {test_r.status_code}")
            
            if test_r.status_code == 200:
                # Check if it has PlayerJS (sign of movie page)
                if 'playerjs' in test_r.text.lower() or 'player' in test_r.text.lower():
                    print(f"   ✓ HAS PLAYER! This is a movie page!")
                    print(f"\n   👆 USE THIS: {url}\n")
                    break
                else:
                    print(f"   - No player found")
        except Exception as e:
            print(f"   ✗ Error: {e}")
        print()
        
except Exception as e:
    print(f"Error: {e}")

# Strategy 2: Try direct pattern
print("\nStrategy 2: Testing common URL patterns")
test_patterns = [
    f"{base_url}/12345-test-movie.html",
    f"{base_url}/1-test.html",
    f"{base_url}/films/1-test/",
]

for url in test_patterns:
    print(f"Testing: {url}")
    try:
        r = requests.head(url, headers=headers, timeout=5)
        print(f"  Status: {r.status_code}")
    except Exception as e:
        print(f"  Error: {e}")
