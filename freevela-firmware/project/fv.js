// modules/fv — FreeVela only (not in Vela's firmware).
// Adds "fv": {"ver", "caps", "trial"} to STATE so the app can tell FreeVela firmware from Vela's
// (sys.ver stays Vela's 2306052112). Confirms a trial boot once a phone unlocks (see fvboot.c).
//
// Key reset: hold the brake lever and the handlebar button together for 15 s with the wheel still.
// The bike chirps every second from 5 s, then sounds a long tone, forgets its owner key and restarts.
// The next phone that connects registers a new key. The hold has to start after the bike is awake
// (both released at least once), so holding on from a wake doesn't count.
//
// Sleep timer (`fv.sleep`, minutes, 0 = never): after that long with no riding, pedalling, button,
// brake or phone command, the bike goes to sleep as if the app had sent pwr/SLEEP_REQUESTED. It
// doesn't while the alarm is armed (sleep would turn the alarm off). Set with fv/SLEEP_SET
// (payload 0–240); Preference "fv"/"sleep", unset = 0, so the bike never sleeps on its own until set (as stock).
//
// Motor settings (`fv.tune`): {"type":"fv/TUNE_SET","payload":{"top":4.8,"btn":1}} sets any of the
// keys in modules/motor `tune`; values outside TUNE_RANGE are ignored. `fv.live` is the throttle
// output and curve right now. Both are the motor module's own objects, so STATE shows them as they
// are when it's read. `fv.adc` is the same for the raw analog inputs (modules/pwr), to find a
// charger signal.
import config from "mc/config";
import Timer from "timer";
import Digital from "pins/digital";
import Preference from "preference";
import { restart } from "lib/sys";
import { confirm, trial, trialLeft, trialBoots } from "fvboot";
import { buttonHeld } from "modules/button";
import { brakeHeld, tune, TUNE_RANGE, live } from "modules/motor";
import { adc } from "modules/pwr";

const RESET_MS = 15000;
const CHIRP_FROM_MS = 5000;
const POLL_MS = 250;
const SIREN = 14;

// `held` is replaceable so the QEMU test can press the controls. `heldFor` is the current hold (ms).
export const keyReset = { held: () => buttonHeld() && brakeHeld(), heldFor: 0 };

// Replaceable so the QEMU test doesn't wait minutes or actually sleep.
export const sleepTimer = { minute: 60000, sleep: (dispatch) => dispatch({ type: "pwr/SLEEP_REQUESTED" }) };
const SLEEP_MAX = 240;

// Actions that count as someone using the bike. Reading STATE isn't one.
const ACTIVITY = ["sys/LOADED", "motor/RPS_UPDATED", "motor/BRAKE_STARTED", "button/PRESSED", "button/RELEASED",
	"pas/PEDAL_STARTED", "phone/CONNECTED", "alarm/DESARM", "motor/ASSIST_SET", "pwr/SAVER_UPDATED",
	"light/MODE_SET", "motor/EBC_SET", "fv/SLEEP_SET", "fv/TUNE_SET"];

const sleepMinutes = (v) => Math.max(0, Math.min(SLEEP_MAX, Math.round(Number(v)) || 0));

const initialState = { ver: config.fvVersion, caps: ["key-reset", "sleep-timer", "motor-tune"],
	trial: trial(), sleep: sleepMinutes(Preference.get("fv", "sleep")), tune, live, adc };

const setTune = (payload) => {
	for (const key in payload ?? {}) {
		const value = Number(payload[key]);
		const range = TUNE_RANGE[key];
		if (!range || !(value >= range[0] && value <= range[1]))
			continue;
		tune[key] = value;
		Preference.set("tune", key, String(value));
	}
};

const reducer = (state = initialState, action) => {
	if (action.type === "fv/CONFIRMED")
		return { ...state, trial: 0 };
	if (action.type === "fv/TUNE_SET") {
		setTune(action.payload);
		return { ...state };
	}
	if (action.type === "fv/SLEEP_SET") {
		const sleep = sleepMinutes(action.payload);
		Preference.set("fv", "sleep", sleep);
		return { ...state, sleep };
	}
	return state;
};

const middleware = ({ dispatch, getState }) => {
	let sleepAt = null;
	const armSleep = () => {
		if (sleepAt)
			Timer.clear(sleepAt);
		sleepAt = null;
		const minutes = getState().fv.sleep;
		if (!minutes)
			return;
		sleepAt = Timer.set(() => {
			sleepAt = null;
			if (getState().alarm.armed)
				return;            // alarm/DESARM restarts the countdown
			if (Number(getState().motor.rps))
				return armSleep();
			trace("fv: sleep timer\n");
			sleepTimer.sleep(dispatch);
		}, minutes * sleepTimer.minute);
	};

	return next => action => {
		const result = next(action);
		if (ACTIVITY.includes(action.type))
			armSleep();
		// phone/CONNECTED is only dispatched after the unlock handshake succeeds (ble.js).
		if (action.type === "phone/CONNECTED" && getState().fv.trial) {
			confirm();
			dispatch({ type: "fv/CONFIRMED" });
		}
		return result;
	};
};

// Public status (the fv_info characteristic, readable without keys) so a phone that doesn't own the
// bike yet can set it up: firmware version, whether it has an owner key, the trial (seconds left in
// this boot's window and unconfirmed boots left), the brake+button hold in whole seconds, and
// battery %. Nothing secret.
let store;
export const info = () => {
	const boots = trial();
	return JSON.stringify({
		ver: config.fvVersion,
		keyed: Preference.get("ble", "key") ? 1 : 0,
		trial: trialLeft(),
		boots: boots ? Math.max(0, trialBoots() - boots) : 0,
		hold: Math.min(15, Math.floor(keyReset.heldFor / 1000)),
		fuel: store ? store.getState().pwr.fuel : 0,
	});
};

const chirp = (ms) => {
	Digital.write(SIREN, 1);
	Timer.set(() => Digital.write(SIREN, 0), ms);
};

const load = ({ getState }) => {
	let ready = false;      // both released at least once since boot
	store = { getState };
	const poll = Timer.repeat(() => {
		if (!keyReset.held()) {
			ready = true;
			keyReset.heldFor = 0;
			return;
		}
		if (!ready || Number(getState().motor.rps)) {
			keyReset.heldFor = 0;
			return;
		}
		if (keyReset.heldFor >= RESET_MS)
			return;                // already done for this hold
		keyReset.heldFor += POLL_MS;
		if (keyReset.heldFor >= RESET_MS) {
			Timer.clear(poll);
			trace("fv: key reset\n");
			Preference.delete("ble", "key");
			chirp(1500);
			Timer.set(() => restart(), 2000);
		}
		else if (keyReset.heldFor >= CHIRP_FROM_MS && keyReset.heldFor % 1000 === 0)
			chirp(40);
	}, POLL_MS);
};

export default { reducer, middleware, load };
