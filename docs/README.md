# ESP32 Heart Rate, SpO2 & ECG Monitor

## Overview

Reads heart rate (BPM) and blood oxygen saturation (SpO2) from a MAX30100 pulse oximeter, and records a single-lead ECG waveform from an AD8232 ECG front-end, using an ESP32 CP2102 Type-C DevKit (30-pin). Supports two output modes: human-readable text and Arduino Serial Plotter CSV.

## Hardware

- ESP32 CP2102 Type-C Development Board (30-pin)
- MAX30100 Pulse Oximeter Sensor Module
- AD8232 ECG Sensor Module
- 3-lead ECG electrode cable with pads
- USB Type-C cable
- Jumper wires (8x)

## Wiring

### MAX30100 (I2C)

| MAX30100 | ESP32    |
|----------|----------|
| VIN      | 3V3      |
| GND      | GND      |
| SDA      | GPIO 21  |
| SCL      | GPIO 22  |
| INT      | GPIO 19  |

### AD8232 (ECG Analog)

| AD8232   | ESP32    |
|----------|----------|
| 3.3V     | 3V3      |
| GND      | GND      |
| OUTPUT   | GPIO 34  |
| LO+      | GPIO 32  |
| LO-      | GPIO 33  |

> **IMPORTANT**: Most MAX30100 modules have a hardware defect. See [WIRING.md](WIRING.md) for the required fix.

## Quick Start

```bash
pip3 install platformio
pio run
pio run --target upload
pio device monitor
```

Place index finger on MAX30100 sensor. Attach ECG electrodes to skin. Wait 5-10 seconds for readings.

## Output Modes

### Text Mode (default)

Human-readable output. Send `t` in serial monitor to switch to this mode.

```
============================================
  ESP32 Heart Monitor (MAX30100 + AD8232)
============================================

[INIT] Attempt 1 of 5...
[INIT] MAX30100 initialized successfully.
[ECG]  AD8232 ready on GPIO34.

HR: 72.3 bpm  |  SpO2: 97%  |  Beats: 5
[ECG] 2048 | Leads: OK
[BEAT] #6
HR: 73.1 bpm  |  SpO2: 98%  |  Beats: 6
[ECG] 2031 | Leads: OK
```

### Plotter Mode

Send `p` in serial monitor. Outputs CSV at 100Hz for Arduino Serial Plotter.

```
ECG:2048,HR:72,SpO2:97
ECG:2055,HR:72,SpO2:97
ECG:2039,HR:73,SpO2:97
```

Open **Tools > Serial Plotter** in Arduino IDE (115200 baud) to visualize the ECG waveform with HR/SpO2 reference lines.

## Troubleshooting

See [WIRING.md](WIRING.md) for wiring issues and the I2C pull-up fix.

| Symptom | Fix |
|---------|-----|
| Init fails every attempt | Fix I2C pull-ups (see WIRING.md) |
| HR always 0 | Press finger firmly, keep still |
| Upload fails | Hold BOOT button during upload |
| Garbled serial output | Check monitor_speed matches 115200 |
| ECG always 0 | Check electrode placement, verify LO+/LO- not HIGH |
| "Leads OFF" message | Reattach electrodes firmly to skin |
| Noisy ECG signal | Keep still, ensure good electrode gel contact |
| Flat ECG in plotter | Send 'p' to enable plotter mode |
