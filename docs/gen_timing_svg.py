#!/usr/bin/env python3
"""
gen_timing_svg.py - Gera os diagramas temporais (SVG) a partir dos VCD da simulacao.

Uso (na raiz, depois de 'make waves'):  python3 docs/gen_timing_svg.py
Produz docs/img/timing_overview.svg e docs/img/timing_{ook,manchester,ppm}.svg

Os diagramas sao desenhados a partir dos ficheiros waves/{ook,manchester,ppm}.vcd
(trama de 2 bytes 0x1B, 0xE4, SPEED=0), por isso mostram o comportamento real do RTL.
"""
import os
import re

MODES = [("ook", "OOK (NRZ)"), ("manchester", "Manchester (IEEE 802.3)"), ("ppm", "4-PPM")]
SIGS = ["clk", "BUSY", "SYNC", "BIT_CLK", "TX_BIT", "LED"]
SECTIONS = [(0, 8, "PREAMBULO 16 b"), (8, 12, "SFD"), (12, 16, "BYTE 0x1B"), (16, 17, "C"),
            (17, 21, "BYTE 0xE4"), (21, 22, "C"), (22, 24, "GAP")]


def parse_vcd(path, wanted):
    """Devolve {nome_curto: [(t, valor_int), ...]} para os sinais pedidos (escopo de topo)."""
    ids, scope, changes, t = {}, [], {}, 0
    with open(path) as f:
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if tok[0] == "$scope":
                scope.append(tok[2])
            elif tok[0] == "$upscope":
                scope.pop()
            elif tok[0] == "$var":
                name = tok[4]
                if len(scope) == 1 and name in wanted:
                    ids.setdefault(tok[3], []).append(name)
            elif tok[0].startswith("#"):
                t = int(tok[0][1:])
            elif tok[0][0] in "01xz" and len(tok) == 1:
                code = tok[0][1:]
                for n in ids.get(code, []):
                    changes.setdefault(n, []).append((t, 1 if tok[0][0] == "1" else 0))
            elif tok[0][0] == "b" and len(tok) == 2:
                for n in ids.get(tok[1], []):
                    v = tok[0][1:]
                    changes.setdefault(n, []).append((t, int(v, 2) if re.fullmatch("[01]+", v) else 0))
    return changes


def value_at(ch, t):
    v = 0
    for tt, vv in ch:
        if tt > t:
            break
        v = vv
    return v


def wave_path(ch, t0, t1, x0, xs, y_hi, y_lo):
    pts, v = [], value_at(ch, t0)
    pts.append((x0, y_hi if v else y_lo))
    for tt, vv in ch:
        if t0 < tt < t1 and vv != v:
            x = x0 + (tt - t0) * xs
            pts.append((x, y_hi if v else y_lo))
            pts.append((x, y_hi if vv else y_lo))
            v = vv
    pts.append((x0 + (t1 - t0) * xs, y_hi if v else y_lo))
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)


def svg_header(w, h, title):
    return [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" '
            f'font-family="Helvetica, Arial, sans-serif" font-size="12">',
            f'<rect width="{w}" height="{h}" fill="#ffffff"/>',
            f'<text x="12" y="20" font-size="14" font-weight="bold" fill="#1f2328">{title}</text>']


def frame_window(ch):
    busy = ch["BUSY"]
    t_rise = next(t for t, v in busy if v == 1)
    t_fall = next(t for t, v in busy if v == 0 and t > t_rise)
    return t_rise, t_fall


def overview(vcds, out):
    W, left, right, row_h = 1180, 150, 20, 70
    H = 60 + row_h * len(vcds) + 40
    s = svg_header(W, H, "Trama completa (0x1B, 0xE4) - saida LED nos tres modos, SPEED=0")
    y_top = 50
    any_ch = next(iter(vcds.values()))[1]
    t0, t1 = frame_window(any_ch)
    sym = (t1 - t0) / 24.0
    xs = (W - left - right) / (t1 - t0)
    for k, (a, b, label) in enumerate(SECTIONS):     # faixas das seccoes
        xa, xb = left + a * sym * xs, left + b * sym * xs
        fill = "#f3f6fa" if k % 2 == 0 else "#ffffff"
        s.append(f'<rect x="{xa:.1f}" y="{y_top - 14}" width="{xb - xa:.1f}" height="{row_h * len(vcds) + 14}" '
                 f'fill="{fill}" stroke="#d0d7de" stroke-width="0.5"/>')
        s.append(f'<text x="{(xa + xb) / 2:.1f}" y="{y_top - 2}" text-anchor="middle" fill="#57606a" '
                 f'font-size="10">{label}</text>')
    for i, (key, (title, ch)) in enumerate(vcds.items()):
        y = y_top + 12 + i * row_h
        s.append(f'<text x="10" y="{y + 25}" fill="#1f2328">{title}</text>')
        s.append(f'<path d="{wave_path(ch["LED"], t0, t1, left, xs, y + 8, y + 40)}" fill="none" '
                 f'stroke="#0969da" stroke-width="1.4"/>')
    s.append(f'<text x="{left}" y="{H - 12}" fill="#57606a" font-size="11">'
             f'1 simbolo = 2 bits = 4 slots; aqui 1 slot = 2 ciclos de clk (SPEED=0). C = bits de controlo '
             f'(10 = segue byte, 01 = ultimo byte).</text>')
    s.append("</svg>")
    open(out, "w").write("\n".join(s))


def detail(title, ch, out):
    t_rise, t_fall = frame_window(ch)
    sym = (t_fall - t_rise) / 24.0
    t0, t1 = t_rise + 11 * sym, t_rise + 17 * sym      # ultimo simbolo do SFD .. CTRL
    W, left, right, row_h = 1180, 110, 20, 44
    H = 70 + row_h * len(SIGS) + 30
    s = svg_header(W, H, f"{title}: fim do SFD, byte 0x1B (00 01 10 11) e bits de controlo")
    xs = (W - left - right) / (t1 - t0)
    y0 = 58
    slot = sym / 4
    labels = ["SFD 11", "00", "01", "10", "11", "CTRL 10"]
    for k in range(6):                               # grelha de simbolos e slots
        xa = left + k * sym * xs
        s.append(f'<rect x="{xa:.1f}" y="{y0 - 18}" width="{sym * xs:.1f}" height="{row_h * len(SIGS) + 18}" '
                 f'fill="{"#f3f6fa" if k % 2 == 0 else "#ffffff"}" stroke="#8c959f" stroke-width="0.8"/>')
        s.append(f'<text x="{xa + sym * xs / 2:.1f}" y="{y0 - 5}" text-anchor="middle" fill="#1f2328">'
                 f'{labels[k]}</text>')
        for j in range(1, 4):
            xj = xa + j * slot * xs
            s.append(f'<line x1="{xj:.1f}" y1="{y0}" x2="{xj:.1f}" y2="{y0 + row_h * len(SIGS)}" '
                     f'stroke="#d0d7de" stroke-dasharray="3,3"/>')
    for i, name in enumerate(SIGS):
        y = y0 + i * row_h
        s.append(f'<text x="10" y="{y + 26}" fill="#1f2328">{name}</text>')
        color = "#cf222e" if name == "LED" else ("#8c959f" if name == "clk" else "#0969da")
        s.append(f'<path d="{wave_path(ch[name], t0, t1, left, xs, y + 10, y + 34)}" fill="none" '
                 f'stroke="{color}" stroke-width="{1.8 if name == "LED" else 1.2}"/>')
    s.append(f'<text x="{left}" y="{H - 10}" fill="#57606a" font-size="11">Linhas tracejadas = fronteiras '
             f'de slot. BIT_CLK = 1 na 1a metade de cada bit; TX_BIT = bit NRZ em transmissao.</text>')
    s.append("</svg>")
    open(out, "w").write("\n".join(s))


def main():
    os.makedirs("docs/img", exist_ok=True)
    vcds = {}
    for key, title in MODES:
        ch = parse_vcd(f"waves/{key}.vcd", set(SIGS))
        vcds[key] = (title, ch)
        detail(title, ch, f"docs/img/timing_{key}.svg")
    overview(vcds, "docs/img/timing_overview.svg")
    print("SVG gerados em docs/img/")


if __name__ == "__main__":
    main()
