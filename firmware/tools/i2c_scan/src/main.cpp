// I2C bus check for the MAX30100 (expected at 0x57).
// Every ~2 s: SDA/SCL idle levels with and without the ESP32's internal pull-ups,
// then a bus scan at 100 kHz and 10 kHz, and one with SDA/SCL swapped.
//   idle "no internal pull-up" = 1  -> external pull-ups to 3.3 V are present
//   idle "no internal pull-up" = 0  -> no external pull-up (or pulled to the module's 1.8 V)
//   0 devices in every scan         -> module unpowered / data wires not reaching it / dead
//   found only when swapped         -> SDA and SCL wires are crossed
#include <Arduino.h>
#include <Wire.h>

static void idleLevels() {
    Wire.end();
    pinMode(21, INPUT);
    pinMode(22, INPUT);
    delay(5);
    int sdaExt = digitalRead(21), sclExt = digitalRead(22);
    pinMode(21, INPUT_PULLUP);
    pinMode(22, INPUT_PULLUP);
    delay(5);
    int sdaInt = digitalRead(21), sclInt = digitalRead(22);
    Serial.printf("[PINS] no internal pull-up: SDA=%d SCL=%d | internal pull-up: SDA=%d SCL=%d\n",
                  sdaExt, sclExt, sdaInt, sclInt);
}

static void scan(uint32_t hz, int sda = 21, int scl = 22) {
    Wire.end();
    Wire.begin(sda, scl);
    Wire.setClock(hz);
    Serial.printf("[SCAN] SDA=%d SCL=%d %6lu Hz: ", sda, scl, (unsigned long)hz);
    int found = 0;
    for (uint8_t a = 1; a < 127; a++) {
        Wire.beginTransmission(a);
        if (Wire.endTransmission() == 0) { Serial.printf("0x%02X ", a); found++; }
    }
    Serial.printf("-> %d device(s)%s\n", found, found ? "" : "  (MAX30100 should be 0x57)");
}

void setup() {
    Serial.begin(115200);
    delay(300);
    Serial.println("\n=== I2C diagnostic (SDA=21, SCL=22) ===");
}

void loop() {
    idleLevels();
    scan(100000);
    scan(10000);
    scan(100000, 22, 21);  // swapped wires?
    delay(2000);
}
