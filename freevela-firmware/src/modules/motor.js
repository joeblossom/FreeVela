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

// FreeVela: live lever read for the key-reset gesture (modules/fv). BRAKE_STARTED isn't dispatched
// while the alarm is armed, so the gesture reads the pin instead.
export const brakeHeld = () => !lever.read();

// FreeVela: motor settings the app can change (fv/TUNE_SET, see modules/fv), saved as strings in
// Preference "tune"/<key>. The defaults are the stock curves, except `cr`.
//   top  speed (rps) assist tapers toward; the throttle ceiling is MOTOR_MIN + mg + sl × top
//        (stock: a fixed 225). The hard cut is the higher of the stock 5.5 rps and top + 0.5.
//   btn  0 = the button is boost / walk assist (stock), 1 = a throttle up to `top`, pedalling or not.
//   mg   throttle margin above the speed floor (MOTOR_MIN + mg + sl × rps).
//   sl   throttle units per rps in the floor and ceiling.
//   cr   climb per 50 ms in the drive curve above 3 rps. The stock 0.06 took ~23 s to get back to the
//        ceiling after a couple of seconds' coasting at speed; 0.4 takes ~3 s.
export const tune = { top: (225 - MOTOR_MIN - 18) / 29, btn: 0, mg: 18, sl: 29, cr: 0.4 };
export const TUNE_RANGE = { top: [2.5, 5.3], btn: [0, 1], mg: [0, 60], sl: [15, 45], cr: [0, 1] };
for (const key in tune) {
	const saved = parseFloat(Preference.get("tune", key));
	if (saved >= TUNE_RANGE[key][0] && saved <= TUNE_RANGE[key][1])
		tune[key] = saved;
}
// Live throttle output and which curve set it, for the app's ride recorder (read with STATE).
export const live = { out: MOTOR_MIN, crv: "stop" };
const ceiling = () => MOTOR_MIN + tune.mg + tune.sl * tune.top;

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
	// FreeVela: Vela counted pulses once a second. This keeps the same one-second window (so rps
	// means the same thing) but slides it every 250 ms, so the throttle floor follows speed sooner.
	const slots = [0, 0, 0, 0];
	let slot = 0;
	let ticks = 0;

	Timer.repeat(() => {
		const pulseCount = rotationSensor.get();
		slots[slot] = pulseCount - lastPulseCount;
		slot = (slot + 1) % slots.length;
		lastPulseCount = pulseCount;
		const pulses = slots[0] + slots[1] + slots[2] + slots[3];
		ticks++;
		if (pulses > 0) {
			const rps = (pulses / 6).toFixed(1); // NB: a string
			if (rps !== getState().motor.rps || ticks % 4 === 0)   // at least once a second while moving
				dispatch({ type: RPS_UPDATED, payload: rps });
		} else if (getState().motor.rps !== 0) {
			dispatch({ type: RPS_UPDATED, payload: 0 });
		}
		if (lastPulseCount > 500) {
			dispatch({ type: MOTOR_ROTATED, payload: lastPulseCount });
			lastPulseCount = 0;
			rotationSensor.set(0);
		}
	}, 250);

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
		if (value > ceiling())
			return value - 2;
		const minReturn = MOTOR_MIN + tune.mg + state.motor.rps * tune.sl;
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
		return value + tune.cr;
	};

	// FreeVela: button as a throttle (tune.btn 1). Climbs about 60 units a second to the ceiling,
	// so it asks for no more than the top speed; drops back the same way if the top is lowered.
	const processThrottle = (value, state) => {
		const top = ceiling();
		if (value < top)
			return Math.min(top, value + 3);
		return Math.max(top, value - 2);
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
		if (state.motor.rps > Math.max(5.5, tune.top + 0.5)) {
			dac.write(0);
			motorValue = MOTOR_MIN;   // FreeVela: start again from the floor, not the old value
			live.out = 0;
			live.crv = "cut";
			log("!# speed motor cut");
			return;
		}
		const [process, crv] =
			(!state.motor.ast || state.motor.brk) ? [processStop, "stop"]
			: (tune.btn && state.motor.boost) ? [processThrottle, "throttle"]
			: (!state.pas.pedal && !state.motor.boost) ? [processStop, "stop"]
			: (!state.pas.pedal && state.motor.boost) ? [processWalk, "walk"]
			: (state.pwr.fuel <= state.pwr.save) ? [processSave, "eco"]
			: state.motor.boost ? [processBoost, "boost"]
			: [processDrive, "drive"];
		const processed = process(motorValue, state);
		const next = processed > 254 ? 254 : processed < MOTOR_MIN ? MOTOR_MIN : processed;
		dac.write(next);
		motorValue = next;
		live.out = Math.round(next);
		live.crv = crv;
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
	// FreeVela: as a throttle the button keeps working when you stop pedalling.
	if (action.type == "motor/BRAKE_STARTED" || (action.type == "pas/PEDAL_STOPED" && !tune.btn))
		dispatch({ type: "motor/BOOST_ENDED" });
	return next(action);
};

export default { load, reducer, middleware };
