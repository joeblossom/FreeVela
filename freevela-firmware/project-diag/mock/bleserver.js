// QEMU-only stand-in for Moddable's BLEServer (the emulator has no Bluetooth controller).
// Plays a scripted "phone" against ble.js: register owner key, reconnect, answer the challenge
// the same way the FreeVela iOS app does, dispatch commands, read state back.
import Timer from "timer";
import { BlockCipher, Mode } from "crypt";
import Preference from "preference";
import { keyReset, sleepTimer } from "modules/fv";
import { charge } from "modules/pwr";
import Analog from "analog";

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
		trace(`mock: [info keyless] ${this.#read("fv_info")}\n`);
		this.#write("auth_key", TEST_KEY);
		this.#state("after register");
		trace(`mock: [info owned] ${this.#read("fv_info")}\n`);
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

		trace("mock: TEST 9 sleep timer: not while armed, then after the set time with nothing happening\n");
		let slept = 0;
		sleepTimer.minute = 200;
		sleepTimer.sleep = () => { slept++; };
		this.#write("redux_dispatch", '{"type":"alarm/ARM"}');
		this.#write("redux_dispatch", '{"type":"fv/SLEEP_SET","payload":2}');
		this.#state("sleep 2");
		await later(1000);
		trace(`mock: sleep while armed: ${slept}\n`);
		this.#write("redux_dispatch", '{"type":"alarm/DESARM"}');
		await later(200);
		trace(`mock: sleep before the time: ${slept}\n`);
		await later(500);
		trace(`mock: sleep after the time: ${slept}\n`);
		this.#write("redux_dispatch", '{"type":"fv/SLEEP_SET","payload":0}');
		this.#state("sleep off");

		trace("mock: TEST 10 motor settings: set, out-of-range ignored, live values in STATE\n");
		this.#state("tune default");
		this.#write("redux_dispatch", '{"type":"fv/TUNE_SET","payload":{"top":4.8,"btn":1,"mg":999}}');
		await later(300);
		this.#state("tune set");
		this.#write("redux_dispatch", '{"type":"fv/TUNE_SET","payload":{"top":4.275862068965517,"btn":0}}');
		this.#state("tune back");

		trace("mock: TEST 11 charging from the battery trend\n");
		const chr = () => JSON.parse(this.#read("redux_state")).pwr.chr;
		const feed = async (values) => { for (const v of values) { Analog.values[7] = v; await later(300); } };
		charge.every = 250;
		await feed(Array(4).fill(650));
		trace(`mock: chr parked: ${chr()}\n`);
		await feed([655, 655]);
		trace(`mock: chr plugged in: ${chr()}\n`);
		await feed(Array(16).fill(655));
		trace(`mock: chr flat: ${chr()}\n`);
		await feed(Array.from({ length: 14 }, (_, i) => 655 + 0.2 * (i + 1)));
		trace(`mock: chr slow rise: ${chr()}\n`);
		await feed([650, 650]);
		trace(`mock: chr unplugged: ${chr()}\n`);
		charge.every = 60000;
		delete Analog.values[7];
		this.#state("probe");
		this.disconnect();

		trace("mock: TEST 4 wrong answer is rejected\n");
		this.#connect();
		this.#write("auth_challenge", new Uint8Array(16).buffer);
		this.#state("after wrong answer");

		trace("mock: TEST 12 a second phone can't register on an owned bike\n");
		this.#connect();
		this.#write("auth_key", new Uint8Array(32).fill(9).buffer);

		trace("mock: TEST 5 unauthenticated dispatch is rejected\n");
		this.#connect();
		this.#write("redux_dispatch", '{"type":"alarm/ARM"}');

		trace("mock: TEST 6 unauthenticated firmware update is rejected\n");
		this.#connect();
		this.#write("ota_data", new Uint8Array(16).buffer);
		this.#connect();
		this.#write("ota_state", new Uint8Array(1).buffer);
		trace("mock: DONE\n");

		trace("mock: TEST 8 hold brake + button for 15 s resets the key\n");
		keyReset.held = () => false;
		await later(1000);
		keyReset.held = () => true;
		trace("mock: holding\n");
		await later(7200);
		trace(`mock: [info holding] ${this.#read("fv_info")}\n`);
	}
}
