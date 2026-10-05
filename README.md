# FreeVela

Keep your **Vela V2 e-bike** working now that Vela has shut down. FreeVela talks
to the bike directly over Bluetooth LE — no Vela app, no Vela servers.
Not affiliated with Vela.

> **Status:** the iOS app is working on a real bike (TestFlight). It unlocks the
> bike with Vela's own handshake and controls assist, alarm, e-brake, light and
> sleep. **FreeVela firmware 0.2.0** is out as a pre-release
> ([`freevela-firmware/`](freevela-firmware/README.md)); it adds setting a bike up
> without its keys. See [`docs/protocol.md`](docs/protocol.md) for what's verified.

## 1. Get your bike into the app

Each bike only obeys a phone that has its keys. You **don't need your old Vela keys**
to use FreeVela: the iOS app can set the bike up from scratch. If you do still have
them (or can still fetch them), you can use them instead.

### Set up on your phone — no keys needed (recommended)

In the app, tap **Set up my bike** (or Settings → Bikes & keys → **Add a bike…** →
Set up a new bike). It takes about 10–15 minutes, with the phone next to the bike:

1. **Wake and find the bike** (hold the brake lever and the handlebar button together).
2. **Install FreeVela firmware.** The bike accepts it without keys; the app downloads
   [FreeVela 0.2.0](https://github.com/joeblossom/FreeVela/releases/tag/firmware-v0.2.0)
   and checks it before sending. The new firmware runs on trial and switches back to
   the old one by itself if setup isn't finished within 10 minutes.
3. **Reset the bike's keys:** hold the brake lever and the handlebar button together
   for 15 seconds with the wheel still. The app shows the count live; the bike chirps
   from 6 s and sounds a long tone at 15 s.
4. **Pair this phone.** The app makes new keys and gives them to the bike, which makes
   this phone the owner.
5. **Save a key backup** (or keep the keys in iCloud Keychain, on by default).

FreeVela firmware is a pre-release and isn't made or supported by Vela, so this is at
your own risk. Details: [`docs/protocol.md`](docs/protocol.md), "Public status and
new-owner setup".

<a id="1-rescue-your-keys--do-this-now"></a>
### Or use your existing keys (optional)

This keeps the bike's original firmware. Each bike's keys (`key` + `releasedKey`)
live in Vela's Firebase, under your account, for as long as Vela's sign-in still
answers. You'll need a computer:

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
- Assist: Off / Low / Auto / High, with an adjustable eco threshold (Settings)
- Alarm arm/disarm, e-brake, light (On / Off), sleep
- Find my bike (sounds the siren for 15 s)
- Battery, speed, odometer, firmware version
- Connects automatically when you open the app
- Developer tools: the bike's state, a ride recorder, motor tuning and a shareable log

New in the latest builds (FreeVela 0.2.0 features are tested in the emulator, not yet on many bikes):

- **Set up a bike without keys** (see above)
- **Keys:** Settings → Bikes & keys → tap a bike to see and copy its keys, save a
  backup, or sync them with iCloud Keychain (end-to-end encrypted; on by default)
- With FreeVela 0.2.0: sleep timer, top speed and the button as boost or throttle

Build it yourself. You need Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
cd ios
echo 'DEVELOPMENT_TEAM = <your team id>' > Local.xcconfig   # gitignored
xcodegen && open FreeVela.xcodeproj
```

Run it on a physical iPhone; Bluetooth doesn't work in the Simulator. Then:

1. Close the old Vela app: the bike only talks to one phone at a time.
2. Tap **Set up my bike**, or, if you have your keys, AirDrop `vela-backup.json`
   to the phone and choose **I already have my keys**.
3. Stand next to the bike. FreeVela finds it, connects and unlocks.

**Waking the bike:** after **Sleep**, the bike wakes only when you hold the
**brake lever and the handlebar button together**. Neither one alone wakes it.

Something not working? Tap **Share log with developer** and attach it to an
issue. Logs never contain your keys.

### Firmware updates

Settings → **Firmware update** installs a firmware image over Bluetooth.
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
