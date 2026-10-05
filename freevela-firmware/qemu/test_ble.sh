#!/bin/zsh
# Build the QEMU diagnostic firmware (mock ADC + scripted mock phone in place of BLE) and check results.
set -e
[ -f ~/esp/env.sh ] && source ~/esp/env.sh   # or export MODDABLE, IDF_PATH and PATH yourself
cd ~/esp/freevela-firmware/project-diag
mcconfig -m -i -p esp32 -t build -o ~/esp/fv-build > ~/esp/fv-diag.log 2>&1
D=~/esp/moddable-OS201230/build/tmp/esp32/release/idf
cd ~/esp/freevela-firmware/qemu
python3 make_flash.py $D/bootloader/bootloader.bin $D/partition_table/partition-table.bin $D/xs_esp32.bin flash-fv-diag.bin >/dev/null
./run_qemu.sh flash-fv-diag.bin 110 boot-fv-diag.log 2>/dev/null
fail=0
for want in "Phone authorization granted." "wrong answer." "unauthenticaded dispatch." "unauthenticated ota." "mock: DONE" "fvboot: confirmed" "fv: key reset"; do
  grep -aqF "$want" boot-fv-diag.log && echo "PASS  $want" || { echo "FAIL  $want"; fail=1; }
done
# No reset lock: STATE and fv_info never report one.
strings boot-fv-diag.log | grep -q '"lock":' && { echo "FAIL  a reset lock is reported"; fail=1; } || echo "PASS  no reset lock"
# Sleep timer: skipped while the alarm is armed, fires once after the set time, can be turned off.
for want in "sleep while armed: 0" "sleep before the time: 0" "sleep after the time: 1" "fv: sleep timer"; do
  grep -aqF "$want" boot-fv-diag.log && echo "PASS  $want" || { echo "FAIL  $want"; fail=1; }
done
strings boot-fv-diag.log | grep 'sleep 2\]' | grep -q '"sleep":2' && echo "PASS  sleep set in STATE" || { echo "FAIL  sleep set in STATE"; fail=1; }
strings boot-fv-diag.log | grep 'sleep off' | grep -q '"sleep":0' && echo "PASS  sleep timer off" || { echo "FAIL  sleep timer off"; fail=1; }
# Motor settings: stock defaults, then set (mg 999 is out of range and ignored), live values present.
strings boot-fv-diag.log | grep 'tune default' | grep -q '"tune":{"top":4.27[0-9]*,"btn":0,"mg":18,"sl":29,"cr":0.4}' && echo "PASS  tune defaults" || { echo "FAIL  tune defaults"; fail=1; }
strings boot-fv-diag.log | grep 'tune set' | grep -q '"top":4.8,"btn":1,"mg":18' && echo "PASS  tune set" || { echo "FAIL  tune set"; fail=1; }
strings boot-fv-diag.log | grep 'tune set' | grep -q '"live":{"out":[0-9]*,"crv":"[a-z]*"}' && echo "PASS  live values" || { echo "FAIL  live values"; fail=1; }
# Charging: off while parked, on when plugged in (step), off when flat, on with a slow rise, off when unplugged.
for want in "chr parked: 0" "chr plugged in: 1" "chr flat: 0" "chr slow rise: 1" "chr unplugged: 0"; do
  grep -aqF "$want" boot-fv-diag.log && echo "PASS  $want" || { echo "FAIL  $want"; fail=1; }
done
strings boot-fv-diag.log | grep 'probe\]' | grep -q '"adc":{"c0":[0-9]*,"c3":[0-9]*,"c6":[0-9]*,"c7":[0-9]*}' && echo "PASS  analog probe in STATE" || { echo "FAIL  analog probe in STATE"; fail=1; }
# Public status (fv_info) without keys; keyed after pairing; hold counted; a second phone refused.
strings boot-fv-diag.log | grep 'info keyless\]' | head -1 | grep -q '"keyed":0' && echo "PASS  fv_info readable without keys" || { echo "FAIL  fv_info without keys"; fail=1; }
strings boot-fv-diag.log | grep 'info owned\]' | head -1 | grep -q '"keyed":1' && echo "PASS  keyed after pairing" || { echo "FAIL  keyed after pairing"; fail=1; }
strings boot-fv-diag.log | grep 'info holding\]' | grep -qE '"hold":(6|7|8)' && echo "PASS  hold seconds reported" || { echo "FAIL  hold seconds"; fail=1; }
grep -aqF "tring to register registered bike" boot-fv-diag.log && echo "PASS  second phone refused" || { echo "FAIL  second phone refused"; fail=1; }
# After the reset the bike restarts with no key.
strings boot-fv-diag.log | sed -n '/fv: key reset/,$p' | grep -q "device has no key" && echo "PASS  restarted without a key after the reset" || { echo "FAIL  no restart without a key"; fail=1; }
grep -aqE "XS abort|Guru Meditation" boot-fv-diag.log && { echo "FAIL  crash in log"; fail=1; } || echo "PASS  no crash"
exit $fail
