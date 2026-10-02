// modules/light.js: Headlight: auto/on/off.
import Preference from "preference";
import Digital from "pins/digital";

Digital.write(4, 0);

const initialState = { mode: Preference.get("light", "mode") || 0 };

const reducer = (state = initialState, action) => {
	switch (action.type) {
		case "light/MODE_SET":
			Preference.set("light", "mode", action.payload);
			return { ...state, mode: action.payload };
		default:
			return state;
	}
};

const load = ({ subscribe }) => {
	let lastIdle;
	subscribe((state) => {
		if (state.light?.mode === 1)
			return Digital.write(4, 1);
		if (state.light?.mode === -1)
			return Digital.write(4, 0);
		if (lastIdle === state.sys.idle)
			return;
		Digital.write(4, state.sys.idle ? 0 : 1);
		lastIdle = state.sys.idle;
	});
};

export default { load, reducer };
