"""Vercel serverless API for the Apotheosis web demo (the laptop server is server/server.py).

vercel.json rewrites /api/<route> and /live/api/<route> here as /api/index?route=<route>.
It reuses server/agents.py and server/insights.py: with OPENAI_API_KEY set in the Vercel project they use AI,
without it their built-in rules answer. Routes that need the laptop (live transcript, voices, card sync) say "offline".
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'server'))
import agents  # noqa: E402
import insights  # noqa: E402

KEY = os.environ.get('OPENAI_API_KEY') or None
MODEL = os.environ.get('OPENAI_MODEL', agents.MODEL_DEFAULT)


def post(url, data, headers):
    req = urllib.request.Request(url, data=data, headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=55) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except Exception as e:  # network trouble: let the caller fall back to rules
        return 599, json.dumps({'error': str(e)}).encode()


def route_of(path):
    q = urllib.parse.parse_qs(urllib.parse.urlsplit(path).query)
    r = (q.get('route') or [''])[0]
    return r.strip('/').split('?')[0]


class handler(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get('Content-Length') or 0)
        try:
            return json.loads(self.rfile.read(min(n, 400000)) or b'{}') if n else {}
        except ValueError:
            return {}

    def do_GET(self):
        r = route_of(self.path)
        if r == 'config':
            return self._json(200, {'deepgram': False, 'elevenlabs': False, 'stripe': False, 'openai': bool(KEY), 'host': 'vercel'})
        if r in ('state', 'actions') or r.startswith('state') or r.startswith('actions'):
            return self._json(200, {'state': None, 'actions': [], 'seq': 0})
        return self._json(503, {'error': 'Not available in the web demo (needs the laptop server).', 'offline': True})

    def do_POST(self):
        r = route_of(self.path)
        req = self._body()
        kw = dict(key=KEY, model=MODEL, post=post)
        try:
            if r == 'pip':
                out = agents.pip(str(req.get('said', '')), req.get('context') or {}, req.get('history') or [], **kw)
            elif r == 'ask':
                out = agents.ask(str(req.get('question', '')), req.get('facts') or {}, **kw)
            elif r == 'report':
                out = agents.report(req.get('facts') or {}, **kw)
            elif r == 'digest':
                out = agents.digest(req.get('facts') or {}, **kw)
            elif r == 'analyze':
                out = insights.analyze(str(req.get('transcript', '')), req.get('history') or [], **kw)
            elif r in ('state', 'actions') or r.startswith('state') or r.startswith('actions'):
                out = {'ok': True}
            else:
                return self._json(503, {'error': 'Not available in the web demo (needs the laptop server).', 'offline': True})
        except Exception as e:
            return self._json(500, {'error': str(e)})
        return self._json(200, out)

    def do_PUT(self):
        return self._json(200, {'ok': True})
