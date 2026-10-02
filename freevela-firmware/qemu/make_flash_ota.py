#!/usr/bin/env python3
"""4 MB QEMU flash with two apps: bootloader @0x1000, partitions @0x8000, ota_0 @0x10000, ota_1 @0x1F0000,
and otadata @0xD000 selecting the slot to boot. Usage: make_flash_ota.py boot parts ota0 ota1 {0|1} out"""
import sys, struct, binascii
boot, parts, ota0, ota1, slot, out = sys.argv[1:7]
img = bytearray(b"\xff" * 4 * 1024 * 1024)
for off, path in ((0x1000, boot), (0x8000, parts), (0x10000, ota0), (0x1F0000, ota1)):
    data = open(path, "rb").read()
    img[off:off + len(data)] = data
seq = 1 + int(slot)              # bootloader boots slot (seq - 1) % 2
entry = struct.pack("<I", seq) + b"\xff" * 20 + struct.pack("<I", 0xFFFFFFFF)
entry += struct.pack("<I", binascii.crc32(struct.pack("<I", seq), 0xFFFFFFFF) & 0xFFFFFFFF)
img[0xD000:0xD000 + len(entry)] = entry
open(out, "wb").write(img)
print("wrote", out)
