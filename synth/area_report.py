#!/usr/bin/env python3
"""
area_report.py - Resume o 'stat -liberty' do Yosys e compara com um tile Tiny Tapeout.

Uso: python3 synth/area_report.py build/synth_sky130_stat.txt

Geometria SKY130 (tt-support-tools/tech/sky130A/tile_sizes.yaml):
  1x1 = 161.00 x 111.52 um   1x2 = 161.00 x 225.76 um
Margens do config.json do template (LibreLane): esquerda/direita 6 sites (0.46 um),
topo/fundo 1 linha (2.72 um). Densidade-alvo de colocacao: 60 %.
"""
import re
import sys

SITE_W, ROW_H = 0.46, 2.72
TILES = {"1x1": (161.00, 111.52), "1x2": (161.00, 225.76)}
TARGET_DENSITY = 0.60


def core_area(w, h):
    return (w - 2 * 6 * SITE_W) * (h - 2 * 1 * ROW_H)


def main(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    m = re.search(r"Chip area for (?:top )?module '?\\?(\S+?)'?:\s*([0-9.]+)", txt)
    if not m:
        sys.exit("Nao encontrei 'Chip area' em " + path)
    area = float(m.group(2))

    # Contagem de celulas: linhas "  <n>  [area]  sky130_fd_sc_hd__xxx"
    cells = {}
    for line in txt.splitlines():
        mm = re.match(r"\s+(\d+)\s+(?:[0-9.Ee+-]+\s+)?(sky130_fd_sc_hd__\S+)", line)
        if mm:
            cells[mm.group(2)] = cells.get(mm.group(2), 0) + int(mm.group(1))
    n_cells = sum(cells.values())
    n_ff = sum(n for c, n in cells.items() if re.search(r"__(df|dl|sdf|edf)", c))

    print("=" * 66)
    print(" Estimativa de area (pre-layout, sky130_fd_sc_hd, tt 25C 1.8V)")
    print("=" * 66)
    print(f" Celulas padrao : {n_cells}   (flip-flops: {n_ff})")
    print(f" Area de celulas: {area:9.1f} um^2")
    for name, (w, h) in TILES.items():
        die = w * h
        core = core_area(w, h)
        util = area / core
        print(f" Tile {name}: die {w:.2f} x {h:.2f} = {die:8.1f} um^2, core ~{core:8.1f} um^2"
              f" -> utilizacao {100 * util:5.1f} %")
    util_1x1 = area / core_area(*TILES["1x1"])
    print("-" * 66)
    if util_1x1 < 0.45:
        verdict = "CABE num tile 1x1 com folga (CTS, tap/decap e buffers incluidos)."
    elif util_1x1 < TARGET_DENSITY:
        verdict = "Deve caber em 1x1, mas com pouca folga: confirmar no GDS action."
    else:
        verdict = "NAO cabe em 1x1 a 60 % de densidade: usar 1x2 ou reduzir logica."
    print(f" Veredicto: {verdict}")
    print(" Tipos de celula mais usados:")
    for c, n in sorted(cells.items(), key=lambda kv: -kv[1])[:12]:
        print(f"   {n:4d}  {c.replace('sky130_fd_sc_hd__', '')}")
    print("=" * 66)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "build/synth_sky130_stat.txt")
