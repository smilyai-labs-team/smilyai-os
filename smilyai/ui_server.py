"""Independent static shell + same-origin API proxy; survives harness failure."""
import http.client
from http.server import ThreadingHTTPServer
from pathlib import Path
from .server import SmilyHandler

class UIHandler(SmilyHandler):
    shell_root = Path(__file__).resolve().parent.parent / "shell"
    def proxy(self):
        if not self.trusted():
            return self._json({"error": "Untrusted origin"}, 403)
        conn = http.client.HTTPConnection("127.0.0.1", 47811, timeout=18)
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 <= length <= 3_000_000 or self.headers.get("Transfer-Encoding"):
                return self._json({"error": "Invalid request size"}, 400)
            payload = self.rfile.read(length) if length else None
            headers = {"Host": "127.0.0.1:47811", "Content-Type": "application/json",
                       "X-SmilyAI-Session": self.headers.get("X-SmilyAI-Session", "")}
            conn.request(self.command, self.path, body=payload, headers=headers)
            response = conn.getresponse()
            self._send(response.read(4_000_000), "application/json", response.status)
        except Exception:
            self._json({"error": "System harness is reconnecting. Native shortcuts still work."}, 503)
        finally:
            conn.close()
    def do_GET(self):
        if self.path.startswith("/api/"):
            return self.proxy()
        if not self.trusted():
            return self._json({"error": "Untrusted origin"}, 403)
        from urllib.parse import urlparse
        return self._static(urlparse(self.path).path)
    def do_POST(self):
        return self.proxy()

def main():
    ThreadingHTTPServer(("127.0.0.1", 47810), UIHandler).serve_forever()

if __name__ == "__main__":
    main()
