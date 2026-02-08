import requests
import base64
import re
import json

class StreamComparator:
    def __init__(self):
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'X-Requested-With': 'XMLHttpRequest',
            # 'Referer': 'https://hdrezka-home.tv/', # Try without first, as per latest finding
        }
        self.mirror = 'https://hdrezka-home.tv'

    def decode_stream_url(self, encoded):
        if not encoded: return ""
        if encoded.startswith('#'):
            base64_part = encoded[2:] if encoded.startswith(('#h', '#0', '#1', '#2')) else encoded[1:]
            known_trash = [
                '//_//JCQhIUAkXiY=', '//_//QEBAQEAhIyM=', '//_//Xl5eIyo=', 
                '//_//JCQkISE=', '//IyMhQEBA', '//QCMjQEA=', 
                '//_//JCQhIUAkJEBeIUAjJCRA', '//_//QEBAQEAhIyMhXl5e', 
                '//_//Xl5eIUAjIyEhIyM=', '//_//QEBAQEAhIyMhXl5e',
                '//_//IyMjI14hISMjIUBA'
            ]
            for trash in known_trash:
                base64_part = base64_part.replace(trash, '')
            
            base64_part = re.sub(r'//[A-Za-z0-9+/]{1,25}=', '', base64_part)
            base64_part = base64_part.replace('//', '').replace('_', '')
            
            try:
                if len(base64_part) % 4: base64_part += '=' * (4 - len(base64_part) % 4)
                return base64.b64decode(base64_part).decode('utf-8')
            except: return encoded
        return encoded

    def get_stream(self, data_id, translator_id, name):
        url = f"{self.mirror}/ajax/get_cdn_series/"
        data = {'id': data_id, 'translator_id': translator_id, 'action': 'get_movie'}
        print(f"Fetching {name} (ID {translator_id})...")
        try:
            resp = requests.post(url, data=data, headers=self.headers)
            json_data = resp.json()
            if json_data.get('success'):
                decoded = self.decode_stream_url(json_data['url'])
                # Extract 1080p URL
                match = re.search(r'\[1080p\]([^,\[]+)', decoded)
                if match:
                     # Clean URL manually just in case
                     clean_url = match.group(1).split(' or ')[0].strip()
                     return clean_url
                else:
                    return f"No 1080p found. Raw: {decoded[:100]}..."
            else:
                return f"Error: {json_data}"
        except Exception as e:
            return f"Exception: {e}"

if __name__ == "__main__":
    comp = StreamComparator()
    # Movie 1+1, ID 289
    # Russian = 56
    # Ukrainian = 358
    
    url_ru = comp.get_stream('289', '56', 'Russian')
    url_ua = comp.get_stream('289', '358', 'Ukrainian')
    
    print(f"\nRussian URL   : {url_ru}")
    print(f"Ukrainian URL : {url_ua}")
    
    if url_ru == url_ua:
        print("\nCRITICAL: URLs are IDENTICAL!")
    else:
        print("\nSUCCESS: URLs are DIFFERENT.")
        
        def get_size(url):
             try:
                 clean_url = url.split(':hls')[0]
                 print(f"Checking size for: {clean_url[:50]}...")
                 headers = {
                     'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
                     'Referer': 'https://hdrezka-home.tv/',
                     'Origin': 'https://hdrezka-home.tv'
                 }
                 resp = requests.head(clean_url, headers=headers, allow_redirects=True)
                 print(f"Status: {resp.status_code}")
                 if resp.status_code == 200:
                     return int(resp.headers.get('Content-Length', 0))
                 return -1
             except Exception as e:
                 print(f"Error: {e}")
                 return -1

        size_ru = get_size(url_ru)
        size_ua = get_size(url_ua)
        
        print(f"\nSize RU: {size_ru / 1024 / 1024:.2f} MB")
        print(f"Size UA: {size_ua / 1024 / 1024:.2f} MB")
        
        if size_ru > 0 and size_ua > 0 and size_ru == size_ua:
             print("WARNING: Files have IDENTICAL size (Likely same content)!")
        elif size_ru > 0 and size_ua > 0:
             print("Files have DIFFERENT sizes (Content is different).")
        else:
             print("Could not verify sizes.")
