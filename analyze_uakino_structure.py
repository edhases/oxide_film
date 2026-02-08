#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Deep dive into UAKino structure to find ALL selectors"""

import requests
from bs4 import BeautifulSoup
import re
import sys

if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

headers = {'User-Agent': 'Mozilla/5.0'}
url = 'https://uakino.best/filmy/boevik/13087-zriv-2026.html'

print(f"Analyzing: {url}\n")
r = requests.get(url, headers=headers)
soup = BeautifulSoup(r.text, 'html.parser')

print("="*80)
print("СТРУКТУРА СТОРІНКИ")
print("="*80)

# Title
print("\n📌 TITLE:")
for tag in ['h1', 'h2', '.movie-title']:
    el = soup.select_one(tag) if '.' in tag else soup.find(tag)
    if el:
        print(f"  {tag}: {el.text.strip()[:80]}")

# Rating
print("\n⭐ RATING:")
for selector in ['.rating', '.imdb', 'span.current-rating', '[class*="rate"]', '[class*="imdb"]']:
    els = soup.select(selector)
    for el in els[:3]:
        text = el.text.strip()
        if text and (re.search(r'\d', text)):
            print(f"  {selector}: {text}")

# Info table
print("\n📋 INFO TABLE:")
tables = soup.find_all('table')
for i, table in enumerate(tables[:3]):
    print(f"\n  Table {i+1}:")
    rows = table.find_all('tr')
    for row in rows[:10]:
        cells = row.find_all(['td', 'th'])
        if len(cells) >= 2:
            label = cells[0].text.strip()
            value = cells[1].text.strip()[:50]
            print(f"    {label}: {value}")

# All divs with class containing 'info', 'detail', 'meta'
print("\n📝 INFO CONTAINERS:")
for pattern in ['info', 'detail', 'meta', 'movie']:
    divs = soup.find_all('div', class_=re.compile(pattern, re.I))
    for div in divs[:3]:
        classes = ' '.join(div.get('class', []))
        text = div.text.strip()[:60]
        if text:
            print(f"  .{classes}: {text}")

# Description
print("\n📖 DESCRIPTION:")
for selector in ['.description', '.synopsis', '.full-text', '.story', 'div[itemprop="description"]']:
    el = soup.select_one(selector)
    if el:
        print(f"  {selector}: {el.text.strip()[:80]}")

# Images
print("\n🖼️ IMAGES (first 5):")
for img in soup.find_all('img')[:5]:
    src = img.get('src', '')
    alt = img.get('alt', '')[:40]
    classes = ' '.join(img.get('class', []))
    print(f"  {classes or 'no-class'}: {src[:60]} (alt: {alt})")

print("\n" + "="*80)
