#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Check UAFlix accessibility and find valid URLs"""

import requests
from bs4 import BeautifulSoup
import sys

if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')

headers = {'User-Agent': 'Mozilla/5.0'}
base_url = 'https://uafix.net'

print(f"Testing UAFlix accessibility: {base_url}\n")

# Test 1: Can we access the homepage?
try:
    r = requests.get(base_url, headers=headers, timeout=10)
    print(f"✓ Homepage: {r.status_code}")
    
    if r.status_code == 200:
        soup = BeautifulSoup(r.text, 'html.parser')
        
        # Find movie links
        print("\n📽️ Looking for movie/content links...")
        
        # Strategy 1: Find links with digits (content IDs)
        all_links = soup.find_all('a', href=True)
        content_links = []
        
        for link in all_links[:100]:
            href = link.get('href', '')
            text = link.text.strip()
            
            # Look for content URLs (with numbers and ukrainian/english text)
            if href and any(c.isdigit() for c in href):
                # Skip navigation/footer links
                if any(skip in href.lower() for skip in ['page', 'user', 'login', 'search', 'tag']):
                    continue
                
                # Build full URL
                if href.startswith('/'):
                    full_url = base_url + href
                elif href.startswith('http'):
                    full_url = href
                else:
                    continue
                
                # Test if it exists
                if full_url not in [c[0] for c in content_links]:
                    content_links.append((full_url, text[:50]))
        
        print(f"\nFound {len(content_links)} potential content links\n")
        
        # Test first 5
        print("Testing first 5 links:")
        for url, title in content_links[:5]:
            try:
                test_r = requests.head(url, headers=headers, timeout=5, allow_redirects=True)
                status = "✓" if test_r.status_code == 200 else "✗"
                print(f"  {status} [{test_r.status_code}] {title}")
                print(f"      {url}")
                
                if test_r.status_code == 200:
                    print(f"      👆 WORKING URL!")
                    break
            except Exception as e:
                print(f"  ✗ Error: {e}")
    else:
        print(f"✗ Homepage not accessible: {r.status_code}")
        
except Exception as e:
    print(f"✗ Error accessing UAFlix: {e}")
