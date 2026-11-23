/*
 * tb_modulators - Teste unitario exaustivo dos moduladores e do mux
 * (Fase 1: OOK de um bit, Fase 3: Manchester, Fase 4: PPM)
 *
 * Compara cada modulador com tabelas de referencia escritas a mao
 * (independentes das expressoes do RTL), para todos os dibits e slots.
 */
`timescale 1ns / 1ps
`default_nettype none

module tb_modulators;

  reg  [1:0] sym, slot, mode;
  wire       o_ook, o_man, o_ppm, o_mux;

  lifi_mod_ook        u_ook (.sym(sym), .slot(slot), .out(o_ook));
  lifi_mod_manchester u_man (.sym(sym), .slot(slot), .out(o_man));
  lifi_mod_ppm        u_ppm (.sym(sym), .slot(slot), .out(o_ppm));
  lifi_mod_mux        u_mux (.mode(mode), .in_ook(o_ook), .in_man(o_man),
                             .in_ppm(o_ppm), .in_rsv(1'b0), .out(o_mux));

  // Tabelas de referencia: forma de onda dos 4 slots (slot0 = bit 3 da string)
  //                         dibit:   00       01       10       11
  reg [3:0] REF_OOK [0:3];
  reg [3:0] REF_MAN [0:3];
  reg [3:0] REF_PPM [0:3];

  integer errors = 0, checks = 0, d, s, m;
  reg exp_v;

  initial begin
    // OOK/NRZ: bit '1' = LED ligado durante o bit inteiro (2 slots)
    REF_OOK[0] = 4'b0000; REF_OOK[1] = 4'b0011; REF_OOK[2] = 4'b1100; REF_OOK[3] = 4'b1111;
    // Manchester IEEE 802.3: '0' = 10 (alto->baixo), '1' = 01 (baixo->alto)
    REF_MAN[0] = 4'b1010; REF_MAN[1] = 4'b1001; REF_MAN[2] = 4'b0110; REF_MAN[3] = 4'b0101;
    // 4-PPM: impulso no slot com indice = valor do dibit
    REF_PPM[0] = 4'b1000; REF_PPM[1] = 4'b0100; REF_PPM[2] = 4'b0010; REF_PPM[3] = 4'b0001;

    $dumpfile("waves/tb_modulators.vcd");
    $dumpvars(0, tb_modulators);

    // ---- Fase 1: OOK de um unico bit (bit '1' isolado e bit '0' isolado) ----
    for (s = 0; s < 4; s = s + 1) begin
      sym = 2'b10; slot = s[1:0]; mode = 2'b00; #10;      // bit '1' seguido de '0'
      exp_v = (s < 2);
      checks = checks + 1;
      if (o_ook !== exp_v) begin errors = errors + 1; $display("ERRO F1 OOK slot %0d: %b", s, o_ook); end
    end

    // ---- Exaustivo: 4 dibits x 4 slots x 4 modos ----
    for (m = 0; m < 4; m = m + 1)
      for (d = 0; d < 4; d = d + 1)
        for (s = 0; s < 4; s = s + 1) begin
          mode = m[1:0]; sym = d[1:0]; slot = s[1:0];
          #10;
          case (m)
            0: exp_v = REF_OOK[d][3-s];
            1: exp_v = REF_MAN[d][3-s];
            2: exp_v = REF_PPM[d][3-s];
            default: exp_v = 1'b0;            // reservado: LED apagado
          endcase
          checks = checks + 1;
          if (o_mux !== exp_v) begin
            errors = errors + 1;
            $display("ERRO modo=%0d dibit=%b slot=%0d: obtido %b esperado %b", m, d[1:0], s, o_mux, exp_v);
          end
        end

    // ---- Propriedades: PPM = exatamente 1 impulso por simbolo; Manchester = 1 transicao a meio de cada bit ----
    for (d = 0; d < 4; d = d + 1) begin
      checks = checks + 2;
      if ((REF_PPM[d][3] + REF_PPM[d][2] + REF_PPM[d][1] + REF_PPM[d][0]) != 1) errors = errors + 1;
      if ((REF_MAN[d][3] == REF_MAN[d][2]) || (REF_MAN[d][1] == REF_MAN[d][0])) errors = errors + 1;
    end

    if (errors == 0) $display("tb_modulators: PASS (%0d verificacoes)", checks);
    else             $fatal(1, "tb_modulators: FAIL (%0d erros em %0d verificacoes)", errors, checks);
    $finish;
  end

endmodule
