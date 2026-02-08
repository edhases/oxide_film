#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Check genres and rating on UAKino page"""

import requests
from bs4 import BeautifulSoup
import re
import sys

if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

headers = {'User-Agent': 'Mozilla/5.0'}
url = 'https://uakino.best/filmy/boevik/13087-zriv-2026.html'

print(f"Fetching: {url}\n")
r = requests.get(url, headers=headers)
soup = BeautifulSoup(r.text, 'html.parser')

# Search for genres in text
print("="*80)
print("SEARCHING FOR GENRES:")
print("="*80)

# Pattern 1
pattern = r'(?:Жанр|Genre)[:\s]+([^\n]+)'
matches = re.findall(pattern, r.text, re.I)
for m in matches[:3]:
    print(f"Pattern 1: {m.strip()}")

# Pattern 2 - in URLs
genre_links = soup.find_all('a', href=re.compile(r'/filmy/\w+/'))
print(f"\nGenre links found: {len(genre_links)}")
for link in genre_links[:5]:
    print(f"  {link.text.strip()}")

# Search for rating
print("\n" + "="*80)
print("SEARCHING FOR RATING:")
print("="*80)

# IMDb pattern
imdb_patterns = [
    r'IMDb[:\s]+([\d.]+)',
    r'imdb.*?([\d.]+)',
    r'kinopoisk.*?([\d.]+)',
]
for pattern in imdb_patterns:
    matches = re.findall(pattern, r.text, re.I)
    if matches:
        print(f"Pattern '{pattern}': {matches}")

# Search in all text
print("\nAll numbers with decimal:")
numbers = re.findall(r'\b(\d+\.\d+)\b', r.text)
unique_numbers = list(set(numbers))[:20]
print(unique_numbers)

print("\n" + "="*80)
