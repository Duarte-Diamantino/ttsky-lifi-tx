/*
 * Copyright (c) 2026 Duarte Diamantino
 * SPDX-License-Identifier: Apache-2.0
 *
 * lifi_clkdiv - Divisor de clock configuravel (gera o "tick" de slot)
 *
 *   N_slot = 2 * 4^speed  ciclos de clk   (speed = 0..7)
 *          = 2, 8, 32, 128, 512, 2048, 8192, 32768
 *
 *   Bit  = 2 slots  ->  T_bit = 4^(speed+1) ciclos de clk
 *   Debito binario  R_b = f_clk / 4^(speed+1)   (igual nos tres modos)
 *
 * Implementacao: contador livre de 15 bits; o tick ocorre quando os
 * (2*speed+1) bits menos significativos estao todos a 1 (divisao por
 * potencia de 2, sem comparador completo). Com run=0 o contador fica a 0,
 * pelo que o primeiro slot de cada trama tem a duracao exata.
 */
`default_nettype none

module lifi_clkdiv (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       run,
    input  wire [2:0] speed,
    output wire       tick
);

  reg  [14:0] cnt;
  wire [14:0] mask;

  // mask = (2*speed+1) uns em codigo termometro
  assign mask[0] = 1'b1;
  genvar k;
  generate
    for (k = 1; k <= 7; k = k + 1) begin : g_mask
      assign mask[2*k-1] = (speed >= k);
      assign mask[2*k]   = (speed >= k);
    end
  endgenerate

  assign tick = run & (&(cnt | ~mask));

  always @(posedge clk) begin
    if (!rst_n || !run) cnt <= 15'd0;
    else                cnt <= cnt + 15'd1;
  end

endmodule
