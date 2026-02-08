#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Find specific movie page on UAFlix"""

import requests
from bs4 import BeautifulSoup
import re
import sys

if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

headers = {'User-Agent': 'Mozilla/5.0'}

# Go to films category and find a movie
category_url = 'https://uafix.net/films/uafilms_2026/'

print(f"Fetching: {category_url}\n")
r = requests.get(category_url, headers=headers)

if r.status_code == 200:
    soup = BeautifulSoup(r.text, 'html.parser')
    
    # Find all links
    links = soup.find_all('a', href=True)
    
    movie_links = []
    for link in links:
        href = link.get('href', '')
        text = link.text.strip()
        
        # Look for movie detail pages (should have number-title pattern)
        if re.search(r'/\d+-[a-z\-]+', href, re.I):
            if 'http' not in href:
                full_url = 'https://uafix.net' + href
            else:
                full_url = href
            
            if full_url not in [m[0] for m in movie_links]:
                movie_links.append((full_url, text[:60]))
    
    print(f"Found {len(movie_links)} movie links\n")
    print("First 10:")
    for i, (url, title) in enumerate(movie_links[:10], 1):
        print(f"{i}. {title}")
        print(f"   {url}")
        
        # Test it
        try:
            test_r = requests.head(url, headers=headers, timeout=5)
            if test_r.status_code == 200:
                print(f"   ✓ {test_r.status_code} - WORKING!")
                if i == 1:
                    print(f"\n   👆 USE THIS URL FOR TESTING!")
                break
        except:
            print(f"   ✗ Failed")
else:
    print(f"Category page returned: {r.status_code}")
