/*
 * ESP32 Heart Rate, SpO2 & ECG Monitor
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
 * Output Modes (toggle via serial):
 *   Send 't' -> Text mode (human-readable, default)
 *   Send 'p' -> Plotter mode (Arduino Serial Plotter CSV)
 */

#include <Arduino.h>
#include <Wire.h>
#include "MAX30100_PulseOximeter.h"


// --- MAX30100 Configuration ---
#define REPORTING_PERIOD_MS   1000
#define MAX_INIT_RETRIES      5
#define INIT_RETRY_DELAY_MS   1000
#define IR_LED_CURRENT        MAX30100_LED_CURR_7_6MA
#define BEAT_LED_PIN          2  // Onboard LED
#define STALL_TIMEOUT_MS      10000

// --- AD8232 ECG Configuration ---
#define ECG_OUTPUT_PIN        34    // Analog output (ADC1_CH6, input-only)
#define ECG_LO_PLUS_PIN       32    // Lead-off detection (+)
#define ECG_LO_MINUS_PIN      33    // Lead-off detection (-)
#define ECG_SAMPLE_PERIOD_MS  10    // 100Hz ECG sampling
#define ECG_TEXT_DIVISOR       10    // Text mode: print every 10th sample (10Hz)

// --- MAX30100 Globals ---
PulseOximeter pox;
uint32_t tsLastReport = 0;
uint32_t beatCount = 0;
uint32_t lastBeatCount = 0;
uint32_t tsLastBeatChange = 0;
bool sensorOk = true;

// --- ECG & Output Mode Globals ---
uint32_t tsLastEcgSample = 0;
uint8_t ecgTextCounter = 0;
bool ecgLeadOff = false;
int lastEcgValue = 0;
bool plotterMode = false;
float lastReportedHR = 0.0;
uint8_t lastReportedSpO2 = 0;

// --- Callbacks ---
void onBeatDetected() {
    beatCount++;
    digitalWrite(BEAT_LED_PIN, HIGH);
    if (!plotterMode) {
        Serial.print("[BEAT] #");
        Serial.println(beatCount);
    }
}

// --- Sensor Init ---
bool initializeSensor() {
    for (int attempt = 1; attempt <= MAX_INIT_RETRIES; attempt++) {
        if (!plotterMode) {
            Serial.print("[INIT] Attempt ");
            Serial.print(attempt);
            Serial.print(" of ");
            Serial.print(MAX_INIT_RETRIES);
            Serial.println("...");
        }

        Wire.end();
        delay(50);
        Wire.begin(21, 22);
        Wire.setClock(100000);

        if (pox.begin()) {
            if (!plotterMode) Serial.println("[INIT] MAX30100 initialized successfully.");
            pox.setIRLedCurrent(IR_LED_CURRENT);
            pox.setOnBeatDetectedCallback(onBeatDetected);
            tsLastBeatChange = millis();
            lastBeatCount = beatCount;
            sensorOk = true;
            return true;
        }

        if (!plotterMode) Serial.println("[INIT] FAILED. Check wiring and I2C pull-ups.");

        if (attempt < MAX_INIT_RETRIES) {
            if (!plotterMode) {
                Serial.print("[INIT] Retrying in ");
                Serial.print(INIT_RETRY_DELAY_MS / 1000);
                Serial.println(" second(s)...");
            }
            delay(INIT_RETRY_DELAY_MS);
        }
    }
    return false;
}

// --- Serial Command Handler ---
void checkSerialCommands() {
    if (Serial.available()) {
        char cmd = Serial.read();
        if (cmd == 'p' || cmd == 'P') {
            plotterMode = true;
        } else if (cmd == 't' || cmd == 'T') {
            plotterMode = false;
            Serial.println();
            Serial.println("[MODE] Switched to TEXT mode.");
            Serial.println("Send 'p' for Plotter mode.");
        }
        while (Serial.available()) Serial.read();
    }
}

// --- Setup ---
void setup() {
    Serial.begin(115200);
    delay(500);

    Serial.println();
    Serial.println("============================================");
    Serial.println("  ESP32 Heart Monitor (MAX30100 + AD8232)");
    Serial.println("============================================");
    Serial.println();

    pinMode(BEAT_LED_PIN, OUTPUT);
    digitalWrite(BEAT_LED_PIN, LOW);

    // Initialize AD8232 ECG pins
    pinMode(ECG_LO_PLUS_PIN, INPUT);
    pinMode(ECG_LO_MINUS_PIN, INPUT);
    analogSetPinAttenuation(ECG_OUTPUT_PIN, ADC_11db);  // Full 0-3.3V range
    analogReadResolution(12);  // 12-bit (0-4095)

    // Initialize I2C at lower speed for MAX30100 pull-up workaround
    Wire.begin(21, 22);
    Wire.setClock(100000);

    if (!initializeSensor()) {
        Serial.println();
        Serial.println("FATAL: Could not initialize MAX30100");
        Serial.println();
        Serial.println("Troubleshooting:");
        Serial.println("  1. Check wiring: VIN->3V3, GND->GND, SDA->21, SCL->22");
        Serial.println("  2. Fix I2C pull-ups (known module defect):");
        Serial.println("     Remove onboard 4.7k pull-ups to 1.8V");
        Serial.println("     Add external 4.7k pull-ups from SDA/SCL to 3.3V");
        Serial.println("  3. Run I2C scanner to check for address 0x57");
        Serial.println();
        Serial.println("System halted. Reset ESP32 to retry.");

        while (true) {
            digitalWrite(BEAT_LED_PIN, HIGH);
            delay(100);
            digitalWrite(BEAT_LED_PIN, LOW);
            delay(100);
        }
    }

    Serial.println("[ECG]  AD8232 ready on GPIO34.");
    Serial.println();
    Serial.println("Place finger on MAX30100. Attach ECG electrodes.");
    Serial.println("Send 'p' for Serial Plotter mode, 't' for text mode.");
    Serial.println("--------------------------------------------");
    Serial.println();
}

// --- Main Loop ---
void loop() {
    // CRITICAL: Must call as frequently as possible
    pox.update();

    // --- ECG Sampling (100Hz) ---
    if (millis() - tsLastEcgSample >= ECG_SAMPLE_PERIOD_MS) {
        ecgLeadOff = (digitalRead(ECG_LO_PLUS_PIN) == HIGH)
                  || (digitalRead(ECG_LO_MINUS_PIN) == HIGH);

        lastEcgValue = ecgLeadOff ? 0 : analogRead(ECG_OUTPUT_PIN);

        if (plotterMode) {
            Serial.print("ECG:");
            Serial.print(lastEcgValue);
            Serial.print(",HR:");
            Serial.print((int)lastReportedHR);
            Serial.print(",SpO2:");
            Serial.println(lastReportedSpO2);
        } else {
            if (++ecgTextCounter >= ECG_TEXT_DIVISOR) {
                ecgTextCounter = 0;
                if (ecgLeadOff) {
                    Serial.println("[ECG] Leads OFF - reattach electrodes!");
                } else {
                    Serial.print("[ECG] ");
                    Serial.print(lastEcgValue);
                    Serial.println(" | Leads: OK");
                }
            }
        }

        tsLastEcgSample = millis();
    }

    // Non-blocking LED off after beat blink
    static uint32_t ledOnTime = 0;
    if (digitalRead(BEAT_LED_PIN) == HIGH) {
        if (ledOnTime == 0) {
            ledOnTime = millis();
        } else if (millis() - ledOnTime > 50) {
            digitalWrite(BEAT_LED_PIN, LOW);
            ledOnTime = 0;
        }
    }

    // Track beat activity for stall detection
    if (beatCount != lastBeatCount) {
        lastBeatCount = beatCount;
        tsLastBeatChange = millis();
    }

    // Auto-recover if sensor stalls
    if (sensorOk && (millis() - tsLastBeatChange > STALL_TIMEOUT_MS) && beatCount > 0) {
        if (!plotterMode) {
            Serial.println();
            Serial.println("[WARN] Sensor stalled. Reinitializing...");
        }
        sensorOk = false;

        if (initializeSensor()) {
            if (!plotterMode) Serial.println("[WARN] Recovery successful.");
        } else {
            if (!plotterMode) Serial.println("[WARN] Recovery failed. Will retry in 10s...");
            tsLastBeatChange = millis();
            sensorOk = true;
        }
    }

    // Report HR/SpO2 periodically
    if (millis() - tsLastReport > REPORTING_PERIOD_MS) {
        float heartRate = pox.getHeartRate();
        uint8_t spo2 = pox.getSpO2();

        lastReportedHR = heartRate;
        lastReportedSpO2 = spo2;

        if (!plotterMode) {
            Serial.print("HR: ");
            if (heartRate < 1.0) {
                Serial.print("--.-");
            } else {
                Serial.print(heartRate, 1);
            }

            Serial.print(" bpm  |  SpO2: ");
            if (spo2 == 0) {
                Serial.print("---");
            } else {
                Serial.print(spo2);
            }

            Serial.print("%  |  Beats: ");
            Serial.println(beatCount);
        }

        tsLastReport = millis();
    }

    // Check for mode switching commands
    checkSerialCommands();
}
