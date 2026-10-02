#!/bin/zsh
# Test the trial-boot safety net (project/native/fvboot.c) in QEMU: Vela's image in ota_0, a FreeVela
# test build (20 s trial, console on) in ota_1, booting ota_1. Never confirmed (no phone in QEMU), so:
#  1. timer: one long run must end with otadata selecting ota_0.
#  2. boots: short runs must switch back on the boot after the 3rd unconfirmed one.
set -e
[ -f ~/esp/env.sh ] && source ~/esp/env.sh   # or export MODDABLE, IDF_PATH and PATH yourself
F=~/esp/freevela-firmware
D=~/esp/moddable-OS201230/build/tmp/esp32/release/idf
sed -i '' 's/^#define FV_TRIAL_SECONDS 600$/#define FV_TRIAL_SECONDS 20/' $F/project/native/fvboot.c
(cd $F/project && mcconfig -m -i -p esp32 -t build -o ~/esp/fv-build > ~/esp/fv-trial-test.log 2>&1) || { sed -i '' 's/^#define FV_TRIAL_SECONDS 20$/#define FV_TRIAL_SECONDS 600/' $F/project/native/fvboot.c; exit 1; }
sed -i '' 's/^#define FV_TRIAL_SECONDS 20$/#define FV_TRIAL_SECONDS 600/' $F/project/native/fvboot.c
cd $F/qemu
cp $D/xs_esp32.bin fv-trial20.bin
cp $D/bootloader/bootloader.bin bootloader-fv-inst.bin
cp $D/partition_table/partition-table.bin partitions-fv.bin
fail=0
python3 make_flash_ota.py bootloader-fv-inst.bin partitions-fv.bin ../V2FW-2306052112.bin fv-trial20.bin 1 flash-trial.bin >/dev/null
./run_qemu.sh flash-trial.bin 90 boot-trial.log 2>/dev/null
strings boot-trial.log | grep fvboot
python3 otaslot.py flash-trial.bin | grep -q 'boots ota_0' && echo "PASS  timer: switched back to ota_0" || { echo "FAIL  timer"; fail=1; }
python3 make_flash_ota.py bootloader-fv-inst.bin partitions-fv.bin ../V2FW-2306052112.bin fv-trial20.bin 1 flash-boots.bin >/dev/null
# Short runs (under the 20 s timer); a run cut off before the check doesn't count, so keep going.
rm -f boot-boots-*.log
for i in 1 2 3 4 5 6 7 8; do
  ./run_qemu.sh flash-boots.bin 16 boot-boots-$i.log 2>/dev/null
  python3 otaslot.py flash-boots.bin | grep -q 'boots ota_0' && break
done
strings boot-boots-*.log | grep fvboot
strings boot-boots-$i.log | grep -q 'too many boots' && python3 otaslot.py flash-boots.bin | grep -q 'boots ota_0' \
  && echo "PASS  boots: switched back after 3 unconfirmed boots" || { echo "FAIL  boots"; fail=1; }
grep -aqE "Guru Meditation" boot-trial.log boot-boots-*.log && { echo "FAIL  crash in log"; fail=1; } || echo "PASS  no crash"
exit $fail
