import requests
import re
import base64

class CookieTester:
    def __init__(self):
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'X-Requested-With': 'XMLHttpRequest',
        }
        self.mirror = 'https://hdrezka-home.tv'
        self.movie_url = f'{self.mirror}/films/comedy/289-1-1-2011.html' # 1+1
        self.id = '289'
        self.ua_translator_id = '358' # Ukrainian

    def decode(self, encoded):
        try:
            # Simple decoder for test
            if not encoded: return ""
            b64 = encoded
            if b64.startswith('#'):
                 b64 = b64[2:] if b64.startswith(('#h', '#0', '#1', '#2')) else b64[1:]
            
            # Trash removal (simplified)
            known_trash = ['//_//QEBAQEAhIyMhXl5e', '//_//JCQhIUAkXiY='] 
            for t in known_trash: b64 = b64.replace(t, '')
            
            b64 = re.sub(r'//[A-Za-z0-9+/]{1,25}=', '', b64).replace('//', '').replace('_', '')
            pad = len(b64) % 4
            if pad: b64 += '=' * (4 - pad)
            return base64.b64decode(b64).decode('utf-8')
        except: return "Decode Error"

    def test(self):
        print("=== TEST 1: NO COOKIES ===")
        # Direct POST without visiting page
        try:
            resp = requests.post(
                f'{self.mirror}/ajax/get_cdn_series/',
                data={'id': self.id, 'translator_id': self.ua_translator_id, 'action': 'get_movie'},
                headers=self.headers
            )
            print(f"Status: {resp.status_code}")
            json_data = resp.json()
            url_no_cookie = self.decode(json_data.get('url', ''))
            print(f"URL Sample: {url_no_cookie[-20:] if url_no_cookie else 'None'}")
        except Exception as e:
            print(f"Error: {e}")
            url_no_cookie = "Error"

        print("\n=== TEST 2: WITH COOKIES & CSRF ===")
        session = requests.Session()
        session.headers.update(self.headers)
        
        # 1. Visit Page to get Cookies and CSRF
        print("Visiting movie page...")
        page_resp = session.get(self.movie_url)
        
        # Extract CSRF (if any - older HDRezka might not need it for guests, but let's check)
        csrf = ''
        match = re.search(r'name="csrf-token" content="([^"]+)"', page_resp.text)
        # OR obscure meta tag
        if not match:
             # Try other regex from Dart code
             # meta name="csrf-token" content="..."
             pass
        
        # 2. POST with cookies
        try:
            resp = session.post(
                f'{self.mirror}/ajax/get_cdn_series/',
                data={'id': self.id, 'translator_id': self.ua_translator_id, 'action': 'get_movie'},
            )
            print(f"Status: {resp.status_code}")
            json_data = resp.json()
            url_with_cookie = self.decode(json_data.get('url', ''))
            print(f"URL Sample: {url_with_cookie[-20:] if url_with_cookie else 'None'}")
        except Exception as e:
            print(f"Error: {e}")
            url_with_cookie = "Error"

        print("\n=== CONCLUSION ===")
        if url_no_cookie == url_with_cookie:
            print("Cookies do NOT change the result.")
        else:
            print("Cookies CHANGED the result! Session is required.")

if __name__ == "__main__":
    CookieTester().test()
