/* "dac": DAC output module (ESP32 DAC, IDF v3.3).
   motor.js uses new DAC({channel: 1}) (GPIO 25) and write(value) with fractional values 0..254. */
#include "xsmc.h"
#include "xsHost.h"
#include "mc.xs.h"
#include "driver/dac.h"

typedef struct { dac_channel_t channel; } xsDACRecord, *xsDAC;

void xs_dac_destructor(void *data)
{
	if (data) {
		dac_output_disable(((xsDAC)data)->channel);
		c_free(data);
	}
}

void xs_dac(xsMachine *the)
{
	int channel;
	xsmcVars(1);
	xsmcGet(xsVar(0), xsArg(0), xsID_channel);
	channel = xsmcToInteger(xsVar(0));
	if (channel != DAC_CHANNEL_1 && channel != DAC_CHANNEL_2)
		xsRangeError("invalid channel");
	xsDAC dac = c_calloc(1, sizeof(xsDACRecord));
	if (!dac)
		xsUnknownError("no memory");
	dac->channel = channel;
	dac_output_enable(dac->channel);
	xsmcSetHostData(xsThis, dac);
}

void xs_dac_close(xsMachine *the)
{
	xs_dac_destructor(xsmcGetHostData(xsThis));
	xsmcSetHostData(xsThis, NULL);
}

void xs_dac_write(xsMachine *the)
{
	xsDAC dac = xsmcGetHostData(xsThis);
	double value = xsmcToNumber(xsArg(0));
	if (!dac)
		xsUnknownError("closed");
	if (value < 0) value = 0;
	if (value > 255) value = 255;
	dac_output_voltage(dac->channel, (uint8_t)value);
}
