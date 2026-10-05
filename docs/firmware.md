# Vela V2 controller reference

How the Vela V2 controller behaves on firmware `2306052112` (June 2023), which FreeVela firmware
0.1.0 keeps. For the Bluetooth side see [protocol.md](protocol.md).

## Platform

- **ESP32**, 4 MB flash (DIO, 80 MHz), ESP-IDF **v3.3.2**, FreeRTOS, NimBLE.
- The bike logic is **JavaScript on Moddable XS** (Moddable SDK release **OS201230**).
- Images aren't signed: an image only carries a SHA-256 checksum, which the bike checks before
  installing it.
- Bike state is a small **Redux** store. Each module has a reducer, and some have middleware or a
  load step. Bluetooth STATE/DISPATCH is a window onto that store.
- Settings persist in ESP32 NVS, e.g. `motor/ast`, `motor/ebc`, `motor/pulses`, `light/mode`.
- The ESP32 sends a throttle signal and a brake signal to a **separate motor controller**. Current
  limiting and the power electronics are there, not in this firmware.

## Modules

| Module | Does |
|---|---|
| `sys` | Uptime, date, idle timer (60 s), heartbeat LED, version |
| `pwr` | Battery level, eco threshold, sleep |
| `motor` | Assist control loop, brake, wheel speed, boost (below) |
| `pas` | Pedal sensor |
| `button` | Handlebar button: press, release, double press |
| `light` | Headlight |
| `alarm` | Alarm arm/trigger, siren, wheel lock |
| `phone` | BLE connection; bridges the BLE server and the store |
| `pos` | Movement and GPS fixes |
| `net`, `cloud` | Cellular modem and cloud link (Vela's servers are gone; FreeVela firmware leaves these out) |

## Pin map

| GPIO | Use | Module |
|---|---|---|
| 0 | Handlebar button (input, pull-up, active low). Also the ESP32 boot strap pin | button |
| 2 | Driven high at boot; also the pulse counter's control pin | motor |
| 3 | Handlebar button (input, pull-up, active low). Also UART0 RX | button |
| 4 | **Headlight** | light |
| 13 | Battery-type strap (input, pull-up): selects the fuel-gauge curve | pwr |
| 14 | **Siren / buzzer** | alarm |
| 15 | Heartbeat: 100 ms high every 3 s (status LED?) | sys |
| 25 (DAC ch 1) | **Throttle signal to the motor controller**, 83 (off) to 254 (full) | motor |
| 26 | Motor brake: e-brake while braking, and wheel lock while the alarm is armed | motor, alarm |
| 27 | Wheel-speed pulse counter, 6 pulses per wheel turn | motor |
| 32 | Brake lever (input, pull-up, active low) | motor |
| 33 | Pedal sensor | pas |
| ADC ch 7 (GPIO 35) | Battery voltage | pwr |

**Sleep and wake:** `pwr/SLEEP_REQUESTED` stops the motor and puts the ESP32 into deep sleep. From
0.2.1-beta1 it wakes on the handlebar button (GPIO 0, ext0) or the brake lever (GPIO 32, ext1) alone.
Up to 0.2.0 it needed both held together, and on the bike that didn't wake (2026-10-05; recovered by
removing the battery). `fv.io` in STATE shows the live inputs (`b3`, `b0`, `brk`: 1 = pressed).

## Quirks

- **"High" assist doesn't survive a reboot.** The saver level is restored as "saved value, or 20",
  so a saved `0` (High) comes back as `20` (Auto).
- `motor.rps` is a string with one decimal. Above 5.5 rev/s the throttle is written 0, but the
  stored level is kept, so assist resumes at that level when you slow down.
- The alarm re-triggers on *any* speed update while armed, even 0.

## Light

Mode is saved. `1` always on, `-1` always off, anything else is auto: on while the bike is awake,
off when it's idle.

## Motor

Every second the wheel speed is computed from the pulse counter (6 pulses per turn) and published as
`motor/RPS_UPDATED`. Every 500 pulses the odometer is saved. Brake lever edges give
`motor/BRAKE_STARTED` / `BRAKE_ENDED` (ignored while the alarm is armed).

Every 50 ms the throttle is updated:

- **E-brake:** if e-brake is on and you brake above 2.1 rev/s, GPIO 26 is set until you release.
- **Over-speed:** above 5.5 rev/s (~46 km/h) the throttle is cut.
- **Which curve:** off (motor disabled, braking, or neither pedalling nor boost) → minimum;
  boost without pedalling → **walk** (holds ~1.1 rev/s, ~9 km/h); battery at or below the eco
  threshold → **eco**; boost while pedalling → **boost**; otherwise → **normal**.
- The result is clamped to 83–254 and written to the DAC.

Curves (`value` is the current throttle output):

- **Normal:** ramp +4 per tick below 115. Holds at least `83 + 18 + rps × 29` while rolling. Then
  +0.9 / +0.65 / +0.2 / +0.06 per tick as rps passes 1 / 2 / 3. Backs off −2 above 225.
- **Eco:** ramp +3 below 115. Backs off above 215–225 or above 3.3 rev/s. Gentler climbs
  (+0.45 below 0.9 rev/s, +0.2 below 1.8).
- **Walk:** +4 below 110, then nudges toward 1.1 rev/s.
- **Boost:** +3 until 0.6 rev/s, then 254.

Button press starts boost; button release, braking or pedalling stopping ends it.

### What the assist settings mean

`motor.ast` 0 turns the motor off completely. `pwr.save` is a **battery-% threshold**: at or below
it, the eco curve is used.

| Mode | Commands | Effect |
|---|---|---|
| Off | `ASSIST_SET 0` | No motor |
| Low | `SAVER_UPDATED 100`, `ASSIST_SET 1` | Eco curve always |
| Auto | `SAVER_UPDATED 20`, `ASSIST_SET 1` | Normal curve, eco at ≤ 20% battery |
| High | `SAVER_UPDATED 0`, `ASSIST_SET 1` | Normal curve always |

**Speed:** `rps` is wheel turns per second. One turn is 6 pulses × 0.39 m = 2.34 m, so km/h ≈ rps × 8.4.

## Alarm

- `alarm/ARM`: GPIO 26 on (wheel hard to turn), the bike goes idle, one beep.
- `alarm/DESARM`: GPIO 26 off, two beeps, clears `armed` and `trig`.
- `alarm/TRIGGER`: siren (GPIO 14) **on for 15 s**, GPIO 26 on, `trig` saved. It works whether or not
  the alarm is armed, which is how FreeVela's "Find my bike" works.
- While armed, a button press, wheel rotation, movement, wheel speed or pedalling triggers the alarm.
- Wheel speed above 7.5 rev/s (~63 km/h) turns the buzzer on.

## Cellular (Vela firmware only)

At boot Vela's firmware starts the modem, brings up a data link and syncs the time. On failure it
retries every 20 s indefinitely; `net.conn: -1` in STATE means start-up is failing (the SIM is no
longer active). There's no command to turn the modem off. FreeVela firmware doesn't include it.

## Actions the phone can send

Every action written to DISPATCH reaches every module. Useful ones beyond the basic commands:

| Action | Effect |
|---|---|
| `light/MODE_SET` 1 / −1 / 0 | Headlight on / off / auto (saved) |
| `pwr/SAVER_UPDATED` 0–100 | Eco below that battery % (any value, not just 0/20/100) |
| `alarm/TRIGGER` | 15 s siren and wheel lock; clear with `alarm/DESARM` |

**Don't send fake sensor events** (`motor/RPS_UPDATED`, `motor/BRAKE_*`, `pas/*`, `pwr/FUEL_UPDATED`,
`button/*`). They feed the motor control loop directly. `motor/BOOST_STARTED` from the phone gives full
throttle while pedalling. Possible, but not exposed.

## Bluetooth ownership

- A bike with no key accepts the first key written to KEY and registers that phone as its owner.
- A wrong challenge answer, or a dispatch before unlocking, disconnects the phone.
- Writing the owner's key to RELEASE releases the bike.

## Firmware updates

See [protocol.md](protocol.md#firmware-update-freevela-app) for how images are installed, and
[`freevela-firmware/`](../freevela-firmware/README.md) for FreeVela firmware.
