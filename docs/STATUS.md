# FreeVela — where we are / what's next

Running notes so we can pick this back up. Last updated 2026-10-02.

## The app (public repo, shipping on TestFlight)

Build 15 uploaded 2026-10-02 (wording cleanup). Build 14 added firmware downloads from GitHub releases; build 13 added FreeVela 0.1.0 and auto-connect. Working and confirmed on the real bike:
- Unlock (challenge/response handshake)
- Assist modes: Off / Low / Auto / High, with an eco-threshold slider under Auto
- Alarm arm/disarm, E-brake toggle, Light (Auto/On/Off), Sleep
- Find my bike (15 s siren via alarm/TRIGGER, then auto-clear)
- Battery %, speed, odometer
- Developer tools screen with raw GATT + shareable log

Uploads: bump `CFBundleVersion` in `ios/project.yml`, run `ios/upload.sh` (uses the
App Store Connect API key in the gitignored `ios/asc.env`).

Controls are gated by firmware version/capabilities (`ios/FreeVela/BLE/Firmware.swift`,
contract in docs/protocol.md "Firmware versions and capabilities"). New FreeVela firmware
should report `"fv": {"ver", "caps"}` in STATE.

### Requested features (user, 2026-10-01)
- **Firmware: sleep gesture.** Hold the brake + button ~5 s while the wheel is stopped →
  `pwr/SLEEP_REQUESTED`, so the bike can be put to sleep without the phone and doesn't drain the
  battery. Wake is already brake + button (Vela's and 0.1.0's). Watch out: the button alone while
  not pedalling is walk assist, and with the brake held the motor is cut, so it shouldn't move.
- **App: auto-connect when opened.** Done in build 13 (looks once on open / return to foreground).

### App bugs to fix
- (fixed in build 11) Rapid taps no longer collide: GATT ops are serialized per
  characteristic, multi-step commands hold a command lock, and stale assist taps are skipped.

## Firmware

Workspace: `~/esp/freevela-firmware` (private, not in git; symlinked as `./firmware`). Toolchain in
`~/esp`: Moddable OS201230, ESP-IDF v3.3.2, xtensa gcc 5.2.0 via Rosetta; `source ~/esp/env.sh`.

**Publishing:** `~/esp/freevela-firmware/publish.sh` copies the source the release build uses into
`freevela-firmware/` (comments in `src/` are cleaned by `sanitize_src.py`); rerun it after firmware
changes. Images go in GitHub releases tagged `firmware-v<ver>`; add each one to
`FirmwareImage.known` with its release URL. Vela's own image is never redistributed.

### FreeVela 0.1.0 — installed and running on the bike (2026-10-02)

`firmware/out/freevela-0.1.0.bin`, 769,200 B, sha256 `6ecf6849…e4cb47` (also in iCloud Drive →
FreeVela Firmware, and the `firmware-v0.1.0` pre-release on GitHub). Same behavior as Vela
2306052112, without cellular/cloud, plus:
- `fv: {ver: "0.1.0", caps: [], trial}` in STATE (`project/fv.js`).
- Sleep wakes on brake + button held together (ext1 ALL_LOW on GPIO 0 + 32, RTC pull-ups on), and
  the wake pins are released from the RTC domain at boot (`project/native/standby.c`, `fvboot.c`).
- Trial-boot safety net (`project/native/fvboot.c`, hooked into Moddable's `app_main` with a weak
  `freevela_boot_check`; patched `main.c`, original saved as `main.c.orig`). See docs/protocol.md.
- OTA begins (erases the spare slot) on the first write, not at boot, so the previous firmware stays
  available to switch back to (`project/native/ota.c`).
- QEMU: `qemu/test_ble.sh` (pairing, unlock, trial confirmed by the unlock) and `qemu/test_fvboot.sh`
  (timer and boot-count switch-back, with Vela's image in the other slot) pass.

Install log (2026-10-02):
- Reinstalling Vela 2306052112 through the app first: 4282 writes of 253 B in 4 m 30 s, bike
  restarted ~1 s after the install command, reconnected and confirmed in ~7 s (`sys.live` 6).
- Then FreeVela 0.1.0: 3041 writes in 3 m 19 s, same restart/reconnect; STATE shows
  `"fv":{"ver":"0.1.0","caps":[],"trial":0}` (confirmed by the unlock), no `net`/`cloud`.
- Wheel-off-ground check: pedal sensor and wheel speed work (rps up to 6.8, odometer pulses count).

Still to check on 0.1.0:
- Motor assist feel, and that the brake cuts the motor.
- Sleep, then brake + button wake; Find my bike after a wake (see the siren note below).
- The slow first write (erase on first write) happens on the next install *from* 0.1.0.
- Front brake + button as a wake combination (only one brake input, GPIO 32, so either both
  levers share it or only the rear lever has a sensor).

### Findings
- **Wake from Sleep (2026-10-01):** after a Sleep, the button alone, the brake alone and pedalling
  don't wake the bike; **holding the (rear) brake lever + handlebar button together does.** GPIO 32
  and GPIO 0 are both RTC GPIOs, active low, so this is ext1 ALL_LOW. GPIO 3 (the button's other
  pin) isn't an RTC GPIO. Earlier "wakes on movement" reports were normal idle wake.
- **Siren silent after waking from Sleep on Vela firmware (2026-10-01):** the bike accepted
  alarm/TRIGGER, ARM and DESARM (STATE changed each time) but made no sound, though Find my bike
  worked earlier that day. Likely the siren pin held by the sleep code and not released after the
  wake; a full power cycle should clear it. 0.1.0 releases the pins after a wake, so check it there.
- **Watchdogs:** neither Vela's image nor ours enables the task or interrupt watchdog (Moddable
  defaults), so a hung JS loop wouldn't reset the chip. Same as stock; worth fixing later.
- Challenge/IV are stable **until the next restart**, not forever.
- Assist mapping: Off = ast 0; Low = save 100; Auto = save 20; High = save 0. `pwr.save` is the
  battery-% threshold below which the eco curve kicks in.
- "High" assist resets to "Auto" after a reboot (the saver level is restored as "value or 20").

### Next firmware work
- **Motor "jolt"** (what the user most wants to fix): no torque sensor, just a pedal on/off sensor.
  In Normal assist the motor ramps fast (+4 every 50 ms to 115 ≈ 0.4 s) and holds a speed-rising
  floor (83 + 18 + rps×29), which feels like a shove vs. a smooth VanMoof-style helper. All in
  `motor.js`. Options: soft-start (ramp over 1.5–2 s), a slew-rate limit, cadence-following (scale
  assist to pedal pulse rate), app-adjustable strength. Test with the rear wheel off the ground.
- **Sleep gesture** (see Requested features).
- Enable a task watchdog so a hang drops the throttle.
