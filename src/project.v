/*
 * Copyright (c) 2026 Duarte Diamantino
 * SPDX-License-Identifier: Apache-2.0
 *
 * tt_um_duarte_diamantino_lifi_tx - Transmissor LiFi digital reconfiguravel (OOK / Manchester / 4-PPM)
 * Wrapper Tiny Tapeout: mapeamento de pinos e output enables.
 *
 * O nome do topo e unico (inclui o utilizador GitHub): o mesmo nome esta em
 *       info.yaml (top_module), test/tb.v, sim/tb_lifi_tx.v, sim/tb_waves.v
 *       e no Makefile (TOP).
 *
 *  ui_in[7:0]  DATA[7:0]   byte a transmitir (binario arbitrario)
 *  uio[1:0]    MODE[1:0]   in : 00 OOK, 01 Manchester, 10 4-PPM, 11 reservado
 *  uio[2]      LOAD        in : flanco ascendente carrega DATA+config
 *  uio[5:3]    SPEED[2:0]  in : R_b = f_clk / 4^(SPEED+1)
 *  uio[6]      LAST        in : 1 = este byte fecha a trama
 *  uio[7]      TX_BIT      out: bit NRZ atual (diagnostico)
 *  uo[0]       LED         modulado, para o driver externo do LED
 *  uo[1]       BUSY        trama em curso
 *  uo[2]       READY       registo de entrada livre (pode fazer LOAD)
 *  uo[3]       DONE        tudo transmitido (limpa no proximo LOAD aceite)
 *  uo[4]       ERR         ultimo LOAD rejeitado (ocupado ou modo 11)
 *  uo[5]       BIT_CLK     1 na 1a metade de cada bit (diagnostico)
 *  uo[6]       SYNC        preambulo/SFD em curso (diagnostico)
 *  uo[7]       LED_N       LED invertido (driver ativo-baixo / I-PPM)
 */
`default_nettype none

module tt_um_duarte_diamantino_lifi_tx (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  wire led, led_n, busy, ready, done, err, bit_clk, sync, tx_bit;

  lifi_tx_core u_core (
      .clk     (clk),
      .rst_n   (rst_n),
      .data_in (ui_in),
      .mode_in (uio_in[1:0]),
      .load_in (uio_in[2]),
      .speed_in(uio_in[5:3]),
      .last_in (uio_in[6]),
      .led     (led),
      .led_n   (led_n),
      .busy    (busy),
      .ready   (ready),
      .done    (done),
      .err     (err),
      .bit_clk (bit_clk),
      .sync    (sync),
      .tx_bit  (tx_bit)
  );

  assign uo_out  = {led_n, sync, bit_clk, err, done, ready, busy, led};
  assign uio_out = {tx_bit, 7'b0000000};
  assign uio_oe  = 8'b1000_0000;   // uio[6:0] entradas, uio[7] saida

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, uio_in[7], 1'b0};

endmodule
