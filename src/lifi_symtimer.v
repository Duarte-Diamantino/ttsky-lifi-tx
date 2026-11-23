/*
 * Copyright (c) 2026 Duarte Diamantino
 * SPDX-License-Identifier: Apache-2.0
 *
 * lifi_symtimer - Gerador de temporizacao de simbolos
 *
 * Um simbolo = 4 slots = 2 bits (dibit). Todos os modos usam a mesma
 * grelha temporal:
 *   slot[1] = indice do bit dentro do simbolo (0 = bit mais significativo)
 *   slot[0] = metade do bit (0 = 1a metade, 1 = 2a metade)
 * sym_end e um impulso no ultimo ciclo do simbolo (tick com slot = 3).
 */
`default_nettype none

module lifi_symtimer (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       run,
    input  wire       tick,
    output reg  [1:0] slot,
    output wire       sym_end
);

  always @(posedge clk) begin
    if (!rst_n || !run) slot <= 2'd0;
    else if (tick)      slot <= slot + 2'd1;
  end

  assign sym_end = tick & (slot == 2'd3);

endmodule
