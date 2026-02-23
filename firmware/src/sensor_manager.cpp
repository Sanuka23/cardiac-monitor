#include "sensor_manager.h"
#include <Wire.h>
#include "MAX30100_PulseOximeter.h"

// --- Internal state ---
static PulseOximeter pox;
static bool _sensorOk = true;

// ECG buffer (linear fill per 10s window)
static uint16_t _ecgBuffer[ECG_SAMPLES_PER_WINDOW];
static uint16_t _ecgIndex = 0;

// Beat timestamps within current window
static uint16_t _beatTimestamps[MAX_BEATS_PER_WINDOW];
static uint8_t  _beatIndex = 0;

// Timing
static uint32_t _windowStartMs = 0;
static uint32_t _tsLastEcgSample = 0;
static uint32_t _tsLastReport = 0;
static uint32_t _tsLastBeatChange = 0;

// Beat detection
static uint32_t _beatCountTotal = 0;
static uint32_t _lastBeatCountForStall = 0;

// Latest readings
static float   _lastHR = 0.0f;
static uint8_t _lastSpO2 = 0;
static int     _lastEcgValue = 0;
static bool    _ecgLeadOff = false;
static bool    _windowReady = false;

// Text printing counter
static uint8_t _ecgTextCounter = 0;
static bool    _shouldPrintText = false;

// --- Beat callback (called by MAX30100 library) ---
static void onBeatDetected() {
    _beatCountTotal++;
    digitalWrite(PIN_BEAT_LED, HIGH);

    // Record beat timestamp relative to current window start
    if (_beatIndex < MAX_BEATS_PER_WINDOW && _windowStartMs > 0) {
        uint32_t relativeMs = millis() - _windowStartMs;
        if (relativeMs <= ECG_WINDOW_MS) {
            _beatTimestamps[_beatIndex++] = (uint16_t)relativeMs;
        }
    }
}

// --- MAX30100 initialization with retries ---
static bool initializeMax30100() {
    for (int attempt = 1; attempt <= MAX_INIT_RETRIES; attempt++) {
        Serial.printf("[SENSOR] MAX30100 init attempt %d/%d...\n", attempt, MAX_INIT_RETRIES);

        Wire.end();
        delay(50);
        Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
        Wire.setClock(100000);

        if (pox.begin()) {
            Wire.setClock(100000);
            Serial.println("[SENSOR] MAX30100 initialized (I2C 100kHz).");
            pox.setIRLedCurrent(IR_LED_CURRENT);
            pox.setOnBeatDetectedCallback(onBeatDetected);
            _tsLastBeatChange = millis();
            _lastBeatCountForStall = _beatCountTotal;
            _sensorOk = true;
            return true;
        }

        Serial.println("[SENSOR] MAX30100 init FAILED. Check wiring/pull-ups.");
        if (attempt < MAX_INIT_RETRIES) {
            delay(INIT_RETRY_DELAY_MS);
        }
    }
    return false;
}

// --- Public: Initialize ---
bool sensorInit() {
    pinMode(PIN_BEAT_LED, OUTPUT);
    digitalWrite(PIN_BEAT_LED, LOW);
    pinMode(PIN_ECG_LO_PLUS, INPUT);
    pinMode(PIN_ECG_LO_MINUS, INPUT);
    analogSetPinAttenuation(PIN_ECG_OUTPUT, ADC_11db);
    analogReadResolution(12);

    Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
    Wire.setClock(100000);

    bool ok = initializeMax30100();
    if (ok) {
        _windowStartMs = millis();
        _ecgIndex = 0;
        _beatIndex = 0;
        _windowReady = false;
    }

    Serial.println("[SENSOR] AD8232 ECG ready on GPIO34.");
    return ok;
}

// --- Public: Update (call from loop as fast as possible) ---
void sensorUpdate() {
    // CRITICAL: MAX30100 needs frequent polling
    pox.update();

    uint32_t now = millis();

    // --- ECG sampling at 100Hz ---
    if (now - _tsLastEcgSample >= ECG_SAMPLE_PERIOD_MS) {
        _tsLastEcgSample = now;

        _ecgLeadOff = (digitalRead(PIN_ECG_LO_PLUS) == HIGH)
                    || (digitalRead(PIN_ECG_LO_MINUS) == HIGH);

        _lastEcgValue = _ecgLeadOff ? 0 : analogRead(PIN_ECG_OUTPUT);

        // Fill buffer if window is still collecting
        if (!_windowReady && _ecgIndex < ECG_SAMPLES_PER_WINDOW) {
            _ecgBuffer[_ecgIndex++] = (uint16_t)_lastEcgValue;

            if (_ecgIndex >= ECG_SAMPLES_PER_WINDOW) {
                _windowReady = true;
            }
        }

        // Text mode printing counter
        _ecgTextCounter++;
        if (_ecgTextCounter >= ECG_TEXT_DIVISOR) {
            _ecgTextCounter = 0;
            _shouldPrintText = true;
        }
    }

    // --- Non-blocking LED off after 50ms blink ---
    static uint32_t ledOnTime = 0;
    if (digitalRead(PIN_BEAT_LED) == HIGH) {
        if (ledOnTime == 0) ledOnTime = now;
        else if (now - ledOnTime > 50) {
            digitalWrite(PIN_BEAT_LED, LOW);
            ledOnTime = 0;
        }
    }

    // --- Stall detection ---
    if (_beatCountTotal != _lastBeatCountForStall) {
        _lastBeatCountForStall = _beatCountTotal;
        _tsLastBeatChange = now;
    }

    if (_sensorOk && (now - _tsLastBeatChange > STALL_TIMEOUT_MS) && _beatCountTotal > 0) {
        Serial.println("[SENSOR] Stall detected. Reinitializing...");
        _sensorOk = false;
        if (initializeMax30100()) {
            Serial.println("[SENSOR] Recovery OK.");
        } else {
            Serial.println("[SENSOR] Recovery failed. Retry in 10s...");
            _tsLastBeatChange = now;
            _sensorOk = true;
        }
    }

    // --- Periodic HR/SpO2 update ---
    if (now - _tsLastReport > HR_REPORT_PERIOD_MS) {
        _lastHR = pox.getHeartRate();
        _lastSpO2 = pox.getSpO2();
        _tsLastReport = now;
    }
}

// --- Public: Window ready check ---
bool sensorIsWindowReady() {
    return _windowReady;
}

// --- Public: Get completed window and reset ---
bool sensorGetWindow(SensorWindow& window) {
    if (!_windowReady) return false;

    memcpy(window.ecgSamples, _ecgBuffer, ECG_SAMPLES_PER_WINDOW * sizeof(uint16_t));
    window.ecgSampleCount = _ecgIndex;

    memcpy(window.beatTimestampsMs, _beatTimestamps, _beatIndex * sizeof(uint16_t));
    window.beatCount = _beatIndex;

    window.heartRateBpm = _lastHR;
    window.spo2Percent = _lastSpO2;
    window.ecgLeadOff = _ecgLeadOff;
    window.windowStartMs = _windowStartMs;

    // Reset for next window
    _ecgIndex = 0;
    _beatIndex = 0;
    _windowStartMs = millis();
    _windowReady = false;

    return true;
}

// --- Public: Accessors ---
float    sensorGetHeartRate()     { return _lastHR; }
uint8_t  sensorGetSpO2()         { return _lastSpO2; }
int      sensorGetLastEcgValue() { return _lastEcgValue; }
bool     sensorIsEcgLeadOff()    { return _ecgLeadOff; }
bool     sensorIsOk()            { return _sensorOk; }
uint32_t sensorGetBeatCount()    { return _beatCountTotal; }

bool sensorShouldPrintEcgText() {
    if (_shouldPrintText) {
        _shouldPrintText = false;
        return true;
    }
    return false;
}

uint16_t sensorGetEcgIndex() { return _ecgIndex; }
const uint16_t* sensorGetEcgBuffer() { return _ecgBuffer; }
