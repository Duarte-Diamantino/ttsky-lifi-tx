/*
 * Copyright (c) 2026 Duarte Diamantino
 * SPDX-License-Identifier: Apache-2.0
 *
 * lifi_input_if - Interface de entrada do transmissor LiFi
 *
 *  - Sincroniza o sinal assincrono LOAD (2 FF) e deteta o flanco ascendente.
 *  - Registo de entrada (holding register) de 8 bits + configuracao do byte
 *    (modo, velocidade, LAST), capturados em conjunto no flanco de LOAD.
 *  - Mecanismo anti-perda de dados: se o registo estiver ocupado (READY=0)
 *    ou se o modo pedido for o reservado (11), o LOAD e REJEITADO, o byte
 *    guardado nao e sobrescrito e ERR fica a 1. Um LOAD aceite limpa ERR.
 *
 * Requisito para o anfitriao: DATA/MODE/SPEED/LAST estaveis enquanto LOAD=1
 * e LOAD=1 durante pelo menos 4 ciclos de clk.
 */
`default_nettype none

module lifi_input_if (
    input  wire       clk,
    input  wire       rst_n,
    // pinos (assincronos)
    input  wire [7:0] data_in,
    input  wire [1:0] mode_in,
    input  wire [2:0] speed_in,
    input  wire       last_in,
    input  wire       load_in,
    // controlo vindo da FSM
    input  wire       consume,     // a FSM retirou o byte do registo
    // registo de entrada
    output reg        hold_valid,
    output reg  [7:0] hold_data,
    output reg  [1:0] hold_mode,
    output reg  [2:0] hold_speed,
    output reg        hold_last,
    // estado
    output wire       accept,      // impulso: LOAD aceite
    output reg        err          // ultimo LOAD rejeitado
);

  // Sincronizador de 2 andares + andar extra para detecao de flanco
  reg [2:0] load_sync;
  always @(posedge clk) begin
    if (!rst_n) load_sync <= 3'b000;
    else        load_sync <= {load_sync[1:0], load_in};
  end

  wire load_rise = load_sync[1] & ~load_sync[2];
  wire mode_rsv  = (mode_in == 2'b11);          // modo reservado

  assign accept  = load_rise & ~hold_valid & ~mode_rsv;
  wire   reject  = load_rise & ( hold_valid |  mode_rsv);

  always @(posedge clk) begin
    if (!rst_n) begin
      hold_valid <= 1'b0;
      hold_data  <= 8'h00;
      hold_mode  <= 2'b00;
      hold_speed <= 3'b000;
      hold_last  <= 1'b0;
      err        <= 1'b0;
    end else begin
      if (accept) begin
        hold_valid <= 1'b1;
        hold_data  <= data_in;
        hold_mode  <= mode_in;
        hold_speed <= speed_in;
        hold_last  <= last_in;
        err        <= 1'b0;
      end else if (consume) begin
        hold_valid <= 1'b0;
      end
      if (reject) err <= 1'b1;
    end
  end

endmodule
