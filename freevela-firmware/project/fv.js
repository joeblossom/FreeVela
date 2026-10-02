// modules/fv — FreeVela only (not in Vela's firmware).
// Adds "fv": {"ver", "caps", "trial"} to STATE so the app can tell FreeVela firmware from Vela's
// (sys.ver stays Vela's 2306052112). Confirms a trial boot once a phone unlocks (see fvboot.c).
import config from "mc/config";
import { confirm, trial } from "fvboot";

const initialState = { ver: config.fvVersion, caps: [], trial: trial() };

const reducer = (state = initialState, action) => {
	if (action.type === "fv/CONFIRMED")
		return { ...state, trial: 0 };
	return state;
};

const middleware = ({ dispatch, getState }) => next => action => {
	const result = next(action);
	// phone/CONNECTED is only dispatched after the unlock handshake succeeds (ble.js).
	if (action.type === "phone/CONNECTED" && getState().fv.trial) {
		confirm();
		dispatch({ type: "fv/CONFIRMED" });
	}
	return result;
};

export default { reducer, middleware };
