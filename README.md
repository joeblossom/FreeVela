# FreeVela

Keep your **Vela V2 e-bike** working now that Vela has shut down. FreeVela talks
to the bike directly over Bluetooth LE — no Vela app, no Vela servers.
Not affiliated with Vela.

> **Status:** the iOS app is working on a real bike (TestFlight). It unlocks the
> bike with Vela's own handshake and controls assist, alarm, e-brake, light and
> sleep. **FreeVela firmware 0.1.0** is out as a pre-release
> ([`freevela-firmware/`](freevela-firmware/README.md)).
> See [`docs/protocol.md`](docs/protocol.md) for what's verified.

## 1. Rescue your keys — do this now

Each bike has a shared secret (`key` + `releasedKey`) that lives only in Vela's
Firebase, under your account. Once Vela's Firebase goes dark, those keys are gone
for good.

```sh
cd tools/web && python3 -m http.server 8000
# open http://localhost:8000/free-my-vela.html
```

Sign in the way you did in the Vela app (Apple / Google / email). Then click
**Download backup**, and keep `vela-backup.json` in a password manager.
Apple and Google sign-in only work from `localhost`.

**Never commit or post your backup.** Anyone with those keys can control
your bike and disarm its alarm.

## 2. iOS app

What it does today, all confirmed on a real bike:

- Unlock (Vela's challenge/response handshake)
- Assist: Off / Low / Auto / High, with an adjustable eco threshold under Auto
- Alarm arm/disarm, e-brake, light (Auto / On / Off), sleep
- Find my bike (sounds the siren for 15 s)
- Battery, speed, odometer, firmware version
- Connects automatically when you open the app
- Developer tools: raw Bluetooth access, a shareable log, and firmware updates

Build it yourself. You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cd ios
echo 'DEVELOPMENT_TEAM = <your team id>' > Local.xcconfig   # gitignored
xcodegen && open FreeVela.xcodeproj
```

Run it on a physical iPhone; Bluetooth doesn't work in the Simulator. Then:

1. AirDrop `vela-backup.json` to the phone and **Import backup** (or paste the keys).
2. Close the old Vela app: the bike only talks to one phone at a time.
3. Stand next to the bike. FreeVela finds it, connects and unlocks.

**Waking the bike:** after **Sleep**, the bike wakes only when you hold the
**brake lever and the handlebar button together**. Neither one alone wakes it.

Something not working? Tap **Share log with developer** and attach it to an
issue. Logs never contain your keys.

### Firmware updates

Developer tools → **Firmware update** installs a firmware image over Bluetooth.
It only accepts images it recognizes (exact size and SHA-256, listed in
`ios/FreeVela/BLE/FirmwareUpdate.swift`). It needs at least 40% battery and the
bike standing still. It reports success only after the bike restarts, unlocks
again and reports the new version. Details: [`docs/protocol.md`](docs/protocol.md#firmware-update-freevela-app).

FreeVela firmware is published in the
[GitHub releases](https://github.com/joeblossom/FreeVela/releases), and the
Firmware update screen downloads it directly. After installing, the firmware
runs on trial: if the app can't unlock the bike within 10 minutes or 3
restarts, the bike switches back to its previous firmware by itself. Source,
build steps and tests: [`freevela-firmware/`](freevela-firmware/README.md).

## 3. Desktop (Python)

`tools/python/vela_ble.py` is a reference client built on `bleak`. It reads
keys from `vela-backup.json` or the `VELA_*` env vars.

```sh
pip install bleak cryptography
python3 tools/python/vela_ble.py status   # also: watch, assist, saver, alarm, repl
```

## Docs

- [`docs/protocol.md`](docs/protocol.md) — GATT map, auth, commands, state, and which parts are verified.
- [`docs/ios-brief.md`](docs/ios-brief.md) — app design and milestones.
- [`docs/firmware.md`](docs/firmware.md) — what's in Vela's firmware: pin map, modules, quirks.
- [`freevela-firmware/`](freevela-firmware/README.md) — FreeVela firmware: what's changed, building, tests.
- [`docs/STATUS.md`](docs/STATUS.md) — where the project is and what's next.

For bikes you own. Changing assist settings may affect your bike's e-bike
class; stay street-legal.
