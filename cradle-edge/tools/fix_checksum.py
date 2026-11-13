#!/usr/bin/env python3
"""LoROM ヘッダのチェックサムを計算して書き込む。"""
import sys

path = sys.argv[1]
rom = bytearray(open(path, "rb").read())
assert len(rom) & (len(rom) - 1) == 0, "ROM サイズは2のべき乗であること"
rom[0x7FDC:0x7FE0] = b"\xff\xff\x00\x00"
s = sum(rom) & 0xFFFF
rom[0x7FDC] = (s ^ 0xFFFF) & 0xFF
rom[0x7FDD] = (s ^ 0xFFFF) >> 8
rom[0x7FDE] = s & 0xFF
rom[0x7FDF] = s >> 8
open(path, "wb").write(rom)
print(f"{path}: {len(rom)} bytes, checksum ${s:04X}")
