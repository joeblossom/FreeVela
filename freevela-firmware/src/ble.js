// ble.js: BLE server: unlock handshake, state and dispatch characteristics, firmware updates.
import BLEServer from "bleserver";
import { uuid } from "btutils";
import { BlockCipher } from "crypt";
import { Mode } from "crypt";
import Base64 from "base64";
import Preference from "preference";
import udid from "udid"; // imported but never referenced in this module
import { udidBytes } from "udid";
import OTA from "ota";
import { restart } from "lib/sys";

// Runs at import time (every boot). `let` because the ota_state handler reassigns it.
let ota = new OTA();

const isPaired = () => !!Preference.get("ble", "key");

const randomBytes = (len) => {
	const ray = new Int8Array(len);
	for (var i = 0; i < len; i++)
		ray[i] = Math.random() * 255;
	return ray.buffer;
};

const encrypt = (data, key, iv) =>
	new Mode("CBC", new BlockCipher("AES", key), iv, undefined)["encrypt"](data);

class BLE extends BLEServer {
	onReady() {
		this.deviceName = "Vela";
		const storedKey = Preference.get("ble", "key");
		this.authKey = storedKey ? Base64.decode(storedKey) : undefined;
		this.authIV = randomBytes(16);
		this.authAnswer = randomBytes(16);
		this.authChallenge = this.authKey ? encrypt(this.authAnswer, this.authKey, this.authIV) : null;
		if (this.authChallenge)
			trace("Started bluetooth challenge: " + Base64.encode(this.authChallenge) + "\n");
		else
			trace("Started bluetooth, device has no key.\n");
		trace("Disconnecting previously connected devices\n");
		this.disconnect();
		this.onDisconnected();
	}
	onAuthenticated(params) {
		this.authenticated = true;
	}
	onConnected() {
		trace("Phone connection initiated, waiting for auth\n");
		this.stopAdvertising();
	}
	onDisconnected() {
		this.authenticated = false;
		this.authorized = false;
		this.onDisconnect();
		this.startAdvertising({
			advertisingData: {
				flags: 6,
				completeName: this.deviceName,
				completeUUID128List: [uuid`00000100-7320-4cda-9830-697df55e369a`],
			},
			scanResponseData: {
				serviceDataUUID128: {
					uuid: uuid`00000100-7320-4cda-9830-697df55e369a`,
					data: new Uint8Array(udidBytes()),
				},
			},
		});
	}
	onCharacteristicNotifyEnabled(characteristic) {
		if (characteristic.name == "redux_state")
			this.characteristic = characteristic;
	}
	onCharacteristicNotifyDisabled(characteristic) {
		if (characteristic.name == "redux_state")
			this.characteristic = null;
	}
	notifyState(state) {
		this.state = state;
	}
	onCharacteristicRead({ name }) {
		if (name === "auth_challenge")
			return this.authChallenge;
		if (name === "auth_key" || name == "auth_release")
			return this.authIV;
		if (name === "redux_state" && this.authorized)
			return JSON.stringify(this.state);
	}
	onCharacteristicWritten({ name }, value) {
		switch (name) {
			case "auth_key":
				if (!this.authKey) {
					trace("Registering new owner device.\n");
					trace(Base64.encode(value.buffer));
					if (value.byteLength !== 32) {
						trace("Bad key size.\n");
						this.disconnect();
						return;
					}
					Preference.set("ble", "key", Base64.encode(value.buffer));
					this.authKey = value.buffer;
					this.authChallenge = encrypt(this.authAnswer, this.authKey, this.authIV);
					this.authorized = true;
					this.onConnect();
				} else {
					trace("tring to register registered bike.\n");
					this.disconnect();
				}
				break;
			case "auth_challenge":
				trace("Phone sent a authorization answer.\n");
				if (Base64.encode(value.buffer) === Base64.encode(this.authAnswer)) {
					trace("Phone authorization granted.\n");
					this.authorized = true;
					this.onConnect();
				} else {
					trace("wrong answer.\n");
					this.disconnect();
				}
				break;
			case "auth_release":
				if (!this.authKey || this.authKey.byteLength !== 32) {
					trace("Bad key size.\n");
					return;
				}
				if (Base64.encode(this.authKey) === Base64.encode(value.buffer)) {
					trace("Releasing Bike\n");
					this.authKey = null;
					this.authChallenge = null;
					Preference.delete("ble", "key", null);
				}
				break;
			case "redux_dispatch":
				if (this.authorized)
					return this.onAction(value);
				trace("unauthenticaded dispatch.\n");
				this.disconnect();
				break;
			case "ota_data":
				ota.write(value.buffer);
				break;
			case "ota_state":
				try {
					ota.complete();
					restart();
				} catch {
					ota = new OTA();
				}
				break;
		}
	}
}

export { isPaired };
export default BLE;
