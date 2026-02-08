#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Find specific movies from UAFlix categories"""

import requests
from bs4 import BeautifulSoup
import re
import sys

if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

headers = {'User-Agent': 'Mozilla/5.0'}
base_url = 'https://uafix.net'

categories = [
    '/film/',
    '/serials/',
    '/cartoons/',
    '/dorama/',
    '/anime/',
]

print("🔍 Searching for movies in UAFlix categories...\n")

for category in categories:
    url = base_url + category
    print(f"📂 Category: {url}")
    
    try:
        r = requests.get(url, headers=headers, timeout=10)
        
        if r.status_code != 200:
            print(f"  ✗ Status: {r.status_code}\n")
            continue
        
        soup = BeautifulSoup(r.text, 'html.parser')
        
        # Find movie links - various patterns
        movie_links = []
        
        # Pattern 1: Direct links with IDs
        for link in soup.find_all('a', href=True):
            href = link.get('href', '')
            
            # Should have number-title pattern
            if re.search(r'/\d+-[\w\-]+', href):
                full_url = base_url + href if href.startswith('/') else href
                title = link.get('title', link.text.strip())[:60]
                
                if full_url not in [m[0] for m in movie_links]:
                    movie_links.append((full_url, title))
        
        print(f"  Found {len(movie_links)} potential movies")
        
        # Test first one
        if movie_links:
            test_url, test_title = movie_links[0]
            print(f"  Testing: {test_title}")
            print(f"  URL: {test_url}")
            
            try:
                test_r = requests.get(test_url, headers=headers, timeout=5)
                print(f"  Status: {test_r.status_code}")
                
                if test_r.status_code == 200:
                    # Check for player
                    if 'playerjs' in test_r.text.lower() or 'video' in test_r.text.lower():
                        print(f"  ✅ HAS PLAYER - This is a movie page!")
                        print(f"\n  👆 USE THIS URL: {test_url}\n")
                        break  # Found working URL, stop
                    else:
                        print(f"  ⚠️ No player found")
            except Exception as e:
                print(f"  ✗ Error: {e}")
        
        print()
        
    except Exception as e:
        print(f"  ✗ Error: {e}\n")

print("\n✅ Search complete!")
