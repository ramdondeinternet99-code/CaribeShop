#!/usr/bin/env python3
"""CaribeShop - app integrada (demo-escalamiento + demo-seguridad). Solo libreria estandar.

Endpoints:
  /               pagina HTML con instancia, zona y color (se recarga cada 3 s)
  /api/info       JSON con host, zona, tamano y uptime
  /work?ms=N      consume ~N ms de CPU REAL de un nucleo (trabajo calibrado, ver abajo)
  /health         sonda del balanceador: 200 si esta sana; 503 si existe
                  /var/run/app-unhealthy (falla logica, prueba P2.1)
  /secret-check   lee un secreto de Key Vault con la identidad administrada y devuelve
                  SOLO longitud y hash SHA-256 truncado (S3). Nunca el valor.

Todas las respuestas incluyen el encabezado X-Served-By con el nombre de la instancia.

Nota sobre /work: el bucle de la demo original espera hasta que pase un tiempo de
reloj, por lo que muchos hilos simultaneos terminan a la vez y la CPU nunca limita el
rendimiento. Aqui se mide cuantos hashes caben en 1 ms al arrancar (calibracion) y cada
peticion ejecuta un numero FIJO de hashes: el costo por peticion es constante, asi la
capacidad por instancia (RPS maximo) es real y medible (P1.1).
"""
import hashlib
import json
import os
import socket
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("APP_PORT", "80"))
KEY_VAULT_NAME = os.environ.get("KEY_VAULT_NAME", "")
SECRET_NAME = os.environ.get("SECRET_NAME", "app-db-password")
FLAG_UNHEALTHY = "/var/run/app-unhealthy"
HOST = socket.gethostname()
START = time.time()
COLORES = ["#0939D7", "#E4572E", "#17BEBB", "#76B041", "#FFC914", "#8E44AD", "#D7263D", "#2E86AB"]
COLOR = COLORES[int(hashlib.md5(HOST.encode()).hexdigest(), 16) % len(COLORES)]

IMDS = "http://169.254.169.254/metadata"
TOKEN_URL = (
    IMDS + "/identity/oauth2/token?api-version=2018-02-01"
    "&resource=https%3A%2F%2Fvault.azure.net"
)


def metadata():
    """Lee zona, nombre y tamano de la VM desde IMDS (169.254.169.254)."""
    try:
        req = urllib.request.Request(
            IMDS + "/instance/compute?api-version=2021-02-01",
            headers={"Metadata": "true"},
        )
        with urllib.request.urlopen(req, timeout=2) as r:
            d = json.load(r)
            return {"zona": d.get("zone") or "sin-zona", "vm": d.get("name"), "tamano": d.get("vmSize")}
    except Exception:  # noqa: BLE001 - la app debe arrancar aunque IMDS falle
        return {"zona": "local", "vm": HOST, "tamano": "n/a"}


META = metadata()


def info(extra=None):
    d = {"host": HOST, **META, "uptime_s": int(time.time() - START), "pid": os.getpid()}
    if extra:
        d.update(extra)
    return d


def _hashes(n, h=b"caribeshop"):
    for _ in range(n):
        h = hashlib.sha256(h).digest()
    return h


def calibrar():
    """Hashes por milisegundo en esta VM (se mide una vez al arrancar, ~300 ms)."""
    n, t0 = 20000, time.perf_counter()
    _hashes(n)
    return max(1.0, n / ((time.perf_counter() - t0) * 1000.0))


HASHES_POR_MS = calibrar()


def quemar_cpu(ms):
    """Trabajo CPU-bound FIJO: equivale a ~ms milisegundos de un nucleo libre."""
    n = int(ms * HASHES_POR_MS)
    _hashes(n)
    return n


def leer_huella_secreto():
    """Token por IMDS (identidad administrada) -> lectura del secreto -> solo la huella."""
    req = urllib.request.Request(TOKEN_URL, headers={"Metadata": "true"})
    with urllib.request.urlopen(req, timeout=5) as resp:
        token = json.load(resp)["access_token"]
    url = f"https://{KEY_VAULT_NAME}.vault.azure.net/secrets/{SECRET_NAME}?api-version=7.4"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=5) as resp:
        value = json.load(resp)["value"]
    return {
        "leido": True,
        "secreto": SECRET_NAME,
        "longitud": len(value),
        "sha256_8": hashlib.sha256(value.encode()).hexdigest()[:8],
    }


HTML = """<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>CaribeShop</title>
<meta http-equiv="refresh" content="3">
<style>body{{margin:0;font-family:Segoe UI,Arial,sans-serif;background:{color};color:#fff;
display:flex;align-items:center;justify-content:center;height:100vh}}
.c{{background:rgba(0,0,0,.25);padding:40px 60px;border-radius:16px;text-align:center}}
h1{{margin:0 0 8px;font-size:42px}}p{{margin:6px 0;font-size:20px}}</style></head>
<body><div class="c"><h1>CaribeShop &middot; {host}</h1><p>Zona de disponibilidad: <b>{zona}</b></p>
<p>Tama&ntilde;o: {tamano} &middot; Uptime: {uptime_s}s</p>
<p style="opacity:.8">La p&aacute;gina se recarga cada 3 s: observe cambiar la instancia</p></div></body></html>"""


class Handler(BaseHTTPRequestHandler):
    server_version = "CaribeShop/1.0"
    sys_version = ""

    def _send(self, code, body, ctype="application/json"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Served-By", HOST)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802
        url = urlparse(self.path)
        if url.path == "/health":
            if os.path.exists(FLAG_UNHEALTHY):
                return self._send(503, json.dumps({"status": "unhealthy", "host": HOST}))
            return self._send(200, json.dumps({"status": "ok", "host": HOST}))
        if url.path == "/api/info":
            return self._send(200, json.dumps(info()))
        if url.path == "/work":
            try:
                ms = max(1, min(int(parse_qs(url.query).get("ms", ["100"])[0]), 2000))
            except ValueError:
                ms = 100
            t0 = time.perf_counter()
            hashes = quemar_cpu(ms)
            real = round((time.perf_counter() - t0) * 1000, 1)
            return self._send(200, json.dumps(info({"ms_pedidos": ms, "ms_reales": real, "hashes": hashes})))
        if url.path == "/secret-check":
            try:
                return self._send(200, json.dumps(leer_huella_secreto()))
            except urllib.error.HTTPError as exc:
                return self._send(502, json.dumps({"leido": False, "error": f"HTTP {exc.code}"}))
            except Exception as exc:  # noqa: BLE001
                return self._send(502, json.dumps({"leido": False, "error": type(exc).__name__}))
        if url.path == "/":
            return self._send(200, HTML.format(color=COLOR, **info()), "text/html")
        return self._send(404, json.dumps({"error": "no encontrado"}))

    def log_message(self, fmt, *args):  # sin log por peticion (carga alta)
        pass


if __name__ == "__main__":
    ThreadingHTTPServer.daemon_threads = True
    print(f"Escuchando en :{PORT} como {HOST} ({HASHES_POR_MS:.0f} hashes/ms)", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
