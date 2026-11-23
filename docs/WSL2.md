# Utilização no Windows 11 com WSL2

Todo o fluxo (simulação, VCD, síntese, testes cocotb, verificação Wokwi) corre no Linux do WSL2.
O GTKWave abre janelas diretamente no Windows 11 através do WSLg.

## 1. Instalar o WSL2 e o Ubuntu

Numa PowerShell **como administrador**:

```powershell
wsl --install -d Ubuntu-24.04
```

Reinicia o PC se for pedido. Abre "Ubuntu 24.04" no menu Iniciar e cria o utilizador Linux.
Se já tiveres uma distribuição (p.ex. Ubuntu‑22.04), também serve. Para ver as que tens:

```powershell
wsl -l -v
```

Confirma que a coluna `VERSION` diz `2`. Se disser 1, converte-a com
`wsl --set-version <nome> 2`.

## 2. Pacotes de base (no terminal Ubuntu)

```bash
sudo apt update
sudo apt install -y make curl git python3 python3-pip
```

## 3. Ferramentas EDA

### Opção A (recomendada): OSS CAD Suite, sem sudo

Traz versões recentes de Yosys, Icarus Verilog, GTKWave, Verilator e Python com cocotb:

```bash
cd /mnt/c/Users/<o-teu-utilizador>/Desktop/tt_lifi_tx
bash tools/install_tools_wsl.sh
```

O script descarrega a última release (~0,75 GB) para `~/oss-cad-suite` e a liberty
`sky130_fd_sc_hd__tt_025C_1v80.lib` (~12 MB) para `~/pdk`, e cria o alias `cadenv`. Em cada
terminal novo, ativa o ambiente antes de usar `make`:

```bash
cadenv          # = source ~/oss-cad-suite/environment
```

### Opção B: pacotes do Ubuntu

```bash
sudo apt install -y iverilog yosys gtkwave verilator
pip3 install --user -r test/requirements.txt     # cocotb 2.1 + pytest
```

As versões do apt são mais antigas (o Ubuntu 22.04 traz o Yosys 0.9). Se `make synth-sky130`
falhar nas opções `-dont_use` de `synth/synth_sky130.tcl`, remove-as: a área muda muito pouco.
Também podes usar o OSS CAD Suite só para a síntese. O projeto foi validado com Yosys 0.71,
Icarus 14 e Verilator 5.055. Para a área sky130 é preciso a liberty:

```bash
mkdir -p ~/pdk && curl -fL -o ~/pdk/sky130_fd_sc_hd__tt_025C_1v80.lib \
  https://raw.githubusercontent.com/The-OpenROAD-Project/OpenROAD-flow-scripts/master/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
```

## 4. Onde pôr o projeto

O projeto pode ficar no Ambiente de Trabalho do Windows e ser usado a partir do WSL em
`/mnt/c/Users/<utilizador>/Desktop/tt_lifi_tx`. Para compilações mais rápidas, copia-o para o
sistema de ficheiros Linux:

```bash
cp -r /mnt/c/Users/<utilizador>/Desktop/tt_lifi_tx ~/
cd ~/tt_lifi_tx
```

No Explorador do Windows, a pasta Linux aparece em `\\wsl$\Ubuntu-24.04\home\<utilizador>`.

## 5. Correr tudo

```bash
cadenv
make lint          # Verilator -Wall
make unit          # testes unitários (moduladores, divisor/temporizador)
make sim           # testbench de sistema completo (~25 s) -> waves/tb_lifi_tx.vcd
make sim-fast      # idem sem SPEED 5..7 (~2 s)
make waves         # VCD + SVG por modulação -> waves/{ook,manchester,ppm}.vcd, docs/img/*.svg
make synth         # Yosys genérico
make synth-sky130  # Yosys + sky130 -> área e veredicto "cabe num tile?"
make gl            # testbench de sistema sobre o netlist sintetizado (genérico)
make gl-sky130     # idem sobre o netlist sky130
make wokwi         # verifica wokwi/diagram.json contra o RTL
make wokwi-export  # idem, sobre o Verilog exportado pela Wokwi
make cocotb        # testes cocotb do template TT (pasta test/)
make mutation      # injeta 14 bugs numa cópia do RTL e confirma que o testbench os apanha
make all           # tudo menos cocotb
```

Cada testbench termina com `PASS` ou com `FAIL` e código de saída ≠ 0. Para outra semente
aleatória: `vvp -n build/tb_lifi_tx.vvp +seed=1234`.

## 6. Ver as formas de onda (GTKWave)

O Windows 11 tem WSLg, por isso o GTKWave abre como uma janela normal:

```bash
gtkwave waves/ppm.vcd waves/demo.gtkw            # trama de demonstração (também ook / manchester)
gtkwave waves/tb_lifi_tx.vcd waves/tb_lifi_tx.gtkw   # testbench de sistema
```

O sinal `test_name`, em ASCII, mostra o teste em curso. A FSM está em
`dut.u_core.u_fsm.state`: 0 IDLE, 1 PRE, 2 SFD, 3 DATA, 4 CTRL, 5 GAP. Alternativas sem
instalar nada: abrir o `.vcd` no Surfer (https://surfer-project.org) ou no GTKWave para Windows.

## 7. Submeter ao Tiny Tapeout

1. No GitHub, abre https://github.com/TinyTapeout/ttsky-verilog-template → **Use this template**
   → cria o teu repositório. Assim os workflows ficam com as versões do shuttle aberto.
2. Copia para lá, por cima dos ficheiros do template: `src/`, `test/`, `docs/info.md`,
   `info.yaml`. Opcionalmente também `docs/DESIGN.md`, `docs/img/`, `sim/`, `synth/` e `Makefile`.
3. Torna o nome do topo único, p.ex. `tt_um_<github>_lifi_tx`, nos sítios indicados no
   cabeçalho de `src/project.v`. Preenche `author` em `info.yaml`.
4. `git push`. Em *Settings → Pages*, escolhe **GitHub Actions** como *source*. Em *Actions*,
   confirma que `gds`, `docs` e `test` ficam verdes. O `gds` mostra a utilização real do tile e
   o timing.
5. Submete em https://app.tinytapeout.com escolhendo o shuttle SKY130 aberto.

Nota: os ficheiros `.github/workflows/` incluídos aqui são cópias de `gds.yaml` e `test.yaml` do
template na versão `ttsky26d`. Se o shuttle mudar, prevalecem os do template.

## 8. Problemas comuns

| Sintoma | Causa / solução |
|---|---|
| `yosys: command not found` | Falta ativar o ambiente: `cadenv` |
| `bash: tools/install_tools_wsl.sh: /bin/bash^M` | Fins de linha CRLF (ficheiro editado no Windows): `sed -i 's/\r$//' tools/install_tools_wsl.sh`. No git: `git config --global core.autocrlf input` |
| Simulação muito lenta | Projeto em `/mnt/c`: copia-o para `~/` (secção 4) |
| GTKWave não abre | Atualiza o WSL (`wsl --update` na PowerShell) para ter WSLg |
| `Falta a liberty sky130` | Define o caminho: `make synth-sky130 SKY130_LIB=/caminho/para/o.lib` |
| `cocotb-config: not found` | `cadenv`, ou `pip3 install --user -r test/requirements.txt` |
