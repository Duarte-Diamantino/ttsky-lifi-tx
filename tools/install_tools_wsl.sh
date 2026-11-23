#!/bin/bash
# =============================================================================
#  Instala as ferramentas do projeto no WSL2 (Ubuntu), SEM sudo:
#    - OSS CAD Suite (Yosys, Icarus Verilog, GTKWave, Verilator, Python + cocotb)
#      em ~/oss-cad-suite  (~0,75 GB a descarregar, ~2,5 GB instalado)
#    - liberty sky130_fd_sc_hd (tt, 25 C, 1.8 V) em ~/pdk  (~12 MB), so para a
#      estimativa de area (make synth-sky130 / make gl-sky130)
#
#  Uso:   bash tools/install_tools_wsl.sh            (ultima release)
#         OSS_TAG=2026-11-21 bash tools/install_tools_wsl.sh   (release fixa)
# =============================================================================
set -euo pipefail

INSTALL_DIR="$HOME/oss-cad-suite"
PDK_DIR="$HOME/pdk"
LIB_URL="https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"

need() { command -v "$1" >/dev/null || { echo "Falta '$1': sudo apt install -y $2"; exit 1; }; }
need curl curl
need tar tar
need python3 python3
need make make

if [ -x "$INSTALL_DIR/bin/yosys" ]; then
  echo "OSS CAD Suite ja instalado em $INSTALL_DIR"
else
  if [ -z "${OSS_TAG:-}" ]; then
    OSS_TAG=$(curl -fsSL https://api.github.com/repos/YosysHQ/oss-cad-suite-build/releases/latest \
              | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
  fi
  TGZ="oss-cad-suite-linux-x64-${OSS_TAG//-/}.tgz"
  URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$OSS_TAG/$TGZ"
  echo "A descarregar $URL"
  TMP=$(mktemp -d)
  curl -fL -o "$TMP/$TGZ" "$URL"
  tar -xzf "$TMP/$TGZ" -C "$HOME"
  rm -rf "$TMP"
fi

mkdir -p "$PDK_DIR"
if [ ! -f "$PDK_DIR/sky130_fd_sc_hd__tt_025C_1v80.lib" ]; then
  echo "A descarregar a liberty sky130_fd_sc_hd"
  curl -fL -o "$PDK_DIR/sky130_fd_sc_hd__tt_025C_1v80.lib" "$LIB_URL"
fi

# Atalho para ativar o ambiente (nao se ativa sozinho: altera o PATH e o prompt)
if ! grep -q "alias cadenv=" "$HOME/.bashrc"; then
  echo "alias cadenv='source $INSTALL_DIR/environment'" >> "$HOME/.bashrc"
fi

source "$INSTALL_DIR/environment"
echo "=== versoes ==="
yosys -V
iverilog -V 2>&1 | head -1
verilator --version
python3 -c 'import cocotb; print("cocotb", cocotb.__version__)' || \
  echo "cocotb nao incluido: pip install -r test/requirements.txt"
echo "Pronto. Abre um terminal novo e escreve 'cadenv' antes de usar make."
