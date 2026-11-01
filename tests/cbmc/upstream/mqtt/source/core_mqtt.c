/* core_mqtt.c: a stand-in for coreMQTT's MQTT_MatchTopic, written for the tests of tools/qp import-cbmc (it
 * is not coreMQTT's code).  MQTT topic matching with the wildcards '+' (one level) and '#' (the rest). */
#include "core_mqtt.h"

static bool matchFilter(const char *name, uint16_t nameLength, const char *filter, uint16_t filterLength)
{
	uint16_t n = 0, f = 0;
	while (f < filterLength) {
		if (filter[f] == '#')
			return true;
		if (filter[f] == '+') {
			/* the wildcard scan: skip one level of the topic name */
			while (n < nameLength && name[n] != '/')
				n = n + 1;
			f = f + 1;
			continue;
		}
		if (n >= nameLength || name[n] != filter[f])
			return false;
		n = n + 1;
		f = f + 1;
	}
	return n == nameLength;
}

MQTTStatus_t MQTT_MatchTopic(const char *pTopicName, const uint16_t topicNameLength,
                             const char *pTopicFilter, const uint16_t topicFilterLength,
                             bool *pIsMatch)
{
	if (pTopicName == NULL || topicNameLength == 0u || pTopicFilter == NULL || topicFilterLength == 0u ||
	    pIsMatch == NULL)
		return MQTTBadParameter;
	/* a topic name starting with '$' never matches a filter starting with a wildcard (MQTT 3.1.1, 4.7.2) */
	if (pTopicName[0] == '$' && (pTopicFilter[0] == '#' || pTopicFilter[0] == '+')) {
		*pIsMatch = false;
		return MQTTSuccess;
	}
	*pIsMatch = matchFilter(pTopicName, topicNameLength, pTopicFilter, topicFilterLength);
	return MQTTSuccess;
}
