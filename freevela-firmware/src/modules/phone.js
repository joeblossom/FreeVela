// modules/phone.js: Phone connection: bridges the BLE server and the store.
import BLE, { isPaired } from "ble";

const initialState = { conn: true, pair: isPaired() };

const reducer = (state = initialState, action) => {
	switch (action.type) {
		case "phone/CONNECTED":
			return { ...state, conn: true, pair: true };
		case "phone/DISCONNECTED":
			return { ...state, conn: false };
		default:
			return state;
	}
};

const load = ({ dispatch, subscribe }) => {
	const phone = new BLE();
	phone.onConnect = () => dispatch({ type: "phone/CONNECTED" });
	phone.onDisconnect = () => dispatch({ type: "phone/DISCONNECTED" });
	phone.onAction = (action) => dispatch(JSON.parse(action));
	subscribe((state) => phone.notifyState(state));
};

export default { load, reducer };
