#!/bin/zsh
# run_qemu.sh <flash.bin> <seconds> <log>: boot an ESP32 flash image in Espressif QEMU, capture the UART.
~/esp/qemu/bin/qemu-system-xtensa -nographic -machine esp32 -m 4M \
  -drive file="$1",if=mtd,format=raw -nic user,model=open_eth -serial file:"$3" -monitor none &
pid=$!
sleep "$2"; kill $pid 2>/dev/null; wait $pid 2>/dev/null
