/*
 * tb_lifi_tx - Testbench de sistema, automatico e auto-verificavel
 *
 * Usa APENAS os pinos do tt_um_duarte_diamantino_lifi_tx (serve tambem para simulacao
 * pos-sintese). Contem:
 *   - um "anfitriao" que carrega bytes pelo protocolo LOAD/READY;
 *   - um RECETOR de referencia que so observa o LED (e conhece o modo e a
 *     velocidade combinados), deteta o preambulo/SFD, descodifica os bytes,
 *     os bits de controlo e o fim de trama, e verifica a temporizacao ciclo
 *     a ciclo (cada slot tem de durar exatamente N_slot ciclos);
 *   - verificacoes de BUSY, READY, DONE, ERR, SYNC, BIT_CLK, TX_BIT, LED_N.
 *
 * Testes: reset, Fases 1-8 (OOK 1 bit, bytes, Manchester, PPM, velocidades,
 * enquadramento, mudanca de modo, busy/overrun/modo reservado), reset a meio
 * da trama, 256 valores por modo e teste aleatorio.
 *
 * Opcoes: +seed=<n> (aleatorio), +fast (salta SPEED 5..7)
 */
`timescale 1ns / 1ps
`default_nettype none

module tb_lifi_tx;

  // ================================================================ DUT
  reg        clk    = 1'b0;
  reg        rst_n  = 1'b0;
  reg        ena    = 1'b1;
  reg  [7:0] ui_in  = 8'h00;
  reg  [7:0] uio_in = 8'h00;
  wire [7:0] uo_out, uio_out, uio_oe;

  tt_um_duarte_diamantino_lifi_tx dut (
      .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out),
      .uio_oe(uio_oe), .ena(ena), .clk(clk), .rst_n(rst_n)
  );

  always #50 clk = ~clk;   // 10 MHz

  wire LED    = uo_out[0];
  wire BUSY   = uo_out[1];
  wire READY  = uo_out[2];
  wire DONE   = uo_out[3];
  wire ERR    = uo_out[4];
  wire BITCLK = uo_out[5];
  wire SYNC   = uo_out[6];
  wire LED_N  = uo_out[7];
  wire TXBIT  = uio_out[7];

  localparam [1:0] M_OOK = 2'd0, M_MAN = 2'd1, M_PPM = 2'd2, M_RSV = 2'd3;
  localparam integer TIMEOUT = 6000000;

  reg [8*40:1] test_name = "reset";   // visivel no GTKWave (formato ASCII)

  // ================================================================ tempo e historico
  integer cyc = 0;
  always @(posedge clk) cyc <= cyc + 1;

  // historico das saidas (o recetor pode "olhar para tras" ate 2^17 ciclos)
  localparam integer HN = 131072;
  reg [8:0] hist [0:HN-1];
  always @(negedge clk) hist[cyc % HN] <= {TXBIT, uo_out};

  // Amostra das saidas no ciclo c (le historico ou espera pelo ciclo)
  // Bits: [8]=TX_BIT [7]=LED_N [6]=SYNC [5]=BIT_CLK [4]=ERR [3]=DONE [2]=READY [1]=BUSY [0]=LED
  task automatic get_sample(input integer c, output [8:0] v);
    begin
      if (c < cyc) v = hist[c % HN];
      else begin
        while (cyc < c) @(negedge clk);
        v = {TXBIT, uo_out};
      end
    end
  endtask

  // ================================================================ erros
  integer errors = 0;
  task automatic fail(input [8*72:1] msg);
    begin
      errors = errors + 1;
      $display("[%0t] ERRO (%0s): %0s", $time, test_name, msg);
      if (errors > 30) $fatal(1, "Demasiados erros - abortado");
    end
  endtask

  // ================================================================ scoreboard
  localparam integer QD = 4096;
  reg [13:0] expq [0:QD-1];       // {last, speed[2:0], mode[1:0], data[7:0]}
  integer q_wr = 0, q_rd = 0;

  task push_exp(input [7:0] d, input [1:0] m, input [2:0] s, input l);
    begin
      expq[q_wr % QD] = {l, s, m, d};
      q_wr = q_wr + 1;
    end
  endtask

  // ================================================================ recetor de referencia
  integer rx_frames = 0, rx_bytes = 0;
  integer fr_size [0:4095];
  integer k_r, f_start, f_end, N, off, symi, nb, bi;
  reg [1:0] f_mode;
  reg [2:0] f_speed;
  reg [13:0] ent;
  reg [3:0] wav, tbw;
  reg [2:0] dec;
  reg [7:0] rbyte;
  reg [8:0] v;
  reg       more;

  // Le um simbolo (4 slots) da trama atual e verifica os sinais auxiliares
  task automatic read_symbol(input integer si, input onair, output [3:0] w, output [3:0] tb);
    integer jj, cc, base;
    reg [8:0] vv, first;
    begin
      for (jj = 0; jj < 4; jj = jj + 1) begin
        base = f_start + (si * 4 + jj) * N;
        for (cc = base; cc < base + N; cc = cc + 1) begin
          get_sample(cc, vv);
          if (cc == base) first = vv;
          else if ((vv & 9'h1E3) !== (first & 9'h1E3)) fail("saida nao constante dentro de um slot");
          if (vv[1] !== 1'b1) fail("BUSY caiu durante a trama");
          if (vv[6] !== (onair && si < 12)) fail("SYNC incorreto");
          if (vv[5] !== (onair && (jj % 2 == 0))) fail("BIT_CLK incorreto");
          if (!onair && (vv[0] !== 1'b0 || vv[8] !== 1'b0)) fail("LED/TX_BIT ativos no GAP");
        end
        w[3 - jj]  = first[0];
        tb[3 - jj] = first[8];
      end
    end
  endtask

  // Desmodula um simbolo: devolve {valido, dibit}
  function [2:0] demod(input [1:0] m, input [3:0] w);
    begin
      case (m)
        M_OOK: demod = {(w[3] == w[2]) && (w[1] == w[0]), w[3], w[1]};
        M_MAN: demod = {(w[3] != w[2]) && (w[1] != w[0]), w[2], w[0]};
        M_PPM: case (w)
                 4'b1000: demod = 3'b100;
                 4'b0100: demod = 3'b101;
                 4'b0010: demod = 3'b110;
                 4'b0001: demod = 3'b111;
                 default: demod = 3'b000;
               endcase
        default: demod = 3'b000;
      endcase
    end
  endfunction

  task automatic rx_symbol(input integer si, output [1:0] dib);
    reg [3:0] w, tb;
    reg [2:0] d;
    begin
      read_symbol(si, 1'b1, w, tb);
      d = demod(f_mode, w);
      if (!d[2]) fail("simbolo invalido para o modo (violacao de codigo)");
      if (tb !== {d[1], d[1], d[0], d[0]}) fail("TX_BIT nao corresponde ao bit transmitido");
      dib = d[1:0];
    end
  endtask

  reg [1:0] dib;
  initial begin : RX_LOOP
    forever begin : RX_FRAME
      // ---- 1) linha em repouso -> primeiro '1' no LED
      @(negedge clk);
      while (LED !== 1'b1) @(negedge clk);
      k_r = cyc;
      if (q_rd == q_wr) begin
        fail("trama inesperada (nenhum byte pendente)");
        while (BUSY === 1'b1) @(negedge clk);
        disable RX_FRAME;
      end
      ent     = expq[q_rd % QD];
      f_mode  = ent[9:8];
      f_speed = ent[12:10];
      N       = 2 << (2 * f_speed);
      // o preambulo comeca com o bit '1': OOK sobe no slot 0, Manchester no 1, PPM no 2
      off     = (f_mode == M_OOK) ? 0 : (f_mode == M_MAN) ? 1 : 2;
      f_start = k_r - off * N;
      get_sample(f_start - 1, v); if (v[1] !== 1'b0) fail("BUSY ja estava ativo antes da trama");
      get_sample(f_start, v);     if (v[1] !== 1'b1) fail("BUSY nao alinhado com o 1o slot");
      // ---- 2) preambulo (8 x '10') + SFD (10 10 10 11)
      for (symi = 0; symi < 12; symi = symi + 1) begin
        rx_symbol(symi, dib);
        if (dib !== ((symi == 11) ? 2'b11 : 2'b10)) fail("preambulo/SFD incorreto");
      end
      // ---- 3) bytes + controlo
      nb = 0; more = 1'b1;
      while (more) begin
        rbyte = 8'h00;
        for (bi = 0; bi < 4; bi = bi + 1) begin
          rx_symbol(symi, dib); symi = symi + 1;
          rbyte = {rbyte[5:0], dib};
        end
        rx_symbol(symi, dib); symi = symi + 1;
        if (dib == 2'b10)      more = 1'b1;
        else if (dib == 2'b01) more = 1'b0;
        else begin fail("bits de controlo invalidos"); more = 1'b0; end
        if (q_rd == q_wr) fail("byte recebido a mais");
        else begin
          ent  = expq[q_rd % QD];
          q_rd = q_rd + 1;
          if (ent[7:0] !== rbyte) begin
            $display("        recebido %02h, esperado %02h", rbyte, ent[7:0]);
            fail("byte incorreto");
          end
          if (ent[9:8] !== f_mode || ent[12:10] !== f_speed) fail("byte com outra configuracao dentro da trama");
          if (ent[13] && more) fail("byte marcado LAST nao fechou a trama");
        end
        nb = nb + 1; rx_bytes = rx_bytes + 1;
      end
      // ---- 4) GAP: 2 simbolos com o LED apagado e BUSY ativo
      read_symbol(symi, 1'b0, wav, tbw); symi = symi + 1;
      read_symbol(symi, 1'b0, wav, tbw); symi = symi + 1;
      // ---- 5) BUSY cai exatamente no fim da trama
      f_end = f_start + (14 + 5 * nb) * 4 * N;
      get_sample(f_end, v);
      if (v[1] !== 1'b0) fail("BUSY nao caiu no fim da trama");
      fr_size[rx_frames % 4096] = nb;
      rx_frames = rx_frames + 1;
    end
  end

  // ================================================================ invariantes globais
  reg  in_load = 1'b0, err_expected = 1'b0, done_d = 1'b0, err_d = 1'b0;
  always @(negedge clk) begin
    if (LED_N !== ~LED)          fail("LED_N != ~LED");
    if (uio_oe !== 8'h80)        fail("uio_oe != 0x80");
    if (uio_out[6:0] !== 7'h00)  fail("uio_out[6:0] != 0");
    if (rst_n && DONE && !done_d && !in_load) begin
      if (q_rd != q_wr) fail("DONE ativo com bytes ainda por transmitir");
      if (BUSY !== 1'b0 || READY !== 1'b1) fail("DONE sem BUSY=0 e READY=1");
    end
    if (rst_n && ERR && !err_d && !err_expected) fail("ERR inesperado");
    done_d <= DONE;
    err_d  <= ERR;
  end

  // ================================================================ anfitriao
  integer t;
  task do_load(input [7:0] d, input [1:0] m, input [2:0] s, input l, input integer hold);
    begin
      in_load = 1'b1;
      @(negedge clk);
      ui_in  = d;
      uio_in = {1'b0, l, s, 1'b0, m};
      @(negedge clk);
      uio_in[2] = 1'b1;                // LOAD
      repeat (hold) @(negedge clk);
      uio_in[2] = 1'b0;
      repeat (2) @(negedge clk);
      in_load = 1'b0;
    end
  endtask

  task send_byte(input [7:0] d, input [1:0] m, input [2:0] s, input l);
    begin
      t = 0;
      while (READY !== 1'b1) begin
        @(negedge clk); t = t + 1;
        if (t > TIMEOUT) $fatal(1, "timeout a espera de READY");
      end
      push_exp(d, m, s, l);
      do_load(d, m, s, l, 4);
      if (ERR !== 1'b0)  fail("LOAD valido mas ERR=1");
      if (DONE !== 1'b0) fail("DONE nao limpou apos LOAD aceite");
    end
  endtask

  task wait_idle;
    begin
      t = 0;
      while (!(q_rd == q_wr && DONE === 1'b1)) begin
        @(negedge clk); t = t + 1;
        if (t > TIMEOUT) $fatal(1, "timeout a espera do fim da transmissao (%0s)", test_name);
      end
      repeat (4) @(negedge clk);
      if (BUSY !== 1'b0 || READY !== 1'b1 || LED !== 1'b0) fail("estado final incorreto apos DONE");
    end
  endtask

  integer f0;
  task check_frames(input integer first, input integer n, input integer s0, input integer s1,
                    input integer s2, input integer s3);
    integer i, e;
    begin
      if (rx_frames - first != n) begin
        $display("        tramas recebidas = %0d, esperadas = %0d", rx_frames - first, n);
        fail("numero de tramas incorreto");
      end else
        for (i = 0; i < n && i < 4; i = i + 1) begin
          e = (i == 0) ? s0 : (i == 1) ? s1 : (i == 2) ? s2 : s3;
          if (fr_size[(first + i) % 4096] != e) begin
            $display("        trama %0d com %0d bytes, esperados %0d", i, fr_size[(first + i) % 4096], e);
            fail("tamanho de trama incorreto");
          end
        end
    end
  endtask

  task check_reset_outputs;
    begin
      if (LED !== 1'b0 || LED_N !== 1'b1 || BUSY !== 1'b0 || DONE !== 1'b0 || ERR !== 1'b0 ||
          BITCLK !== 1'b0 || SYNC !== 1'b0 || TXBIT !== 1'b0)
        fail("saidas incorretas durante o reset");
    end
  endtask

  // ================================================================ sequencia de testes
  reg [7:0] pat [0:7];
  integer i, m, s, seed, seed0, nbytes, dly, fast;
  reg [1:0] rm;
  reg [2:0] rs;
  reg       rl;

  initial begin
    pat[0] = 8'h00; pat[1] = 8'hFF; pat[2] = 8'hA5; pat[3] = 8'h5A;
    pat[4] = 8'h3C; pat[5] = 8'hC3; pat[6] = 8'h1B; pat[7] = 8'hE4;
    if (!$value$plusargs("seed=%d", seed)) seed = 20261122;
    seed0 = seed;
    fast = $test$plusargs("fast");

`ifdef GL_SIM
    $dumpfile("waves/tb_lifi_tx_gl.vcd");          // simulacao pos-sintese
`else
    $dumpfile("waves/tb_lifi_tx.vcd");
`endif
    $dumpvars(0, dut);
    $dumpvars(1, tb_lifi_tx);

    // ------------------------------------------------------------ RESET
    test_name = "T0 reset";
    rst_n = 1'b0;
    repeat (5) @(negedge clk);
    check_reset_outputs;
    if (READY !== 1'b0) fail("READY deve ser 0 durante o reset");
    rst_n = 1'b1;
    repeat (2) @(negedge clk);
    if (READY !== 1'b1 || DONE !== 1'b0 || ERR !== 1'b0 || BUSY !== 1'b0) fail("estado apos reset");
    $display("T0 reset ............................ ok");

    // ------------------------------------------------------------ FASE 1
    test_name = "F1 OOK um bit";
    f0 = rx_frames;
    send_byte(8'h80, M_OOK, 3'd0, 1'b1);  wait_idle;
    send_byte(8'h01, M_OOK, 3'd0, 1'b1);  wait_idle;
    check_frames(f0, 2, 1, 1, 0, 0);
    $display("F1 OOK com um unico bit ............. ok");

    // ------------------------------------------------------------ FASES 2-4
    for (m = 0; m < 3; m = m + 1) begin
      test_name = (m == 0) ? "F2 bytes OOK" : (m == 1) ? "F3 Manchester" : "F4 PPM";
      f0 = rx_frames;
      for (i = 0; i < 8; i = i + 1) send_byte(pat[i], m[1:0], 3'd1, (i == 7));
      wait_idle;
      check_frames(f0, 1, 8, 0, 0, 0);
      $display("%0s: 8 bytes numa trama ....... ok", test_name);
    end

    // ------------------------------------------------------------ 256 valores por modo
    $dumpoff;
    for (m = 0; m < 3; m = m + 1) begin
      test_name = "256 valores";
      f0 = rx_frames;
      for (i = 0; i < 256; i = i + 1) send_byte(i[7:0], m[1:0], 3'd0, (i == 255));
      wait_idle;
      check_frames(f0, 1, 256, 0, 0, 0);
    end
    $dumpon;
    $display("Todos os 256 valores x 3 modos ...... ok");

    // ------------------------------------------------------------ FASE 5: velocidades
    test_name = "F5 velocidades";
    for (s = 0; s < 8; s = s + 1) begin
      if (s == 3) $dumpoff;
      if (!(fast && s >= 5)) begin
        for (m = 0; m < 3; m = m + 1) begin
          if (s < 3 || m == (s % 3)) begin
            f0 = rx_frames;
            send_byte(8'hC0 | s[7:0], m[1:0], s[2:0], 1'b0);
            send_byte(8'h0F ^ s[7:0], m[1:0], s[2:0], 1'b1);
            wait_idle;
            check_frames(f0, 1, 2, 0, 0, 0);
            $display("F5 SPEED=%0d modo=%0d: T_bit=%0d ciclos -> %0d bit/s @10 MHz .. ok",
                     s, m, 4 << (2 * s), 10000000 / (4 << (2 * s)));
          end
        end
      end else $display("F5 SPEED=%0d: saltado (+fast)", s);
    end
    $dumpon;

    // ------------------------------------------------------------ FASE 6: enquadramento
    test_name = "F6 LAST";
    f0 = rx_frames;
    send_byte(8'h11, M_MAN, 3'd1, 1'b0);
    send_byte(8'h22, M_MAN, 3'd1, 1'b1);
    send_byte(8'h33, M_MAN, 3'd1, 1'b0);
    send_byte(8'h44, M_MAN, 3'd1, 1'b1);
    wait_idle;
    check_frames(f0, 2, 2, 2, 0, 0);
    $display("F6 LAST divide tramas [2,2] ......... ok");

    test_name = "F6 anfitriao lento";
    f0 = rx_frames;
    for (i = 0; i < 3; i = i + 1) begin
      send_byte(8'h70 + i[7:0], M_PPM, 3'd0, 1'b0);
      wait_idle;
    end
    check_frames(f0, 3, 1, 1, 1, 0);
    $display("F6 anfitriao lento: 1 byte/trama ... ok");

    test_name = "F6 byte tardio";
    f0 = rx_frames;
    send_byte(8'h96, M_OOK, 3'd2, 1'b0);
    @(negedge SYNC);                                // fim do SFD
    repeat (16 * 32 + 8) @(negedge clk);            // ja dentro do simbolo CTRL (M=0 decidido)
    send_byte(8'h69, M_OOK, 3'd2, 1'b1);
    while (BUSY !== 1'b0) @(negedge clk);           // fim da 1a trama
    if (DONE !== 1'b0) fail("DONE nao pode subir com um byte ainda pendente");
    wait_idle;
    check_frames(f0, 2, 1, 1, 0, 0);
    $display("F6 byte tardio -> nova trama, sem perda . ok");

    // ------------------------------------------------------------ FASE 7: mudanca de modo
    test_name = "F7 modo entre bytes";
    f0 = rx_frames;
    send_byte(8'hA1, M_OOK, 3'd1, 1'b0);
    send_byte(8'hA2, M_OOK, 3'd1, 1'b0);
    send_byte(8'hB1, M_MAN, 3'd1, 1'b0);
    send_byte(8'hB2, M_MAN, 3'd1, 1'b0);
    send_byte(8'hC1, M_PPM, 3'd1, 1'b0);
    send_byte(8'hC2, M_PPM, 3'd1, 1'b0);
    send_byte(8'hD1, M_PPM, 3'd2, 1'b0);            // muda so a velocidade
    send_byte(8'hD2, M_PPM, 3'd2, 1'b1);
    wait_idle;
    check_frames(f0, 4, 2, 2, 2, 2);
    $display("F7 mudanca de modo/velocidade entre bytes ok");

    test_name = "F7 pinos a mudar em BUSY";
    f0 = rx_frames;
    send_byte(8'h5E, M_MAN, 3'd2, 1'b0);
    send_byte(8'hE5, M_MAN, 3'd2, 1'b1);
    while (DONE !== 1'b1) begin                     // agitar MODE/SPEED/LAST sem LOAD
      repeat (7) @(negedge clk);
      uio_in[1:0] = $random(seed);
      uio_in[5:3] = $random(seed);
      uio_in[6]   = $random(seed);
    end
    wait_idle;
    check_frames(f0, 1, 2, 0, 0, 0);
    $display("F7 pinos alterados durante BUSY ..... ok");

    // ------------------------------------------------------------ FASE 8: busy / overrun
    test_name = "F8 overrun";
    f0 = rx_frames;
    send_byte(8'h01, M_PPM, 3'd2, 1'b0);            // vai para o shift register
    send_byte(8'h02, M_PPM, 3'd2, 1'b0);            // fica no registo de entrada
    if (READY !== 1'b0) fail("READY devia ser 0 com o registo cheio");
    err_expected = 1'b1;
    do_load(8'hEE, M_PPM, 3'd2, 1'b0, 4);           // LOAD ilegal: tem de ser rejeitado
    if (ERR !== 1'b1) fail("ERR nao assinalou o LOAD rejeitado");
    err_expected = 1'b0;
    send_byte(8'h03, M_PPM, 3'd2, 1'b1);            // LOAD valido limpa ERR
    wait_idle;
    check_frames(f0, 1, 3, 0, 0, 0);                // 01 02 03, sem EE e sem perdas
    $display("F8 overrun rejeitado sem perda ...... ok");

    test_name = "F8 modo reservado";
    err_expected = 1'b1;
    do_load(8'h77, M_RSV, 3'd0, 1'b1, 4);
    if (ERR !== 1'b1 || READY !== 1'b1) fail("modo 11 devia ser rejeitado com READY=1");
    err_expected = 1'b0;
    for (i = 0; i < 300; i = i + 1) begin
      @(negedge clk);
      if (BUSY !== 1'b0 || LED !== 1'b0) fail("modo reservado nao deve transmitir");
    end
    f0 = rx_frames;
    send_byte(8'h78, M_OOK, 3'd0, 1'b1);
    wait_idle;
    check_frames(f0, 1, 1, 0, 0, 0);
    $display("F8 modo reservado rejeitado ......... ok");

    test_name = "F8 LOAD longo";
    f0 = rx_frames;
    push_exp(8'h42, M_MAN, 3'd0, 1'b1);
    do_load(8'h42, M_MAN, 3'd0, 1'b1, 300);        // LOAD alto 300 ciclos -> 1 so byte
    wait_idle;
    check_frames(f0, 1, 1, 0, 0, 0);
    $display("F8 LOAD por flanco (nivel longo) .... ok");

    // ------------------------------------------------------------ RESET a meio da trama
    test_name = "reset a meio";
    send_byte(8'hF0, M_PPM, 3'd2, 1'b0);
    send_byte(8'h0F, M_PPM, 3'd2, 1'b1);
    @(negedge SYNC);
    repeat (100) @(negedge clk);                    // a meio do 1o byte
    disable RX_LOOP.RX_FRAME;                       // o recetor descarta a trama truncada
    rst_n = 1'b0;
    repeat (2) @(negedge clk);
    check_reset_outputs;
    q_rd = q_wr;                                    // bytes pendentes sao descartados pelo reset
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    for (i = 0; i < 2000; i = i + 1) begin
      @(negedge clk);
      if (BUSY !== 1'b0 || LED !== 1'b0 || DONE !== 1'b0) fail("atividade residual apos reset");
    end
    f0 = rx_frames;
    send_byte(8'hAB, M_MAN, 3'd1, 1'b0);
    send_byte(8'hCD, M_MAN, 3'd1, 1'b1);
    wait_idle;
    check_frames(f0, 1, 2, 0, 0, 0);
    $display("Reset a meio da trama + recuperacao . ok");

    // ------------------------------------------------------------ aleatorio
    test_name = "aleatorio";
    $dumpoff;
    f0 = rx_frames;
    nbytes = 300;
    for (i = 0; i < nbytes; i = i + 1) begin
      rm  = $unsigned($random(seed)) % 3;
      rs  = $unsigned($random(seed)) % 3;
      rl  = ($unsigned($random(seed)) % 8) == 0;
      dly = $unsigned($random(seed)) % 400;
      repeat (dly) @(negedge clk);
      send_byte($random(seed), rm, rs, rl);
    end
    wait_idle;
    $dumpon;
    $display("Aleatorio: %0d bytes em %0d tramas (seed=%0d) ok", nbytes, rx_frames - f0, seed0);

    // ------------------------------------------------------------ resumo
    repeat (10) @(negedge clk);
    if (q_rd != q_wr) fail("bytes por receber no fim");
    $display("--------------------------------------------------------------");
    $display("Tramas recebidas: %0d   Bytes recebidos: %0d   Ciclos: %0d", rx_frames, rx_bytes, cyc);
    if (errors == 0) $display("tb_lifi_tx: PASS");
    else             $fatal(1, "tb_lifi_tx: FAIL (%0d erros)", errors);
    $finish;
  end

endmodule
