/*
 * tb_wokwi - Verifica o circuito Wokwi simplificado (gerado a partir do
 * wokwi/diagram.json) contra os moduladores do RTL (src/lifi_modulators.v).
 *
 * No Wokwi cada impulso de CLK = 1 slot. Para cada modo (00..11) e dibit
 * (IN1 IN0 = 00..11) aplica reset, corre 3 simbolos e compara slot a slot:
 *   OUT0 LED, OUT1/OUT2 contador de slots, OUT3 TX_BIT, OUT5 BIT_CLK,
 *   OUT6 SYM_START, OUT7 LED_N.
 *
 * Por omissao testa o netlist gerado localmente (tt_um_wokwi_lifi). Com
 * -DWOKWI_TOP=tt_um_wokwi_<id> testa a exportacao Verilog da propria Wokwi
 * (make wokwi-export).
 */
`timescale 1ns / 1ps
`default_nettype none

module tb_wokwi;

  reg        clk = 1'b0, rst_n = 1'b0;
  reg  [7:0] ui_in = 8'h00;
  wire [7:0] uo_out, uio_out, uio_oe;

`ifndef WOKWI_TOP
  `define WOKWI_TOP tt_um_wokwi_lifi
`endif
  `WOKWI_TOP dut (
      .ui_in(ui_in), .uo_out(uo_out), .uio_in(8'h00), .uio_out(uio_out),
      .uio_oe(uio_oe), .ena(1'b1), .clk(clk), .rst_n(rst_n)
  );

  always #50 clk = ~clk;

  // Referencia: moduladores do RTL
  reg  [1:0] slot;
  wire [1:0] sym  = ui_in[1:0];          // IN1 = bit mais significativo
  wire [1:0] mode = ui_in[3:2];
  wire r_ook, r_man, r_ppm, r_led;
  lifi_mod_ook        u_ook (.sym(sym), .slot(slot), .out(r_ook));
  lifi_mod_manchester u_man (.sym(sym), .slot(slot), .out(r_man));
  lifi_mod_ppm        u_ppm (.sym(sym), .slot(slot), .out(r_ppm));
  lifi_mod_mux        u_mux (.mode(mode), .in_ook(r_ook), .in_man(r_man), .in_ppm(r_ppm),
                             .in_rsv(1'b0), .out(r_led));

  integer m, d, k, errors = 0, checks = 0;
  reg [7:0] exp_uo;

  initial begin
`ifdef WOKWI_EXPORT
    $dumpfile("waves/tb_wokwi_export.vcd");
`else
    $dumpfile("waves/tb_wokwi.vcd");
`endif
    $dumpvars(0, tb_wokwi);
    for (m = 0; m < 4; m = m + 1)
      for (d = 0; d < 4; d = d + 1) begin
        rst_n = 1'b0;
        ui_in = {4'b0000, m[1:0], d[1:0]};
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        for (k = 0; k < 12; k = k + 1) begin
          if (k > 0) @(negedge clk);
          slot = k % 4;
          #1;
          exp_uo = {~r_led,                         // OUT7 LED_N
                    (slot == 2'd0),                 // OUT6 SYM_START
                    ~slot[0],                       // OUT5 BIT_CLK
                    1'b0,                           // OUT4 nao usado
                    (slot[1] ? sym[0] : sym[1]),    // OUT3 TX_BIT
                    slot[1], slot[0],               // OUT2/OUT1 contador de slots
                    r_led};                         // OUT0 LED
          checks = checks + 1;
          if (uo_out !== exp_uo || uio_oe !== 8'h00 || uio_out !== 8'h00) begin
            errors = errors + 1;
            $display("ERRO modo=%0d dibit=%b slot=%0d: uo_out=%b esperado %b", m, d[1:0], slot, uo_out, exp_uo);
          end
        end
      end
    if (errors == 0) $display("tb_wokwi: PASS (%0d verificacoes, circuito Wokwi == RTL)", checks);
    else             $fatal(1, "tb_wokwi: FAIL (%0d erros)", errors);
    $finish;
  end

endmodule
