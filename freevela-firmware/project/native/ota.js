// "ota": firmware updates over BLE (see ota.c).
// API as used by ble.js: new OTA() (begins a session, erasing the spare slot), write(ArrayBuffer), complete().
class OTA @ "xs_ota_destructor" {
	constructor() @ "xs_ota";
	write(buffer) @ "xs_ota_write";
	complete() @ "xs_ota_complete";
	cancel() @ "xs_ota_cancel";
}
Object.freeze(OTA.prototype);
export default OTA;
