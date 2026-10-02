# FreeVela iOS app — build brief

A native **SwiftUI + CoreBluetooth** app that talks to a Vela V2 directly over
BLE. It uses nothing of Vela's, apart from the optional one-time key import.
The protocol itself is in [`protocol.md`](protocol.md).

## Principles
- **Implement only what's verified.** Anything ⚠️/❓ in `protocol.md` is
  confirmed through the **Lab** screen first.
- **Multi-bike, no hardcoded values.** Keys are stored in the Keychain, keyed by device ID.
- **Keys never leave the device.** No logging of key bytes in exported logs
  (they're redacted), no analytics, no network calls after import.

## Getting keys into the app

The original brief proposed native Sign in with Apple / Google exchanged through
Firebase `signInWithIdp`. **That doesn't work for a third-party app:**
- Apple identity tokens carry *our* bundle ID as `aud`, which Vela's Firebase
  Apple provider rejects. Apple's user `sub` is also scoped per developer team,
  so it would never map to the same Firebase user.
- Google cross-client ID tokens need the iOS client ID to be in Vela's GCP project.

What does work:

1. **Backup file (primary).** `vela-backup.json` from
   `tools/web/free-my-vela.html`: `{ "bikes": [ { "id", "key", "releasedKey",
   "displayName", "sku", "serial", … } ] }`. Imported with the Files picker or a share sheet.
2. **Manual paste** of the device ID, `key` and `releasedKey`.
3. **Email/password sign-in**, natively over REST:
   `POST identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=<Vela apiKey>`
   → `idToken` / `localId`, then a Firestore `runQuery` on `devices` where
   `owner == users/<localId>`.
4. **Apple / Google users** run the web tool on a computer (localhost is an
   authorized Firebase domain), then import the backup (1).

Vela's public Firebase client config (not secret; it's client-side config):
`apiKey AIzaSyBUywpEBKBVfaOYzhnPWKSOW4EGZmjPy-U`, `projectId vela-c1f68`.

## Structure

```
ios/
  project.yml                 # XcodeGen spec  (brew install xcodegen; xcodegen)
  FreeVela/
    FreeVelaApp.swift
    BLE/BikeProtocol.swift    # UUIDs, encoding, action presets
    BLE/BikeLink.swift        # CBCentralManager wrapper; each step callable individually
    Lab/LabView.swift         # protocol lab: scan, GATT dump, step-by-step auth, dispatch, log export
    Lab/LabLog.swift
    Keys/KeyStore.swift       # Keychain (later) / in-memory + Secrets.swift (dev)
    Keys/Backup.swift         # vela-backup.json decoding
```

CoreBluetooth notes:
- `Info.plist` needs `NSBluetoothAlwaysUsageDescription`.
- Add the `bluetooth-central` background mode for later.
- Only one central can hold the bike at a time, so close the old Vela app.
- BLE doesn't work in the Simulator. Test on a physical iPhone.

## Milestones
0. **Lab** (now): prove connect → auth → STATE → one dispatch on the real bike.
   Export logs and update `protocol.md`.
1. **Import**: backup file, paste, and email sign-in; the Keychain store.
2. **Dashboard**: battery, assist, saver, alarm, lights, firmware.
3. **Controls**: only the actions verified in the Lab.
4. **Polish**: auto-reconnect, background, haptics.
5. **Distribution**: TestFlight for other owners. Avoid Vela trademarks in the app name and icon.
