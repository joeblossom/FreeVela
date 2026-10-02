#!/bin/zsh
# Build the QEMU diagnostic firmware (mock ADC + scripted mock phone in place of BLE) and check results.
set -e
[ -f ~/esp/env.sh ] && source ~/esp/env.sh   # or export MODDABLE, IDF_PATH and PATH yourself
cd ~/esp/freevela-firmware/project-diag
mcconfig -m -i -p esp32 -t build -o ~/esp/fv-build > ~/esp/fv-diag.log 2>&1
D=~/esp/moddable-OS201230/build/tmp/esp32/release/idf
cd ~/esp/freevela-firmware/qemu
python3 make_flash.py $D/bootloader/bootloader.bin $D/partition_table/partition-table.bin $D/xs_esp32.bin flash-fv-diag.bin >/dev/null
./run_qemu.sh flash-fv-diag.bin 40 boot-fv-diag.log 2>/dev/null
fail=0
for want in "Phone authorization granted." "wrong answer." "unauthenticaded dispatch." "mock: DONE" "fvboot: confirmed"; do
  grep -aqF "$want" boot-fv-diag.log && echo "PASS  $want" || { echo "FAIL  $want"; fail=1; }
done
grep -aqE "XS abort|Guru Meditation" boot-fv-diag.log && { echo "FAIL  crash in log"; fail=1; } || echo "PASS  no crash"
exit $fail
