/* mqtt_cbmc_state.h: a stand-in for coreMQTT's proof helper header, written for the tests of tools/qp
 * import-cbmc (it is not coreMQTT's code). */
#ifndef MQTT_CBMC_STATE_H
#define MQTT_CBMC_STATE_H
#include <stdbool.h>
#include "core_mqtt.h"

#ifndef MAX_TOPIC_NAME_FILTER_LENGTH
#define MAX_TOPIC_NAME_FILTER_LENGTH 10
#endif

bool isValidMqttTopic(const char *pTopic, uint16_t length);
#endif
