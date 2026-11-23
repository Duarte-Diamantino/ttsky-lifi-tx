/* Automatically generated from https://wokwi.com/projects/481391130244247553 */

`default_nettype none

// verilator lint_off UNUSEDSIGNAL
// verilator lint_off PINCONNECTEMPTY

module tt_um_wokwi_481391130244247553(
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,    // Dedicated outputs
  input  wire [7:0] uio_in,    // IOs: Input path
  output wire [7:0] uio_out,    // IOs: Output path
  output wire [7:0] uio_oe,    // IOs: Enable path (active high: 0=input, 1=output)
  input ena,
  input clk,
  input rst_n
);
  wire net1 = clk;
  wire net2 = rst_n;
  wire net3 = ui_in[0];
  wire net4 = ui_in[1];
  wire net5 = ui_in[2];
  wire net6 = ui_in[3];
  wire net7;
  wire net8;
  wire net9;
  wire net10;
  wire net11;
  wire net12;
  wire net13;
  wire net14 = 1'b1;
  wire net15 = 1'b1;
  wire net16 = 1'b0;
  wire net17 = 1'b1;
  wire net18 = 1'b0;
  wire net19;
  wire net20;
  wire net21;
  wire net22;
  wire net23;
  wire net24;
  wire net25;
  wire net26 = 1'b0;
  wire net27;
  wire net28;
  wire net29 = 1'b0;
  wire net30 = 1'b0;

  assign uo_out[0] = net7;
  assign uo_out[1] = net8;
  assign uo_out[2] = net9;
  assign uo_out[3] = net10;
  assign uo_out[4] = 0;
  assign uo_out[5] = net11;
  assign uo_out[6] = net12;
  assign uo_out[7] = net13;
  assign uio_out[0] = 0;
  assign uio_oe[0] = 0;
  assign uio_out[1] = 0;
  assign uio_oe[1] = 0;
  assign uio_out[2] = 0;
  assign uio_oe[2] = 0;
  assign uio_out[3] = 0;
  assign uio_oe[3] = 0;
  assign uio_out[4] = 0;
  assign uio_oe[4] = 0;
  assign uio_out[5] = 0;
  assign uio_oe[5] = 0;
  assign uio_out[6] = 0;
  assign uio_oe[6] = 0;
  assign uio_out[7] = 0;
  assign uio_oe[7] = 0;

  not_cell notR (
    .in (net2),
    .out (net19)
  );
  dffr_cell ff0 (
    .d (net20),
    .clk (net1),
    .r (net19),
    .q (net8),
    .notq (net20)
  );
  xor_cell x1 (
    .a (net8),
    .b (net9),
    .out (net21)
  );
  dffr_cell ff1 (
    .d (net21),
    .clk (net1),
    .r (net19),
    .q (net9),
    .notq ()
  );
  not_cell notB (
    .in (net8),
    .out (net11)
  );
  nor_cell norS (
    .a (net8),
    .b (net9),
    .out (net12)
  );
  mux_cell mxb (
    .a (net4),
    .b (net3),
    .sel (net9),
    .out (net10)
  );
  xnor_cell xman (
    .a (net10),
    .b (net8),
    .out (net22)
  );
  xnor_cell xp1 (
    .a (net9),
    .b (net4),
    .out (net23)
  );
  xnor_cell xp0 (
    .a (net8),
    .b (net3),
    .out (net24)
  );
  and_cell andp (
    .a (net23),
    .b (net24),
    .out (net25)
  );
  mux_cell mx0 (
    .a (net10),
    .b (net22),
    .sel (net5),
    .out (net27)
  );
  mux_cell mx1 (
    .a (net25),
    .b (net26),
    .sel (net5),
    .out (net28)
  );
  mux_cell mx2 (
    .a (net27),
    .b (net28),
    .sel (net6),
    .out (net7)
  );
  not_cell notL (
    .in (net7),
    .out (net13)
  );
endmodule
