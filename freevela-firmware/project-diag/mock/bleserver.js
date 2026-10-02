// QEMU-only stand-in for Moddable's BLEServer (the emulator has no Bluetooth controller).
// Plays a scripted "phone" against ble.js: register owner key, reconnect, answer the challenge
// the same way the FreeVela iOS app does, dispatch commands, read state back.
import Timer from "timer";
import { BlockCipher, Mode } from "crypt";
import Preference from "preference";

const TEST_KEY = new Uint8Array(32).map((_, i) => (i * 7 + 3) & 0xff).buffer;   // test owner key
const hex = (b) => Array.from(new Uint8Array(b), (x) => x.toString(16).padStart(2, "0")).join("");
const later = (ms) => new Promise((resolve) => Timer.set(resolve, ms));

export default class BLEServer {
	constructor() {
		this.connected = false;
		Timer.set(() => { this.onReady(); this.#script(); }, 10);
	}
	set deviceName(v) { this._name = v; }
	get deviceName() { return this._name; }
	startAdvertising(p) { trace(`mock: advertising as ${p.advertisingData.completeName}, scan data ${hex(p.scanResponseData.serviceDataUUID128.data.buffer)}\n`); }
	stopAdvertising() { trace("mock: stop advertising\n"); }
	disconnect() {
		trace("mock: disconnect\n");
		if (this.connected) { this.connected = false; this.onDisconnected(); }
	}
	notifyValue(characteristic, value) { trace(`mock: notify ${characteristic.name}\n`); }
	#connect() { this.connected = true; trace("mock: --- phone connects ---\n"); this.onConnected(); }
	#read(name) { return this.onCharacteristicRead({ name }); }
	#write(name, value) {
		const v = (typeof value === "string") ? value : new Uint8Array(value);
		return this.onCharacteristicWritten({ name }, v);
	}
	#state(label) {
		const s = this.#read("redux_state");
		trace(`mock: [${label}] redux_state = ${s === undefined ? "undefined" : s}\n`);
	}
	async #script() {
		await later(500);
		Preference.delete("ble", "key");          // start from an unpaired bike
		this.onReady();

		trace("mock: TEST 1 register owner key\n");
		this.#connect();
		this.#state("before register");
		this.#write("auth_key", TEST_KEY);
		this.#state("after register");
		this.disconnect();

		trace("mock: TEST 2 reboot, then unlock like the FreeVela app\n");
		this.onReady();                              // as on reboot: reload stored key, new challenge
		this.#connect();
		this.#state("locked");
		const challenge = this.#read("auth_challenge");
		const iv = this.#read("auth_key");
		const releaseRead = this.#read("auth_release");
		trace(`mock: challenge ${hex(challenge)} iv ${hex(iv)} release-read==iv ${hex(releaseRead) === hex(iv)}\n`);
		const answer = new Mode("CBC", new BlockCipher("AES", TEST_KEY), iv).decrypt(challenge);
		this.#write("auth_challenge", answer);
		this.#state("unlocked");

		trace("mock: TEST 3 commands\n");
		for (const action of ['{"type":"alarm/ARM"}', '{"type":"light/MODE_SET","payload":1}',
			'{"type":"pwr/SAVER_UPDATED","payload":40}', '{"type":"motor/EBC_SET","payload":1}', '{"type":"alarm/DESARM"}']) {
			this.#write("redux_dispatch", action);
			await later(300);
			this.#state(action);
		}
		this.disconnect();

		trace("mock: TEST 4 wrong answer is rejected\n");
		this.#connect();
		this.#write("auth_challenge", new Uint8Array(16).buffer);
		this.#state("after wrong answer");

		trace("mock: TEST 5 unauthenticated dispatch is rejected\n");
		this.#connect();
		this.#write("redux_dispatch", '{"type":"alarm/ARM"}');
		trace("mock: DONE\n");
	}
}
