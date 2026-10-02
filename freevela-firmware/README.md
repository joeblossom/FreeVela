# FreeVela firmware

Replacement firmware for the **Vela V2** e-bike controller (ESP32). It behaves like Vela's last
firmware (`2306052112`), without the cellular/cloud parts, plus a few additions. Download builds from the [GitHub releases](https://github.com/joeblossom/FreeVela/releases)
and install them with the FreeVela iOS app.

> **Pre-release, at your own risk.** 0.1.0 has been installed and tested on one bike. Assist and the
> brake cut-off haven't been fully checked on it yet. Test with the rear wheel off the ground before
> riding.

## 0.1.0

Same behavior as Vela `2306052112`, plus:

- **Reports its own version.** STATE gains `"fv": {"ver": "0.1.0", "caps": [], "trial": 0}` so the app
  can tell it from Vela's firmware (`sys.ver` stays `2306052112`).
- **Trial boot.** A newly installed image is on trial until a phone completes the unlock handshake,
  which the app does right after installing. If that doesn't happen within 10 minutes or 3 restarts,
  the bike switches back to the firmware it was installed from. This catches an image that crashes,
  or boots but whose Bluetooth doesn't work, which otherwise could only be fixed over a wired
  connection. Once confirmed, the image stays. (`project/native/fvboot.c`)
- **Wakes from Sleep on brake + button held together,** as Vela's does (confirmed on the bike).
  The wake pins are released afterwards so they work as normal inputs. (`project/native/standby.c`)
- **Keeps the previous firmware.** Vela's firmware erases the spare update slot at every boot. This
  one erases it only when an update starts, so the trial boot has something to switch back to.
  (`project/native/ota.c`)
- **No cellular or cloud code** (Vela's servers are gone).

## Installing

In the FreeVela app: Developer tools → **Firmware update**. The app only installs images it knows
(exact size and SHA-256), needs at least 40% battery and the bike standing still, and reports success
only after the bike restarts, unlocks again and reports the new version. To go back to Vela's
original firmware, install `V2FW-2306052112.bin` the same way. FreeVela doesn't distribute that file,
but the app recognizes it if you have it.

| Image | Size | SHA-256 |
|---|---|---|
| `freevela-0.1.0.bin` | 769,200 | `6ecf684908de661d9649b515b3f67120204582b089cf3549ef60277ce4e4cb47` |
| Vela `V2FW-2306052112.bin` (not distributed) | 1,083,232 | `b41f83d63310defd2543595a6a9efa75a97ed5ab987b14beba2ade5f5a8c28ea` |

## Building

The toolchain matches the one Vela used:

- [Moddable SDK](https://github.com/Moddable-OpenSource/moddable) tag **OS201230**, with
  `moddable-OS201230.patch` applied (adds the trial-boot hook to the ESP32 `app_main`)
- [ESP-IDF](https://github.com/espressif/esp-idf) **v3.3.2**
- xtensa-esp32-elf **gcc 5.2.0** (on Apple Silicon it runs under Rosetta)

Paths must not contain spaces. The manifests expect this folder to sit next to the Moddable SDK, at
`$MODDABLE/../freevela-firmware`:

```
~/esp/moddable-OS201230/      Moddable SDK (patched)
~/esp/esp-idf-v3.3.2/
~/esp/xtensa-esp32-elf/
~/esp/freevela-firmware/      this folder
```

```sh
export MODDABLE=~/esp/moddable-OS201230
export IDF_PATH=~/esp/esp-idf-v3.3.2
export PATH="$HOME/esp/xtensa-esp32-elf/bin:$MODDABLE/build/bin/mac/release:$IDF_PATH/tools:$PATH"
export CMAKE_POLICY_VERSION_MINIMUM=3.5   # IDF 3.3's CMake files predate CMake 4

(cd $MODDABLE && patch -p1 < ~/esp/freevela-firmware/moddable-OS201230.patch)
cd ~/esp/freevela-firmware/project
mcconfig -m -p esp32 -t build -o ~/esp/fv-build
# image: $MODDABLE/build/tmp/esp32/release/idf/xs_esp32.bin
```

The build isn't byte-for-byte reproducible (it embeds build paths), so your image's hash won't
match the release's, and the app won't install it until you add it to `FirmwareImage.known`.

## Tests (Espressif QEMU)

- `qemu/test_ble.sh` builds `project-diag` (the same firmware with a scripted mock phone in
  place of the Bluetooth stack). It checks the pairing, unlock, wrong-answer and unauthenticated
  paths, that the unlock confirms the trial boot, and that nothing crashes.
- `qemu/test_fvboot.sh` puts Vela's image in one OTA slot and a 20-second-trial build in the other,
  then checks that the bike switches back on the timer and after 3 unconfirmed boots. It needs your
  own copy of `V2FW-2306052112.bin` next to the `qemu` folder.

## Layout

| Path | What |
|---|---|
| `src/` | The bike modules (BLE server, assist, alarm, light, battery, ...) and a minimal Redux |
| `project/` | The FreeVela build: manifest, `main.js`, `fv.js`, GATT service definitions, partition table |
| `project/native/` | Native modules: `ota`, `standby`, `dac`, `udid`, `lib/sys`, and the `fvboot` safety net |
| `project-diag/` | QEMU build with mocks for the Bluetooth server and the battery ADC |
| `qemu/` | Flash-image builders and the tests above |

## Licenses

The Moddable runtime linked into the image is LGPL-3.0 (with Apache-2.0 parts for XS), and ESP-IDF
is Apache-2.0. This folder is the complete source for the released images, as LGPL-3.0 requires.

Not affiliated with Vela.
