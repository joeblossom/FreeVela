// modules/pwr.js: Battery level, eco threshold, sleep.

import Analog from "analog";
import Timer from "timer";
import Preference from "preference";
import standby from "standby";
import Digital from "pins/digital";
import Time from "time";

// GPIO 13 strapped low => battery pack with "linear" (polynomial) voltage curve
const linearBatPin = new Digital({ pin: 13, mode: Digital.InputPullUp });
const isLinearBat = !linearBatPin.read();

// ADC channel 7 (ESP32 ADC1_CH7 = GPIO 35), averaged over two reads
export const battRead = () => (Analog.read(7) + Analog.read(7)) / 2;

export const toFuel = (b) => {
	if (isLinearBat) {
		const calc = (x) => (5.73 + -0.406 * x + 0.00716 * x * x) * 100;
		const result = ~~Math.min(Math.max(calc(b / 10.13), 0), 100);
		return result;
	}
	if (b < 560)
		return 0;
	return ~~Math.min(Math.max((b - 570) / 160 * 100, 0), 100);
};

// FreeVela: charging from the battery's trend. The bike has no charger signal that Vela read; Vela set
// `chr` when one reading was a whole percent higher than the one before, and read the battery rarely,
// so it mostly showed 0 while charging. Here, every minute while the bike is parked (wheel still, not
// pedalling), the battery is read 16 times and averaged, `fuel` is refreshed, and 11 minutes of
// readings are kept. Charging turns on when the battery jumps CHR_STEP in a minute (plugging in) or the
// last three readings average CHR_RISE above three from 8–10 minutes earlier; it turns off when the
// battery drops CHR_STEP in a minute (unplugging), stays flat or falls over that span (full, or not
// plugged in), or the bike is ridden. Readings are 0–1023 counts; one count is roughly 1%.
// `every` is replaceable so the QEMU test doesn't wait minutes.
export const charge = { every: 60000 };
const CHR_STEP = 3;
const CHR_RISE = 1;
const CHR_FLAT = 0.2;
const HISTORY = 11;

// FreeVela: raw readings of the spare analog inputs (GPIO 36, 39, 34) and the battery (GPIO 35), read
// when STATE is read, to look for a charger signal on the board. Nothing else uses those pins.
export const adc = {
	get c0() { return Analog.read(0); },
	get c3() { return Analog.read(3); },
	get c6() { return Analog.read(6); },
	get c7() { return Analog.read(7); },
};

const initialState = {
	fuel: toFuel(battRead()),
	save: Preference.get("pwr", "save") || 20, // note: a stored 0 reads back as 20
	chr: 0,
};

const FUEL_UPDATED = "pwr/FUEL_UPDATED";
const SAVER_UPDATED = "pwr/SAVER_UPDATED";
const SLEEP_REQUESTED = "pwr/SLEEP_REQUESTED";

export const fuelUpdated = (payload) => ({ type: FUEL_UPDATED, payload });
export const saverUpdated = (payload) => ({ type: SAVER_UPDATED, payload });

const reducer = (state = initialState, { type, payload }) => {
	switch (type) {
		case FUEL_UPDATED:
			return { ...state, fuel: payload };   // FreeVela: `chr` comes from pwr/CHARGING
		case "pwr/CHARGING":
			return { ...state, chr: payload ? 1 : 0 };
		case SAVER_UPDATED:
			Preference.set("pwr", "save", payload);
			return { ...state, save: payload };
		default:
			return state;
	}
};

const middleware = ({ dispatch, getState }) => {
	let fuelTimer = null;
	let fuelTimer2 = null;
	const updateFuel = () => dispatch({ type: FUEL_UPDATED, payload: toFuel(battRead()) });

	// FreeVela: the charging trend (see `charge`).
	const samples = [];
	let lastSample = Time.ticks;
	const setCharging = (on) => {
		if ((getState().pwr.chr ? 1 : 0) !== (on ? 1 : 0))
			dispatch({ type: "pwr/CHARGING", payload: on ? 1 : 0 });
	};
	const mean = (list) => list.reduce((a, b) => a + b, 0) / list.length;
	Timer.repeat(() => {
		const state = getState();
		if (Number(state.motor?.rps) || state.pas?.pedal) {
			samples.length = 0;   // riding: the motor's draw pulls the voltage down
			lastSample = Time.ticks;
			setCharging(false);
			return;
		}
		if (Time.ticks - lastSample < charge.every)
			return;
		lastSample = Time.ticks;
		let sum = 0;
		for (let i = 0; i < 8; i++)
			sum += battRead();
		const reading = sum / 8;
		samples.push(reading);
		if (samples.length > HISTORY)
			samples.shift();
		dispatch({ type: FUEL_UPDATED, payload: toFuel(reading) });
		const n = samples.length;
		const step = n >= 2 ? samples[n - 1] - samples[n - 2] : 0;
		if (step >= CHR_STEP)
			return setCharging(true);
		if (step <= -CHR_STEP)
			return setCharging(false);
		if (n < HISTORY)
			return;
		const rise = mean(samples.slice(-3)) - mean(samples.slice(0, 3));
		if (rise >= CHR_RISE)
			setCharging(true);
		else if (rise <= CHR_FLAT)
			setCharging(false);
	}, 250);
	return (next) => (action) => {
		if (action.type === "sys/LOADED")
			updateFuel();
		if (action.type === SLEEP_REQUESTED) {
			dispatch({ type: "motor/BRAKE_STARTED" });
			standby();
		}
		if (action.type === "pas/PEDAL_STOPED") {
			if (!getState().button)
				fuelTimer2 = Timer.set(() => {
					updateFuel();
					fuelTimer2 = null;
				}, 5000);
		}
		if (action.type === "button/RELEASED") {
			if (!getState().pas.pedal)
				fuelTimer2 = Timer.set(() => {
					updateFuel();
					fuelTimer2 = null;
				}, 5000);
		}
		if (action.type === "pas/PEDAL_STARTED" || action.type === "button/PRESSED") {
			if (fuelTimer2) {
				Timer.clear(fuelTimer2);
				fuelTimer2 = null;
			}
		}
		if (action.type === "sys/IDLE_TIMEOUT") {
			updateFuel();
			fuelTimer = Timer.repeat(updateFuel, 60 * 10 * 1000);
		}
		if (action.type === "sys/IDLE_CLEARED" && fuelTimer) {
			updateFuel();
			Timer.clear(fuelTimer);
			fuelTimer = null;
		}
		next(action);
	};
};

export default { middleware, reducer };
