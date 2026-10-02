// modules/sys.js: Uptime, date, idle timer, heartbeat LED, version.
import config from "mc/config";
import Time from "time";
import Timer from "timer";
import Digital from "pins/digital";
import sleep from "lib/sleep";

const IDLE_TIMEOUT = 60000;

const currentDate = () => Date.now() / 1000 | 0;

const currentLive = () => Time.ticks / 1000 | 0;

const initialState = {
	idle: 1,
	date: currentDate(),
	ver: config.version || "DEV",
	live: 0,
};

// These are action objects, not action creators.
const loaded = { type: "sys/LOADED" };
export const idleCleared = { type: "sys/IDLE_CLEARED" };
export const idleTimeout = { type: "sys/IDLE_TIMEOUT" };

const reducer = (state = initialState, { type }) => {
	const datedState = { ...state, date: currentDate(), live: currentLive() };
	switch (type) {
		case "sys/IDLE_CLEARED":
			return { ...datedState, idle: 0 };
		case "sys/IDLE_TIMEOUT":
			return { ...datedState, idle: 1 };
	}
	return { ...datedState };
};

const middleware = ({ dispatch, getState }) => {
	let idleTimer = null;

	// Heartbeat: GPIO 15 pulses high for 100 ms every 3 s.
	Digital.write(15, 0);
	Timer.repeat(async () => {
		Digital.write(15, 1);
		await sleep(100);
		Digital.write(15, 0);
	}, 3000);

	return (next) => (action) => {
		switch (action.type) {
			case "sys/LOADED":
			case "pos/BUTTON_PRESSED":
			case "pos/BUTTON_RELEASED": // sic
			case "motor/BRAKE_STARTED":
			case "motor/RPS_UPDATED":
			case "phone/CONNECTED":
			case "button/PRESSED":
			case "alarm/DESARM":
				if (idleTimer)
					Timer.clear(idleTimer);
				idleTimer = Timer.set(() => {
					dispatch(idleTimeout);
					idleTimer = null;
				}, IDLE_TIMEOUT);
				if (getState().sys.idle)
					dispatch(idleCleared);
		}
		return next(action);
	};
};

const load = ({ dispatch }) => {
	dispatch(loaded);
};

export default { middleware, reducer, load };
