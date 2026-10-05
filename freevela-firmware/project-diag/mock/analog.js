// QEMU-only mock: the emulator has no SAR ADC (real read hangs). Returns a fixed mid-scale reading,
// or what a test puts in `Analog.values[channel]`.
export default class Analog {
	static values = {};
	static read(channel) {
		return Analog.values[channel] ?? 2600;
	}
}
