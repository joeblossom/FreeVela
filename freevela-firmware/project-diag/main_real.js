// main.js: FreeVela firmware entry point. Builds the store from the modules (no cellular/cloud) plus modules/fv.
// Nothing is exported; `loadModules` is module-local.
import Time from "time";
import { createStore, combineReducers, applyMiddleware } from "lib/redux";
import loggerMiddleware from "lib/redux-logger";
import sys from "modules/sys";
import alarm from "modules/alarm";
import pas from "modules/pas";
import phone from "modules/phone";
import light from "modules/light";
import pos from "modules/pos";
import pwr from "modules/pwr";
import button from "modules/button";
import motor from "modules/motor";
import fv from "modules/fv";

const loadModules = (modules) => {
	const reducers = {};
	Object.keys(modules).forEach((name) => {
		if (!modules[name].reducer) return;
		reducers[name] = modules[name].reducer;
	});
	const reducer = combineReducers(reducers);
	const moduleArray = Object.keys(modules).map((name) => modules[name]);
	const middlewareSelector = (module) => module.middleware;
	const middlewares = moduleArray.filter(middlewareSelector).map(middlewareSelector);
	const createStoreWithMiddleware = applyMiddleware(loggerMiddleware, ...middlewares)(createStore);
	const store = createStoreWithMiddleware(reducer);
	moduleArray.forEach((module) => module.load?.(store));
};

loadModules({ sys, alarm, pas, phone, light, pos, pwr, button, motor, fv });
trace(Time.ticks + "\n");
