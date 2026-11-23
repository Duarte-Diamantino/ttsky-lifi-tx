/*
 * Copyright (c) 2026 Duarte Diamantino
 * SPDX-License-Identifier: Apache-2.0
 *
 * lifi_tx_core - Nucleo do transmissor LiFi reconfiguravel
 *
 *   pinos -> lifi_input_if -> lifi_ctrl_fsm -> moduladores -> mux -> reg. saida
 *                                |  ^   |
 *              lifi_clkdiv -> lifi_symtimer   lifi_shiftreg
 *
 * Todas as saidas sao registadas (sem glitches) e alinhadas entre si:
 * o 1o slot de cada trama aparece no LED no mesmo ciclo em que BUSY sobe.
 */
`default_nettype none

module lifi_tx_core (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,
    input  wire [1:0] mode_in,
    input  wire       load_in,
    input  wire [2:0] speed_in,
    input  wire       last_in,
    output reg        led,       // saida modulada (1 = LED ligado)
    output wire       led_n,     // saida modulada invertida
    output reg        busy,      // trama em curso (inclui GAP)
    output reg        ready,     // registo de entrada livre
    output reg        done,      // transmissao concluida
    output reg        err,       // ultimo LOAD rejeitado
    output reg        bit_clk,   // 1 na 1a metade de cada bit (diagnostico)
    output reg        sync,      // preambulo/SFD (diagnostico)
    output reg        tx_bit     // bit NRZ atual (diagnostico)
);

  // ---------------- registo de entrada ----------------
  wire       hold_valid, hold_last, accept, consume, err_c, done_c;
  wire [7:0] hold_data;
  wire [1:0] hold_mode;
  wire [2:0] hold_speed;

  lifi_input_if u_in (
      .clk(clk), .rst_n(rst_n),
      .data_in(data_in), .mode_in(mode_in), .speed_in(speed_in),
      .last_in(last_in), .load_in(load_in),
      .consume(consume),
      .hold_valid(hold_valid), .hold_data(hold_data), .hold_mode(hold_mode),
      .hold_speed(hold_speed), .hold_last(hold_last),
      .accept(accept), .err(err_c)
  );

  // ---------------- temporizacao ----------------
  wire       run, tick, sym_end;
  wire [1:0] slot;
  wire [2:0] speed_q;

  lifi_clkdiv u_div (
      .clk(clk), .rst_n(rst_n), .run(run), .speed(speed_q), .tick(tick)
  );

  lifi_symtimer u_sym (
      .clk(clk), .rst_n(rst_n), .run(run), .tick(tick),
      .slot(slot), .sym_end(sym_end)
  );

  // ---------------- registo de deslocamento ----------------
  wire       sr_load, sr_shift;
  wire [1:0] sr_dibit;

  lifi_shiftreg u_sr (
      .clk(clk), .rst_n(rst_n), .load(sr_load), .din(hold_data),
      .shift(sr_shift), .dibit(sr_dibit)
  );

  // ---------------- controlo / enquadramento ----------------
  wire [1:0] sym, mode_q;
  wire       on_air, sync_c;
  wire [2:0] state;

  lifi_ctrl_fsm u_fsm (
      .clk(clk), .rst_n(rst_n),
      .hold_valid(hold_valid), .hold_mode(hold_mode), .hold_speed(hold_speed),
      .hold_last(hold_last), .accept(accept), .consume(consume),
      .sym_end(sym_end), .run(run),
      .sr_dibit(sr_dibit), .sr_load(sr_load), .sr_shift(sr_shift),
      .sym(sym), .on_air(on_air), .mode_q(mode_q), .speed_q(speed_q),
      .sync(sync_c), .done(done_c), .state(state)
  );

  // ---------------- moduladores + multiplexador ----------------
  wire m_ook, m_man, m_ppm, m_sel;

  lifi_mod_ook        u_ook (.sym(sym), .slot(slot), .out(m_ook));
  lifi_mod_manchester u_man (.sym(sym), .slot(slot), .out(m_man));
  lifi_mod_ppm        u_ppm (.sym(sym), .slot(slot), .out(m_ppm));

  lifi_mod_mux u_mux (
      .mode(mode_q), .in_ook(m_ook), .in_man(m_man), .in_ppm(m_ppm),
      .in_rsv(1'b0), .out(m_sel)
  );

  wire nrz_bit = slot[1] ? sym[0] : sym[1];

  // ---------------- registo de saida ----------------
  always @(posedge clk) begin
    if (!rst_n) begin
      led     <= 1'b0;
      busy    <= 1'b0;
      ready   <= 1'b0;
      done    <= 1'b0;
      err     <= 1'b0;
      bit_clk <= 1'b0;
      sync    <= 1'b0;
      tx_bit  <= 1'b0;
    end else begin
      led     <= on_air & m_sel;
      busy    <= run;
      ready   <= ~hold_valid;
      done    <= done_c;
      err     <= err_c;
      bit_clk <= on_air & ~slot[0];
      sync    <= sync_c;
      tx_bit  <= on_air & nrz_bit;
    end
  end

  assign led_n = ~led;

  wire _unused = &{state, 1'b0};

endmodule
