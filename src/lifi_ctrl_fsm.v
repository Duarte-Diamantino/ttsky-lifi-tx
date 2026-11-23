/*
 * Copyright (c) 2026 Duarte Diamantino
 * SPDX-License-Identifier: Apache-2.0
 *
 * lifi_ctrl_fsm - Maquina de estados de controlo da transmissao + enquadramento
 *
 * Trama (em bits, MSB primeiro; 1 simbolo = 1 dibit = 2 bits = 4 slots):
 *
 *   | PREAMBULO 16 b | SFD 8 b  | BYTE 8 b | CTRL 2 b | BYTE | CTRL | ... | GAP 4 b |
 *   | 1010...10      | 10101011 | d7..d0   | M ~M     |      |      |     | (idle)  |
 *     8 simbolos       4 simb.    4 simb.    1 simb.                       2 simb.
 *
 *   CTRL = 10 -> segue-se outro byte na mesma trama (M=1)
 *   CTRL = 01 -> ultimo byte da trama (M=0); depois vem o GAP (LED apagado)
 *
 * M = 1 quando, no inicio do simbolo CTRL, ha um byte a espera no registo de
 * entrada, o byte atual nao foi marcado com LAST e o byte seguinte tem a
 * mesma configuracao (modo e velocidade). Caso contrario a trama fecha e o
 * byte seguinte (se existir) abre uma nova trama com a sua configuracao.
 *
 * A configuracao (modo/velocidade) e fixada no inicio de cada trama: mudar
 * os pinos durante a transmissao nunca corrompe a trama em curso.
 */
`default_nettype none

module lifi_ctrl_fsm (
    input  wire       clk,
    input  wire       rst_n,
    // registo de entrada
    input  wire       hold_valid,
    input  wire [1:0] hold_mode,
    input  wire [2:0] hold_speed,
    input  wire       hold_last,
    input  wire       accept,       // LOAD aceite (limpa DONE)
    output wire       consume,      // retira o byte do registo de entrada
    // temporizacao
    input  wire       sym_end,
    output wire       run,          // ativa divisor e temporizador de simbolos
    // registo de deslocamento
    input  wire [1:0] sr_dibit,
    output wire       sr_load,
    output wire       sr_shift,
    // para os moduladores
    output reg  [1:0] sym,          // dibit a modular no simbolo atual
    output wire       on_air,       // LED ativo (preambulo .. CTRL)
    output reg  [1:0] mode_q,       // modo da trama atual
    output reg  [2:0] speed_q,      // velocidade da trama atual
    // estado
    output wire       sync,         // preambulo ou SFD
    output reg        done,         // transmissao concluida (sticky)
    output reg  [2:0] state
);

  localparam [2:0] S_IDLE = 3'd0,
                   S_PRE  = 3'd1,
                   S_SFD  = 3'd2,
                   S_DATA = 3'd3,
                   S_CTRL = 3'd4,
                   S_GAP  = 3'd5;

  localparam [2:0] PRE_LAST  = 3'd7;   // 8 simbolos "10"  = 16 bits
  localparam [2:0] SFD_LAST  = 3'd3;   // 4 simbolos       =  8 bits
  localparam [2:0] DATA_LAST = 3'd3;   // 4 simbolos       =  8 bits
  localparam [2:0] GAP_LAST  = 3'd1;   // 2 simbolos       =  4 bits

  reg [2:0] cnt;        // contador de simbolos dentro da seccao
  reg       cur_last;   // o byte em transmissao foi marcado com LAST
  reg       more_q;     // decisao M tomada no inicio do simbolo CTRL

  wire start     = (state == S_IDLE) & hold_valid;
  wire cfg_match = (hold_mode == mode_q) & (hold_speed == speed_q);
  wire more_now  = hold_valid & ~cur_last & cfg_match;
  wire next_byte = (state == S_CTRL) & sym_end & more_q;

  assign consume  = start | next_byte;
  assign sr_load  = consume;
  assign sr_shift = (state == S_DATA) & sym_end;
  assign run      = (state != S_IDLE);
  assign on_air   = (state == S_PRE) | (state == S_SFD) |
                    (state == S_DATA) | (state == S_CTRL);
  assign sync     = (state == S_PRE) | (state == S_SFD);

  // Fonte de simbolos (bits de enquadramento ou dados)
  always @(*) begin
    case (state)
      S_PRE:   sym = 2'b10;
      S_SFD:   sym = (cnt == SFD_LAST) ? 2'b11 : 2'b10;
      S_DATA:  sym = sr_dibit;
      S_CTRL:  sym = {more_q, ~more_q};
      default: sym = 2'b00;
    endcase
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      state    <= S_IDLE;
      cnt      <= 3'd0;
      mode_q   <= 2'b00;
      speed_q  <= 3'd0;
      cur_last <= 1'b0;
      more_q   <= 1'b0;
      done     <= 1'b0;
    end else begin
      case (state)
        S_IDLE: begin
          cnt <= 3'd0;
          if (hold_valid) begin
            state    <= S_PRE;
            mode_q   <= hold_mode;
            speed_q  <= hold_speed;
            cur_last <= hold_last;
          end
        end

        S_PRE: if (sym_end) begin
          if (cnt == PRE_LAST) begin state <= S_SFD; cnt <= 3'd0; end
          else cnt <= cnt + 3'd1;
        end

        S_SFD: if (sym_end) begin
          if (cnt == SFD_LAST) begin state <= S_DATA; cnt <= 3'd0; end
          else cnt <= cnt + 3'd1;
        end

        S_DATA: if (sym_end) begin
          if (cnt == DATA_LAST) begin
            state  <= S_CTRL;
            cnt    <= 3'd0;
            more_q <= more_now;
          end else cnt <= cnt + 3'd1;
        end

        S_CTRL: if (sym_end) begin
          cnt <= 3'd0;
          if (more_q) begin
            state    <= S_DATA;
            cur_last <= hold_last;
          end else begin
            state    <= S_GAP;
          end
        end

        S_GAP: if (sym_end) begin
          if (cnt == GAP_LAST) begin
            state <= S_IDLE;
            cnt   <= 3'd0;
            if (!hold_valid) done <= 1'b1;
          end else cnt <= cnt + 3'd1;
        end

        default: begin
          state <= S_IDLE;
          cnt   <= 3'd0;
        end
      endcase

      if (accept) done <= 1'b0;
    end
  end

endmodule
