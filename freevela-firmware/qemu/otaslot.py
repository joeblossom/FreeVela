#!/usr/bin/env python3
"""Print which OTA slot a flash image's otadata selects (highest valid ota_seq wins)."""
import sys, struct, binascii
img = open(sys.argv[1], "rb").read()
best = None
for off in (0xD000, 0xE000):
    seq, = struct.unpack_from("<I", img, off)
    crc, = struct.unpack_from("<I", img, off + 28)
    ok = seq != 0xFFFFFFFF and crc == binascii.crc32(struct.pack("<I", seq), 0xFFFFFFFF) & 0xFFFFFFFF
    if ok and (best is None or seq > best): best = seq
print("no valid otadata (boots ota_0)" if best is None else f"ota_seq {best} -> boots ota_{(best - 1) % 2}")
