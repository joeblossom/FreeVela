/* "ota": firmware updates over BLE, on ESP-IDF v3.3 esp_ota_* APIs.
   Error strings: "no update parition" (sic), "begin failed", "write failed", "bad state", "bad image",
   "can't change boot partition".
   The session begins (and erases the spare slot) on the first write, not in the constructor that
   ble.js runs at every boot, so the previous firmware stays in the spare slot for fvboot.c to switch
   back to. Vela's firmware erases it at every boot. The first write takes several seconds. */
#include "xsmc.h"
#include "xsHost.h"
#include "esp_partition.h"

/* esp_ota_ops.h (components/app_update) isn't on Moddable OS201230's include path; declare what we use. */
typedef uint32_t esp_ota_handle_t;
#define OTA_SIZE_UNKNOWN 0xffffffff
extern const esp_partition_t *esp_ota_get_next_update_partition(const esp_partition_t *start_from);
extern esp_err_t esp_ota_begin(const esp_partition_t *partition, size_t image_size, esp_ota_handle_t *out_handle);
extern esp_err_t esp_ota_write(esp_ota_handle_t handle, const void *data, size_t size);
extern esp_err_t esp_ota_end(esp_ota_handle_t handle);
extern esp_err_t esp_ota_set_boot_partition(const esp_partition_t *partition);

typedef struct {
	esp_ota_handle_t handle;
	const esp_partition_t *partition;
	int open;
} xsOTARecord, *xsOTA;

void xs_ota_destructor(void *data)
{
	xsOTA ota = data;
	if (!ota) return;
	if (ota->open)
		esp_ota_end(ota->handle);
	c_free(ota);
}

void xs_ota(xsMachine *the)
{
	xsOTA ota = c_calloc(1, sizeof(xsOTARecord));
	if (!ota)
		xsUnknownError("no memory");
	ota->partition = esp_ota_get_next_update_partition(NULL);
	if (!ota->partition) {
		c_free(ota);
		xsUnknownError("no update parition");
	}
	xsmcSetHostData(xsThis, ota);
}

static xsOTA getOTA(xsMachine *the)
{
	xsOTA ota = xsmcGetHostData(xsThis);
	if (!ota || !ota->open)
		xsUnknownError("bad state");
	return ota;
}

void xs_ota_write(xsMachine *the)
{
	xsOTA ota = xsmcGetHostData(xsThis);
	if (ota && !ota->open && ota->partition) {
		if (ESP_OK != esp_ota_begin(ota->partition, OTA_SIZE_UNKNOWN, &ota->handle))
			xsUnknownError("begin failed");
		ota->open = 1;
	}
	ota = getOTA(the);
	void *data = xsmcToArrayBuffer(xsArg(0));
	int length = xsmcGetArrayBufferLength(xsArg(0));
	if (ESP_OK != esp_ota_write(ota->handle, data, length))
		xsUnknownError("write failed");
}

void xs_ota_complete(xsMachine *the)
{
	xsOTA ota = getOTA(the);
	ota->open = 0;
	if (ESP_OK != esp_ota_end(ota->handle))
		xsUnknownError("bad image");
	if (ESP_OK != esp_ota_set_boot_partition(ota->partition))
		xsUnknownError("can't change boot partition");
}

void xs_ota_cancel(xsMachine *the)
{
	xsOTA ota = xsmcGetHostData(xsThis);
	if (ota && ota->open) {
		ota->open = 0;
		esp_ota_end(ota->handle);
	}
}
