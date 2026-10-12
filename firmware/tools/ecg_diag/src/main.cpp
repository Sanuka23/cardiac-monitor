// Bench test for the AD8232 ECG module (no WiFi, no BLE, no MAX30100).
// - Every second: whether LO+/LO- are actively driven (vs floating), plus ADC stats on GPIO34.
// - Raw 250 Hz samples streamed as "D:v,v,...", 4x oversampled like the main firmware, unfiltered.
// Capture with tools/serial_capture.py and plot/check with tools/ecg_analyze.py.
#include <Arduino.h>

static const int PIN_OUT = 34, PIN_LOP = 32, PIN_LOM = 33;

// A driven pin keeps its level whichever internal pull is applied; a floating pin follows the pull.
static const char* pinDrive(int pin) {
    pinMode(pin, INPUT_PULLUP);   delayMicroseconds(200); int up = digitalRead(pin);
    pinMode(pin, INPUT_PULLDOWN); delayMicroseconds(200); int down = digitalRead(pin);
    pinMode(pin, INPUT);
    if (up == 1 && down == 0) return "FLOATING (not connected?)";
    return up ? "driven HIGH (lead off)" : "driven LOW (lead on)";
}

uint32_t tSample = 0, tReport = 0, n = 0, sum = 0, loToggles = 0;
int adcMin = 4095, adcMax = 0, lastLo = -1;
char buf[256]; int len = 0, inBuf = 0;

void setup() {
    Serial.begin(115200);
    delay(300);
    analogSetPinAttenuation(PIN_OUT, ADC_11db);
    analogReadResolution(12);
    pinMode(PIN_LOP, INPUT);
    pinMode(PIN_LOM, INPUT);
    Serial.println("\n=== AD8232 diagnostic ===");
    tSample = tReport = millis();
}

void loop() {
    uint32_t now = millis();
    if (now - tSample >= 4) {  // 250 Hz
        tSample += 4;
        uint32_t s = 0;
        for (int i = 0; i < 4; i++) s += analogRead(PIN_OUT);
        int v = s / 4;
        n++; sum += v; adcMin = min(adcMin, v); adcMax = max(adcMax, v);
        int lo = digitalRead(PIN_LOP) | (digitalRead(PIN_LOM) << 1);
        if (lastLo >= 0 && lo != lastLo) loToggles++;
        lastLo = lo;
        len += snprintf(buf + len, sizeof(buf) - len, inBuf ? ",%d" : "D:%d", v);
        if (++inBuf == 25) { Serial.println(buf); len = inBuf = 0; }
    }
    if (now - tReport >= 1000) {
        tReport = now;
        Serial.printf("[ECG] LO+ %s | LO- %s | lead-off toggles/s=%lu | ADC mean=%lu min=%d max=%d p2p=%d n=%lu\n",
                      pinDrive(PIN_LOP), pinDrive(PIN_LOM), loToggles,
                      n ? sum / n : 0, adcMin, adcMax, adcMax - adcMin, n);
        n = sum = loToggles = 0; adcMin = 4095; adcMax = 0;
    }
}
