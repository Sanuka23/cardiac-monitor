/*
 * ESP32 + MAX30100 Heart Rate & SpO2 Monitor
 *
 * Board: ESP32 CP2102 Type-C DevKit (30-pin)
 * Sensor: MAX30100 Pulse Oximeter
 *
 * Wiring:
 *   MAX30100 VIN  -> ESP32 3V3
 *   MAX30100 GND  -> ESP32 GND
 *   MAX30100 SDA  -> ESP32 GPIO21
 *   MAX30100 SCL  -> ESP32 GPIO22
 *   MAX30100 INT  -> ESP32 GPIO19
 */

#include <Arduino.h>
#include <Wire.h>
#include "MAX30100_PulseOximeter.h"

// --- Configuration ---
#define REPORTING_PERIOD_MS   1000
#define MAX_INIT_RETRIES      5
#define INIT_RETRY_DELAY_MS   1000
#define IR_LED_CURRENT        MAX30100_LED_CURR_7_6MA
#define BEAT_LED_PIN          2  // Onboard LED

// Stall detection: if no new beat for this many ms, reinitialize sensor
#define STALL_TIMEOUT_MS      10000

// --- Globals ---
PulseOximeter pox;
uint32_t tsLastReport = 0;
uint32_t beatCount = 0;
uint32_t lastBeatCount = 0;
uint32_t tsLastBeatChange = 0;
bool sensorOk = true;

// --- Callbacks ---
void onBeatDetected() {
    beatCount++;
    digitalWrite(BEAT_LED_PIN, HIGH);
    Serial.print("[BEAT] #");
    Serial.println(beatCount);
}

// --- Sensor Init ---
bool initializeSensor() {
    for (int attempt = 1; attempt <= MAX_INIT_RETRIES; attempt++) {
        Serial.print("[INIT] Attempt ");
        Serial.print(attempt);
        Serial.print(" of ");
        Serial.print(MAX_INIT_RETRIES);
        Serial.println("...");

        // Reset I2C bus before each attempt
        Wire.end();
        delay(50);
        Wire.begin(21, 22);
        Wire.setClock(100000);

        if (pox.begin()) {
            Serial.println("[INIT] MAX30100 initialized successfully.");
            pox.setIRLedCurrent(IR_LED_CURRENT);
            pox.setOnBeatDetectedCallback(onBeatDetected);
            tsLastBeatChange = millis();
            lastBeatCount = beatCount;
            sensorOk = true;
            return true;
        }

        Serial.println("[INIT] FAILED. Check wiring and I2C pull-ups.");

        if (attempt < MAX_INIT_RETRIES) {
            Serial.print("[INIT] Retrying in ");
            Serial.print(INIT_RETRY_DELAY_MS / 1000);
            Serial.println(" second(s)...");
            delay(INIT_RETRY_DELAY_MS);
        }
    }
    return false;
}

// --- Setup ---
void setup() {
    Serial.begin(115200);
    delay(500);

    Serial.println();
    Serial.println("============================================");
    Serial.println("  ESP32 + MAX30100 Heart Rate / SpO2 Monitor");
    Serial.println("============================================");
    Serial.println();

    pinMode(BEAT_LED_PIN, OUTPUT);
    digitalWrite(BEAT_LED_PIN, LOW);

    // Initialize I2C at lower speed to work around MAX30100 pull-up issue
    Wire.begin(21, 22);
    Wire.setClock(100000);  // 100kHz (default 400kHz causes errors with 1.8V pull-ups)

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

        // Blink LED rapidly to indicate error
        while (true) {
            digitalWrite(BEAT_LED_PIN, HIGH);
            delay(100);
            digitalWrite(BEAT_LED_PIN, LOW);
            delay(100);
        }
    }

    Serial.println();
    Serial.println("Place your finger on the sensor. Keep steady.");
    Serial.println("Readings every 1 second.");
    Serial.println("--------------------------------------------");
    Serial.println();
}

// --- Main Loop ---
void loop() {
    // CRITICAL: Must call as frequently as possible - no delays here
    pox.update();

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

    // Auto-recover if sensor stalls (no beats for STALL_TIMEOUT_MS while finger likely on)
    if (sensorOk && (millis() - tsLastBeatChange > STALL_TIMEOUT_MS) && beatCount > 0) {
        Serial.println();
        Serial.println("[WARN] Sensor stalled. Reinitializing...");
        sensorOk = false;

        if (initializeSensor()) {
            Serial.println("[WARN] Recovery successful.");
        } else {
            Serial.println("[WARN] Recovery failed. Will retry in 10s...");
            tsLastBeatChange = millis();  // Reset timer to retry later
            sensorOk = true;  // Allow retry loop to continue
        }
    }

    // Report readings periodically
    if (millis() - tsLastReport > REPORTING_PERIOD_MS) {
        float heartRate = pox.getHeartRate();
        uint8_t spo2 = pox.getSpO2();

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

        tsLastReport = millis();
    }
}
