// lib/redux.js: Minimal Redux: store, reducers, middleware.

function mapValues(obj, fn) {
	return Object.keys(obj).reduce((result, key) => {
		result[key] = fn(obj[key], key);
		return result;
	}, {});
}

function pick(obj, fn) {
	return Object.keys(obj).reduce((result, key) => {
		if (fn(obj[key])) {
			result[key] = obj[key];
		}
		return result;
	}, {});
}

function bindActionCreator(actionCreator, dispatch) {
	return (...args) => dispatch(actionCreator(...args));
}

export function bindActionCreators(actionCreators, dispatch) {
	return typeof actionCreators === "function"
		? bindActionCreator(actionCreators, dispatch)
		: mapValues(actionCreators, (actionCreator) => bindActionCreator(actionCreator, dispatch));
}

export function compose(...funcs) {
	return (arg) => funcs.reduceRight((composed, f) => f(composed), arg);
}

export function applyMiddleware(...middlewares) {
	return (next) => (reducer, initialState) => {
		var store = next(reducer, initialState);
		var dispatch = store.dispatch;
		var chain = [];

		chain = middlewares.map((middleware) => middleware({
			getState: store.getState,
			dispatch: (action) => dispatch(action),
		}));
		dispatch = compose(...chain)(store.dispatch);

		return { ...store, dispatch };
	};
}

export function combineReducers(reducers) {
	const finalReducers = pick(reducers, (val) => typeof val === "function");
	return (state, action) => mapValues(finalReducers, (reducer, key) => reducer(state && state[key], action));
}

export function createStore(reducer) {
	let currentReducer = reducer;
	let currentState;
	let listeners = [];

	function getState() {
		return currentState;
	}

	function subscribe(listener) {
		listeners.push(listener);
		return function unsubscribe() {
			var index = listeners.indexOf(listener);
			listeners.splice(index, 1);
		};
	}

	function dispatch(action) {
		const nextState = currentReducer(currentState, action);
		// Note: listeners run BEFORE currentState is updated (getState() inside a listener
		listeners.slice().forEach((listener) => listener(nextState));
		currentState = nextState;
		return action;
	}

	function replaceReducer(nextReducer) {
		currentReducer = nextReducer;
		dispatch({ type: "@@redux/INIT" });
	}

	dispatch({ type: "@@redux/INIT" });

	return { dispatch, subscribe, getState, replaceReducer };
}

export function toValueChange(module, key, fn) {
	let lastValue;
	return (state) => {
		if (lastValue !== state[module][key]) {
			fn(state);
			lastValue = state[module][key];
		}
	};
}
