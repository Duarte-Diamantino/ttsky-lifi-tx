/*
 * Copyright (c) 2026 Duarte Diamantino
 * SPDX-License-Identifier: Apache-2.0
 *
 * lifi_shiftreg - Registo de deslocamento de 8 bits (MSB primeiro)
 *
 * Desloca 2 bits de cada vez (um dibit por simbolo). O dibit atual e
 * sempre sr[7:6], estavel durante todo o simbolo.
 */
`default_nettype none

module lifi_shiftreg (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       load,
    input  wire [7:0] din,
    input  wire       shift,
    output wire [1:0] dibit
);

  reg [7:0] sr;

  always @(posedge clk) begin
    if (!rst_n)     sr <= 8'h00;
    else if (load)  sr <= din;
    else if (shift) sr <= {sr[5:0], 2'b00};
  end

  assign dibit = sr[7:6];

endmodule
