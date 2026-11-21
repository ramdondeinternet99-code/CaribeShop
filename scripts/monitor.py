#!/usr/bin/env python3
"""Sondea la tienda cada N segundos y guarda epoch, codigo HTTP e instancia.

Uso:  python3 scripts/monitor.py http://<IP_LB> evidencias/p2/monitor_logica.csv [intervalo_s]
Detener con Ctrl+C. Ejecutelo en paralelo a Locust (carga moderada) y a la falla.
"""
import csv
import sys
import time
import urllib.error
import urllib.request


def sondear(url):
    try:
        with urllib.request.urlopen(url, timeout=3) as resp:
            return resp.status, resp.headers.get("X-Instance", "")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.headers.get("X-Instance", "") if exc.headers else ""
    except Exception:  # timeout, conexion rechazada, etc.
        return 0, ""


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    base, salida = sys.argv[1].rstrip("/"), sys.argv[2]
    intervalo = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
    with open(salida, "w", newline="") as fh:
        escritor = csv.writer(fh)
        escritor.writerow(["epoch", "codigo", "instancia"])
        print(f"Sondeando {base}/ cada {intervalo}s -> {salida} (Ctrl+C para detener)")
        try:
            while True:
                t = time.time()
                codigo, instancia = sondear(base + "/")
                escritor.writerow([f"{t:.3f}", codigo, instancia])
                fh.flush()
                time.sleep(max(0, intervalo - (time.time() - t)))
        except KeyboardInterrupt:
            print("Detenido.")


if __name__ == "__main__":
    main()
