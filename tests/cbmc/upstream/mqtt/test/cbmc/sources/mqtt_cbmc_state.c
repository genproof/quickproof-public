/* mqtt_cbmc_state.c: a stand-in for coreMQTT's proof helpers, written for the tests of tools/qp import-cbmc
 * (it is not coreMQTT's code). */
#include <stdlib.h>
#include "mqtt_cbmc_state.h"

bool isValidMqttTopic(const char *pTopic, uint16_t length)
{
	bool ok;
	if (pTopic == NULL || length == 0u)
		ok = false;
	return ok;
}
