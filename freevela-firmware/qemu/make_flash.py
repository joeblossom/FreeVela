#!/usr/bin/env python3
"""Assemble a 4 MB ESP32 flash image for QEMU: bootloader @0x1000, partition table @0x8000, app @0x10000 (ota_0)."""
import sys, os
boot, parts, app, out = sys.argv[1:5]
img = bytearray(b"\xff" * 4 * 1024 * 1024)
for off, path in ((0x1000, boot), (0x8000, parts), (0x10000, app)):
    data = open(path, "rb").read()
    img[off:off + len(data)] = data
open(out, "wb").write(img)
print("wrote", out)
