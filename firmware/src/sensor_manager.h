#ifndef SENSOR_MANAGER_H
#define SENSOR_MANAGER_H

#include <Arduino.h>
#include "config.h"

// Data window: one 10-second collection ready for transmission
struct SensorWindow {
    uint16_t ecgSamples[ECG_SAMPLES_PER_WINDOW];
    uint16_t ecgSampleCount;
    uint16_t beatTimestampsMs[MAX_BEATS_PER_WINDOW];
    uint8_t  beatCount;
    float    heartRateBpm;
    uint8_t  spo2Percent;
    bool     ecgLeadOff;
    uint32_t windowStartMs;
};

// Initialize both sensors. Returns false if MAX30100 fails after retries.
bool sensorInit();

// Must be called from loop() as frequently as possible.
void sensorUpdate();

// Returns true when 1000 ECG samples have been collected.
bool sensorIsWindowReady();

// Copy completed window data and reset for next window.
bool sensorGetWindow(SensorWindow& window);

// Real-time accessors for serial debug
float    sensorGetHeartRate();
uint8_t  sensorGetSpO2();
int      sensorGetLastEcgValue();
bool     sensorIsEcgLeadOff();
bool     sensorIsOk();
uint32_t sensorGetBeatCount();

// Returns true every ECG_TEXT_DIVISOR samples (for 10Hz text output)
bool sensorShouldPrintEcgText();

// ECG buffer access for BLE streaming
uint16_t        sensorGetEcgIndex();
const uint16_t* sensorGetEcgBuffer();

#endif // SENSOR_MANAGER_H
