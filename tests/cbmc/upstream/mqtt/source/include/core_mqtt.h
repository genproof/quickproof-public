/* core_mqtt.h: a stand-in for coreMQTT's header, written for the tests of tools/qp import-cbmc (it is not
 * coreMQTT's code): just what the vendored MQTT_MatchTopic harness needs. */
#ifndef CORE_MQTT_H
#define CORE_MQTT_H
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

typedef enum MQTTStatus {
	MQTTSuccess = 0,
	MQTTBadParameter
} MQTTStatus_t;

MQTTStatus_t MQTT_MatchTopic(const char *pTopicName, const uint16_t topicNameLength,
                             const char *pTopicFilter, const uint16_t topicFilterLength,
                             bool *pIsMatch);
#endif
