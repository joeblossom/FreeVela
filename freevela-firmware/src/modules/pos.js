// modules/pos.js: Movement detection.

import Timer from "timer";
import Time from "time";

const MOVING_STARTED = "pos/MOVING_STARTED";
const MOVING_STOPED = "pos/MOVING_STOPED";
const SAT_DATA_RECEIVED = "pos/SAT_DATA_RECEIVED";

export const movingStarted = () => ({ type: MOVING_STARTED });
export const movingStoped = () => ({ type: MOVING_STOPED });
export const satDataReceived = (payload) => ({ type: SAT_DATA_RECEIVED, payload });

const initialState = { move: 0, sat: null };

const reducer = (state = initialState, { type, payload }) => {
	switch (type) {
		case MOVING_STARTED:
			return { ...state, move: 1 };
		case MOVING_STOPED:
			return { ...state, move: 0 };
		case SAT_DATA_RECEIVED:
			return { ...state, sat: payload };
		default:
			return state;
	}
};

export default { reducer };
