// QEMU-only mock: the emulator has no SAR ADC (real read hangs). Returns a fixed mid-scale reading.
export default class Analog {
	static read(channel) {
		return 2600;
	}
}
