/* "lib/sys": log and restart helpers. */
#include "xsmc.h"
#include "xsHost.h"
#include "esp_system.h"

void xs_sys_log(xsMachine *the)
{
	if (xsmcArgc > 0)
		xsTrace(xsmcToString(xsArg(0)));
}

void xs_sys_restart(xsMachine *the)
{
	esp_restart();
}
