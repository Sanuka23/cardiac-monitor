/*
 * ESP32 Cardiac Monitor - Phase 4
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
 *   WIFI_MODE_ENABLED=1 -> WiFi + BLE operational
 *   WIFI_MODE_ENABLED=0 -> Serial debug only
 *
 * Serial commands:
 *   't' / 'T' -> Text mode (human-readable, default)
 *   'p' / 'P' -> Plotter mode (Arduino Serial Plotter CSV)
 *   'b' / 'B' -> Enter BLE provisioning mode
 */

#include <Arduino.h>
#include "config.h"
#include "sensor_manager.h"
#include "wifi_manager.h"
#include "data_sender.h"
#include "ble_provisioner.h"

// --- Output mode ---
static bool plotterMode = false;

// --- BLE vitals notification timing ---
static uint32_t _lastBleNotify = 0;

// --- Provisioning LED blink ---
static uint32_t _lastProvLedToggle = 0;
static bool _provLedState = false;

// --- Serial command handler ---
static void checkSerialCommands() {
    if (Serial.available()) {
        char cmd = Serial.read();
        if (cmd == 'p' || cmd == 'P') {
            plotterMode = true;
        } else if (cmd == 't' || cmd == 'T') {
            plotterMode = false;
            Serial.println("\n[MODE] Text mode. Send 'p' for Plotter, 'b' for BLE.");
        } else if (cmd == 'b' || cmd == 'B') {
            Serial.println("[MODE] Entering BLE provisioning mode...");
            bleClearCredentials();
            wifiReconnect();
            bleEnterProvisioning();
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
            if (prediction.valid) {
                if (!plotterMode) {
                    Serial.printf("[RISK] %s (score=%.3f, confidence=%.3f)\n",
                        prediction.riskLabel, prediction.riskScore, prediction.confidence);
                }
                bleNotifyRisk(prediction.riskScore, prediction.riskLabel);
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
    Serial.println("  ESP32 Cardiac Monitor - Phase 4");
    Serial.println("============================================");
    Serial.printf("  Mode: %s\n", WIFI_MODE_ENABLED ? "WiFi+BLE" : "Serial Debug");
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

    // Initialize BLE and check NVS for stored WiFi credentials
    BleBootMode bootMode = bleInit();

#if WIFI_MODE_ENABLED
    if (bootMode == BOOT_WIFI) {
        char ssid[33], pass[64];
        if (bleGetStoredSSID(ssid, sizeof(ssid)) &&
            bleGetStoredPassword(pass, sizeof(pass))) {
            wifiSetCredentials(ssid, pass);
        }
        wifiInit();
        dataSenderInit();
        Serial.println("[MAIN] Booting with stored WiFi credentials.");
    } else {
        // Use default credentials if defined (for testing)
        #if defined(WIFI_DEFAULT_SSID) && defined(WIFI_DEFAULT_PASS)
        Serial.println("[MAIN] No stored credentials. Using default WiFi for testing.");
        wifiSetCredentials(WIFI_DEFAULT_SSID, WIFI_DEFAULT_PASS);
        #else
        Serial.println("[MAIN] No WiFi credentials. Waiting for BLE provisioning...");
        Serial.println("[MAIN] Use nRF Connect or the Flutter app to configure WiFi.");
        #endif
        wifiInit();
        dataSenderInit();
    }
#else
    wifiInit();
#endif

    Serial.println("\nPlace finger on MAX30100. Attach ECG electrodes.");
    Serial.println("Send 'p'=Plotter, 't'=Text, 'b'=BLE Provisioning");
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

    // BLE event processing (non-blocking)
    bleUpdate();

    // WiFi state machine (non-blocking)
#if WIFI_MODE_ENABLED
    WifiState prevState = wifiGetState();
    wifiUpdate();
    WifiState currState = wifiGetState();

    // Sync WiFi state changes to BLE provisioning status
    if (currState != prevState) {
        switch (currState) {
            case WIFI_STATE_CONNECTING:
                bleSetProvisioningStatus(BLE_STATUS_CONNECTING);
                break;
            case WIFI_STATE_NTP_SYNCING:
                bleSetProvisioningStatus(BLE_STATUS_NTP_SYNC);
                break;
            case WIFI_STATE_READY:
                bleSetProvisioningStatus(BLE_STATUS_READY);
                bleSetOperationalMode();
                wifiResetBootFailCount();
                break;
            case WIFI_STATE_DISCONNECTED:
                if (wifiGetBootFailCount() >= WIFI_BOOT_MAX_RETRIES &&
                    !bleIsProvisioning()) {
                    Serial.println("[MAIN] WiFi failed 3x, entering BLE provisioning.");
                    bleEnterProvisioning();
                    bleSetProvisioningStatus(BLE_STATUS_WIFI_FAIL);
                }
                break;
            default:
                break;
        }

        if (!plotterMode) printWifiStatus();
    }
#endif

    // Handle completed 10s data window
    handleDataWindow();

    // BLE vitals notifications (every 1 second, only if client connected)
    if (bleIsClientConnected() && millis() - _lastBleNotify >= BLE_VITALS_NOTIFY_MS) {
        _lastBleNotify = millis();

        bleNotifyHeartRate(sensorGetHeartRate());
        bleNotifySpO2(sensorGetSpO2());

        uint8_t devStatus = 0;
        if (sensorIsOk())         devStatus |= 0x01;
        if (wifiIsReady())        devStatus |= 0x02;
        if (sensorIsEcgLeadOff()) devStatus |= 0x04;
        if (wifiGetState() == WIFI_STATE_READY) devStatus |= 0x08;
        bleNotifyDeviceStatus(devStatus);
    }

    // Provisioning mode LED blink (500ms toggle)
    if (bleIsProvisioning()) {
        if (millis() - _lastProvLedToggle >= 500) {
            _lastProvLedToggle = millis();
            _provLedState = !_provLedState;
            digitalWrite(PIN_BEAT_LED, _provLedState ? HIGH : LOW);
        }
    }

    // Serial commands
    checkSerialCommands();
}
