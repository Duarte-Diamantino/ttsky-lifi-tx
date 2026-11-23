/*
 * tb_timebase - Teste unitario do divisor de clock e do temporizador de simbolos
 * (Fase 5: configuracao de velocidade)
 *
 * Para cada SPEED = 0..7 verifica:
 *   - com run=0 nao ha ticks e o slot fica em 0;
 *   - o 1o tick surge exatamente N_slot ciclos depois de run subir;
 *   - os ticks seguintes estao espacados de N_slot = 2*4^SPEED ciclos;
 *   - sym_end ocorre a cada 4*N_slot ciclos, com o slot a percorrer 0,1,2,3.
 */
`timescale 1ns / 1ps
`default_nettype none

module tb_timebase;

  reg        clk = 1'b0, rst_n = 1'b0, run = 1'b0;
  reg  [2:0] speed = 3'd0;
  wire       tick, sym_end;
  wire [1:0] slot;

  lifi_clkdiv   u_div (.clk(clk), .rst_n(rst_n), .run(run), .speed(speed), .tick(tick));
  lifi_symtimer u_sym (.clk(clk), .rst_n(rst_n), .run(run), .tick(tick), .slot(slot), .sym_end(sym_end));

  always #50 clk = ~clk;

  integer errors = 0, sp, i, n_slot, c, last_tick, last_end, nt, ne;
  reg [1:0] exp_slot;

  initial begin
    $dumpfile("waves/tb_timebase.vcd");
    $dumpvars(0, tb_timebase);
    $dumpoff;                                   // so os casos rapidos vao para o VCD
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    for (sp = 0; sp < 8; sp = sp + 1) begin
      if (sp == 0) $dumpon;
      if (sp == 3) $dumpoff;
      speed  = sp[2:0];
      n_slot = 2 << (2 * sp);
      run    = 1'b0;
      // run = 0: sem ticks
      for (i = 0; i < 20; i = i + 1) begin
        @(negedge clk);
        if (tick !== 1'b0 || slot !== 2'd0) begin errors = errors + 1; $display("ERRO run=0 speed=%0d", sp); end
      end
      // arranque: run sobe entre flancos; no nucleo isto equivale ao flanco
      // "-1" (o estado passa a PRE), por isso as referencias comecam em -1.
      run = 1'b1; c = 0; last_tick = -1; last_end = -1; nt = 0; ne = 0; exp_slot = 2'd0;
      while (ne < 3) begin
        @(posedge clk); #1;                     // estado apos o flanco
        c = c + 1;
        // tick e combinacional: verificado antes do proximo flanco
        if (tick) begin
          nt = nt + 1;
          if (c - last_tick != n_slot) begin
            errors = errors + 1;
            $display("ERRO speed=%0d: intervalo entre ticks = %0d (esperado %0d)", sp, c - last_tick, n_slot);
          end
          last_tick = c;
          if (slot !== exp_slot) begin errors = errors + 1; $display("ERRO speed=%0d: slot=%0d esperado %0d", sp, slot, exp_slot); end
          if (sym_end !== (exp_slot == 2'd3)) begin errors = errors + 1; $display("ERRO speed=%0d: sym_end", sp); end
          if (sym_end) begin
            ne = ne + 1;
            if (c - last_end != 4 * n_slot) begin errors = errors + 1; $display("ERRO speed=%0d: simbolo com %0d ciclos", sp, c - last_end); end
            last_end = c;
          end
          exp_slot = exp_slot + 2'd1;
        end else if (sym_end) begin
          errors = errors + 1; $display("ERRO speed=%0d: sym_end sem tick", sp);
        end
      end
      $display("  speed=%0d  N_slot=%0d ciclos  T_bit=%0d ciclos  ticks=%0d  OK", sp, n_slot, 2 * n_slot, nt);
      @(negedge clk);
    end

    if (errors == 0) $display("tb_timebase: PASS");
    else             $fatal(1, "tb_timebase: FAIL (%0d erros)", errors);
    $finish;
  end

endmodule
