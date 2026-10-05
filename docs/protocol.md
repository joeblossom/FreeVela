# Vela V2 — BLE protocol reference

How FreeVela talks to a Vela V2 bike over Bluetooth LE.

> **Status legend.** ✅ verified on a real bike · ⚠️ not yet confirmed on a bike ·
> ❓ contradictory or unknown.
> Unlock and alarm are ✅ on a real bike (firmware 2306052112, 2026-09-30). Confirm items with the
> app's Developer tools screen and update this file with the exported log as evidence.

## Model

The bike is a **Redux store exposed over BLE**. After authenticating with a
shared secret (`key` + `releasedKey`), you read state from one characteristic
as JSON, and send commands by writing JSON Redux actions
(`{"type": ..., "payload": ...}`) to another.

## GATT map

All UUIDs share the suffix `-7320-4cda-9830-697df55e369a`.

| Service | Characteristic | Name | Properties | Purpose |
|---|---|---|---|---|
| Auth `00000100` | `00000101` | CHALLENGE | read / write | Challenge from the bike; the answer is written back here |
| | `00000102` | KEY | read / write | Read: the IV for the answer. Write: 32-byte `key` (unpaired bike) |
| | `00000199` | RELEASE | read / write | `releasedKey` (release / rotation) |
| Redux `00000200` | `00000201` | STATE | read + notify | Bike → app: full state JSON |
| | `00000202` | DISPATCH | write w/ response | App → bike: JSON action |
| Firmware `00000300` | `00000301` / `00000302` | OTA state / OTA data | write w/ response | Firmware update (see below) |

There's also a standard Battery service (`180F` / `2A19`).

## Encoding ✅

- **KEY / RELEASE writes:** the raw 32 bytes you get from base64-decoding the stored key strings.
- **DISPATCH writes:** JSON as UTF-8 bytes.
- **STATE reads/notifications:** UTF-8 JSON.

## Authentication — challenge-response

Confirmed on a real bike (2026-09-30):
- ✅ **CHALLENGE** (`…0101`) reads **16 bytes**, random-looking. It stays the same until the bike restarts.
- ✅ **RELEASE** (`…0199`) reads **16 bytes**. This is *not* the 32-byte `releasedKey`.
- ✅ Before auth, **STATE** reads the 9-byte text `undefined`, and notifications send nothing.
- ✅ **Any DISPATCH write while unauthenticated makes the bike drop the connection** (~40 ms later).
- ✅ Max write is 512 B.

The handshake ✅:

1. Read RELEASE. If you have a `releasedKey`, write it (32 raw bytes) to RELEASE.
2. Read CHALLENGE, then read **KEY** (its current value is the IV).
3. If CHALLENGE is empty, write `key` (32 raw bytes) to KEY. Done.
4. Otherwise compute `AES-256-CBC-decrypt(challenge)` with key = `key` (32 bytes) and
   IV = the value read from KEY, with no padding, and write the 16-byte result **to CHALLENGE**.
5. STATE now returns real JSON and DISPATCH is accepted.

The KEY read returns the same 16 bytes as RELEASE.

⚠️ A bike with no key registers the next phone that writes one, and writing RELEASE releases the
bike. Writing `releasedKey` as in step 1 is safe, but don't experiment with RELEASE.

## Commands (DISPATCH)

Plain UTF-8 JSON written to DISPATCH (✅). Any dispatch before unlocking gets you disconnected.

Basic commands, supported by any Vela firmware:

| Intent | Action | Status |
|---|---|---|
| Arm alarm | `{"type":"alarm/ARM"}` | ✅ |
| Disarm alarm | `{"type":"alarm/DESARM"}` (sic) | ✅ |
| Assist mode | see below | ✅ |
| E-brake on / off | `{"type":"motor/EBC_SET","payload":1\|0}` | ✅ |
| Sleep | `{"type":"pwr/SLEEP_REQUESTED"}` | ✅ (wake: hold brake + button) |

**Assist modes** (see [firmware.md](firmware.md)): `motor.ast` 0 turns the motor **off**.
`pwr.save` is the battery % at or below which the eco curve is used. Manual modes send SAVER
first, then ASSIST_SET 1 after 150 ms.

| Mode | Actions | Effect |
|---|---|---|
| Off | `motor/ASSIST_SET 0` | no motor |
| Low | `pwr/SAVER_UPDATED 100`, then `motor/ASSIST_SET 1` | eco curve always |
| Auto | `pwr/SAVER_UPDATED 20`, then `motor/ASSIST_SET 1` | normal, eco at ≤ 20% battery |
| High | `pwr/SAVER_UPDATED 0`, then `motor/ASSIST_SET 1` | normal curve always |

**Lights** (`light/MODE_SET`) ✅: `1` always on, `-1` always off, anything else is auto (on
unless the bike is idle). Saved on the bike. Headlight is GPIO 4.

**Find my bike:** `alarm/TRIGGER` sounds the siren for 15 s and locks the wheel, even when the
alarm isn't armed. Clear it with `alarm/DESARM`.

**Other actions the firmware handles.** Most are internal events; see firmware.md before sending
any of them.

`alarm/TRIGGER` · `button/PRESSED|RELEASED|DOUBLED` · `light/MODE_SET` · `motor/BOOST_STARTED|ENDED` ·
`motor/BRAKE_STARTED|ENDED` · `motor/ROTATED` · `motor/RPS_UPDATED` · `pas/PEDAL_STARTED|STOPED` ·
`pos/MOVING_STARTED|STOPED` · `pos/SAT_DATA_RECEIVED` · `pwr/FUEL_UPDATED` · `sys/IDLE_TIMEOUT|CLEARED` ·
`net/*` · `cloud/*` · `phone/*`

## State (STATE)

✅ Read STATE to get the full JSON (about 370 B). **Notifications are sporadic** (a few per minute
even with notify on), so poll it. FreeVela polls every 1.5 s.

```json
{"sys":{"idle":0,"date":16815,"ver":"2306052112","live":13995},"alarm":{"armed":false,"trig":false},
 "pas":{"pedal":false},"phone":{"conn":true,"pair":true},"light":{"mode":0},"pos":{"move":0,"sat":null},
 "pwr":{"fuel":100,"save":20,"chr":0},"button":false,
 "motor":{"boost":false,"rps":0,"pulse":246977,"brk":false,"ast":1,"ebc":0},
 "net":{"conn":-1},"cloud":{"conn":0}}
```

| UI | Field | Notes |
|---|---|---|
| Battery % | `pwr.fuel` | |
| Charging | `pwr.chr` | |
| Assist mode | `motor.ast` + `pwr.save` | see above |
| E-brake | `motor.ebc` | |
| Odometer | `motor.pulse` | × 0.00039 km, or × 0.00023 mi |
| Speed | `motor.rps` | wheel turns per second; km/h ≈ rps × 8.4 (2.34 m per turn) |
| Lights | `light.mode` | |
| Alarm | `alarm.armed`, `alarm.trig` | |
| Firmware | `sys.ver`, and `fv.ver` on FreeVela firmware | |
| Uptime | `sys.live` | seconds since the bike started |

## Platform

The controller is an **ESP32** (ESP-IDF, FreeRTOS, NimBLE) running JavaScript on the Moddable
XS engine, with a SIMCom SIM7000/SIM868 modem and GPS. Vela's cellular and cloud features (MQTT
to Google Cloud IoT Core, shut down in 2023) no longer work, so Bluetooth is all that's left.
Details: [firmware.md](firmware.md).

## Getting your keys

`key` and `releasedKey` live in Vela's Firestore (`devices` collection,
`owner == users/<uid>`), readable only by the signed-in owner. Use
`tools/web/free-my-vela.html` from `localhost` **while Vela's Firebase is still
up**. Its old key-minting endpoint
(`us-central1-vela-c1f68.cloudfunctions.net/device/register`) may or may not
still answer.

If Firebase is gone, the fallbacks are:
- A cached copy in an old phone backup of the Vela app.
- Dumping the secret from the bike controller (UART/SWD). This is hard.

## Vela firmware download

Vela distributed `V2FW-2306052112.bin` (1,083,232 B, sha256 `b41f83d6…8c28ea`) from Firebase Storage:
`…/o/public%2Fdownloads%2Fv2fw%2FV2FW-2306052112.bin?alt=media&token=81a00e06-7aca-4398-84c3-4c00fcebb220`.
FreeVela doesn't redistribute it. If you have a copy, the app's Firmware update screen can install it to
return a bike to stock firmware.

## Firmware update (FreeVela app)

Developer tools → Firmware update (`ios/FreeVela/BLE/FirmwareUpdate.swift`). ✅ Used on a real bike
2026-10-02 (Vela 2306052112 reinstalled, then FreeVela 0.1.0).

- **Bike side:** raw image bytes to `0302` in order (no framing, no offsets), then any byte to `0301`.
  The bike validates the image (ESP-IDF `esp_ota_end`) and restarts only if it's valid; otherwise it
  silently starts a fresh session. Neither characteristic needs the unlock handshake.
- **Allowed images:** only those listed in `FirmwareImage.known` (exact size + SHA-256), and the
  file must have an ESP32 app header (magic `0xE9`, chip 0, SHA-256 appended). Images stay on the
  phone so an earlier version can be sent again. Listed today: Vela `2306052112` (import your own
  copy) and FreeVela `0.1.0`, which the app downloads from the `firmware-v0.1.0` GitHub release.
- **Preconditions:** unlocked, battery ≥ 40%, wheel still and not pedalling. Warns if not charging.
- **Transfer:** chunk = one ATT packet (`maximumWriteValueLength(.withoutResponse)`, MTU − 3),
  because larger "with response" writes become long writes on iOS. One write in flight, 8 ms
  between chunks, `offset < size` (no empty final write). 200 ms pause, then `0x01` to `0301`.
  About 4.5 min for Vela's image and 3.3 min for FreeVela 0.1.0.
- **Success** only if the bike disconnects (restart) within 30 s, the app reconnects and unlocks
  within 2 min, the bike booted after the update started (`sys.live`), and it reports the image's
  version (`fv.ver` for FreeVela, `sys.ver` for Vela). Anything else is reported as failed.
  On the bike the restart came ~1 s after the install command and the app was back in ~7 s.
- **Interrupted transfer:** the bike keeps appending to its session, so the app remembers the
  bike's boot time and, on the next attempt in the same boot, first writes `0301` to discard the
  partial image (the image check fails, the bike starts a fresh session) and waits 15 s.
- FreeVela firmware builds must report their own `fv.ver`, because `sys.ver` stays `2306052112`.
- **First data write is slow on FreeVela firmware** (several seconds): it erases the update slot
  when the first write arrives, where Vela's erases it at every boot. The app allows 30 s for it.

### Trial boot (FreeVela firmware)

A newly installed FreeVela image is on trial until a phone completes the unlock handshake on it,
which the app's post-install check does. Until then, the bike switches back to the firmware in the
other slot (the one it was installed from) after 3 unconfirmed boots, or 10 minutes of running
unconfirmed. This catches an image that crashes, or boots but whose Bluetooth doesn't work, which
otherwise could only be fixed over a wired connection. Once confirmed, it's permanent for that image.

## Firmware versions and capabilities (FreeVela app)

The app decides which controls to show from STATE (`ios/FreeVela/BLE/Firmware.swift`):

| Firmware | How it's recognized | Controls shown |
|---|---|---|
| Vela `2306052112` (verified) | `sys.ver` | assist modes, eco threshold, alarm, e-brake, light, find my bike, sleep |
| Other Vela versions | `sys.ver` not in the known list | basic controls only: assist modes, alarm, e-brake, sleep |
| FreeVela firmware | has an `fv` block | everything from `2306052112`, plus what `fv.caps` declares |

**Contract for FreeVela firmware:** add a top-level `fv` object to STATE:

```json
"fv": { "ver": "1.0.0", "caps": ["soft-start", "assist-strength"] }
```

FreeVela 0.1.0 also sends `"trial"`: the number of boots so far while the image is on trial, or 0
once confirmed (see "Trial boot" above).

### Key reset (FreeVela 0.2.0, QEMU-tested, not yet on a bike)

- **From the app (any firmware):** Settings → Keys → **Reset keys…** writes the current `key` to
  RELEASE (the bike forgets it), then a new random `key` to KEY (the bike registers it and stays
  unlocked). The new `releasedKey` is random and different from `key`, since a RELEASE write that
  matches the key releases the bike.
- **From the bike:** hold the brake lever and the handlebar button together for 15 s, wheel still.
  Chirps every second from 5 s, then a long tone; the key is erased and the bike restarts. The hold
  must start after the bike is awake. The next phone that writes KEY becomes the owner.
- **No lock:** the hold always works (wheel still), so anyone with the bike in hand can reset it and
  pair a new phone. That keeps new-owner setup working for any bike. (A reset lock in early 0.2.0
  test builds was removed.)
- **Firmware updates need the unlock** on FreeVela 0.2.0: OTA writes from a phone that hasn't
  unlocked are refused and the phone is disconnected.

### Sleep timer (FreeVela 0.2.0, QEMU-tested, not yet on a bike)

- STATE `fv.sleep` is the number of minutes without use before the bike goes to sleep; 0 (the
  default) means never, as on Vela's firmware. `{"type":"fv/SLEEP_SET","payload":<0–240>}` sets it
  (Settings → Power → **Sleep after**). Capability `sleep-timer`.
- Use means riding (`motor/RPS_UPDATED`), pedalling, the button, the brake, an unlock, or a command
  from the app (assist, saver, light, e-brake, alarm off, fv settings). Reading STATE doesn't count,
  so a connected phone that's only showing the bike doesn't keep it awake.
- When the time runs out it does what `pwr/SLEEP_REQUESTED` does. Not while the alarm is armed;
  disarming starts the countdown again. Wake is brake lever + handlebar button, as after any sleep.

### Motor settings and live throttle (FreeVela 0.2.0, QEMU-tested, not yet on a bike)

- STATE `fv.tune` holds the motor settings; `{"type":"fv/TUNE_SET","payload":{"top":4.8,"btn":1}}`
  sets any of them (out-of-range values are ignored). Capability `motor-tune`.

  | key | range | default | meaning |
  |---|---|---|---|
  | `top` | 2.5–5.3 rps | 4.276 (stock) | top speed: throttle ceiling = 83 + mg + sl × top (stock: fixed 225); hard cut at max(5.5, top + 0.5) rps |
  | `btn` | 0/1 | 0 | 0 = boost / walk assist (stock behavior); 1 = button is a throttle up to `top`, pedalling or not (no walk assist) |
  | `mg` | 0–60 | 18 | throttle floor margin: floor = 83 + mg + sl × rps while pedalling |
  | `sl` | 15–45 | 29 | throttle units per rps in the floor and ceiling |
  | `cr` | 0–1 | 0.4 | drive-curve climb per 50 ms above 3 rps (stock 0.06) |

- STATE `fv.live` is `{out, crv}`: the throttle written to the controller (83–254, 0 = speed cut) and
  the curve that wrote it (`stop`, `walk`, `eco`, `boost`, `drive`, `throttle`, `cut`). The app's
  Developer tools → Ride recorder logs it with speed, pedal, brake and button.
- Speed (`motor.rps`) still counts pulses over one second, but the window slides every 250 ms
  (stock: once a second).
- Finding: in the stock drive curve the throttle reaches the 225 ceiling by
  about 2 rps (~10 mph) and stays there; after 2 s of coasting at speed it restarts at the speed
  floor and took ~23 s to climb back (cr 0.06). With cr 0.4 it takes ~4 s.

### Charging and the analog probe (FreeVela 0.2.0-beta2, QEMU-tested, not yet on a bike)

- On stock firmware `pwr.chr` is 1 only when a battery reading is a whole percent above the previous
  one, and the battery is read rarely (start, 5 s after riding, then every 10 min while idle), so it
  mostly shows 0 while charging. FreeVela reads the battery every minute while parked (wheel still, not
  pedalling), refreshes `pwr.fuel`, and sets `chr` from the trend: on for a jump of 3 counts in a
  minute or a rise of 1 count over ~8 minutes; off for a drop of 3 counts, flat or falling over that
  span, or riding. New action `pwr/CHARGING` (payload 0/1). Still an estimate.
- STATE `fv.adc` = `{c0, c3, c6, c7}`: raw 0–1023 readings of ADC1 channels 0, 3, 6 (GPIO 36, 39, 34,
  unused by the firmware) and 7 (GPIO 35, battery), read when STATE is read. To find a charger
  signal: compare them unplugged vs plugged in (app: Developer tools → State → Charger probe).

### Public status and new-owner setup (FreeVela 0.2.0, QEMU-tested, not yet on a bike)

- **Device id:** the scan response carries 7 bytes of service data under the auth service UUID;
  their lowercase hex is the device id that key backups use (`BikeKeys.id`).
- **`fv_info`** (service `00000400-…`, characteristic `00000401-…`, read, **no unlock needed**):
  JSON `{ver, keyed, trial, boots, hold, fuel}` — FreeVela version; 1 if the bike has an owner key;
  seconds left in this boot's trial window (0 once confirmed); unconfirmed boots left; whole seconds
  of the current brake + button hold (0–15); battery %. Vela firmware doesn't have it.
- **Setup without keys** (app: signed out → Set up my bike):
  1. Find the bike and connect without unlocking.
  2. Vela firmware (and FreeVela 0.1.0) accepts a firmware install without the unlock, so the app
     installs FreeVela 0.2.0 (downloaded from the GitHub release, checked by size and SHA-256). It
     confirms the install from `fv_info.ver` after the restart. The bike can't report its battery
     without keys on Vela firmware, so the app asks for at least 40%; on FreeVela it checks `fuel`.
  3. The new firmware runs on trial: 10 minutes per boot, 3 unconfirmed boots. The owner holds the
     brake lever + button for 15 s (`hold` counts it live); the bike erases its key and restarts.
  4. The app writes a new random `key` to KEY. A keyless bike registers it and unlocks, which
     confirms the trial. A bike that already has a key refuses and disconnects ("another phone got
     there first").
  5. The app offers a key backup (`vela-backup.json`).

Capability names the app knows: `assist-strength`, `soft-start`, `push-state`, `key-reset`, `sleep-timer`, `motor-tune`. Unknown names are
ignored, so firmware can add capabilities before the app supports them. To add a new verified Vela
version, add it to `FirmwareInfo.knownVela`.
