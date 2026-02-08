#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Analyze ALL providers structure"""

import requests
from bs4 import BeautifulSoup
import re
import sys

if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

headers = {'User-Agent': 'Mozilla/5.0'}

providers = {
    'UAKino': 'https://uakino.best/filmy/boevik/13087-zriv-2026.html',
    'Eneyida': 'https://eneyida.tv/2673-ochi-legenda-karpat.html',
    'UaSerials': 'https://uaserials.com/6454-linkoln-dlya-advokata.html',
}

for name, url in providers.items():
    print(f"\n{'='*80}")
    print(f"{name}: {url}")
    print('='*80)
    
    try:
        r = requests.get(url, headers=headers, timeout=15)
        if r.status_code != 200:
            print(f"Error: {r.status_code}")
            continue
            
        soup = BeautifulSoup(r.text, 'html.parser')
        
        # Find year
        print("\n📅 YEAR:")
        year_patterns = [
            r'(?:Рік|Год|Year)[:\s]+(\d{4})',
            r'(?:Год выпуска|Рік виходу)[:\s]+(\d{4})',
        ]
        for pattern in year_patterns:
            match = re.search(pattern, soup.text, re.I)
            if match:
                print(f"  Found: {match.group(1)} (pattern: {pattern})")
                break
        
        # Genres
        print("\n🎭 GENRES:")
        for selector in ['[class*="genre"]', '[class*="ganre"]', '.movie-genres']:
            els = soup.select(selector)
            for el in els[:2]:
                links = el.find_all('a')
                if links:
                    genres = [a.text.strip() for a in links]
                    print(f"  {selector}: {', '.join(genres[:3])}")
                    break
        
        # Countries
        print("\n🌍 COUNTRIES:")
        country_patterns = [
            r'(?:Країн|Стран|Country)[:\s]+([А-ЯЁA-Z][а-яёa-z\s,]+)',
        ]
        for pattern in country_patterns:
            match = re.search(pattern, soup.text)
            if match:
                print(f"  Found: {match.group(1)[:50]}")
                break
        
        # Rating
        print("\n⭐ RATING:")
        # IMDb
        imdb_patterns = [r'IMDb[:\s]+([\d.]+)', r'imdb.*?([\d.]+)']
        for pattern in imdb_patterns:
            match = re.search(pattern, soup.text, re.I)
            if match:
                print(f"  IMDb: {match.group(1)}")
                break
        
        # Kinopoisk
        kp_patterns = [r'(?:Кінопошук|Кинопоиск|KP)[:\s]+([\d.]+)']
        for pattern in kp_patterns:
            match = re.search(pattern, soup.text, re.I)
            if match:
                print(f"  Kinopoisk: {match.group(1)}")
                break
        
        # Director
        print("\n🎬 DIRECTOR:")
        director_patterns = [
            r'(?:Режисер|Режисс?ёр|Director)[:\s]+([А-ЯЁA-Z][а-яёa-z\s]+)',
        ]
        for pattern in director_patterns:
            match = re.search(pattern, soup.text)
            if match:
                print(f"  Found: {match.group(1)[:50]}")
                break
        
        # Actors
        print("\n🎭 ACTORS:")
        actor_patterns = [
            r'(?:Актор|Актёр|Actor)[ис]*[:\s]+([А-ЯЁA-Z][а-яёa-z\s,]+)',
        ]
        for pattern in actor_patterns:
            match = re.search(pattern, soup.text)
            if match:
                print(f"  Found: {match.group(1)[:80]}")
                break
                
    except Exception as e:
        print(f"Error: {e}")

print(f"\n{'='*80}\n")
