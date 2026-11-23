#!/bin/bash
# =============================================================================
#  Testes de mutacao: injeta um bug de cada vez numa COPIA do RTL e confirma que
#  o testbench de sistema (sim/tb_lifi_tx.v) FALHA. Uma mutacao "nao detetada"
#  indica uma lacuna no testbench.
#  Uso (na raiz, com as ferramentas ativas):  bash sim/mutation_test.sh
# =============================================================================
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
fails=0

run_mut () {
  local name="$1" file="$2" from="$3" to="$4"
  rm -rf "$W/src"; cp -r "$PROJ/src" "$W/src"; mkdir -p "$W/waves"
  python3 - "$W/src/$file" "$from" "$to" <<'EOF' || { echo "[$name] padrao nao encontrado"; fails=$((fails+1)); return; }
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
if a not in s: sys.exit(1)
open(p, "w").write(s.replace(a, b, 1))
EOF
  ( cd "$W" && iverilog -g2012 -Isrc -o tb.vvp src/lifi_input_if.v src/lifi_clkdiv.v src/lifi_symtimer.v \
      src/lifi_shiftreg.v src/lifi_modulators.v src/lifi_ctrl_fsm.v src/lifi_tx_core.v src/project.v \
      "$PROJ/sim/tb_lifi_tx.v" && timeout 300 vvp -n tb.vvp +fast > log.txt 2>&1 )
  if grep -q "tb_lifi_tx: PASS" "$W/log.txt"; then
    echo "[$name] NAO DETETADA"; fails=$((fails+1))
  else
    echo "[$name] detetada: $(grep -m1 ERRO "$W/log.txt" | cut -c1-100)"
  fi
}

run_mut "Manchester invertido"     lifi_modulators.v "assign out = ~(b ^ slot[0]);" "assign out = (b ^ slot[0]);"
run_mut "PPM slot trocado"         lifi_modulators.v "assign out = (slot == sym);" "assign out = (slot == {sym[0],sym[1]});"
run_mut "SFD sem '11'"             lifi_ctrl_fsm.v   "(cnt == SFD_LAST) ? 2'b11 : 2'b10" "2'b10"
run_mut "preambulo curto"          lifi_ctrl_fsm.v   "PRE_LAST  = 3'd7" "PRE_LAST  = 3'd6"
run_mut "GAP curto"                lifi_ctrl_fsm.v   "GAP_LAST  = 3'd1" "GAP_LAST  = 3'd0"
run_mut "ignora mudanca de config" lifi_ctrl_fsm.v   "& cfg_match" ""
run_mut "ignora LAST"              lifi_ctrl_fsm.v   "hold_valid & ~cur_last" "hold_valid"
run_mut "DONE com byte pendente"   lifi_ctrl_fsm.v   "if (!hold_valid) done <= 1'b1;" "done <= 1'b1;"
run_mut "sobrescreve registo"      lifi_input_if.v   "load_rise & ~hold_valid & ~mode_rsv" "load_rise & ~mode_rsv"
run_mut "aceita modo reservado"    lifi_input_if.v   "wire mode_rsv  = (mode_in == 2'b11);" "wire mode_rsv  = 1'b0;"
run_mut "divisor speed>=2 errado"  lifi_clkdiv.v     "assign mask[2*k]   = (speed >= k);" "assign mask[2*k]   = (speed > k);"
run_mut "MSB/LSB trocados"         lifi_shiftreg.v   "assign dibit = sr[7:6];" "assign dibit = {sr[6],sr[7]};"
run_mut "BIT_CLK invertido"        lifi_tx_core.v    "bit_clk <= on_air & ~slot[0];" "bit_clk <= on_air & slot[0];"
run_mut "LED ativo no GAP"         lifi_tx_core.v    "led     <= on_air & m_sel;" "led     <= run & m_sel;"

if [ "$fails" -eq 0 ]; then echo "mutation_test: todas as mutacoes detetadas"; else echo "mutation_test: $fails problema(s)"; exit 1; fi
