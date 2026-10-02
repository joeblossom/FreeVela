/* "udid": unique-id bytes.
   The bike advertises 7 bytes (e.g. b2 34 94 54 1a e1 64 = ? + MAC 34:94:54:1a:e1:64).
   ASSUMPTION: first byte is the factory-MAC CRC from eFuse BLK0, then the 6-byte factory MAC.
   Verify against the real bike's scan response before relying on it. */
#include "xsmc.h"
#include "xsHost.h"
#include "soc/efuse_reg.h"

void xs_udid_bytes(xsMachine *the)
{
	uint32_t low = REG_READ(EFUSE_BLK0_RDATA1_REG);
	uint32_t high = REG_READ(EFUSE_BLK0_RDATA2_REG);
	uint8_t bytes[7] = {
		(uint8_t)(high >> 16),	/* MAC CRC */
		(uint8_t)(high >> 8), (uint8_t)high,
		(uint8_t)(low >> 24), (uint8_t)(low >> 16), (uint8_t)(low >> 8), (uint8_t)low
	};
	xsmcSetArrayBuffer(xsResult, bytes, sizeof(bytes));
}
