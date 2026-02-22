# Wiring & Pinout Reference

## Pin Connections

```
  MAX30100 Module          ESP32 CP2102 Type-C (30-pin)
  +---------------+        +------------------+
  | VIN  ---------|------->| 3V3              |
  | GND  ---------|------->| GND              |
  | SDA  ---------|------->| GPIO 21 (SDA)    |
  | SCL  ---------|------->| GPIO 22 (SCL)    |
  | INT  ---------|------->| GPIO 19          |
  +---------------+        +------------------+
```

GPIO 21/22 are the default I2C pins on ESP32. The INT pin is used by the library for data-ready signaling.

## CRITICAL: I2C Pull-Up Resistor Fix

Most MAX30100 modules have a **design flaw**: the 4.7k ohm I2C pull-up resistors are connected to the internal **1.8V** regulator instead of **3.3V**. This makes I2C communication fail.

### Symptoms
- `pox.begin()` fails on every attempt
- I2C scanner does not find device at address 0x57

### Fix
1. Remove or desolder the two onboard 4.7k pull-up resistors (near SDA/SCL pins)
2. Add external 4.7k ohm resistors:
   - SDA (GPIO21) to 3.3V
   - SCL (GPIO22) to 3.3V

### Verify with I2C Scanner

Upload this sketch to confirm the sensor is detected:

```cpp
#include <Wire.h>

void setup() {
    Serial.begin(115200);
    Wire.begin(21, 22);
    Serial.println("I2C Scanner...");

    for (byte addr = 1; addr < 127; addr++) {
        Wire.beginTransmission(addr);
        if (Wire.endTransmission() == 0) {
            Serial.print("Device at 0x");
            Serial.println(addr, HEX);
        }
    }
    Serial.println("Done.");
}

void loop() {}
```

Expected: `Device at 0x57`

## Troubleshooting Table

| Symptom | Cause | Fix |
|---------|-------|-----|
| Init always fails | I2C pull-ups on 1.8V | Apply pull-up fix above |
| No I2C devices found | Wiring error or pull-ups | Check wires + fix pull-ups |
| HR always 0 | Bad finger contact | Firm flat finger, keep still |
| SpO2 reads 0 | Ambient light interference | Shield sensor from light |
| Erratic readings | Finger movement / low LED current | Keep still, increase IR_LED_CURRENT |
| Sensor gets hot | LED current too high | Reduce to MAX30100_LED_CURR_7_6MA |
| Upload fails | Boot mode needed | Hold BOOT button during upload |
| Garbled serial | Baud rate mismatch | Ensure both sides use 115200 |
