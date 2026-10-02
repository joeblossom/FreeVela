/* "standby": deep sleep.
   Wake source confirmed on the bike (2026-10-01): holding the brake lever (GPIO 32) and the
   handlebar button (GPIO 0) together; neither alone wakes it. Both are RTC GPIOs, active low.
   fvboot.c releases them from the RTC domain after the wake. */
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
	esp_sleep_enable_ext1_wakeup((1ULL << GPIO_NUM_0) | (1ULL << GPIO_NUM_32), ESP_EXT1_WAKEUP_ALL_LOW);
	esp_deep_sleep_start();
}
