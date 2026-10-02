// modules/pas.js: Pedal sensor.
import Monitor from "monitor";
import Timer from "timer";
import Time from "time";
import { log } from "lib/sys";

const PAS_TIMEOUT = 500;

const initialState = { pedal: false };

const reducer = (state = initialState, action) => {
	switch (action.type) {
		case "pas/PEDAL_STARTED":
			return { ...state, pedal: true };
		case "pas/PEDAL_STOPED": // sic: "STOPED"
			return { ...state, pedal: false };
		default:
			return state;
	}
};

const load = (store) => {
	const pas = new Monitor({ pin: 33, edge: Monitor.Falling | Monitor.Rising });
	let pasTimer = null;
	let lastPas = pas.read();
	let lastPasTick = Time.ticks;

	pas.onChanged = () => {
		if (lastPasTick + 5 > Time.ticks)
			return log("#! Pas Intrp Panic");
		lastPasTick = Time.ticks;
		if (pas.read() === lastPas)
			return log("#! Pas Miss Intrp");
		lastPas = pas.read();
		if (!store.getState().pas.pedal)
			store.dispatch({ type: "pas/PEDAL_STARTED" });
		if (pasTimer)
			Timer.clear(pasTimer);
		pasTimer = Timer.set(() => {
			store.dispatch({ type: "pas/PEDAL_STOPED" });
			pasTimer = null;
		}, PAS_TIMEOUT);
	};
};

export default { load, reducer };
