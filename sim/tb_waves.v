/*
 * tb_waves - Gera VCD de demonstracao (uma trama de 2 bytes: 0x1B, 0xE4)
 * e imprime a forma de onda do LED slot a slot (usada nos diagramas).
 *
 *   vvp build/tb_waves.vvp +mode=0 +vcd=waves/ook.vcd
 *   vvp build/tb_waves.vvp +mode=1 +vcd=waves/manchester.vcd
 *   vvp build/tb_waves.vvp +mode=2 +vcd=waves/ppm.vcd
 *   (opcional +speed=<0..3>)
 *
 * 0x1B = 00 01 10 11 e 0xE4 = 11 10 01 00 cobrem os quatro dibits.
 */
`timescale 1ns / 1ps
`default_nettype none

module tb_waves;

  reg        clk = 1'b0, rst_n = 1'b0;
  reg  [7:0] ui_in = 8'h00, uio_in = 8'h00;
  wire [7:0] uo_out, uio_out, uio_oe;

  tt_um_duarte_diamantino_lifi_tx dut (
      .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out),
      .uio_oe(uio_oe), .ena(1'b1), .clk(clk), .rst_n(rst_n)
  );

  always #50 clk = ~clk;   // 10 MHz

  wire LED = uo_out[0], BUSY = uo_out[1], READY = uo_out[2], DONE = uo_out[3];
  wire BIT_CLK = uo_out[5], SYNC = uo_out[6], TX_BIT = uio_out[7];

  integer mode, speed, n_slot, sl, sy, nsym;
  reg [8*64:1] vcd;
  reg [8*12:1] label;
  reg [3:0]    w;

  task load(input [7:0] d, input last);
    begin
      while (READY !== 1'b1) @(negedge clk);
      @(negedge clk);
      ui_in  = d;
      uio_in = {1'b0, last, speed[2:0], 1'b0, mode[1:0]};
      @(negedge clk); uio_in[2] = 1'b1;
      repeat (4) @(negedge clk); uio_in[2] = 1'b0;
      repeat (2) @(negedge clk);
    end
  endtask

  initial begin
    if (!$value$plusargs("mode=%d", mode))   mode  = 0;
    if (!$value$plusargs("speed=%d", speed)) speed = 0;
    if (!$value$plusargs("vcd=%s", vcd))     vcd   = "waves/demo.vcd";
    n_slot = 2 << (2 * speed);
    $dumpfile(vcd);
    $dumpvars(0, tb_waves);

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (4) @(negedge clk);

    fork
      begin
        load(8'h1B, 1'b0);
        load(8'hE4, 1'b1);
      end
      begin
        // imprime a trama slot a slot a partir da subida de BUSY
        @(posedge BUSY);
        @(negedge clk);
        nsym = 12 + 5 * 2 + 2;
        $display("modo=%0d (%0s) speed=%0d  N_slot=%0d ciclos", mode,
                 (mode == 0) ? "OOK" : (mode == 1) ? "Manchester" : "4-PPM", speed, n_slot);
        for (sy = 0; sy < nsym; sy = sy + 1) begin
          for (sl = 0; sl < 4; sl = sl + 1) begin
            w[3 - sl] = LED;
            repeat (n_slot) @(negedge clk);
          end
          if (sy < 8)        label = "PREAMBULO";
          else if (sy < 12)  label = "SFD";
          else if (sy < 16)  label = "BYTE 0x1B";
          else if (sy == 16) label = "CTRL";
          else if (sy < 21)  label = "BYTE 0xE4";
          else if (sy == 21) label = "CTRL";
          else               label = "GAP";
          $display("  simbolo %2d  %-10s LED slots = %b", sy, label, w);
        end
      end
    join

    wait (DONE === 1'b1);
    repeat (20) @(negedge clk);
    $finish;
  end

endmodule
