import requests
import re
import base64
import json
import time
from bs4 import BeautifulSoup

class HDRezkaAnalyzer:
    def __init__(self):
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'X-Requested-With': 'XMLHttpRequest',
        }
        self.mirrors = [
            'https://hdrezka-home.tv',
            'https://rezka.ag',
            'https://hdrezka.ag',
            'https://hdrezka.me',
            'https://hdrezka.co',
            'https://hdrezka.sh',
        ]
        self.active_mirror = None

    def find_working_mirror(self):
        print("Finding working mirror...")
        for mirror in self.mirrors:
            try:
                print(f"Checking {mirror}...")
                response = requests.get(mirror, headers=self.headers, timeout=5)
                if response.status_code == 200:
                    print(f"Found working mirror: {mirror}")
                    self.active_mirror = mirror
                    return
            except Exception as e:
                print(f"Error checking {mirror}: {e}")
        raise Exception("No working mirror found")

    def search(self, query):
        if not self.active_mirror:
            self.find_working_mirror()
        
        url = f"{self.active_mirror}/engine/ajax/search.php"
        data = {'q': query}
        print(f"Searching for '{query}' at {url}...")
        
        response = requests.post(url, data=data, headers=self.headers)
        print(f"Response status: {response.status_code}")
        # print(response.text[:500]) # Debug
        
        soup = BeautifulSoup(response.content, 'html.parser')
        results = []
        
        for item in soup.find_all('div', class_='b-content__inline_item'):
            link = item.find('a')
            if not link:
                continue
            
            title = link.text.strip()
            href = link['href']
            results.append({'title': title, 'url': href})
            
        print(f"Found {len(results)} results")
        
        if not results:
             print("Search returned no results. Trying to get popular movies from main page...")
             main_resp = requests.get(f"{self.active_mirror}/films/", headers=self.headers)
             if main_resp.status_code == 200:
                 main_soup = BeautifulSoup(main_resp.content, 'html.parser')
                 for item in main_soup.find_all('div', class_='b-content__inline_item'):
                    link = item.find('a')
                    if not link: continue
                    title = link.text.strip()
                    href = link['href']
                    results.append({'title': title, 'url': href})
                    if len(results) >= 5: break
                 print(f"Found {len(results)} popular movies")
        
        return results

    def get_stream_data(self, url):
        print(f"Fetching streams from {url}...")
        response = requests.get(url, headers=self.headers)
        if response.status_code != 200:
            print(f"Failed to fetch page: {response.status_code}")
            return None

        # Extract IDs for extraction
        html = response.text
        soup = BeautifulSoup(html, 'html.parser')
        
        mw_id = None
        translator_id = None
        
        # Try to find initCDNMoviesEvents(id, translator_id)
        init_match = re.search(r'initCDN(?:Movies|Series)Events\s*\(\s*(\d+)\s*,\s*(\d+)', html)
        if init_match:
            mw_id = init_match.group(1)
            translator_id = init_match.group(2)
        else:
             sof_match = re.search(r'sof\.tv\.initCDN\w+Events\s*\(\s*(\d+)\s*,\s*(\d+)', html)
             if sof_match:
                 mw_id = sof_match.group(1)
                 translator_id = sof_match.group(2)
        
        if not mw_id:
            # Fallback: look for data-id in player div
            player_div = soup.find('div', id='cdnplayer')
            if not player_div:
                player_div = soup.find('div', class_='b-player')
            
            if player_div:
                 mw_id = player_div.get('data-id')
                 translator_id = player_div.get('data-translator_id')

        if not mw_id:
            print("Could not find data_id")
            return None
            
        if not translator_id:
            # Try to find first translator
             translator_item = soup.find('li', class_='b-translator__item')
             if translator_item:
                 translator_id = translator_item.get('data-translator_id')
        
        if not translator_id:
            translator_id = '238' # Default
            
        print(f"ID: {mw_id}, Translator: {translator_id}")
        
        is_movie = '/films/' in url
        action = 'get_movie' if is_movie else 'get_episodes'
        
        # If it's a series, we need season/episode. For simplicity, let's assume movie for now or just fetch valid stream for movie
        # If it is a series, get_episodes returns a list of episodes, not stream URL directly usually?
        # Actually get_cdn_series with action 'get_stream' is for episodes.
        
        if is_movie:
            return self.fetch_stream(mw_id, translator_id, 'get_movie')
        else:
            print("Series explicit analysis not fully implemented in this script (needs season/ep), trying as movie just in case or assuming first ep")
            # For series, we normally need season/episode.
            # But let's try to get stream for first episode if possible?
            return None

    def fetch_stream(self, data_id, translator_id, action):
        url = f"{self.active_mirror}/ajax/get_cdn_series/"
        data = {
            'id': data_id,
            'translator_id': translator_id,
            'action': action
        }
        
        print(f"Posting to {url} with {data}")
        response = requests.post(url, data=data, headers=self.headers)
        
        if response.status_code != 200:
            print(f"Stream fetch failed: {response.status_code}")
            print(response.text)
            return None
            
        try:
            json_data = response.json()
            if json_data.get('success'):
                url_data = json_data.get('url')
                print(f"Raw URL Data: {url_data}")
                decoded = self.decode_stream_url(url_data)
                print(f"Decoded Data: {decoded}")
                return decoded
            else:
                print(f"API returned success=false: {json_data}")
        except Exception as e:
            print(f"Failed to parse JSON: {e}")
            print(response.text)
            return None

    def decode_stream_url(self, encoded):
        # Python implementation of decodeStreamUrl
        if not encoded: return ""
        
        decoded = encoded
        if encoded.startswith('#'):
            base64_part = encoded
            if len(encoded) > 2 and encoded.startswith(('#h', '#0', '#1', '#2')):
                base64_part = encoded[2:]
            else:
                base64_part = encoded[1:]
            
            known_trash = [
                '//_//JCQhIUAkXiY=', '//_//QEBAQEAhIyM=', '//_//Xl5eIyo=', 
                '//_//JCQkISE=', '//IyMhQEBA', '//QCMjQEA=', 
                '//_//JCQhIUAkJEBeIUAjJCRA', '//_//QEBAQEAhIyMhXl5e', 
                '//_//Xl5eIUAjIyEhIyM=',
                '//_//QEBAQEAhIyMhXl5e', # NEW ONE
                '//_//IyMjI14hISMjIUBA', # Another potential one based on output
            ]
            
            for trash in known_trash:
                base64_part = base64_part.replace(trash, '')
                
            base64_part = re.sub(r'//[A-Za-z0-9+/]{1,25}=', '', base64_part)
            base64_part = base64_part.replace('//', '')
            base64_part = base64_part.replace('_', '')
            
            try:
                missing_padding = len(base64_part) % 4
                if missing_padding:
                    base64_part += '=' * (4 - missing_padding)
                decoded = base64.b64decode(base64_part).decode('utf-8')
            except Exception as e:
                print(f"Decoding failed: {e}")
                
        return decoded

    def parse_qualities(self, decoded_string):
        if not decoded_string: return []
        # pattern = RegExp(r'\[(\d+)p?\s*[^\]]*\]([^\[]+)');
        pattern = r'\[(\d+)p?\s*[^\]]*\]([^\[]+)'
        matches = re.findall(pattern, decoded_string)
        qualities = []
        for q, url in matches:
            # Handle .mp4 separation
            urls = url.split(' or ')
            final_url = urls[0].strip()
            qualities.append({'quality': q, 'url': final_url})
        return qualities

if __name__ == "__main__":
    analyzer = HDRezkaAnalyzer()
    try:
        # results = analyzer.search("Avatar")
        # Direct test for 1+1 which has Ukrainian dubbing
        # Use the mirror from user logs: hdrezka-home.tv
        results = [{'title': '1+1', 'url': 'https://hdrezka-home.tv/films/drama/289-11-2011.html'}]
        # Or search: results = analyzer.search("1+1")
        if results:
            target = results[0] # Pick first result
            print(f"Analyzing: {target['title']} ({target['url']})")
            
            # First, just get the ID and translators list
            print(f"Fetching page to extract ID and translators from {target['url']}...")
            analyzer.active_mirror = 'https://hdrezka-home.tv' # Ensure analyzer uses this mirror for requests
            response = requests.get(target['url'], headers=analyzer.headers)
            print(f"Page response status: {response.status_code}")
            
            if response.status_code == 200:
                soup = BeautifulSoup(response.text, 'html.parser')
                
                # Extract IDs
                mw_id = None
                translator_id = None
                
                # Try to find initCDNMoviesEvents(id, translator_id)
                init_match = re.search(r'initCDN(?:Movies|Series)Events\s*\(\s*(\d+)\s*,\s*(\d+)', response.text)
                if init_match:
                    mw_id = init_match.group(1)
                    translator_id = init_match.group(2)
                else:
                     sof_match = re.search(r'sof\.tv\.initCDN\w+Events\s*\(\s*(\d+)\s*,\s*(\d+)', response.text)
                     if sof_match:
                         mw_id = sof_match.group(1)
                         translator_id = sof_match.group(2)
                
                if not mw_id:
                    player_div = soup.find('div', id='cdnplayer')
                    if not player_div:
                        player_div = soup.find('div', class_='b-player')
                    
                    if player_div:
                         mw_id = player_div.get('data-id')
                         translator_id = player_div.get('data-translator_id')

                print(f"ID: {mw_id}, Default Translator: {translator_id}")

                # Find all translators
                translators = []
                translators_list = soup.find('ul', id='translators-list')
                if translators_list:
                    for li in translators_list.find_all('li'):
                        tid = li.get('data-translator_id')
                        tname = li.text.strip()
                        if tid:
                            translators.append({'id': tid, 'name': tname})
                            if li.get('class') and 'active' in li.get('class'):
                                print(f"Active translator: {tname} ({tid})")
                
                print(f"\nFound {len(translators)} translators:")
                for t in translators:
                    print(f" - {t['name']} (ID: {t['id']})")
                
                if not translators and translator_id:
                     print(f" - Default/Single Translator (ID: {translator_id})")
                     translators.append({'id': translator_id, 'name': 'Default'})

                filtered_translators = [t for t in translators if t['id'] in ['358']]
                print(f"Filtering to check only IDs 358 (Ukr). Found {len(filtered_translators)} matching.")
                
                print("\n=== STREAM URL COMPARISON ===")
                stream_urls = {}
                for t in filtered_translators:
                    print(f"\nFetching stream for {t['name']} (ID: {t['id']})...")
                    is_movie = '/films/' in target['url']
                    decoded = analyzer.fetch_stream(mw_id, t['id'], 'get_movie' if is_movie else 'get_episodes')
                    if decoded:
                        qs = analyzer.parse_qualities(decoded)
                        print(f"  Found {len(qs)} qualities")
                        # Store the 1080p or best quality URL for comparison
                        best_q = qs[-1] if qs else None
                        if best_q:
                            stream_urls[t['name']] = best_q['url']
                            print(f"  Best URL ({best_q['quality']}p): {best_q['url']}")
                    else:
                        print("  No stream found")

                print("\n=== DUPLICATE CHECK ===")
                seen_urls = {}
                for name, url in stream_urls.items():
                    if url in seen_urls:
                        print(f"WARNING: {name} has SAME URL as {seen_urls[url]}!")
                    else:
                        seen_urls[url] = name
                        print(f"OK: {name} has unique URL")

    except Exception as e:
        print(f"Error: {e}")
