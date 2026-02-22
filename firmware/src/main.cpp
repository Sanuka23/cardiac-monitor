/*
 * ESP32 Cardiac Monitor - Phase 3
 *
 * Board: ESP32 CP2102 Type-C DevKit (30-pin)
 * Sensors:
 *   - MAX30100 Pulse Oximeter (HR + SpO2 via I2C)
 *   - AD8232 ECG Monitor (analog output + lead-off detection)
 *
 * MAX30100 Wiring:
 *   VIN  -> ESP32 3V3
 *   GND  -> ESP32 GND
 *   SDA  -> ESP32 GPIO21
 *   SCL  -> ESP32 GPIO22
 *   INT  -> ESP32 GPIO19
 *
 * AD8232 Wiring:
 *   3.3V   -> ESP32 3V3
 *   GND    -> ESP32 GND
 *   OUTPUT -> ESP32 GPIO34 (ADC1_CH6)
 *   LO+    -> ESP32 GPIO32
 *   LO-    -> ESP32 GPIO33
 *
 * Modes:
 *   WIFI_MODE_ENABLED=1 -> WiFi operational (POST to API every 10s)
 *   WIFI_MODE_ENABLED=0 -> Serial debug only
 *
 * Serial commands:
 *   't' / 'T' -> Text mode (human-readable, default)
 *   'p' / 'P' -> Plotter mode (Arduino Serial Plotter CSV)
 */

#include <Arduino.h>
#include "config.h"
#include "sensor_manager.h"
#include "wifi_manager.h"
#include "data_sender.h"

// --- Output mode ---
static bool plotterMode = false;

// --- Serial command handler ---
static void checkSerialCommands() {
    if (Serial.available()) {
        char cmd = Serial.read();
        if (cmd == 'p' || cmd == 'P') {
            plotterMode = true;
        } else if (cmd == 't' || cmd == 'T') {
            plotterMode = false;
            Serial.println("\n[MODE] Text mode. Send 'p' for Plotter.");
        }
        while (Serial.available()) Serial.read();
    }
}

// --- Serial output ---
static void serialOutputPlotter() {
    Serial.printf("ECG:%d,HR:%d,SpO2:%d\n",
        sensorGetLastEcgValue(),
        (int)sensorGetHeartRate(),
        sensorGetSpO2());
}

static void serialOutputText() {
    if (sensorShouldPrintEcgText()) {
        if (sensorIsEcgLeadOff()) {
            Serial.println("[ECG] Leads OFF - reattach electrodes!");
        } else {
            Serial.printf("[ECG] %d | Leads: OK\n", sensorGetLastEcgValue());
        }
    }
}

static uint32_t _lastVitalReport = 0;
static void serialReportVitals() {
    if (millis() - _lastVitalReport < HR_REPORT_PERIOD_MS) return;
    _lastVitalReport = millis();

    if (plotterMode) return;

    float hr = sensorGetHeartRate();
    uint8_t spo2 = sensorGetSpO2();

    if (hr < 1.0) {
        Serial.print("HR: --.-");
    } else {
        Serial.printf("HR: %.1f", hr);
    }

    if (spo2 == 0) {
        Serial.print(" bpm  |  SpO2: ---%");
    } else {
        Serial.printf(" bpm  |  SpO2: %d%%", spo2);
    }

    Serial.printf("  |  Beats: %lu\n", sensorGetBeatCount());
}

// --- WiFi status display ---
static void printWifiStatus() {
    static WifiState lastPrintedState = WIFI_STATE_DISCONNECTED;
    WifiState current = wifiGetState();
    if (current != lastPrintedState) {
        lastPrintedState = current;
        const char* names[] = {
            "DISCONNECTED", "CONNECTING", "CONNECTED", "NTP_SYNCING", "READY"
        };
        Serial.printf("[WIFI] State: %s\n", names[current]);
    }
}

// --- Handle completed 10s data window ---
static void handleDataWindow() {
    if (!sensorIsWindowReady()) return;

    SensorWindow window;
    if (!sensorGetWindow(window)) return;

#if !WIFI_MODE_ENABLED
    // Serial-debug mode: just log the window summary
    Serial.printf("[WINDOW] %u samples, %u beats, HR=%.1f, SpO2=%u, LeadOff=%d\n",
        window.ecgSampleCount, window.beatCount,
        window.heartRateBpm, window.spo2Percent, window.ecgLeadOff);
    return;
#else
    if (!wifiIsReady()) {
        Serial.println("[WINDOW] WiFi not ready, data discarded.");
        return;
    }

    time_t timestamp = wifiGetTimestamp();
    if (timestamp == 0) {
        Serial.println("[WINDOW] NTP not synced, data discarded.");
        return;
    }

    PredictionResult prediction;

    for (int attempt = 0; attempt <= API_MAX_RETRIES; attempt++) {
        if (attempt > 0) {
            Serial.printf("[WINDOW] Retry %d/%d...\n", attempt, API_MAX_RETRIES);
            delay(500);
        }

        SendResult result = dataSenderPost(window, wifiGetDeviceId(), timestamp, prediction);

        if (result == SEND_OK) {
            if (prediction.valid && !plotterMode) {
                Serial.printf("[RISK] %s (score=%.3f, confidence=%.3f)\n",
                    prediction.riskLabel, prediction.riskScore, prediction.confidence);
            }
            return;
        }

        if (result == SEND_JSON_ERROR || result == SEND_NOT_READY) {
            return;
        }
    }

    Serial.printf("[WINDOW] POST failed. Stats: %lu OK, %lu FAIL\n",
        dataSenderGetSuccessCount(), dataSenderGetFailCount());
#endif
}

// ============================================================
//  SETUP
// ============================================================
void setup() {
    Serial.begin(115200);
    delay(500);

    Serial.println();
    Serial.println("============================================");
    Serial.println("  ESP32 Cardiac Monitor - Phase 3");
    Serial.println("============================================");
    Serial.printf("  Mode: %s\n", WIFI_MODE_ENABLED ? "WiFi" : "Serial Debug");
    Serial.println();

    // Initialize sensors
    if (!sensorInit()) {
        Serial.println("\nFATAL: Could not initialize MAX30100.");
        Serial.println("Check wiring: VIN->3V3, GND->GND, SDA->21, SCL->22");
        Serial.println("Fix I2C pull-ups if needed. System halted.");

        while (true) {
            digitalWrite(PIN_BEAT_LED, HIGH); delay(100);
            digitalWrite(PIN_BEAT_LED, LOW);  delay(100);
        }
    }

    // Initialize WiFi (non-blocking)
#if WIFI_MODE_ENABLED
    wifiInit();
    dataSenderInit();
#else
    wifiInit();  // Just derives device ID
#endif

    Serial.println("\nPlace finger on MAX30100. Attach ECG electrodes.");
    Serial.println("Send 'p' for Plotter, 't' for Text.");
    Serial.println("--------------------------------------------\n");
}

// ============================================================
//  LOOP
// ============================================================
void loop() {
    // CRITICAL: Sensor update must be called as frequently as possible
    sensorUpdate();

    // Serial output (always active)
    if (plotterMode) {
        serialOutputPlotter();
    } else {
        serialOutputText();
    }
    serialReportVitals();

    // WiFi state machine (non-blocking)
#if WIFI_MODE_ENABLED
    wifiUpdate();
    if (!plotterMode) {
        printWifiStatus();
    }
#endif

    // Handle completed 10s data window
    handleDataWindow();

    // Serial commands
    checkSerialCommands();
}
