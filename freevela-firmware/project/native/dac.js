// "dac": DAC output, used by modules/motor for the throttle signal (see dac.c).
class DAC @ "xs_dac_destructor"  {
	constructor(dictionary) @ "xs_dac" ;
	close() @ "xs_dac_close" ;
	write() @ "xs_dac_write" ;
}
Object.freeze(DAC.prototype);
export { DAC };
export default DAC;
