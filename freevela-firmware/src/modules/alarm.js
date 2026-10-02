// modules/alarm.js: Alarm: arm/disarm, siren, wheel lock, over-speed buzzer.
import Timer from "timer";
import Preference from "preference";
import Digital from "pins/digital";

let timer = null;

Digital.write(14, 0);

const beep = (cb) => {
	if (timer)
		Timer.clear(timer);
	timer = null;
	Digital.write(14, 0);
	timer = Timer.set(() => {
		Digital.write(14, 1);
		timer = Timer.set(() => {
			Digital.write(14, 0);
			timer = null;
			cb?.();
		}, 100);
	}, 10);
};

const beepTwice = () => {
	if (timer)
		Timer.clear(timer);
	timer = null;
	beep(() => {
		timer = Timer.set(() => beep(), 100);
	});
};

const initialState = {
	armed: Preference.get("alarm", "armed") || false,
	trig: Preference.get("alarm", "trig") || false,
};

export const trigger = { type: "alarm/TRIGGER" };

const reducer = (state = initialState, action) => {
	switch (action.type) {
		case "alarm/ARM":
			Preference.set("alarm", "armed", true);
			return { ...state, armed: true };
		case "alarm/TRIGGER":
			Preference.set("alarm", "trig", true);
			return { ...state, trig: true };
		case "alarm/DESARM":
			Preference.set("alarm", "trig", false);
			Preference.set("alarm", "armed", false);
			return { ...state, armed: false, trig: false };
		default:
			return state;
	}
};

const middleware = ({ dispatch, getState }) => next => action => {
	// Over-speed buzzer. Every RPS update drives GPIO 14 on or off, regardless of alarm state.
	if ("motor/RPS_UPDATED" === action.type) {
		if (action.payload > 7.5)
			Digital.write(14, 1);
		else
			Digital.write(14, 0);
	}
	switch (action.type) {
		case "button/PRESSED":
		case "motor/ROTATED":
		case "pos/MOVING_STARTED":
		case "motor/RPS_UPDATED":
		case "pas/PEDAL_STARTED":
			if (getState().alarm.armed)
				dispatch(trigger);
			break;
		case "alarm/ARM":
			Digital.write(26, 1);
			dispatch({ type: "sys/IDLE_TIMEOUT" });
			beep();
			break;
		case "alarm/DESARM":
			Digital.write(26, 0);
			beepTwice();
			break;
		case "alarm/TRIGGER":
			Digital.write(14, 1);
			Digital.write(26, 1);
			if (timer)
				Timer.clear(timer);
			timer = Timer.set(() => {
				Digital.write(14, 0);
				timer = null;
			}, 15000);
	}
	return next(action);
};

export default { reducer, middleware };
