// modules/pwr.js: Battery level, eco threshold, sleep.

import Analog from "analog";
import Timer from "timer";
import Preference from "preference";
import standby from "standby";
import Digital from "pins/digital";

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
			return { ...state, fuel: payload, chr: payload > state.fuel ? 1 : 0 };
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
