// "udid": unique device id bytes, used by the BLE server (see udid.c).
import Hex from "hex";

export function udidBytes() @ "xs_udid_bytes" ;

function udid(dictionary) {
	return Hex.toString(udidBytes(dictionary)).toLowerCase();
}
export default udid;
