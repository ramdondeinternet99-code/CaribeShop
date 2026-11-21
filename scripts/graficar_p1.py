#!/usr/bin/env python3
"""Grafico alineado en el tiempo: usuarios/instancias, RPS reales y p95 (P1.3).

Entrada: el CSV *_stats_history.csv que genera Locust con --csv-full-history.
Las instancias activas se deducen de las filas BACKEND <instancia> (una instancia cuenta
como activa en un instante si su contador de peticiones crecio). Es una vista desde el
cliente: completela con el historial de ejecucion del autoscale (portal) o la consulta KQL
AutoscaleScaleActions, que muestran cuando Azure decidio escalar.

Uso:
  python3 scripts/graficar_p1.py evidencias/p1/escalonada_stats_history.csv [salida.png]
Requiere matplotlib (pip install matplotlib).
"""
import csv
import sys
from collections import defaultdict
from datetime import datetime


def leer(ruta):
    with open(ruta, newline="") as fh:
        return list(csv.DictReader(fh))


def num(valor):
    try:
        return float(valor)
    except (TypeError, ValueError):
        return None


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    ruta = sys.argv[1]
    salida = sys.argv[2] if len(sys.argv) > 2 else ruta.replace(".csv", ".png")
    filas = leer(ruta)
    if not filas:
        sys.exit("CSV vacio")

    t0 = min(int(f["Timestamp"]) for f in filas)
    por_t = defaultdict(lambda: {"rps": 0.0, "p95": None, "users": 0, "backends": {}})
    for f in filas:
        t = (int(f["Timestamp"]) - t0) / 60.0  # minutos desde el inicio
        d = por_t[t]
        if f["Type"] == "BACKEND":
            d["backends"][f["Name"]] = num(f.get("Total Request Count")) or 0
        elif f["Name"] in ("/work", "/api/info"):
            d["rps"] += num(f.get("Requests/s")) or 0.0
            if f["Name"] == "/work":
                d["p95"] = num(f.get("95%"))
        if f["Name"] == "Aggregated":
            d["users"] = int(num(f.get("User Count")) or 0)

    tiempos = sorted(por_t)
    previo, activos = {}, []
    for t in tiempos:
        actuales = por_t[t]["backends"]
        activas = {n for n, c in actuales.items() if c > previo.get(n, 0)}
        previo.update(actuales)
        activos.append(len(activas))
    # suavizado (ventana de 5 muestras) para no contar una instancia como caida por un tick vacio
    suave = [max(activos[max(0, i - 4): i + 1]) for i in range(len(activos))]

    print("Resumen (desde el cliente):")
    print(f"  RPS maximo (/work + /api/info): {max(por_t[t]['rps'] for t in tiempos):.1f}")
    p95s = [por_t[t]["p95"] for t in tiempos if por_t[t]["p95"] is not None]
    if p95s:
        print(f"  p95 de /work: min {min(p95s):.0f} ms | max {max(p95s):.0f} ms")
    prev = 0
    for t, n in zip(tiempos, suave):
        if n != prev:
            print(f"  minuto {t:5.1f}: instancias atendiendo = {n}")
            prev = n

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        sys.exit("Instale matplotlib para generar el grafico")

    fig, ax = plt.subplots(3, 1, figsize=(10, 8), sharex=True)
    ax[0].step(tiempos, suave, where="post", color="tab:blue", label="instancias atendiendo")
    ax[0].set_ylabel("instancias")
    ax2 = ax[0].twinx()
    ax2.plot(tiempos, [por_t[t]["users"] for t in tiempos], color="tab:gray", alpha=.6, label="usuarios Locust")
    ax2.set_ylabel("usuarios")
    ax[0].set_title("Escalamiento: instancias, RPS y p95 alineados en el tiempo")
    ax[1].plot(tiempos, [por_t[t]["rps"] for t in tiempos], color="tab:green")
    ax[1].set_ylabel("RPS (/work + /api/info)")
    ax[2].plot(tiempos, [por_t[t]["p95"] if por_t[t]["p95"] is not None else float("nan") for t in tiempos], color="tab:red")
    ax[2].set_ylabel("p95 /work (ms)")
    ax[2].set_xlabel("minutos desde el inicio de la prueba")
    for a in ax:
        a.grid(alpha=.3)
    fig.tight_layout()
    fig.savefig(salida, dpi=150)
    print("Grafico:", salida, "(generado", datetime.now().strftime("%H:%M:%S") + ")")


if __name__ == "__main__":
    main()
