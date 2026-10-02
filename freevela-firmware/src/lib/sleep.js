// lib/sleep.js: await sleep(ms).
import Timer from "timer";

const sleep = (ms) => new Promise((resolve) => Timer.set(resolve, ms));

export default sleep;
