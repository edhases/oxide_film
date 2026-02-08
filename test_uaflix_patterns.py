#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Test UAFlix URL patterns from repository"""

import requests
from bs4 import BeautifulSoup
import sys

if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

headers = {'User-Agent': 'Mozilla/5.0'}
base_url = 'https://uafix.net'

# Repository pattern: $baseUrl/$id/
# where id is like "46098-dolina-posmishok-svyatiy-hlopchik-dyvitys-onlayn"

test_ids = [
    '46098-dolina-posmishok-svyatiy-hlopchik-dyvitys-onlayn',
    'films/uafilms_2026',
    'film',
]

print("Testing UAFlix URL patterns...\n")

for test_id in test_ids:
    url = f"{base_url}/{test_id}/"
    print(f"Testing: {url}")
    
    try:
        r = requests.get(url, headers=headers, timeout=10)
        print(f"  Status: {r.status_code}")
        
        if r.status_code == 200:
            soup = BeautifulSoup(r.text, 'html.parser')
            
            # Check for title
            title = soup.find('h1')
            if title:
                print(f"  Title: {title.text.strip()[:60]}")
            
            # Check page size
            print(f"  Page size: {len(r.text)} bytes")
            print(f"  ✓ WORKING!")
            
            # This could be used for analyzer
            print(f"\n  👆 USE THIS URL: {url}\n")
            break
        else:
            print(f"  ✗ Not found")
    except Exception as e:
        print(f"  ✗ Error: {e}")
    
    print()
