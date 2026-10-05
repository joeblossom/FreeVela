/* "fvboot" — FreeVela trial-boot safety net (not in Vela's firmware).

   A newly installed image runs on trial until a phone completes the unlock handshake on it
   (JS calls confirm() on phone/CONNECTED). While on trial it switches the bike back to the image
   in the other OTA slot — the firmware it was installed from — if either:
     - it boots FV_TRIAL_BOOTS times without being confirmed (crash loops, resets), or
     - it runs FV_TRIAL_SECONDS without being confirmed (boots but Bluetooth doesn't work).
   Once confirmed, that image is never switched away from by this code.

   freevela_boot_check() runs from app_main (Moddable main.c patch) after nvs_flash_init and before
   any JS, so it also runs when the JS side crashes. It also releases the wake pins from the RTC
   domain after a deep-sleep wake, so they work as ordinary inputs again. */
#include "xsmc.h"
#include "xsHost.h"
#include "esp_system.h"
#include "esp_attr.h"
#include "esp_partition.h"
#include "esp_sleep.h"
#include "driver/rtc_io.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>
#include <stdio.h>

/* nvs.h and esp_ota_ops.h aren't on Moddable OS201230's include path; declare what we use. */
typedef uint32_t nvs_handle;
typedef enum { NVS_READONLY, NVS_READWRITE } nvs_open_mode;
extern esp_err_t nvs_open(const char *name, nvs_open_mode open_mode, nvs_handle *out_handle);
extern esp_err_t nvs_get_u8(nvs_handle handle, const char *key, uint8_t *out_value);
extern esp_err_t nvs_set_u8(nvs_handle handle, const char *key, uint8_t value);
extern esp_err_t nvs_get_u32(nvs_handle handle, const char *key, uint32_t *out_value);
extern esp_err_t nvs_set_u32(nvs_handle handle, const char *key, uint32_t value);
extern esp_err_t nvs_get_u64(nvs_handle handle, const char *key, uint64_t *out_value);
extern esp_err_t nvs_set_u64(nvs_handle handle, const char *key, uint64_t value);
extern esp_err_t nvs_erase_all(nvs_handle handle);
extern esp_err_t nvs_commit(nvs_handle handle);
extern void nvs_close(nvs_handle handle);
extern const esp_partition_t *esp_ota_get_running_partition(void);
extern const esp_partition_t *esp_ota_get_next_update_partition(const esp_partition_t *start_from);
extern esp_err_t esp_ota_set_boot_partition(const esp_partition_t *partition);

#ifndef FV_TRIAL_SECONDS
#define FV_TRIAL_SECONDS 600
#endif
#define FV_TRIAL_BOOTS 3
#define NS "fvboot"

static volatile int gConfirmed = 1;
static uint32_t gBoots;
static TickType_t gTrialStart;

/* Set by the trial timer, then the chip restarts and freevela_boot_check does the switch. Flash
   writes from the timer task can stall (seen in QEMU while the BLE controller holds the other
   core), whereas the boot check runs before anything else starts. Survives a software restart. */
#define REVERT_MAGIC 0x46565256
static RTC_NOINIT_ATTR uint32_t gRevertRequested;

static void revert(const char *why)
{
	const esp_partition_t *other = esp_ota_get_next_update_partition(NULL);
	printf("fvboot: not confirmed (%s); switching back to the previous firmware\n", why);
	/* set_boot_partition verifies the image first, so this fails safely if the slot is empty. */
	if (other && ESP_OK == esp_ota_set_boot_partition(other)) {
		nvs_handle h;
		if (ESP_OK == nvs_open(NS, NVS_READWRITE, &h)) {
			nvs_erase_all(h);   /* a later reinstall of this image starts a fresh trial */
			nvs_commit(h);
			nvs_close(h);
		}
		esp_restart();
	}
	printf("fvboot: no valid previous firmware; staying on this one\n");
}

static void trialTask(void *arg)
{
	vTaskDelay(pdMS_TO_TICKS(FV_TRIAL_SECONDS * 1000));
	if (!gConfirmed) {
		printf("fvboot: trial time ran out; restarting to switch back\n");
		gRevertRequested = REVERT_MAGIC;
		esp_restart();
	}
	vTaskDelete(NULL);
}

void freevela_boot_check(void)
{
	int revertRequested = (gRevertRequested == REVERT_MAGIC);
	gRevertRequested = 0;
	if (ESP_SLEEP_WAKEUP_EXT1 == esp_sleep_get_wakeup_cause()) {
		rtc_gpio_deinit(GPIO_NUM_0);
		rtc_gpio_deinit(GPIO_NUM_32);
	}

	uint8_t sha[32];
	uint64_t img = 0, stored = 0;
	if (ESP_OK != esp_partition_get_sha256(esp_ota_get_running_partition(), sha)) {
		printf("fvboot: can't hash the running image; trial disabled\n");
		return;
	}
	memcpy(&img, sha, sizeof(img));

	nvs_handle h;
	if (ESP_OK != nvs_open(NS, NVS_READWRITE, &h)) {
		printf("fvboot: no NVS; trial disabled\n");
		return;
	}
	uint8_t confirmed = 0;
	gBoots = 0;
	if (ESP_OK != nvs_get_u64(h, "img", &stored) || stored != img) {
		/* First boot of a newly installed image. */
		nvs_set_u64(h, "img", img);
		nvs_set_u8(h, "ok", 0);
		nvs_set_u32(h, "boots", 0);
	} else {
		nvs_get_u8(h, "ok", &confirmed);
		nvs_get_u32(h, "boots", &gBoots);
	}
	if (confirmed) {
		nvs_close(h);
		gConfirmed = 1;
		return;
	}
	gBoots += 1;
	nvs_set_u32(h, "boots", gBoots);
	nvs_commit(h);
	nvs_close(h);
	gConfirmed = 0;
	if (revertRequested) {
		revert("trial time ran out");
		return;
	}
	if (gBoots > FV_TRIAL_BOOTS) {
		revert("too many boots");
		return;
	}
	printf("fvboot: trial boot %u of %u (confirm by unlocking from the app within %u s)\n",
		(unsigned)gBoots, (unsigned)FV_TRIAL_BOOTS, (unsigned)FV_TRIAL_SECONDS);
	gTrialStart = xTaskGetTickCount();
	xTaskCreate(trialTask, "fvtrial", 4096, NULL, 5, NULL);
}

/* JS: confirm() — a phone completed the unlock handshake on this image. */
void xs_fvboot_confirm(xsMachine *the)
{
	if (gConfirmed)
		return;
	nvs_handle h;
	if (ESP_OK == nvs_open(NS, NVS_READWRITE, &h)) {
		nvs_set_u8(h, "ok", 1);
		nvs_commit(h);
		nvs_close(h);
	}
	gConfirmed = 1;
	printf("fvboot: confirmed\n");
}

/* JS: trialLeft() — seconds left in this boot's trial window, or 0 once confirmed. */
void xs_fvboot_trial_left(xsMachine *the)
{
	uint32_t ran = (uint32_t)((xTaskGetTickCount() - gTrialStart) * portTICK_PERIOD_MS / 1000);
	xsmcSetInteger(xsResult, gConfirmed || ran >= FV_TRIAL_SECONDS ? 0 : (int)(FV_TRIAL_SECONDS - ran));
}

/* JS: trialBoots() — how many unconfirmed boots the trial allows. */
void xs_fvboot_trial_boots(xsMachine *the)
{
	xsmcSetInteger(xsResult, FV_TRIAL_BOOTS);
}

/* JS: trial() — boots so far while on trial, or 0 once confirmed. */
void xs_fvboot_trial(xsMachine *the)
{
	xsmcSetInteger(xsResult, gConfirmed ? 0 : (int)gBoots);
}
