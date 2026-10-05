// modules/button.js: Handlebar button: press, release, double press.
import Monitor from "monitor";
import Digital from "pins/digital";
import Time from "time";
import { log } from "lib/sys";

const button1 = new Monitor({ pin: 3, mode: Digital.InputPullUp, edge: Monitor.Falling | Monitor.Rising });
const button2 = new Monitor({ pin: 0, mode: Digital.InputPullUp, edge: Monitor.Falling | Monitor.Rising });

// FreeVela: live pin read for the key-reset gesture (modules/fv). Active low.
export const buttonHeld = () => !button1.read() || !button2.read();
// FreeVela: each of the button's two inputs (GPIO 3, GPIO 0), 1 = pressed, for finding the wake pin.
export const buttonPins = () => ({ b3: button1.read() ? 0 : 1, b0: button2.read() ? 0 : 1 });

const initialState = false;

const reducer = (state = initialState, action) => {
	switch (action.type) {
		case "button/PRESSED":
			return true;
		case "button/RELEASED":
			return false;
		default:
			return state;
	}
};

const load = ({ dispatch }) => {
	let lastPressed = !button1.read();
	let lastReleaseTime = Time.ticks;
	let lastChangeTime = Time.ticks;

	const handleButton1Press = () => {
		const pressed = !button1.read();
		// lastChangeTime is set once in load() and never updated, so this guard can only fire
		if (lastChangeTime + 2 > Time.ticks)
			return log("#! Btn Intrp Panic");
		if (lastPressed == pressed)
			return log("#! Btn Miss Intrp");
		lastPressed = pressed;
		dispatch({ type: pressed ? "button/PRESSED" : "button/RELEASED" });
		if (!pressed) {
			if (Time.ticks - lastReleaseTime < 400)
				dispatch({ type: "button/DOUBLED" });
			lastReleaseTime = Time.ticks;
		}
	};

	// lastReleaseTime / lastChangeTime state.
	const handleButton2Press = () => {
		const pressed = !button2.read();
		if (lastChangeTime + 2 > Time.ticks)
			return log("#! Btn Intrp Panic");
		if (lastPressed == pressed)
			return log("#! Btn Miss Intrp");
		lastPressed = pressed;
		dispatch({ type: pressed ? "button/PRESSED" : "button/RELEASED" });
		if (!pressed) {
			if (Time.ticks - lastReleaseTime < 400)
				dispatch({ type: "button/DOUBLED" });
			lastReleaseTime = Time.ticks;
		}
	};

	button1.onChanged = handleButton1Press;
	button2.onChanged = handleButton2Press;
};

export default { load, reducer };
