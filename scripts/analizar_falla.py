#!/usr/bin/env python3
"""Analiza el CSV de monitor.py alrededor de una falla.

Ejemplos:
  # Falla logica: t0 sale de la salida de Run Command (hora de la instancia)
  python3 scripts/analizar_falla.py evidencias/p2/monitor_logica.csv \
      --t0-file evidencias/p2/t0_logica.txt --instancia _1 --ventana 120

  # Falla abrupta: t0 es el epoch local guardado por falla_abrupta.sh
  python3 scripts/analizar_falla.py evidencias/p2/monitor_abrupta.csv \
      --t0-file evidencias/p2/t0_abrupta.txt --ventana 300

Sin --instancia solo calcula errores; con --instancia (subcadena del nombre,
p. ej. _1) calcula cuanto tarda en dejar de recibir trafico.
Si matplotlib esta instalado, guarda un grafico PNG junto al CSV.
"""
import argparse
import csv
import re


def leer_t0(ruta):
    texto = open(ruta).read()
    m = re.search(r"\b(\d{10})(?:\.\d+)?\b", texto)
    if not m:
        raise SystemExit(f"No encontre un epoch en {ruta}")
    return float(m.group(1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--t0-file", required=True)
    ap.add_argument("--ventana", type=float, default=120, help="segundos despues de t0")
    ap.add_argument("--instancia", default="", help="subcadena del nombre de la instancia afectada")
    a = ap.parse_args()

    t0 = leer_t0(a.t0_file)
    filas = []
    with open(a.csv) as fh:
        for r in csv.DictReader(fh):
            filas.append((float(r["epoch"]), int(r["codigo"]), r["instancia"]))

    ventana = [f for f in filas if t0 <= f[0] <= t0 + a.ventana]
    errores = [f for f in ventana if f[1] != 200]
    print(f"Peticiones en la ventana [{a.ventana:.0f}s]: {len(ventana)}")
    print(f"Errores (codigo != 200): {len(errores)}")
    if ventana:
        print(f"% de error en la ventana: {100 * len(errores) / len(ventana):.2f} %")
    if errores:
        print(f"Primer error: t0+{errores[0][0] - t0:.1f}s | ultimo error: t0+{errores[-1][0] - t0:.1f}s")
        print(f"Duracion de la ventana con errores: {errores[-1][0] - errores[0][0]:.1f}s")

    if a.instancia:
        pasado = [f for f in filas if f[0] >= t0 and a.instancia in f[2]]
        if pasado:
            print(f"Ultima respuesta de '{a.instancia}' tras t0: t0+{pasado[-1][0] - t0:.1f}s "
                  "(tiempo hasta dejar de recibir trafico)")
        else:
            print(f"'{a.instancia}' no respondio nada despues de t0")

    cuentas = {}
    for f in ventana:
        cuentas[f[2] or "(error)"] = cuentas.get(f[2] or "(error)", 0) + 1
    print("Respuestas por instancia en la ventana:", cuentas)

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("(instale matplotlib para generar el grafico)")
        return
    xs = [f[0] - t0 for f in filas if t0 - 30 <= f[0] <= t0 + a.ventana]
    ys = [0 if f[1] == 200 else 1 for f in filas if t0 - 30 <= f[0] <= t0 + a.ventana]
    plt.figure(figsize=(9, 3))
    plt.scatter(xs, ys, s=6, c=["tab:red" if y else "tab:green" for y in ys])
    plt.axvline(0, color="k", linestyle="--", label="falla (t0)")
    plt.yticks([0, 1], ["OK", "Error"])
    plt.xlabel("segundos desde la falla")
    plt.title("Peticiones durante la ventana de falla")
    plt.legend()
    plt.tight_layout()
    salida = a.csv.replace(".csv", ".png")
    plt.savefig(salida, dpi=150)
    print("Grafico:", salida)


if __name__ == "__main__":
    main()
