# ESP32 + MAX30100 Heart Rate & SpO2 Monitor

## Overview

Reads heart rate (BPM) and blood oxygen saturation (SpO2) from a MAX30100 pulse oximeter sensor using an ESP32 CP2102 Type-C DevKit (30-pin). Outputs readings via Serial at 1-second intervals.

## Hardware

- ESP32 CP2102 Type-C Development Board (30-pin)
- MAX30100 Pulse Oximeter Sensor Module
- USB Type-C cable
- Jumper wires (5x)

## Wiring

| MAX30100 | ESP32    |
|----------|----------|
| VIN      | 3V3      |
| GND      | GND      |
| SDA      | GPIO 21  |
| SCL      | GPIO 22  |
| INT      | GPIO 19  |

> **IMPORTANT**: Most MAX30100 modules have a hardware defect. See [WIRING.md](WIRING.md) for the required fix.

## Quick Start

```bash
# Install PlatformIO
pip3 install platformio

# Build
pio run

# Upload to ESP32 (connect via USB first)
pio run --target upload

# Open serial monitor
pio device monitor
```

Place your index finger pad firmly on the sensor. Wait 5-10 seconds for readings to stabilize.

## Expected Output

```
============================================
  ESP32 + MAX30100 Heart Rate / SpO2 Monitor
============================================

[INIT] Attempt 1 of 5...
[INIT] MAX30100 initialized successfully.

Place your finger on the sensor. Keep steady.
Readings every 1 second.
--------------------------------------------

HR: --.-- bpm  |  SpO2: ---%  |  Beats: 0
[BEAT] #1
HR: 72.3 bpm   |  SpO2: 97%   |  Beats: 1
[BEAT] #2
HR: 74.1 bpm   |  SpO2: 98%   |  Beats: 2
```

## Troubleshooting

See [WIRING.md](WIRING.md) for wiring issues and the I2C pull-up fix.

| Symptom | Fix |
|---------|-----|
| Init fails every attempt | Fix I2C pull-ups (see WIRING.md) |
| HR always 0 | Press finger firmly, keep still |
| Upload fails | Hold BOOT button during upload |
| Garbled serial output | Check monitor_speed matches 115200 |
