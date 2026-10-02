// modules/motor.js: Assist: throttle signal, brake, wheel speed, boost.
import Monitor from "monitor";
import Timer from "timer";
import Time from "time";
import DAC from "dac";
import PulseCount from "pulsecount";
import Preference from "preference";
import Digital from "pins/digital";
import { battRead } from "modules/pwr";
import { log } from "lib/sys";

const BOOST_TIMEOUT = 20000;
const MOTOR_MIN = 83;

Digital.write(2, 1);

const lever = new Monitor({
	pin: 32,
	mode: Digital.InputPullUp,
	edge: Monitor.Falling | Monitor.Rising,
});

const initialState = {
	boost: false,
	rps: 0,
	pulse: Preference.get("motor", "pulses") || 0,
	brk: !lever.read(),
	ast: Preference.get("motor", "ast") === 0 ? 0 : 1,
	ebc: Preference.get("motor", "ebc") === 1 ? 1 : 0,
};

export const MOTOR_ROTATED = "motor/MOTOR_ROTADED"; // sic: "ROTADED" in the string
export const RPS_UPDATED = "motor/RPS_UPDATED";
export const BRAKE_STARTED = "motor/BRAKE_STARTED";
export const BRAKE_ENDED = "motor/BRAKE_ENDED";

const reducer = (state = initialState, { type, payload }) => {
	switch (type) {
		case MOTOR_ROTATED:
			Preference.set("motor", "pulses", state.pulse + payload);
			return { ...state, pulse: state.pulse + payload };
		case RPS_UPDATED:
			return { ...state, rps: payload };
		case "motor/BOOST_STARTED":
			return { ...state, boost: true };
		case "motor/BOOST_ENDED":
			return { ...state, boost: false };
		case "motor/BRAKE_STARTED":
			return { ...state, brk: true };
		case "motor/BRAKE_ENDED":
			return { ...state, brk: false };
		case "motor/ASSIST_SET":
			Preference.set("motor", "ast", payload ? 1 : 0);
			return { ...state, ast: payload ? 1 : 0 };
		case "motor/EBC_SET":
			Preference.set("motor", "ebc", payload ? 1 : 0);
			return { ...state, ebc: payload ? 1 : 0 };
	}
	return state;
};

const load = ({ subscribe, dispatch, getState }) => {
	// Wheel-speed sensor. control pin 2 is the same GPIO driven high at module top.
	const rotationSensor = new PulseCount({ signal: 27, control: 2 });
	let lastPulseCount = 0;

	Timer.repeat(() => {
		const pulseCount = rotationSensor.get();
		if (pulseCount > lastPulseCount) {
			const rps = ((pulseCount - lastPulseCount) / 6).toFixed(1); // NB: a string
			dispatch({ type: RPS_UPDATED, payload: rps });
			lastPulseCount = pulseCount;
		} else if (getState().motor.rps !== 0) {
			dispatch({ type: RPS_UPDATED, payload: 0 });
		}
		if (lastPulseCount > 500) {
			dispatch({ type: MOTOR_ROTATED, payload: lastPulseCount });
			lastPulseCount = 0;
			rotationSensor.set(0);
		}
	}, 1000);

	let brakeLastState;
	lever.onChanged = () => {
		if (getState().alarm.armed)
			return;
		const isPressed = !lever.read();
		if (brakeLastState == isPressed)
			return log("#! Brk Miss Intrp");
		brakeLastState = isPressed;
		if (isPressed)
			return dispatch({ type: "motor/BRAKE_STARTED" });
		dispatch({ type: "motor/BRAKE_ENDED" });
	};

	const dac = new DAC({ channel: 1 });
	dac.write(MOTOR_MIN);

	const processWalk = (value, state) => {
		if (value < 110)
			return value + 4;
		if (state.motor.rps < 1.1)
			return value + 1;
		return value - 1;
	};

	const processSave = (value, state) => {
		if (value < 115)
			return value + 3;
		if (value > 215 && state.motor.rps > 2)
			return value - 0.2;
		if (value > 225)
			return value - 0.1;
		if (state.motor.rps > 3.3)
			return value - 0.3;
		if (state.motor.rps < 0.9)
			return value + 0.45;
		if (state.motor.rps < 1.8)
			return value + 0.2;
		return motorValue + 0.09; // sic: uses the captured motorValue, not `value`
	};

	const processDrive = (value, state) => {
		if (value > 225)
			return value - 2;
		const minReturn = MOTOR_MIN + 18 + state.motor.rps * 29;
		if (state.motor.rps && value < minReturn)
			return minReturn;
		if (value < 115)
			return value + 4;
		if (state.motor.rps < 1)
			return value + 0.9;
		if (state.motor.rps < 2)
			return value + 0.65;
		if (state.motor.rps < 3)
			return value + 0.2;
		return value + 0.06;
	};

	const processBoost = (value, state) => {
		if (state.motor.rps < 0.6)
			return value + 3;
		return 254;
	};

	const processStop = (value, state) => MOTOR_MIN;

	let motorTimer;
	let motorValue = MOTOR_MIN;
	let ebcHold = false;

	motorTimer = Timer.repeat(() => {
		const state = getState();
		if (state.motor.brk && state.motor.ebc && state.motor.rps > 2.1 && !ebcHold) {
			ebcHold = true;
			Digital.write(26, 1);
		}
		if (!state.motor.brk && state.motor.ebc && ebcHold) {
			ebcHold = false;
			Digital.write(26, 0);
		}
		if (state.motor.rps > 5.5) {
			dac.write(0);
			log("!# speed motor cut");
			return;
		}
		const process =
			(!state.motor.ast || (!state.pas.pedal && !state.motor.boost) || state.motor.brk) ? processStop
			: (!state.pas.pedal && state.motor.boost) ? processWalk
			: (state.pwr.fuel <= state.pwr.save) ? processSave
			: state.motor.boost ? processBoost
			: processDrive;
		const processed = process(motorValue, state);
		const next = processed > 254 ? 254 : processed < MOTOR_MIN ? MOTOR_MIN : processed;
		dac.write(next);
		motorValue = next;
	}, 50);
};

const middleware = ({ dispatch, getState }) => next => action => {
	if (action.type == "button/PRESSED") {
		if (getState().motor.boost)
			return;
		dispatch({ type: "motor/BOOST_STARTED" });
	}
	if (action.type == "button/RELEASED")
		dispatch({ type: "motor/BOOST_ENDED" });
	if (action.type == "motor/BRAKE_STARTED" || action.type == "pas/PEDAL_STOPED")
		dispatch({ type: "motor/BOOST_ENDED" });
	return next(action);
};

export default { load, reducer, middleware };
