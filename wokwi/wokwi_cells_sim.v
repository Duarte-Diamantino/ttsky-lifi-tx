/*
 * wokwi_cells_sim.v - Modelos de simulacao das celulas Wokwi suportadas pelo
 * fluxo Tiny Tapeout (mesma semantica do src/cells.v do ttsky-wokwi-template):
 *   mux: out = sel ? b : a      dffr: reset assincrono ativo-alto (R) -> Q=0
 * Usado apenas por 'make wokwi' para verificar o diagram.json contra o RTL.
 */
`default_nettype none

module w_buf  (input wire in, output wire out);           assign out = in;          endmodule
module w_not  (input wire in, output wire out);           assign out = ~in;         endmodule
module w_and2 (input wire a, input wire b, output wire out); assign out = a & b;    endmodule
module w_or2  (input wire a, input wire b, output wire out); assign out = a | b;    endmodule
module w_xor2 (input wire a, input wire b, output wire out); assign out = a ^ b;    endmodule
module w_nand2(input wire a, input wire b, output wire out); assign out = ~(a & b); endmodule
module w_nor2 (input wire a, input wire b, output wire out); assign out = ~(a | b); endmodule
module w_xnor2(input wire a, input wire b, output wire out); assign out = ~(a ^ b); endmodule

module w_mux2 (input wire a, input wire b, input wire sel, output wire out);
  assign out = sel ? b : a;
endmodule

module w_dff (input wire clk, input wire d, output reg q, output wire notq);
  always @(posedge clk) q <= d;
  assign notq = ~q;
endmodule

module w_dffr (input wire clk, input wire d, input wire r, output reg q, output wire notq);
  always @(posedge clk or posedge r)
    if (r) q <= 1'b0;
    else   q <= d;
  assign notq = ~q;
endmodule

module w_dffsr (input wire clk, input wire d, input wire s, input wire r, output reg q, output wire notq);
  always @(posedge clk or posedge s or posedge r)
    if (r)      q <= 1'b0;
    else if (s) q <= 1'b1;
    else        q <= d;
  assign notq = ~q;
endmodule

// -----------------------------------------------------------------------------
// Os mesmos modelos com os nomes usados pela exportacao Verilog da Wokwi
// (https://wokwi.com/api/projects/<id>/verilog) e pelo src/cells.v do TT.
// Usados por 'make wokwi-export'.
// -----------------------------------------------------------------------------
module buffer_cell(input wire in, output wire out);          assign out = in;          endmodule
module not_cell   (input wire in, output wire out);          assign out = ~in;         endmodule
module and_cell   (input wire a, input wire b, output wire out); assign out = a & b;    endmodule
module or_cell    (input wire a, input wire b, output wire out); assign out = a | b;    endmodule
module xor_cell   (input wire a, input wire b, output wire out); assign out = a ^ b;    endmodule
module nand_cell  (input wire a, input wire b, output wire out); assign out = ~(a & b); endmodule
module nor_cell   (input wire a, input wire b, output wire out); assign out = ~(a | b); endmodule
module xnor_cell  (input wire a, input wire b, output wire out); assign out = ~(a ^ b); endmodule

module mux_cell (input wire a, input wire b, input wire sel, output wire out);
  assign out = sel ? b : a;
endmodule

module dff_cell (input wire clk, input wire d, output reg q, output wire notq);
  always @(posedge clk) q <= d;
  assign notq = ~q;
endmodule

module dffr_cell (input wire clk, input wire d, input wire r, output reg q, output wire notq);
  always @(posedge clk or posedge r)
    if (r) q <= 1'b0;
    else   q <= d;
  assign notq = ~q;
endmodule

module dffsr_cell (input wire clk, input wire d, input wire s, input wire r, output reg q, output wire notq);
  always @(posedge clk or posedge s or posedge r)
    if (r)      q <= 1'b0;
    else if (s) q <= 1'b1;
    else        q <= d;
  assign notq = ~q;
endmodule
