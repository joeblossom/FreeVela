// lib/redux-logger.js: Logs each dispatched action.
import { log } from "lib/sys";

const loggerMiddleware = ({ dispatch, getState }) => (next) => (action) => {
	log(JSON.stringify(action));
	return next(action);
};

export default loggerMiddleware;
