#ifndef DATA_SENDER_H
#define DATA_SENDER_H

#include <Arduino.h>
#include "sensor_manager.h"

enum SendResult {
    SEND_OK,
    SEND_HTTP_ERROR,
    SEND_NETWORK_ERROR,
    SEND_JSON_ERROR,
    SEND_NOT_READY
};

struct PredictionResult {
    float riskScore;
    char  riskLabel[16];
    float confidence;
    bool  valid;
};

// Job passed from main loop to background task
struct DataSendJob {
    SensorWindow window;
    char deviceId[20];
    time_t timestamp;
};

// Result passed back from background task to main loop
struct DataSendResult {
    PredictionResult prediction;
    SendResult result;
};

void       dataSenderInit();
SendResult dataSenderPost(const SensorWindow& window,
                          const char* deviceId,
                          time_t timestamp,
                          PredictionResult& prediction);
int        dataSenderGetLastHttpCode();
uint32_t   dataSenderGetSuccessCount();
uint32_t   dataSenderGetFailCount();

// Async API (FreeRTOS background task)
void       dataSenderStartTask();
bool       dataSenderEnqueue(const SensorWindow& window, const char* deviceId, time_t timestamp);
bool       dataSenderPollResult(DataSendResult& out);
bool       dataSenderIsBusy();

#endif // DATA_SENDER_H
