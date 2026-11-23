# Versão Wokwi (editor gráfico do workshop Tiny Tapeout)

## Conclusões da investigação (novembro 2026)

| Pergunta | Resposta |
|---|---|
| Pode-se representar o circuito no Wokwi? | **Uma versão simplificada, sim.** O fluxo TT só converte para GDS um conjunto pequeno de células desenhadas à mão |
| Que peças são convertidas? | Só estas 12: `wokwi-gate-buffer`, `-not`, `-and-2`, `-or-2`, `-xor-2`, `-nand-2`, `-nor-2`, `-xnor-2`, `wokwi-mux-2`, `wokwi-flip-flop-d`, `-dr`, `-dsr`. Também `wokwi-vcc`/`wokwi-gnd` (constantes) e `wokwi-junction`. Não há portas de 3 ou 4 entradas, contadores, somadores nem latches |
| E as outras peças (LED, interruptores, 7 segmentos, relógio, analisador lógico)? | São equipamento de teste **fora do chip**: o conversor ignora-as sem dar erro |
| Pode-se importar Verilog no editor gráfico? | **Não.** Não existe essa função. As únicas "importações" documentadas pelo TT geram portas a partir de tabelas de verdade |
| E os *custom chips* em Verilog do Wokwi? | Existem (experimentais, compilados com Yosys/CXXRTL para WASM), mas **só para simulação**. O conversor TT descarta-os, por isso a sua lógica não chegaria ao GDS |
| Um `diagram.json` qualquer funciona? | Não. O projeto tem de partir do **template TT**, com as peças `board-tt-block-input` (`verilogRole: input`) e `board-tt-block-output` (`verilogRole: output`). Sem elas a exportação cai num formato antigo e incompatível |
| Limite de tamanho? | Não há limite de portas documentado, só a área do tile. O TT recomenda o Wokwi para circuitos de < ~100 portas |

Fontes: template oficial https://wokwi.com/projects/354858054593504257, repositório
`TinyTapeout/ttsky-wokwi-template` (`src/cells.v`), `TinyTapeout/tt-support-tools`
(`project_info.py`, `project.py`), páginas tinytapeout.com/digital_design/wokwi e
/guides/workshop, e docs.wokwi.com (chips-api, wokwi-logic-analyzer, wokwi-led).

## O que está em `wokwi/diagram.json`

É o **núcleo modulador** do transmissor (fases 1, 3 e 4), com 15 células:

| Bloco | Células Wokwi | Equivalente no RTL |
|---|---|---|
| Contador de slots 0..3 (= temporizador de símbolos) | 2 × `flip-flop-dr`, 1 × `xor-2`, 1 × `not` (reset) | `lifi_symtimer` |
| Bit atual (MSB no slot 0–1, LSB no 2–3) | 1 × `mux-2` | `nrz_bit` |
| OOK | o próprio bit | `lifi_mod_ook` |
| Manchester | 1 × `xnor-2` | `lifi_mod_manchester` |
| 4-PPM | 2 × `xnor-2` + 1 × `and-2` | `lifi_mod_ppm` |
| Mux de modo (11 = reservado → 0) | 3 × `mux-2` + `gnd` | `lifi_mod_mux` |
| BIT_CLK, início de símbolo, LED_N | `not`, `nor-2`, `not` | registo de saída |

| Entrada | Interruptor | Função |
|---|---|---|
| IN0 | DIP 1 | `b0`: bit menos significativo do dibit |
| IN1 | DIP 2 | `b1`: bit mais significativo do dibit |
| IN2, IN3 | DIP 3, 4 | `MODE[0]`, `MODE[1]` |
| CLK | gerador (4 Hz) ou botão **Step** | 1 impulso = 1 slot |
| RST_N | botão **RESET** | reset assíncrono dos 2 flip-flops |

| Saída | Segmento | Sinal |
|---|---|---|
| OUT0 | a | **LED** modulado (também o LED branco "LiFi TX") |
| OUT1, OUT2 | b, c | contador de slots (bit 0, bit 1) |
| OUT3 | d | `TX_BIT` (bit NRZ atual) |
| OUT5 | f | `BIT_CLK` |
| OUT6 | g | início de símbolo (slot 0) |
| OUT7 | dp | `LED_N` |

Também há um analisador lógico (`logic1`) ligado às 8 saídas. Ao parar a simulação, descarrega
o ficheiro `lifi-wokwi.vcd`, que se abre no GTKWave.

**O que fica de fora, e porquê:** o registo de entrada, o registo de deslocamento, o divisor de
15 bits e a FSM de enquadramento. Juntos dariam várias centenas de portas de 2 entradas ligadas
à mão, o que é impraticável e muito propenso a erros. É exatamente o tipo de circuito para o qual
o fluxo HDL (o projeto Verilog principal) existe. Para "enviar" um byte nesta versão, muda-se o
dibit nos DIP 1–2 a cada 4 impulsos de relógio.

## Verificação antes de abrir no Wokwi

```bash
make wokwi
```

1. `wokwi/wokwi_to_verilog.py` converte o `diagram.json` num netlist Verilog, com a mesma
   semântica do `cells.v` do TT.
2. O script falha se houver entradas sem driver, curto-circuitos entre saídas, peças não
   suportadas ligadas ao interior do chip, ou pinos `EXT*` ligados à lógica.
3. `wokwi/tb_wokwi.v` compara o circuito com os moduladores do RTL nos 4 modos × 4 dibits ×
   12 slots: 192 verificações, todas a passar.

## Como abrir no Wokwi

O circuito já está guardado em https://wokwi.com/projects/481391130244247553 (ver o fim deste
documento). Os passos abaixo servem para o recriar a partir do template, p.ex. noutra conta.

1. Abre o template TT: https://wokwi.com/projects/354858054593504257 e faz login.
2. Guarda uma cópia na tua conta (*Save* / *Save a copy*). O projeto tem de nascer do template
   para o TT o aceitar.
3. No editor, abre o separador **diagram.json**, apaga o conteúdo e cola o de
   `wokwi/diagram.json`. O circuito é redesenhado.
4. Carrega no ▶ (simular).
   * Com o interruptor deslizante na posição do relógio, o LED pisca ao ritmo do modo escolhido.
   * Na outra posição, cada toque em **Step** (tecla `s`) avança um slot.
   * Modos: DIP3 e DIP4 desligados = OOK; só DIP3 = Manchester; só DIP4 = 4-PPM; ambos =
     reservado (LED apagado).
5. Os fios são desenhados em linha reta. Podes arrumá-los no editor sem alterar a lógica.
6. Depois de guardar, confirma a conversão em `https://wokwi.com/api/projects/<id>/verilog`:
   têm de aparecer 15 instâncias de células (`not_cell`, `dffr_cell`, `xor_cell`, `mux_cell`,
   `xnor_cell`, `and_cell`, `nor_cell`).

## Submeter a versão Wokwi (opcional)

É um **projeto TT separado** do projeto Verilog. Cada submissão tem um só topo; não se mistura
Wokwi e Verilog no mesmo tile. Para a submeter, usa o assistente de projetos Wokwi em
https://app.tinytapeout.com (ou o repositório `TinyTapeout/ttsky-wokwi-template`) e indica o
`wokwi_id`, que é o número no URL do teu projeto. O topo passa a chamar-se `tt_um_wokwi_<id>`.

Limitações conhecidas: o TT desaconselha o `flip-flop-dsr` (dá erro noutros processos; aqui usa-se
só o `flip-flop-dr`), e o simulador Wokwi deve correr com relógios ≤ 100 kHz.

## Teste no próprio Wokwi (22‑11‑2026)

O `diagram.json` foi colado no template TT em wokwi.com, sem conta, e simulado:

* **Renderização**: as 39 peças e as 85 ligações foram aceites. Cada peça lógica foi reconhecida
  com o seu tipo (`wokwi-gate-*`, `wokwi-flip-flop-dr`, `wokwi-mux-2`, `board-tt-block-input` e
  `board-tt-block-output`).
* **Lógica, com o botão Step**: 4 modos × 4 dibits × 4 slots × 8 saídas = **512 verificações, 0
  erros**. O LED mostra `0000/0011/1100/1111` em OOK, `1010/1001/0110/0101` em Manchester,
  `1000/0100/0010/0001` em 4‑PPM e `0000` no modo reservado.
* **Relógio automático** (gerador de 4 Hz através do interruptor deslizante): o contador avança
  sozinho e, em 4‑PPM com o dibit 10, o LED acende só no slot 2.
* **RESET**: é assíncrono e põe o contador a 0. Mantém o botão premido um instante, porque um
  clique muito rápido pode não ser registado.
* O display de 7 segmentos e o LED do Wokwi fazem a média do brilho (~100 ms). Por isso, nas
  transições aparecem segmentos meio acesos durante um instante. É um efeito visual do
  simulador, não do circuito.

## Projeto guardado e exportação Verilog (22‑11‑2026)

* Projeto público: **https://wokwi.com/projects/481391130244247553** ("LiFi TX - Tiny Tapeout",
  cópia do template TT). O `wokwi_id` é `481391130244247553` e o topo TT passa a ser
  `tt_um_wokwi_481391130244247553`.
* A exportação `https://wokwi.com/api/projects/481391130244247553/verilog` funciona e tem as
  **15 instâncias** esperadas: 3 `not_cell`, 2 `dffr_cell`, 1 `xor_cell`, 1 `nor_cell`,
  4 `mux_cell`, 3 `xnor_cell` e 1 `and_cell`.
* Está guardada, sem alterações, em `wokwi/tt_um_wokwi_481391130244247553.v` (SHA‑256 igual ao
  da API). `make wokwi-export` faz lint com o Verilator e corre o `tb_wokwi.v` sobre ela:
  **192 verificações, 0 erros**, o mesmo resultado do netlist gerado localmente.
* Se alterares o circuito no site, volta a copiar a exportação para esse ficheiro antes de
  correres `make wokwi-export`.
