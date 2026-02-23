# Cardiac Monitor Firmware

ESP32-based firmware for real-time heart rate, SpO2, and ECG monitoring with BLE provisioning and cloud data transmission.

## Hardware Components

| Component | Model | Purpose |
|-----------|-------|---------|
| MCU | ESP32 CP2102 DevKit (30-pin) | Main controller |
| Pulse Oximeter | MAX30100 | Heart rate + SpO2 via I2C |
| ECG Front-End | AD8232 | Single-lead ECG via ADC |
| Electrodes | 3-lead cable + pads | ECG signal acquisition |

## Wiring

### MAX30100 (I2C)

| MAX30100 | ESP32 |
|----------|-------|
| VIN | 3V3 |
| GND | GND |
| SDA | GPIO 21 |
| SCL | GPIO 22 |
| INT | GPIO 19 |

### AD8232 (ECG Analog)

| AD8232 | ESP32 |
|--------|-------|
| 3.3V | 3V3 |
| GND | GND |
| OUTPUT | GPIO 34 |
| LO+ | GPIO 32 |
| LO- | GPIO 33 |

> Most MAX30100 modules have a hardware defect requiring I2C pull-up resistor modification. See `docs/WIRING.md`.

## Build & Flash

Requires [PlatformIO](https://platformio.org/).

```bash
# CLI
cd firmware
pio run --target upload
pio device monitor

# Or use VS Code PlatformIO extension:
# Click Upload button (arrow icon) in bottom toolbar
```

## Configuration

Edit `include/config.h` to customize:

| Setting | Default | Description |
|---------|---------|-------------|
| `WIFI_MODE_ENABLED` | 1 | Enable WiFi + cloud upload |
| `BLE_ENABLED` | 1 | Enable BLE provisioning + vitals broadcast |
| `API_BASE_URL` | HF Spaces URL | Backend API endpoint |
| `API_KEY` | `esp32-cardiac-...` | Device authentication key |
| `SENSOR_SAMPLE_RATE_HZ` | 100 | ECG ADC sampling rate |
| `DATA_WINDOW_MS` | 10000 | Vitals upload window (10s) |

## BLE Services

### WiFi Provisioning Service (`0000FF00-...`)

| Characteristic | UUID | Type | Description |
|---------------|------|------|-------------|
| SSID | FF01 | Write | WiFi network name (UTF-8) |
| Password | FF02 | Write | WiFi password (UTF-8) |
| Command | FF03 | Write | 0x01=connect, 0x02=clear |
| Status | FF04 | Notify | Provisioning status code |

Status codes: `0x00`=idle, `0x01`=connecting, `0x02`=NTP sync, `0x03`=WiFi fail, `0x04`=cleared, `0x05`=ready

### Cardiac Monitor Service (`0000CC00-...`)

| Characteristic | UUID | Format | Description |
|---------------|------|--------|-------------|
| Heart Rate | CC01 | uint16 LE (x10) | 723 = 72.3 bpm |
| SpO2 | CC02 | uint8 | 98 = 98% |
| Risk Score | CC03 | float32 LE | IEEE 754, 0.0-1.0 |
| Risk Label | CC04 | UTF-8 string | "low", "elevated", etc. |
| Device Status | CC05 | uint8 bitmask | See below |

Status bitmask: bit0=sensor OK, bit1=WiFi ready, bit2=ECG lead off, bit3=API ready

## Firmware Architecture

```
firmware/
├── include/
│   └── config.h              # All configuration constants
├── src/
│   ├── main.cpp              # Setup + main loop orchestration
│   ├── sensor.cpp/h          # MAX30100 + AD8232 sampling
│   ├── ecg_buffer.cpp/h      # Ring buffer for ECG samples
│   ├── beat_detector.cpp/h   # R-peak detection algorithm
│   ├── wifi_manager.cpp/h    # WiFi connection state machine
│   ├── data_sender.cpp/h     # HTTPS POST to backend API
│   ├── ble_provisioner.cpp/h # BLE GATT server for WiFi setup
│   └── ble_vitals.cpp/h      # BLE GATT cardiac data broadcast
└── platformio.ini            # PlatformIO build config
```

## Data Flow

1. **Sampling**: MAX30100 reads HR/SpO2, AD8232 reads ECG at 100Hz
2. **Buffering**: ECG samples stored in ring buffer (10s window = 1000 samples)
3. **Beat Detection**: R-peaks detected for beat timestamps
4. **BLE Broadcast**: HR, SpO2, risk score sent as BLE notifications every 1s
5. **Cloud Upload**: Every 10s window, POST vitals + ECG samples to backend API
6. **Risk Receive**: Backend returns ML prediction, broadcast via BLE

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| MAX30100 init fails | Check I2C pull-ups (see WIRING.md) |
| HR always 0 | Press finger firmly on sensor |
| WiFi won't connect | Check credentials, verify 2.4GHz network |
| BLE not advertising | Ensure `BLE_ENABLED 1` in config.h |
| API upload fails | Check API_BASE_URL and API_KEY in config.h |
| Upload button greyed out | Install PlatformIO ESP32 platform |
