/*
 * Copyright (c) 2026 Duarte Diamantino
 * SPDX-License-Identifier: Apache-2.0
 *
 * Moduladores (combinacionais) e multiplexador de modo.
 *
 * Entrada comum: sym[1:0] = dibit atual {bit_msb, bit_lsb}
 *                slot[1:0] = posicao temporal dentro do simbolo (0..3)
 *
 *   dibit | OOK (NRZ) | Manchester (IEEE 802.3) | 4-PPM
 *   ------+-----------+-------------------------+------
 *    00   |   0 0 0 0 |   1 0 1 0               | 1 0 0 0
 *    01   |   0 0 1 1 |   1 0 0 1               | 0 1 0 0
 *    10   |   1 1 0 0 |   0 1 1 0               | 0 0 1 0
 *    11   |   1 1 1 1 |   0 1 0 1               | 0 0 0 1
 *          (slot 0 1 2 3)
 */
`default_nettype none

// OOK / NRZ: o LED fica ligado durante todo o bit '1'
module lifi_mod_ook (
    input  wire [1:0] sym,
    input  wire [1:0] slot,
    output wire       out
);
  assign out = slot[1] ? sym[0] : sym[1];
  wire _unused = slot[0];   // em NRZ as duas metades do bit sao iguais
endmodule

// Manchester (IEEE 802.3): '1' = baixo->alto, '0' = alto->baixo a meio do bit
module lifi_mod_manchester (
    input  wire [1:0] sym,
    input  wire [1:0] slot,
    output wire       out
);
  wire b = slot[1] ? sym[0] : sym[1];
  assign out = ~(b ^ slot[0]);
endmodule

// 4-PPM: um impulso de 1 slot na posicao igual ao valor do dibit
module lifi_mod_ppm (
    input  wire [1:0] sym,
    input  wire [1:0] slot,
    output wire       out
);
  assign out = (slot == sym);
endmodule

// Multiplexador de modulacao (00 OOK, 01 Manchester, 10 PPM, 11 reservado)
module lifi_mod_mux (
    input  wire [1:0] mode,
    input  wire       in_ook,
    input  wire       in_man,
    input  wire       in_ppm,
    input  wire       in_rsv,     // entrada reservada para uma modulacao futura
    output reg        out
);
  always @(*) begin
    case (mode)
      2'b00:   out = in_ook;
      2'b01:   out = in_man;
      2'b10:   out = in_ppm;
      default: out = in_rsv;
    endcase
  end
endmodule
