/* "standby": deep sleep.
   Wakes when the handlebar button (GPIO 0) or the brake lever (GPIO 32) is pressed. Both are RTC
   GPIOs, active low. Requiring both together (as after a sleep from the original firmware) didn't
   wake the bike from this firmware's sleep (2026-10-05), so either one now does; Developer tools →
   State shows the live inputs to confirm the pins. fvboot.c releases them after the wake. */
#include "xsmc.h"
#include "xsHost.h"
#include "esp_sleep.h"
#include "driver/rtc_io.h"

void xs_standby(xsMachine *the)
{
	/* Keep the RTC pull-ups on during sleep so the inputs idle high. */
	esp_sleep_pd_config(ESP_PD_DOMAIN_RTC_PERIPH, ESP_PD_OPTION_ON);
	rtc_gpio_pullup_en(GPIO_NUM_0);
	rtc_gpio_pulldown_dis(GPIO_NUM_0);
	rtc_gpio_pullup_en(GPIO_NUM_32);
	rtc_gpio_pulldown_dis(GPIO_NUM_32);
	/* IDF 3.3's ext1 can't wake on "any low", so: ext0 on the button, ext1 on the brake lever alone. */
	esp_sleep_enable_ext0_wakeup(GPIO_NUM_0, 0);
	esp_sleep_enable_ext1_wakeup(1ULL << GPIO_NUM_32, ESP_EXT1_WAKEUP_ALL_LOW);
	esp_deep_sleep_start();
}
