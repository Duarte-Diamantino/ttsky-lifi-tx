# SPDX-FileCopyrightText: © 2026 Duarte Diamantino
# SPDX-License-Identifier: Apache-2.0
"""
Testes cocotb do transmissor LiFi (tt_um_duarte_diamantino_lifi_tx).

Correm no CI do Tiny Tapeout em RTL e em gate-level (GATES=yes), por isso usam
APENAS os pinos do topo. O testbench Verilog completo (sim/tb_lifi_tx.v) cobre
mais casos; aqui fica um subconjunto rapido e representativo.

Inclui um recetor de referencia em Python (capture_frames + decode_frame) que
so observa o LED, tal como um recetor otico real.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge

OOK, MAN, PPM, RSV = 0, 1, 2, 3
LED, BUSY, READY, DONE, ERR, BIT_CLK, SYNC, LED_N = range(8)
FIRST_ONE_SLOT = {OOK: 0, MAN: 1, PPM: 2}   # slot do 1o '1' do preambulo


def n_slot(speed):
    """Duracao de um slot em ciclos de clk: 2 * 4^speed."""
    return 2 << (2 * speed)


def uo(dut):
    return dut.uo_out.value.to_unsigned()


def bit(dut, b):
    return (uo(dut) >> b) & 1


async def reset(dut):
    clock = Clock(dut.clk, 100, unit="ns")   # 10 MHz
    cocotb.start_soon(clock.start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 3)
    await FallingEdge(dut.clk)


async def wait_bit(dut, b, val, timeout=200_000):
    for _ in range(timeout):
        if bit(dut, b) == val:
            return
        await FallingEdge(dut.clk)
    raise AssertionError(f"timeout a espera de uo_out[{b}] == {val}")


async def load(dut, data, mode, speed, last=0, hold=4):
    """Impulso em LOAD (uio[2]) com DATA e configuracao estaveis."""
    cfg = (last << 6) | (speed << 3) | mode
    dut.ui_in.value = data
    dut.uio_in.value = cfg
    await FallingEdge(dut.clk)
    dut.uio_in.value = cfg | 0x04
    for _ in range(hold):
        await FallingEdge(dut.clk)
    dut.uio_in.value = cfg
    for _ in range(3):
        await FallingEdge(dut.clk)


async def send(dut, data, mode, speed, last=0):
    await wait_bit(dut, READY, 1)
    await load(dut, data, mode, speed, last)
    assert bit(dut, ERR) == 0, "LOAD valido com ERR=1"
    assert bit(dut, DONE) == 0, "DONE devia limpar apos LOAD aceite"


async def capture_frames(dut, mode, speed, count=1, timeout=400_000):
    """Recetor: espera pelo 1o '1' do LED e guarda o LED ciclo a ciclo ate BUSY cair."""
    n = n_slot(speed)
    frames = []
    for _ in range(count):
        for _ in range(timeout):
            await FallingEdge(dut.clk)
            if bit(dut, LED):
                break
        else:
            raise AssertionError("nenhuma trama detetada")
        samples = [0] * (FIRST_ONE_SLOT[mode] * n) + [1]
        while True:
            await FallingEdge(dut.clk)
            v = uo(dut)
            assert ((v >> LED_N) & 1) == 1 - (v & 1), "LED_N != ~LED"
            if not (v >> BUSY) & 1:
                break
            samples.append(v & 1)
        frames.append(samples)
    return frames


def decode_frame(samples, mode, speed):
    """Desmodula uma trama completa e devolve a lista de bytes."""
    n = n_slot(speed)
    assert len(samples) % (4 * n) == 0, f"trama com {len(samples)} ciclos (nao e multiplo de um simbolo)"
    slots = []
    for j in range(len(samples) // n):
        chunk = samples[j * n:(j + 1) * n]
        assert all(s == chunk[0] for s in chunk), f"slot {j} nao constante"
        slots.append(chunk[0])
    symbols = [slots[i:i + 4] for i in range(0, len(slots), 4)]
    assert symbols[-2:] == [[0, 0, 0, 0]] * 2, "GAP final com o LED aceso"

    def demod(w):
        if mode == OOK:
            assert w[0] == w[1] and w[2] == w[3], f"OOK invalido {w}"
            return (w[0] << 1) | w[2]
        if mode == MAN:
            assert w[0] != w[1] and w[2] != w[3], f"Manchester invalido {w}"
            return (w[1] << 1) | w[3]
        assert sum(w) == 1, f"PPM invalido {w}"
        return w.index(1)

    dib = [demod(w) for w in symbols[:-2]]
    assert dib[:12] == [0b10] * 11 + [0b11], "preambulo/SFD incorreto"
    data, i = [], 12
    while True:
        b = 0
        for k in range(4):
            b = (b << 2) | dib[i + k]
        ctrl = dib[i + 4]
        i += 5
        data.append(b)
        assert ctrl in (0b10, 0b01), f"controlo invalido {ctrl:02b}"
        if ctrl == 0b01:
            break
    assert i == len(dib), "simbolos a mais depois do ultimo byte"
    return data


@cocotb.test()
async def test_reset_e_pinos(dut):
    """Estado apos reset e direcao dos pinos bidirecionais."""
    await reset(dut)
    assert dut.uio_oe.value.to_unsigned() == 0x80, "uio[6:0] entradas, uio[7] saida"
    v = uo(dut)
    assert v & 1 == 0 and (v >> LED_N) & 1 == 1, "LED apagado em repouso"
    assert (v >> READY) & 1 == 1 and (v >> BUSY) & 1 == 0
    assert (v >> DONE) & 1 == 0 and (v >> ERR) & 1 == 0


@cocotb.test()
async def test_modulacoes(dut):
    """OOK, Manchester e 4-PPM: 3 bytes numa trama, descodificados so pelo LED."""
    await reset(dut)
    payload = [0x1B, 0xE4, 0xA5]
    for mode in (OOK, MAN, PPM):
        rx = cocotb.start_soon(capture_frames(dut, mode, 0))
        for i, b in enumerate(payload):
            await send(dut, b, mode, 0, last=int(i == len(payload) - 1))
        frames = await rx
        got = decode_frame(frames[0], mode, 0)
        assert got == payload, f"modo {mode}: recebido {got}"
        await wait_bit(dut, DONE, 1)
        dut._log.info(f"modo {mode}: {[hex(x) for x in got]} ok")


@cocotb.test()
async def test_velocidades(dut):
    """SPEED 0..2: duracao exata da trama = (14 + 5*nbytes) * 4 * N_slot."""
    await reset(dut)
    for speed in range(3):
        mode = speed % 3
        rx = cocotb.start_soon(capture_frames(dut, mode, speed))
        await send(dut, 0x3C + speed, mode, speed, last=1)
        frames = await rx
        assert len(frames[0]) == (14 + 5) * 4 * n_slot(speed)
        assert decode_frame(frames[0], mode, speed) == [0x3C + speed]
        await wait_bit(dut, DONE, 1)
        dut._log.info(f"SPEED={speed}: T_bit = {2 * n_slot(speed)} ciclos ok")


@cocotb.test()
async def test_ocupado_overrun_e_reservado(dut):
    """LOAD com o registo cheio e LOAD no modo 11 sao rejeitados (ERR) sem perda de dados."""
    await reset(dut)
    rx = cocotb.start_soon(capture_frames(dut, PPM, 1))
    await send(dut, 0x01, PPM, 1)
    await send(dut, 0x02, PPM, 1)
    assert bit(dut, READY) == 0, "registo de entrada devia estar cheio"
    await load(dut, 0xEE, PPM, 1)                  # LOAD ilegal
    assert bit(dut, ERR) == 1, "ERR devia assinalar a rejeicao"
    await send(dut, 0x03, PPM, 1, last=1)          # LOAD valido limpa ERR
    frames = await rx
    assert decode_frame(frames[0], PPM, 1) == [0x01, 0x02, 0x03]
    await wait_bit(dut, DONE, 1)

    await load(dut, 0x77, RSV, 0, last=1)          # modo reservado
    assert bit(dut, ERR) == 1 and bit(dut, READY) == 1
    for _ in range(200):
        await FallingEdge(dut.clk)
        assert bit(dut, BUSY) == 0 and bit(dut, LED) == 0


@cocotb.test()
async def test_last_divide_tramas(dut):
    """O pino LAST fecha a trama; o byte seguinte abre uma trama nova."""
    await reset(dut)
    rx = cocotb.start_soon(capture_frames(dut, MAN, 0, count=2))
    await send(dut, 0x11, MAN, 0)
    await send(dut, 0x22, MAN, 0, last=1)
    await send(dut, 0x33, MAN, 0, last=1)
    frames = await rx
    assert decode_frame(frames[0], MAN, 0) == [0x11, 0x22]
    assert decode_frame(frames[1], MAN, 0) == [0x33]
