# =============================================================================
#  Transmissor LiFi reconfiguravel - Tiny Tapeout (SKY130)
#
#  Requer: iverilog/vvp, yosys, verilator (OSS CAD Suite recomendado)
#          python3 + cocotb (apenas para 'make cocotb')
#
#  make lint          Verilator --lint-only -Wall (o fluxo TT tambem faz lint)
#  make unit          testes unitarios (moduladores, divisor/temporizador)
#  make sim           testbench de sistema completo  -> waves/tb_lifi_tx.vcd
#  make sim-fast      idem, sem SPEED 5..7 (mais rapido)
#  make waves         VCD de demonstracao por modulacao -> waves/{ook,manchester,ppm}.vcd
#  make synth         sintese Yosys generica + estatisticas
#  make synth-sky130  sintese mapeada em sky130_fd_sc_hd + area vs. tile 1x1
#  make gl            simulacao pos-sintese (netlist Yosys generico) com o testbench de sistema
#  make gl-sky130     idem, sobre o netlist mapeado em celulas sky130_fd_sc_hd
#  make cocotb        testes cocotb do template Tiny Tapeout (pasta test/)
#  make wokwi         verifica o circuito Wokwi (wokwi/diagram.json) contra o RTL
#  make wokwi-export  idem, sobre o Verilog exportado pela propria Wokwi (projeto guardado)
#  make mutation      injeta 14 bugs no RTL (copia) e confirma que o testbench os deteta
#  make all           lint + unit + sim + waves + synth + synth-sky130 + gl + wokwi + wokwi-export
# =============================================================================

TOP      := tt_um_duarte_diamantino_lifi_tx
SRC_DIR  := src
SRCS     := $(SRC_DIR)/lifi_input_if.v \
            $(SRC_DIR)/lifi_clkdiv.v \
            $(SRC_DIR)/lifi_symtimer.v \
            $(SRC_DIR)/lifi_shiftreg.v \
            $(SRC_DIR)/lifi_modulators.v \
            $(SRC_DIR)/lifi_ctrl_fsm.v \
            $(SRC_DIR)/lifi_tx_core.v \
            $(SRC_DIR)/project.v

BUILD    := build
# Projeto Wokwi guardado: https://wokwi.com/projects/$(WOKWI_ID)
WOKWI_ID := 481391130244247553
WAVES    := waves
IVERILOG := iverilog -g2012 -Wall -Wno-timescale -I$(SRC_DIR)
VVP      := vvp -n
YOSYS    := yosys
SKY130_LIB ?= $(HOME)/pdk/sky130_fd_sc_hd__tt_025C_1v80.lib

.PHONY: all lint unit sim sim-fast waves synth synth-sky130 gl gl-sky130 cocotb wokwi wokwi-export mutation clean dirs

all: lint unit sim waves synth synth-sky130 gl gl-sky130 wokwi wokwi-export

dirs:
	@mkdir -p $(BUILD) $(WAVES)

# ----------------------------------------------------------------------------- lint
lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME --top-module $(TOP) $(SRCS)
	@echo "lint: OK"

# ----------------------------------------------------------------------------- testes unitarios
$(BUILD)/tb_modulators.vvp: sim/tb_modulators.v $(SRC_DIR)/lifi_modulators.v | dirs
	$(IVERILOG) -o $@ $^

$(BUILD)/tb_timebase.vvp: sim/tb_timebase.v $(SRC_DIR)/lifi_clkdiv.v $(SRC_DIR)/lifi_symtimer.v | dirs
	$(IVERILOG) -o $@ $^

unit: $(BUILD)/tb_modulators.vvp $(BUILD)/tb_timebase.vvp
	$(VVP) $(BUILD)/tb_modulators.vvp
	$(VVP) $(BUILD)/tb_timebase.vvp

# ----------------------------------------------------------------------------- sistema
$(BUILD)/tb_lifi_tx.vvp: sim/tb_lifi_tx.v $(SRCS) | dirs
	$(IVERILOG) -o $@ $(SRCS) sim/tb_lifi_tx.v

sim: $(BUILD)/tb_lifi_tx.vvp
	$(VVP) $(BUILD)/tb_lifi_tx.vvp

sim-fast: $(BUILD)/tb_lifi_tx.vvp
	$(VVP) $(BUILD)/tb_lifi_tx.vvp +fast

# ----------------------------------------------------------------------------- VCD de demonstracao
$(BUILD)/tb_waves.vvp: sim/tb_waves.v $(SRCS) | dirs
	$(IVERILOG) -o $@ $(SRCS) sim/tb_waves.v

waves: $(BUILD)/tb_waves.vvp
	$(VVP) $(BUILD)/tb_waves.vvp +mode=0 +vcd=$(WAVES)/ook.vcd
	$(VVP) $(BUILD)/tb_waves.vvp +mode=1 +vcd=$(WAVES)/manchester.vcd
	$(VVP) $(BUILD)/tb_waves.vvp +mode=2 +vcd=$(WAVES)/ppm.vcd
	python3 docs/gen_timing_svg.py

# ----------------------------------------------------------------------------- sintese
synth: | dirs
	$(YOSYS) -q -l $(BUILD)/synth_generic.log -s synth/synth_generic.ys
	@grep -A40 "=== $(TOP) ===" $(BUILD)/synth_generic.log | head -60

synth-sky130: | dirs
	@test -f "$(SKY130_LIB)" || (echo "Falta a liberty sky130: defina SKY130_LIB=..."; exit 1)
	SKY130_LIB="$(SKY130_LIB)" $(YOSYS) -q -l $(BUILD)/synth_sky130.log -c synth/synth_sky130.tcl
	python3 synth/area_report.py $(BUILD)/synth_sky130_stat.txt

# ----------------------------------------------------------------------------- pos-sintese
gl: $(BUILD)/netlist_generic.v
	$(IVERILOG) -o $(BUILD)/tb_gl.vvp -DGL_SIM $(BUILD)/netlist_generic.v \
	    $$($(YOSYS)-config --datdir)/simcells.v sim/tb_lifi_tx.v
	$(VVP) $(BUILD)/tb_gl.vvp +fast

$(BUILD)/netlist_generic.v: synth

# Pos-sintese no netlist sky130: modelos das celulas gerados a partir da propria liberty
$(BUILD)/sky130_cells_sim.v: | dirs
	$(YOSYS) -q -p "read_liberty -ignore_miss_func $(SKY130_LIB); write_verilog -noattr $@"

gl-sky130: $(BUILD)/sky130_cells_sim.v
	@test -f $(BUILD)/netlist_sky130.v || $(MAKE) synth-sky130
	$(IVERILOG) -o $(BUILD)/tb_gl_sky130.vvp -DGL_SIM $(BUILD)/netlist_sky130.v \
	    $(BUILD)/sky130_cells_sim.v sim/tb_lifi_tx.v
	$(VVP) $(BUILD)/tb_gl_sky130.vvp +fast

# ----------------------------------------------------------------------------- cocotb (template TT)
cocotb:
	$(MAKE) -C test -B

# ----------------------------------------------------------------------------- testes de mutacao
mutation:
	bash sim/mutation_test.sh

# ----------------------------------------------------------------------------- Wokwi
wokwi: | dirs
	python3 wokwi/wokwi_to_verilog.py wokwi/diagram.json $(BUILD)/wokwi_netlist.v
	$(IVERILOG) -o $(BUILD)/tb_wokwi.vvp $(BUILD)/wokwi_netlist.v wokwi/wokwi_cells_sim.v \
	    $(SRC_DIR)/lifi_modulators.v wokwi/tb_wokwi.v
	$(VVP) $(BUILD)/tb_wokwi.vvp

# Verilog exportado pela Wokwi (https://wokwi.com/api/projects/$(WOKWI_ID)/verilog),
# guardado em wokwi/tt_um_wokwi_$(WOKWI_ID).v
wokwi-export: | dirs
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY \
	    --top-module tt_um_wokwi_$(WOKWI_ID) wokwi/tt_um_wokwi_$(WOKWI_ID).v wokwi/wokwi_cells_sim.v
	$(IVERILOG) -DWOKWI_EXPORT -DWOKWI_TOP=tt_um_wokwi_$(WOKWI_ID) -o $(BUILD)/tb_wokwi_export.vvp \
	    wokwi/tt_um_wokwi_$(WOKWI_ID).v wokwi/wokwi_cells_sim.v $(SRC_DIR)/lifi_modulators.v wokwi/tb_wokwi.v
	$(VVP) $(BUILD)/tb_wokwi_export.vvp

clean:
	rm -rf $(BUILD) $(WAVES)/*.vcd test/sim_build test/results.xml test/*.fst test/*.vcd
