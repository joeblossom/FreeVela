#!/usr/bin/env python3
"""
vela_ble.py — standalone controller for a Vela e-bike over Bluetooth LE.

Depends on nothing of Vela's — no app, no server, no internet. Everything it needs is the two keys
(loaded below), which came out of your own Firestore device record.

The bike is a Redux store over BLE:
  * you AUTHENTICATE by presenting a shared secret (releasedKey + key),
  * you READ state by subscribing to the STATE characteristic (JSON),
  * you COMMAND it by writing JSON Redux actions to the DISPATCH characteristic.

-------------------------------------------------------------------------------
SETUP (once):
    pip install bleak cryptography
RUN:
    python3 vela_ble.py status          # connect, authenticate, print state
    python3 vela_ble.py watch           # stream live state until Ctrl-C
    python3 vela_ble.py assist on|off
    python3 vela_ble.py saver 0|20|100  # power-saver level
    python3 vela_ble.py alarm arm|off
    python3 vela_ble.py sleep
    python3 vela_ble.py send '{"type":"motor/ASSIST_SET","payload":1}'   # raw
    python3 vela_ble.py repl            # interactive
-------------------------------------------------------------------------------
"""

import asyncio
import base64
import json
import sys

from bleak import BleakClient, BleakScanner

# ---------------------------------------------------------------------------
# YOUR BIKE — these three values are what make this work. Keep them safe; they
# are the only thing you need if the app/server ever disappear. NEVER commit
# them. They're loaded from (first match wins):
#   1. env vars VELA_DEVICE_ID / VELA_KEY / VELA_RELEASED_KEY
#   2. vela-backup.json (from free-my-vela.html) in the current directory, or
#      the path in VELA_BACKUP. Uses the first bike, or VELA_DEVICE_ID's bike.
# ---------------------------------------------------------------------------
def _load_bike():
    import os
    dev = os.environ.get("VELA_DEVICE_ID")
    key = os.environ.get("VELA_KEY")
    rel = os.environ.get("VELA_RELEASED_KEY")
    if dev and key and rel:
        return dev, key, rel
    path = os.environ.get("VELA_BACKUP", "vela-backup.json")
    if os.path.exists(path):
        with open(path) as f:
            bikes = json.load(f).get("bikes", [])
        bike = next((b for b in bikes if not dev or b.get("id") == dev), None)
        if bike:
            return bike["id"], bike["key"], bike["releasedKey"]
    raise SystemExit("No bike keys found. Put vela-backup.json here, or set "
                     "VELA_DEVICE_ID, VELA_KEY and VELA_RELEASED_KEY.")


DEVICE_ID = KEY = RELEASED_KEY = None  # filled in by main()

# ---------------------------------------------------------------------------
# GATT map (base: ....-7320-4cda-9830-697df55e369a)
# ---------------------------------------------------------------------------
AUTH_SERVICE   = "00000100-7320-4cda-9830-697df55e369a"
AUTH_CHALLENGE = "00000101-7320-4cda-9830-697df55e369a"   # read
AUTH_KEY       = "00000102-7320-4cda-9830-697df55e369a"   # write  <- key
AUTH_RELEASE   = "00000199-7320-4cda-9830-697df55e369a"   # write  <- releasedKey

REDUX_SERVICE  = "00000200-7320-4cda-9830-697df55e369a"
REDUX_STATE    = "00000201-7320-4cda-9830-697df55e369a"   # read + notify (JSON)
REDUX_DISPATCH = "00000202-7320-4cda-9830-697df55e369a"   # write (JSON action)

# ENCODING: the bytes on the wire are:
#   * AUTH_KEY / AUTH_RELEASE  = the raw 32 secret bytes (base64-decoded here)
#   * DISPATCH                 = the JSON action as UTF-8
#   * STATE                    = the JSON state as UTF-8
# So with bleak (which is raw-bytes) we decode the keys and send/receive plain
# JSON bytes. No extra base64 on the wire.


async def find_bike(timeout=15.0):
    print(f"Scanning for {DEVICE_ID} ...")
    def match(dev, adv):
        name = (adv.local_name or dev.name or "")
        return DEVICE_ID.lower() in name.lower() or DEVICE_ID.lower() in dev.address.lower()
    dev = await BleakScanner.find_device_by_filter(match, timeout=timeout)
    if not dev:
        # Fall back: show what's around so you can adjust DEVICE_ID.
        print("Didn't match by id. Nearby devices:")
        for d in await BleakScanner.discover(timeout=timeout):
            print(f"   {d.address}  {d.name!r}")
        raise SystemExit("Bike not found — set DEVICE_ID to the name/address above.")
    print(f"Found {dev.address} ({dev.name!r})")
    return dev


async def authenticate(client: BleakClient):
    """The unlock handshake (see docs/protocol.md)."""
    key_bytes = base64.b64decode(KEY)
    rel_bytes = base64.b64decode(RELEASED_KEY)

    await client.read_gatt_char(AUTH_RELEASE)
    await client.write_gatt_char(AUTH_RELEASE, rel_bytes, response=True)
    print("[auth] wrote releasedKey")

    challenge = bytes(await client.read_gatt_char(AUTH_CHALLENGE))
    iv = bytes(await client.read_gatt_char(AUTH_KEY))
    if not challenge:
        await client.write_gatt_char(AUTH_KEY, key_bytes, response=True)
        print("[auth] empty challenge — wrote key")
        return

    # response = AES-256-CBC-decrypt(challenge, key, iv=current KEY value) -> CHALLENGE
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    dec = Cipher(algorithms.AES(key_bytes), modes.CBC(iv)).decryptor()
    response = dec.update(challenge) + dec.finalize()
    await client.write_gatt_char(AUTH_CHALLENGE, response, response=True)
    print("[auth] answered challenge")


def _decode_state(data: bytearray):
    try:
        return json.loads(bytes(data).decode("utf-8"))
    except Exception:
        return {"_raw_hex": bytes(data).hex()}


def summarize(state: dict) -> str:
    if "_raw_hex" in state:
        return f"raw: {state['_raw_hex']}"
    pwr = state.get("pwr", {})
    motor = state.get("motor", {})
    light = state.get("light", {})
    alarm = state.get("alarm", {})
    return (f"battery={pwr.get('fuel')}%  charging={pwr.get('chr')}  saver={pwr.get('save')}  "
            f"assist={motor.get('ast')}  ebc={motor.get('ebc')}  "
            f"light={light.get('mode')}  alarm_armed={alarm.get('armed')}")


async def dispatch(client: BleakClient, action: dict):
    payload = json.dumps(action, separators=(",", ":")).encode("utf-8")
    await client.write_gatt_char(REDUX_DISPATCH, payload, response=True)
    print(f"[dispatch] {action}")


# Confirmed action vocabulary (docs/protocol.md):
ACTIONS = {
    "assist_on":  {"type": "motor/ASSIST_SET", "payload": 1},
    "assist_off": {"type": "motor/ASSIST_SET", "payload": 0},
    "alarm_arm":  {"type": "alarm/ARM"},
    "alarm_off":  {"type": "alarm/DESARM"},
    "sleep":      {"type": "pwr/SLEEP_REQUESTED"},
}


async def with_bike(do):
    dev = await find_bike()
    async with BleakClient(dev) as client:
        print("Connected.")
        await authenticate(client)
        await do(client)


async def cmd_status(client):
    data = await client.read_gatt_char(REDUX_STATE)
    print(summarize(_decode_state(data)))


async def cmd_watch(client):
    def on_notify(_, data):
        print(summarize(_decode_state(data)))
    await client.start_notify(REDUX_STATE, on_notify)
    print("Streaming state — Ctrl-C to stop.")
    while True:
        await asyncio.sleep(1)


async def cmd_repl(client):
    def on_notify(_, data):
        print("  state:", summarize(_decode_state(data)))
    try:
        await client.start_notify(REDUX_STATE, on_notify)
    except Exception:
        pass
    print("Commands: assist on|off, saver N, alarm arm|off, sleep, "
          "send <json>, quit")
    loop = asyncio.get_event_loop()
    while True:
        line = (await loop.run_in_executor(None, input, "vela> ")).strip()
        if not line:
            continue
        if line in ("quit", "exit"):
            break
        try:
            if line.startswith("send "):
                await dispatch(client, json.loads(line[5:]))
            elif line == "assist on":
                await dispatch(client, ACTIONS["assist_on"])
            elif line == "assist off":
                await dispatch(client, ACTIONS["assist_off"])
            elif line.startswith("saver "):
                await dispatch(client, {"type": "pwr/SAVER_UPDATED", "payload": int(line.split()[1])})
            elif line == "alarm arm":
                await dispatch(client, ACTIONS["alarm_arm"])
            elif line == "alarm off":
                await dispatch(client, ACTIONS["alarm_off"])
            elif line == "sleep":
                await dispatch(client, ACTIONS["sleep"])
            else:
                print("?")
        except Exception as e:
            print("error:", e)


def main():
    global DEVICE_ID, KEY, RELEASED_KEY
    DEVICE_ID, KEY, RELEASED_KEY = _load_bike()
    args = sys.argv[1:]
    if not args:
        args = ["status"]
    cmd = args[0]

    if cmd == "status":
        asyncio.run(with_bike(cmd_status))
    elif cmd == "watch":
        asyncio.run(with_bike(cmd_watch))
    elif cmd == "repl":
        asyncio.run(with_bike(cmd_repl))
    elif cmd == "assist" and len(args) > 1:
        asyncio.run(with_bike(lambda c: dispatch(c, ACTIONS["assist_on" if args[1] == "on" else "assist_off"])))
    elif cmd == "saver" and len(args) > 1:
        asyncio.run(with_bike(lambda c: dispatch(c, {"type": "pwr/SAVER_UPDATED", "payload": int(args[1])})))
    elif cmd == "alarm" and len(args) > 1:
        asyncio.run(with_bike(lambda c: dispatch(c, ACTIONS["alarm_arm" if args[1] == "arm" else "alarm_off"])))
    elif cmd == "sleep":
        asyncio.run(with_bike(lambda c: dispatch(c, ACTIONS["sleep"])))
    elif cmd == "send" and len(args) > 1:
        asyncio.run(with_bike(lambda c: dispatch(c, json.loads(args[1]))))
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
