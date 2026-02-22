# Wiring & Pinout Reference

## MAX30100 Pin Connections (I2C)

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

## AD8232 Pin Connections (ECG Analog)

```
  AD8232 ECG Module        ESP32 CP2102 Type-C (30-pin)
  +---------------+        +------------------+
  | 3.3V ---------|------->| 3V3              |
  | GND  ---------|------->| GND              |
  | OUTPUT--------|------->| GPIO 34 (ADC1)   |
  | LO+  ---------|------->| GPIO 32          |
  | LO-  ---------|------->| GPIO 33          |
  +---------------+        +------------------+
```

- **GPIO 34**: Input-only pin, ADC1 channel 6. Reads analog ECG waveform (centered ~1.5V). Configured for 0-3.3V range, 12-bit resolution (0-4095).
- **GPIO 32/33**: Digital inputs for lead-off detection. Go HIGH when an electrode loses skin contact.
- **3.3V/GND**: Shared power rail with MAX30100.

## ECG Electrode Placement

The AD8232 uses a 3-electrode setup:

- **RA (Right Arm)**: Right wrist or right collarbone area
- **LA (Left Arm)**: Left wrist or left collarbone area
- **RL (Right Leg / Reference)**: Right ankle or lower right abdomen

Ensure skin is clean and dry. Use fresh electrode pads with adequate gel.

## ESP32 Pin Summary

```
  Top Row:
  VIN  GND  D13 D12 D14 D27 D26 D25 D33 D32 D35 D34 VN VP EN
                                      ^^^  ^^^          ^^^
                                      LO-  LO+         ECG OUT

  Bottom Row:
  3V3 GND D15 D2 D4 RX2 TX2 D5 D18 D19 D21 RX0 TX0 D22 D23
  ^^^ ^^^                         ^^^  ^^^          ^^^
  PWR GND                         INT  SDA          SCL
```

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
| Erratic HR readings | Finger movement / low LED current | Keep still, increase IR_LED_CURRENT |
| Sensor gets hot | LED current too high | Reduce to MAX30100_LED_CURR_7_6MA |
| Upload fails | Boot mode needed | Hold BOOT button during upload |
| Garbled serial | Baud rate mismatch | Ensure both sides use 115200 |
| ECG value stuck at 0 | Leads disconnected | Reattach electrodes firmly |
| Very noisy ECG | Poor electrode contact or movement | Clean skin, hold still |
| ECG value near 4095 | Signal clipping / wiring error | Check OUTPUT->GPIO34 wire |
| "Leads OFF" message | Electrode not on skin | Reattach with fresh pads |
