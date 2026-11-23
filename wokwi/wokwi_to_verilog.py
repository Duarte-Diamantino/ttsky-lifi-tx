#!/usr/bin/env python3
"""
wokwi_to_verilog.py - Converte um diagram.json do Wokwi (subconjunto aceite pelo
Tiny Tapeout) num netlist Verilog, para o simular e comparar com o RTL.

Nao substitui o conversor oficial (https://wokwi.com/api/projects/<id>/verilog):
serve para apanhar erros de ligacao ANTES de colar o diagrama no Wokwi e para
garantir que so sao usadas pecas que o fluxo TT sabe converter.

Uso: python3 wokwi/wokwi_to_verilog.py wokwi/diagram.json build/wokwi_netlist.v
"""
import json
import sys

# tipo Wokwi -> (celula de simulacao, pinos de entrada, pinos de saida)
LOGIC = {
    "wokwi-gate-buffer":   ("w_buf",   ["IN"], ["OUT"]),
    "wokwi-gate-not":      ("w_not",   ["IN"], ["OUT"]),
    "wokwi-gate-and-2":    ("w_and2",  ["A", "B"], ["OUT"]),
    "wokwi-gate-or-2":     ("w_or2",   ["A", "B"], ["OUT"]),
    "wokwi-gate-xor-2":    ("w_xor2",  ["A", "B"], ["OUT"]),
    "wokwi-gate-nand-2":   ("w_nand2", ["A", "B"], ["OUT"]),
    "wokwi-gate-nor-2":    ("w_nor2",  ["A", "B"], ["OUT"]),
    "wokwi-gate-xnor-2":   ("w_xnor2", ["A", "B"], ["OUT"]),
    "wokwi-mux-2":         ("w_mux2",  ["A", "B", "SEL"], ["OUT"]),
    "wokwi-flip-flop-d":   ("w_dff",   ["D", "CLK"], ["Q", "NOTQ"]),
    "wokwi-flip-flop-dr":  ("w_dffr",  ["D", "CLK", "R"], ["Q", "NOTQ"]),
    "wokwi-flip-flop-dsr": ("w_dffsr", ["D", "CLK", "S", "R"], ["Q", "NOTQ"]),
}
CONST = {"wokwi-vcc": ("VCC", "1'b1"), "wokwi-gnd": ("GND", "1'b0")}
TT_IN, TT_OUT, JUNCTION = "board-tt-block-input", "board-tt-block-output", "wokwi-junction"
TT_IN_PINS = {**{f"IN{i}": f"ui_in[{i}]" for i in range(8)}, "CLK": "clk", "RST_N": "rst_n"}
TT_OUT_PINS = {f"OUT{i}": i for i in range(8)}


class DSU:
    def __init__(self):
        self.p = {}

    def find(self, x):
        self.p.setdefault(x, x)
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x

    def union(self, a, b):
        self.p[self.find(a)] = self.find(b)


def main(src, dst):
    d = json.load(open(src, encoding="utf-8"))
    parts = {p["id"]: p for p in d["parts"]}
    dsu = DSU()
    for c in d["connections"]:
        a, b = c[0], c[1]
        for ep in (a, b):
            pid = ep.split(":")[0]
            if pid not in parts:
                sys.exit(f"ERRO: ligacao a uma peca inexistente: {ep}")
        dsu.union(a, b)

    errors, warnings = [], []
    ttin = [p for p in parts.values() if p["type"] == TT_IN]
    ttout = [p for p in parts.values() if p["type"] == TT_OUT]
    if len(ttin) != 1 or len(ttout) != 1:
        sys.exit("ERRO: tem de existir exatamente um board-tt-block-input e um board-tt-block-output")
    ttin, ttout = ttin[0], ttout[0]
    for p, role in ((ttin, "input"), (ttout, "output")):
        if p.get("attrs", {}).get("verilogRole") != role:
            errors.append(f"{p['id']}: attrs.verilogRole deve ser '{role}'")

    # Fontes (drivers) de cada net
    drivers = {}

    def drive(ep, expr):
        r = dsu.find(ep)
        if r in drivers and drivers[r] != expr:
            errors.append(f"net com dois drivers: {drivers[r]} e {expr} (em {ep})")
        drivers[r] = expr

    for pin, expr in TT_IN_PINS.items():
        drive(f"{ttin['id']}:{pin}", expr)
    for p in parts.values():
        if p["type"] in CONST:
            pin, val = CONST[p["type"]]
            drive(f"{p['id']}:{pin}", val)

    net_name = {}

    def net(ep):
        r = dsu.find(ep)
        if r not in net_name:
            net_name[r] = f"n{len(net_name)}"
        return net_name[r]

    logic_parts = [p for p in parts.values() if p["type"] in LOGIC]
    for p in logic_parts:
        _, _, outs = LOGIC[p["type"]]
        for o in outs:
            drive(f"{p['id']}:{o}", net(f"{p['id']}:{o}"))

    # Nets "internas" (dentro do chip) e pecas nao suportadas ligadas a elas
    internal_roots = set()
    for p in logic_parts:
        cell, ins, outs = LOGIC[p["type"]]
        for pin in ins + outs:
            internal_roots.add(dsu.find(f"{p['id']}:{pin}"))
    for pin in TT_IN_PINS:
        internal_roots.add(dsu.find(f"{ttin['id']}:{pin}"))
    for pin in TT_OUT_PINS:
        internal_roots.add(dsu.find(f"{ttout['id']}:{pin}"))
    supported = set(LOGIC) | set(CONST) | {TT_IN, TT_OUT, JUNCTION}
    for c in d["connections"]:
        for ep in c[:2]:
            pid, pin = ep.split(":", 1)
            t = parts[pid]["type"]
            if dsu.find(ep) in internal_roots and t not in supported:
                errors.append(f"peca '{pid}' ({t}) ligada ao interior do chip: o fluxo TT ignora-a")
            if t in (TT_IN, TT_OUT) and pin.startswith("EXT") and dsu.find(ep) in internal_roots:
                errors.append(f"pino externo {ep} ligado ao interior do chip")

    lines = [
        "// Gerado por wokwi/wokwi_to_verilog.py a partir de " + src,
        "`default_nettype none",
        "module tt_um_wokwi_lifi (",
        "    input  wire [7:0] ui_in,  output wire [7:0] uo_out,",
        "    input  wire [7:0] uio_in, output wire [7:0] uio_out, output wire [7:0] uio_oe,",
        "    input  wire ena, input wire clk, input wire rst_n);",
    ]
    decl, body = [], []
    used = {}   # nets internas declaradas (saidas de celulas)

    def ref(ep):
        r = dsu.find(ep)
        if r not in drivers:
            errors.append(f"entrada sem driver: {ep}")
            return "1'bx"
        return drivers[r]

    for p in logic_parts:
        cell, ins, outs = LOGIC[p["type"]]
        conns = []
        for pin in ins:
            conns.append(f".{pin.lower()}({ref(p['id'] + ':' + pin)})")
        for pin in outs:
            n = net(f"{p['id']}:{pin}")
            used[n] = True
            conns.append(f".{pin.lower()}({n})")
        body.append(f"  {cell} {p['id']} ({', '.join(conns)});")
    for n in sorted(used, key=lambda s: int(s[1:])):
        decl.append(f"  wire {n};")
    outs = []
    for pin, idx in TT_OUT_PINS.items():
        ep = f"{ttout['id']}:{pin}"
        r = dsu.find(ep)
        connected = any(dsu.find(c[i]) == r and c[i] != ep for c in d["connections"] for i in (0, 1))
        src_expr = drivers.get(r, "1'b0") if connected else "1'b0"
        outs.append(f"  assign uo_out[{idx}] = {src_expr};")
    lines += decl + body + outs + [
        "  assign uio_out = 8'h00;",
        "  assign uio_oe  = 8'h00;",
        "  wire _unused = &{ena, uio_in, 1'b0};",
        "endmodule",
    ]

    if errors:
        print("\n".join("ERRO: " + e for e in dict.fromkeys(errors)))
        sys.exit(1)
    open(dst, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    n_ff = sum(1 for p in logic_parts if "flip-flop" in p["type"])
    print(f"wokwi_to_verilog: {len(logic_parts)} celulas ({n_ff} flip-flops), "
          f"{len(used)} nets internas -> {dst}")
    for w in warnings:
        print("AVISO: " + w)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
