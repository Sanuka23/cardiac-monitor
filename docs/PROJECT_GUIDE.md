# Cardiac Monitor — Complete Technical Guide

**How the whole system works, and how to rebuild it from scratch**

This guide describes the ESP32 cardiac monitor end to end: the hardware, the firmware, the cloud API, the machine-learning models, the Flutter app, and how to deploy and operate them. It reflects the repository at the time of writing (October 2026, after PR #4).

Where the code and older docs disagree, this guide follows the code and points out the difference. Section 15 lists the known issues honestly. Read it before a demo.

> **Medical disclaimer.** This is a student/prototype project, not a medical device. The risk model is a *screening* classifier for "normal vs abnormal ECG". It was trained on hospital recordings (PTB-XL) and has not been clinically validated on this hardware. It must never be used for diagnosis.

---

## Contents

1. [What the system does](#1-what-the-system-does)
2. [Links](#2-links)
3. [Architecture and data flow](#3-architecture-and-data-flow)
4. [Repository layout](#4-repository-layout)
5. [Hardware](#5-hardware)
6. [Firmware (ESP32)](#6-firmware-esp32)
7. [BLE protocol reference](#7-ble-protocol-reference)
8. [Backend API (FastAPI)](#8-backend-api-fastapi)
9. [ML models: inference](#9-ml-models-inference)
10. [ML models: training](#10-ml-models-training)
11. [Mobile app (Flutter)](#11-mobile-app-flutter)
12. [Deployment and CI/CD](#12-deployment-and-cicd)
13. [Rebuild from scratch: step-by-step](#13-rebuild-from-scratch-step-by-step)
14. [Testing, diagnostics and demo tools](#14-testing-diagnostics-and-demo-tools)
15. [Known issues and limitations](#15-known-issues-and-limitations)
16. [Security notes](#16-security-notes)
17. [Validation evidence](#17-validation-evidence)
18. [Project history](#18-project-history)
19. [Glossary](#19-glossary)

---

## 1. What the system does

A wearable-style ESP32 board records a **single-lead ECG** with an AD8232 front end. It does two things with the signal at the same time:

- **Over Bluetooth Low Energy (BLE)** it streams live data to a phone app. The app shows the ECG waveform, the latest risk score, and device status.
- **Over WiFi (HTTPS)** it uploads every **10-second ECG window** (2,500 samples at 250 Hz) to a FastAPI backend on Hugging Face Spaces. For each window the backend:
  1. checks signal quality;
  2. if the signal is clean, runs an ensemble ML model (ECGFounder CNN + XGBoost) that scores the probability of an *abnormal* ECG;
  3. derives heart rate from the ECG R-peaks;
  4. stores everything in MongoDB Atlas;
  5. returns the prediction to the board, which relays it to the app over BLE.

WiFi is configured **from the app over BLE**. The board boots into "provisioning mode" and the app sends the network name and password.

**Current configuration (defaults in the code):**

| Area | Setting |
|---|---|
| MAX30100 pulse oximeter | **Disabled** (`MAX30100_ENABLED 0`). The module was unreliable (Section 15). HR and SpO2 from the device are sent as 0, and the server derives HR from the ECG. |
| WiFi setup | BLE-first provisioning. No WiFi credentials are compiled into the firmware. |
| Device visibility | Every real device that has sent data, plus the recorded session `PLAYBACK_DEVICE_REC`, is a **shared device**, visible to every account (`SHARED_DEVICE_IDS`, with `*`). A board does not need to be registered to an account. |
| Web dashboard | `/dashboard` on the API: sign in or register, then see the live ECG, heart rate and risk assessment of any shared device (Section 8.9). |
| Demo data | Recorded clinical ECGs (PTB-XL) and a 5-minute real recording from this device can be **replayed** through the API. They are always labelled as playback and never presented as live data. |

---

## 2. Links

| What | URL |
|---|---|
| Source code (GitHub) | https://github.com/Sanuka23/cardiac-monitor |
| Releases (APK + firmware .bin) | https://github.com/Sanuka23/cardiac-monitor/releases/latest |
| CI runs | https://github.com/Sanuka23/cardiac-monitor/actions |
| Live API base URL | https://sanuka0523-cardiac-monitor-api.hf.space |
| Web dashboard (live ECG and risk) | https://sanuka0523-cardiac-monitor-api.hf.space/dashboard |
| Swagger UI (interactive API docs) | https://sanuka0523-cardiac-monitor-api.hf.space/docs |
| ReDoc | https://sanuka0523-cardiac-monitor-api.hf.space/redoc |
| OpenAPI JSON | https://sanuka0523-cardiac-monitor-api.hf.space/openapi.json |
| Health check | https://sanuka0523-cardiac-monitor-api.hf.space/api/v1/health |
| Hugging Face Space (hosting) | https://huggingface.co/spaces/Sanuka0523/Cardiac_Monitor_API |
| Database hosting | MongoDB Atlas (free M0 cluster), https://www.mongodb.com/atlas |
| PTB-XL dataset v1.0.3 (training data, CC BY 4.0) | https://physionet.org/content/ptb-xl/1.0.3/ — DOI https://doi.org/10.13026/kfzx-aw45 — paper https://doi.org/10.1038/s41597-020-0495-6 |
| ECGFounder pretrained model (MIT) | https://huggingface.co/PKUDigitalHealth/ECGFounder — paper https://arxiv.org/abs/2410.04133 |
| PlatformIO (firmware build tool) | https://platformio.org |
| NimBLE-Arduino (BLE stack) | https://github.com/h2zero/NimBLE-Arduino |
| ArduinoJson | https://arduinojson.org |
| MAX30100 library (oxullo) | https://github.com/oxullo/Arduino-MAX30100 |
| AD8232 product page / datasheet | https://www.analog.com/en/products/ad8232.html |
| flutter_blue_plus (app BLE) | https://pub.dev/packages/flutter_blue_plus |

---

## 3. Architecture and data flow

```
                 ┌──────────────────────── ESP32 DevKit (CardiacMon) ────────────────────────┐
 Electrodes ─►   │ AD8232 ─► GPIO34 ADC @250 Hz ─► 50 Hz notch ─► 40 Hz LPF ─► DC removal ─► │
 (RA, LA, RL)    │   ×0.5, re-centre 2048 ─► 2,500-sample window (10 s)                       │
                 │        │                                   │                               │
                 │        │ every 200 ms: ≤60 samples          │ every 10 s: JSON window       │
                 │        ▼ (BLE notify CC06)                  ▼ (FreeRTOS task, core 0)       │
                 └────────┼───────────────────────────────────┼───────────────────────────────┘
                          │ BLE                               │ WiFi → HTTPS POST /api/v1/vitals
                          ▼                                   ▼   header X-API-Key
              ┌──────────────────────┐            ┌────────────────────────────────────────┐
              │ Flutter app          │◄── JWT ───►│ FastAPI (Docker on Hugging Face Space) │
              │ live ECG, risk,      │   HTTPS    │ 1. signal-quality gate                 │
              │ status, history,     │            │ 2. ECGFounder + XGBoost ensemble        │
              │ WiFi provisioning    │            │ 3. ECG-derived heart rate               │
              └──────────▲───────────┘            │ 4. store → MongoDB Atlas                │
                         │ BLE notify CC03/CC04   └───────────────┬────────────────────────┘
                         │ (risk score + label)                   │ response: prediction
                         └──────────────── ESP32 ◄────────────────┘
```

### Lifecycle of one 10-second window

1. The firmware samples GPIO34 every 4 ms. Each sample averages 4 ADC reads.
2. If either lead-off pin is HIGH, the sample is stored as `0` and the filters reset. Otherwise the sample goes through the notch, low-pass and DC-remover filters, is multiplied by 0.5, has 2048 added, and is clamped to 0–4095.
3. While the window fills, the loop sends batches of up to 60 new samples to the phone over BLE every 200 ms (≈50 samples per batch at 250 Hz).
4. When 2,500 samples are collected, the window is copied into a static buffer. If WiFi is READY and NTP time is known, it is queued for the upload task. Otherwise it is discarded.
5. The upload task (core 0) builds JSON (≈12.7 KB) and POSTs it to `https://…hf.space/api/v1/vitals` with the `X-API-Key` header. It retries up to 2 more times.
6. The backend:
   1. resolves the device owner;
   2. runs the quality gate, which stores the result as `good`, `poor` or `lead_off`;
   3. inserts the vitals document;
   4. if quality is `good`, runs the ML model, fills in heart rate from the ECG, and stores a prediction;
   5. returns the vitals record with an optional `prediction` object.
7. The firmware parses `prediction.risk_score` and `risk_label` and notifies the app over BLE (CC03/CC04).
8. The app's **History** tab later reads stored windows and predictions over HTTPS (`/api/v1/vitals/me/history`, `/api/v1/predictions/me/history`).

---

## 4. Repository layout

```
cardiac-monitor/
├── README.md                     project overview (some details outdated — see this guide)
├── docs/
│   ├── PROJECT_GUIDE.md          ← this document
│   ├── WIRING.md                 wiring tables, MAX30100 pull-up fix, I2C scanner
│   └── README.md                 original serial-monitor readme (pre-WiFi, partly outdated)
├── firmware/                     ESP32 firmware (PlatformIO, Arduino framework)
│   ├── platformio.ini
│   ├── include/config.h          all pins, rates, URLs, UUIDs, timings
│   ├── include/secrets.example.h template for include/secrets.h (git-ignored: API key, optional WiFi)
│   ├── src/                      main.cpp, sensor_manager.*, ecg_filter.h, data_sender.*,
│   │                             wifi_manager.*, ble_provisioner.*
│   ├── lib/MAX30100lib/          vendored/patched MAX30100 lib (NOT what gets compiled — Section 6.10)
│   └── tools/                    bench-test sketches + capture/analysis scripts (Section 14)
├── backend/                      FastAPI service (deployed as a Docker Space)
│   ├── app/                      main.py, config.py, database.py, middleware/, models/, routes/, services/
│   ├── ml_src/                   net1d.py (ECGFounder architecture), feature_extractor.py
│   ├── ml_models/                ecgfounder_best.pt, xgboost_cardiac.joblib (Git LFS)
│   ├── scripts/                  playback_ptbxl.py, replay_recording.py, firmware_ecg.py
│   ├── tests/                    pytest suite (61 tests) + fixtures
│   ├── Dockerfile, requirements.in, requirements.txt (pinned), render.yaml, README.md (Space metadata)
├── ml/                           offline training pipeline (dataset + outputs are git-ignored)
│   ├── train_all.py
│   └── src/                      data_loader, finetune_ecgfounder, train_xgboost, evaluate, ...
├── app/cardiac_monitor/          Flutter app (Android/iOS)
└── .github/workflows/            backend-ci, firmware-ci, flutter-ci, release, security-scan
```

The following are git-ignored and never committed:

- `firmware/include/secrets.h`
- `backend/.env`
- `ml/data/*` (the PTB-XL dataset, processed arrays, and personal device recordings)
- trained artefacts in `ml/models/`

---

## 5. Hardware

### 5.1 Bill of materials

| Qty | Part | Notes |
|---|---|---|
| 1 | **ESP32 DevKit, 30-pin, CP2102 USB-UART, USB-C** | Any ESP32-WROOM-32 DevKit works; PlatformIO board `esp32dev`. |
| 1 | **AD8232 single-lead heart-rate monitor module** (e.g. SparkFun-style breakout) | Pins used: 3.3V, GND, OUTPUT, LO+, LO−. Fixed gain ≈1100. |
| 1 | 3-lead ECG cable (3.5 mm jack, red/yellow/green snaps) + disposable gel electrodes | Use fresh pads. Dry pads cause noise and lead-off. |
| 1 | MAX30100 pulse-oximeter module (*optional — currently disabled*) | Needs the I2C pull-up fix (5.5). |
| 2 | 4.7 kΩ resistors | Only for the MAX30100 pull-up fix. |
| ~10 | Jumper wires (female–female or via breadboard) | 5 for the AD8232, 5 for the MAX30100. |
| 1 | USB-C cable + 5 V USB supply or power bank | A power bank gives a cleaner ECG than a laptop on its charger (mains noise). |
| 1 | Android phone with BLE | The iOS build currently fails to connect (Section 15). |

### 5.2 Wiring

The code is authoritative (`firmware/include/config.h`).

| Module pin | ESP32 pin | Purpose |
|---|---|---|
| AD8232 **3.3V** | **3V3** | Power. **Never 5 V.** |
| AD8232 **GND** | **GND** | Common ground |
| AD8232 **OUTPUT** | **GPIO34** (ADC1_CH6, input-only) | Analog ECG. ADC1 is required because ADC2 cannot be used while WiFi is on. 12-bit, 11 dB attenuation (≈0–3.1 V). |
| AD8232 **LO+** | **GPIO32** | Lead-off detect (HIGH = electrode off) |
| AD8232 **LO−** | **GPIO33** | Lead-off detect |
| AD8232 SDN | not connected | |
| MAX30100 **VIN** | **3V3** | *(optional sensor)* |
| MAX30100 **GND** | **GND** | |
| MAX30100 **SDA** | **GPIO21** | I2C data (address 0x57, part ID 0x11) |
| MAX30100 **SCL** | **GPIO22** | I2C clock (firmware forces 100 kHz) |
| MAX30100 **INT** | GPIO19 | Wired by convention but **not used** by the code |
| Onboard LED | GPIO2 | Beat flash (MAX30100 only), provisioning blink |

```
            AD8232                         ESP32 DevKit                     MAX30100 (optional)
        ┌────────────┐                ┌──────────────────┐               ┌──────────────┐
        │ 3.3V  ●────┼────────────────┤ 3V3          3V3 ├───────────────┼────● VIN     │
        │ GND   ●────┼────────────────┤ GND          GND ├───────────────┼────● GND     │
        │ OUTPUT●────┼────────────────┤ GPIO34    GPIO21 ├───────────────┼────● SDA     │
        │ LO+   ●────┼────────────────┤ GPIO32    GPIO22 ├───────────────┼────● SCL     │
        │ LO-   ●────┼────────────────┤ GPIO33    GPIO19 ├───────────────┼────● INT     │
        │ jack ◄─ RA/LA/RL cable      │ GPIO2 = LED      │   4.7k SDA→3V3, 4.7k SCL→3V3 │
        └────────────┘                └──────────────────┘               └──────────────┘
```

> **Note:** `docs/WIRING.md` has an ASCII pin-row drawing whose carets are misaligned. Use the table above.

### 5.3 Power

Both modules share the DevKit's 3V3 regulator and ground. The board is powered over USB-C. For the cleanest ECG, run from a **power bank** or unplug the laptop charger: mains interference at 50 Hz was the main cause of bad readings. Keep ECG leads away from power cords.

### 5.4 AD8232 and electrodes

- **Placement (Lead II-like):**
  - **Red / RA:** just below the right collarbone, or the right wrist.
  - **Yellow / LA:** just below the left collarbone, or the left wrist.
  - **Green / RL (reference):** lower right abdomen, or the right ankle.
  - Clean, dry skin and fresh gel pads. Sit still; talking and arm movement add artefacts.
- **Signal levels seen on real hardware:**
  - With leads on, the raw output sits at ≈1,770 counts.
  - R-peaks reach the 4,095 ceiling. The tips clip for 1–3 samples (≈1.25% of samples) because of the module's high gain.
  - The firmware's `ECG_OUTPUT_SCALE 0.5` exists so that re-centring at 2048 after filtering does not push peaks onto the rails (Section 6.4).
- **Lead-off pins:**
  - LO+ and LO− are push-pull outputs of a powered AD8232: HIGH when an electrode is off, LOW when all are on.
  - If the module is unpowered or the LO wires are disconnected, the ESP32 inputs **float** (no pull resistor is configured). They then toggle at about 100 transitions per second from mains pickup. `firmware/tools/ecg_diag` detects this (Section 14.2).
- **Normal bench readings:**
  - **No electrodes:** both LO pins driven HIGH. The output sits at 0 with bursts of rail-to-rail mains noise. This is expected.
  - **Electrodes on:** both LO pins driven LOW. Baseline ≈1,800 with sharp R-peaks once per beat, and P and T waves visible.

### 5.5 MAX30100 (optional, currently disabled)

- **Pull-up defect:** most modules tie their onboard 4.7 kΩ SDA/SCL pull-ups to an internal **1.8 V** regulator, and I2C then fails. To fix it:
  1. Remove the two onboard pull-ups.
  2. Add 4.7 kΩ resistors from SDA (GPIO21) to 3.3 V and from SCL (GPIO22) to 3.3 V.
  3. Verify with `firmware/tools/i2c_scan`: the device must appear at `0x57`.
- **Observed problem (October 2026):**
  - The module was intermittent. It disappeared from the bus, and only a full USB power-off brought it back.
  - After configuration it sampled for ≈3 s and then stopped, with I2C timeouts (`Error 263`).
  - This happened at both 100 kHz and 10 kHz, and at both 27 mA and 4.4 mA LED current.
  - Diagnosis: a loose power or ground connection (or unsoldered headers), plus pull-ups that had become disconnected.
  - **Decision:** the firmware runs **ECG-only** (`MAX30100_ENABLED 0`).
- **To re-enable it:**
  1. Fix the wiring (solder the headers, short firm VIN/GND wires, 3.3 V pull-ups).
  2. Confirm a stable `0x57` with the scanner.
  3. Set `MAX30100_ENABLED 1` in `config.h` and rebuild.

### 5.6 Assembly checklist

1. Wire the AD8232 per 5.2. Plug the electrode cable into the module's 3.5 mm jack.
2. (Optional) Wire the MAX30100 with the pull-up fix.
3. Connect the ESP32 over USB. Check it appears as a serial port, e.g. `/dev/cu.usbserial-0001` on macOS or `COMx` on Windows. CP2102 drivers may be needed on Windows.
4. Flash `firmware/tools/ecg_diag` and run the bench test in Section 14.2 before flashing the main firmware.

---

## 6. Firmware (ESP32)

### 6.1 Toolchain and build

| Item | Value |
|---|---|
| Build tool | PlatformIO (CLI `pio` or the VS Code extension) |
| Platform | `espressif32` (6.12.0 used) |
| Core | Arduino-ESP32 2.0.17 (framework-arduinoespressif32 3.20017.241212, ESP-IDF 4.4), GCC 8.4.0 |
| Board | `esp32dev` |
| Libraries | `bblanchon/ArduinoJson@^7.0.0` (7.4.2), `h2zero/NimBLE-Arduino@^2.1.0` (2.3.7), `oxullo/MAX30100lib` (1.2.1) |
| Partitions | `min_spiffs.csv`: nvs 0x9000/0x5000, otadata, app0/app1 0x1E0000 each, spiffs, coredump (two OTA slots, but no OTA code) |
| Binary size | ≈1.2 MB, about 61% of the app slot |

`firmware/platformio.ini`:

```ini
[env:esp32dev]
platform = espressif32
board = esp32dev
framework = arduino
monitor_speed = 115200
upload_speed = 921600
board_build.partitions = min_spiffs.csv
build_flags =
    -DWIFI_MODE_ENABLED=1
    -DCONFIG_BT_NIMBLE_MAX_CONNECTIONS=1
    -DCONFIG_BT_NIMBLE_MAX_BONDS=3
    -DCONFIG_BT_NIMBLE_ROLE_CENTRAL_DISABLED
    -DCONFIG_BT_NIMBLE_ROLE_OBSERVER_DISABLED
lib_deps =
    oxullo/MAX30100lib
    bblanchon/ArduinoJson@^7.0.0
    h2zero/NimBLE-Arduino@^2.1.0
```

Commands (run from the repo root):

```bash
pip install platformio                                     # or install the VS Code extension
cp firmware/include/secrets.example.h firmware/include/secrets.h   # then set API_KEY (6.2)
pio run -d firmware                                        # build
pio run -d firmware -t upload --upload-port /dev/cu.usbserial-0001  # flash (port name varies)
pio device monitor -b 115200 -p /dev/cu.usbserial-0001     # serial console (Ctrl+C to exit)
```

Opening the serial port usually **resets** the board, because of the DTR/RTS auto-reset circuit. Flashing does **not** erase NVS, so stored WiFi credentials survive a re-flash.

### 6.2 Secrets and compile-time switches

`config.h` includes `secrets.h` if it exists, otherwise `secrets.example.h`:

```c
#if __has_include("secrets.h")
#include "secrets.h"
#else
#include "secrets.example.h"
#endif
```

`firmware/include/secrets.h` (git-ignored):

```c
#ifndef SECRETS_H
#define SECRETS_H
// Optional fallback WiFi, used only when no network was provisioned over BLE.
// Leave undefined so the board starts in BLE provisioning mode and the app sets WiFi.
// #define WIFI_DEFAULT_SSID       "your-ssid"
// #define WIFI_DEFAULT_PASS       "your-password"

// Must match the backend's API_KEY secret
#define API_KEY                 "<same value as the server's API_KEY>"
#endif
```

| Switch | Default | Where | Effect |
|---|---|---|---|
| `WIFI_MODE_ENABLED` | 1 | **`platformio.ini` build flag** (overrides `config.h`) | 1 = WiFi + HTTPS upload + BLE. 0 = serial debug only. |
| `MAX30100_ENABLED` | **0** | `config.h` | 0 = no I2C. HR, SpO2 and beats are 0, and the server derives HR from the ECG. 1 = pulse oximeter on, with init retries, stall recovery and beat LED. |
| `WIFI_DEFAULT_SSID/PASS` | undefined | `secrets.h` | Fallback WiFi used only when NVS has no credentials. Never saved to NVS. Leave undefined for BLE-first setup. |
| `API_KEY` | `"change-me"` | `secrets.h` | Sent as the `X-API-Key` header. Must equal the server's `API_KEY`. |

### 6.3 `config.h` reference

| Group | Constants |
|---|---|
| Pins | `PIN_I2C_SDA 21`, `PIN_I2C_SCL 22`, `PIN_MAX30100_INT 19` (unused), `PIN_ECG_OUTPUT 34`, `PIN_ECG_LO_PLUS 32`, `PIN_ECG_LO_MINUS 33`, `PIN_BEAT_LED 2` |
| MAX30100 | `MAX30100_ENABLED 0`, `MAX_INIT_RETRIES 5`, `INIT_RETRY_DELAY_MS 1000`, `IR_LED_CURRENT MAX30100_LED_CURR_27_1MA`, `STALL_TIMEOUT_MS 10000`, `HR_REPORT_PERIOD_MS 1000` |
| ECG | `ECG_SAMPLE_RATE_HZ 250`, `ECG_SAMPLE_PERIOD_MS 4`, `ECG_WINDOW_MS 10000`, `ECG_SAMPLES_PER_WINDOW 2500`, `ECG_TEXT_DIVISOR 25`, `ECG_OVERSAMPLE_COUNT 4`, `ECG_OUTPUT_SCALE 0.5f`, `MAX_BEATS_PER_WINDOW 30` |
| WiFi | `WIFI_CONNECT_TIMEOUT_MS 15000`, `WIFI_RECONNECT_BASE_MS 1000`, `WIFI_RECONNECT_MAX_MS 30000`, `WIFI_BOOT_MAX_RETRIES 3` |
| NVS | `NVS_NAMESPACE "cardiac"`, `NVS_KEY_SSID "wifi_ssid"`, `NVS_KEY_PASSWORD "wifi_pass"` |
| NTP | `NTP_SERVER_1 "pool.ntp.org"`, `NTP_SERVER_2 "time.nist.gov"`, GMT and DST offsets 0 (all times are UTC) |
| API | `API_BASE_URL "https://sanuka0523-cardiac-monitor-api.hf.space"`, `API_VITALS_PATH "/api/v1/vitals"`, `API_TIMEOUT_MS 10000`, `API_MAX_RETRIES 2` |
| Upload task | `DATA_SEND_TASK_STACK 12288` bytes, `DATA_SEND_TASK_PRIORITY 1`, `DATA_SEND_TASK_CORE 0`, `DATA_SEND_QUEUE_DEPTH 2` |
| BLE | `BLE_DEVICE_NAME "CardiacMon"`, UUIDs (Section 7), command and status codes, advertising intervals `FAST 160–240` (100–150 ms) and `SLOW 1600` (1 s), `BLE_VITALS_NOTIFY_MS 1000`, `ECG_BLE_NOTIFY_MS 200`, `ECG_BLE_BATCH_MAX 60` |
| WiFi scan | `WIFI_SCAN_TIMEOUT_MS 10000`, `WIFI_SCAN_NOTIFY_INTERVAL_MS 30`, `WIFI_SCAN_MAX_RESULTS 20` |

To point the board at a different backend, change `API_BASE_URL`. It is compiled in.

### 6.4 ECG acquisition (`sensor_manager.cpp`, `ecg_filter.h`)

**Sampling and lead-off**

- **Sampling:** every 4 ms (`millis()`-based), read GPIO34 four times and average (12-bit, 11 dB attenuation).
- **Lead-off:** `LO+ == HIGH || LO− == HIGH`. If true, the sample value is `0` and **all three filters reset**.

**Filter chain** (Fs = 250 Hz, applied in this order):

| # | Filter | Form | Coefficients |
|---|---|---|---|
| 1 | 50 Hz notch, Q = 25 (−3 dB ≈49.25–50.75 Hz) | Direct form I: `y = b0x + b1x1 + b2x2 − a1y1 − a2y2` | b0 = 0.981334, b1 = −0.606498, b2 = 0.981334, a1 = −0.606498, a2 = 0.962668 |
| 2 | 40 Hz Butterworth low-pass, 2nd order | Direct form II transposed: `y = b0x + z1; z1 = b1x − a1y + z2; z2 = b2x − a2y` | b0 = 0.145310, b1 = 0.290620, b2 = 0.145310, a1 = −0.670919, a2 = 0.252160 |
| 3 | DC remover (high-pass ≈0.5 Hz) | `w = x + αw_prev; y = w − w_prev` | α = 0.9875 (time constant 80 samples, 0.32 s) |

**Output, buffering and windowing**

- **Output:** `value = constrain((int)(filtered * 0.5 + 2048), 0, 4095)`. The 0.5 scale keeps clipped R-peaks off the rails. Without it, 20 of 32 windows of a real recording failed the server's saturation check; with it, 32 of 32 passed.
- **Window buffer:** a linear `uint16_t[2500]`. When full, `windowReady` is set and sampling continues but nothing is stored until the main loop takes the window.
- **Taking the window** (`sensorGetWindow`):
  - copies the samples, beat timestamps (MAX30100 only), HR, SpO2 and the lead-off state at window end;
  - resets the index;
  - **resets all filters**, so every window starts with a short DC-settling transient (≈1.5 s).
- **Python twin:** `backend/scripts/firmware_ecg.py` is an exact Python port of this chain, used to replay raw recordings.

### 6.5 Main loop (`main.cpp`)

**`setup()` runs these steps in order:**

1. `Serial.begin(115200)` and print the banner.
2. `sensorInit()`. With MAX30100 enabled, a failure halts the board here with a fast-blinking LED.
3. `bleInit()` returns `BOOT_WIFI` if NVS has an SSID, otherwise `BOOT_PROVISIONING`.
4. Load WiFi credentials, or wait for provisioning. Then call `wifiInit()` and start the upload task.

**`loop()` runs these steps in order on every pass:**

1. `sensorUpdate()` (ECG sample at 250 Hz).
2. Serial output (text or plotter).
3. `bleUpdate()` (processes queued BLE events: connect, clear and scan commands).
4. `bleProcessWifiScan()`.
5. `wifiUpdate()` (state machine). On a state change it maps the WiFi state to a provisioning status:

   | WiFi state | Provisioning status |
   |---|---|
   | CONNECTING | `0x01` |
   | NTP_SYNCING | `0x04` |
   | READY | `0x05`, then switch to operational mode and reset the fail count |
   | DISCONNECTED after 3 failures | enter provisioning, then `0x03` |

6. `handleDataWindow()` (queue the full window for upload).
7. `checkSendResult()` (prediction comes back, then BLE CC03/CC04).
8. Every 1 s, if a phone is connected: notify HR (CC01), SpO2 (CC02) and the status byte (CC05).
9. Every 200 ms, if a phone is connected: notify up to 60 new ECG samples (CC06).
10. Blink the LED while provisioning.
11. Handle serial commands.

Window buffers are declared `static`. A 2,500-sample window is ≈5 KB and the Arduino loop task has only an 8 KB stack; two copies on the stack overflowed it (measured at 10,384 bytes).

### 6.6 Upload task (`data_sender.cpp`)

**FreeRTOS task**

- Task `DataSender`, pinned to **core 0**, priority 1, 12,288-byte stack.
- The send queue holds **2** windows. The result queue has depth 1 (only the latest result is kept).
- Each window gets up to **3 attempts** (1 + `API_MAX_RETRIES`), 500 ms apart. HTTP errors, including 4xx, are retried.

**Request:** `POST https://sanuka0523-cardiac-monitor-api.hf.space/api/v1/vitals`

- Headers: `Content-Type: application/json`, `X-API-Key: <API_KEY>`.
- TLS uses `setInsecure()`: the server certificate is **not** verified.
- 10 s timeout.

**JSON body** (≈12.7 KB with ECG, ≈5.2 KB when all samples are 0 because leads are off):

```json
{
  "device_id": "ESP32_21E5F0",
  "timestamp": 1760137478,
  "window_ms": 10000,
  "sample_rate_hz": 250,
  "heart_rate_bpm": 0,
  "spo2_percent": 0,
  "ecg_lead_off": false,
  "ecg_samples": [2048, 2051, 2047, "… 2500 integers 0–4095 …"],
  "beat_timestamps_ms": []
}
```

Field notes:

- `device_id` is `"ESP32_"` plus the last 3 bytes of the WiFi STA MAC in uppercase hex.
- `timestamp` is Unix epoch seconds (UTC) at the moment the window is queued, i.e. the window's **end**.
- `heart_rate_bpm` and `spo2_percent` are 0 when the MAX30100 is disabled.
- `beat_timestamps_ms` holds MAX30100 beats, in ms from window start, at most 30.

**Response handling**

- On 200 or 201, the task reads `prediction.risk_score` (float), `prediction.risk_label` (string, up to 15 chars) and `prediction.confidence`.
- It logs `[SEND] Risk: …` and `[RISK] …`, then sends the score and label to the phone over BLE.
- The task returns `SEND_OK` even when the body has no `prediction` (for example a poor-signal window).

### 6.7 WiFi state machine (`wifi_manager.cpp`)

```
DISCONNECTED ──(credentials + backoff elapsed)──► CONNECTING ──(WL_CONNECTED)──► NTP_SYNCING ──(year ≥ 2024)──► READY
     ▲                                               │ 15 s timeout                    │ link lost                   │ link lost
     └──────────── fail count +1, backoff 1→2→4→8→16→30 s ┘◄──────────────────────────────┴───────────────────────────────┘
```

- **Timeouts and failures:**
  - Connect timeout is 15 s. Only the timeout counts as a failure; wrong-password and no-SSID statuses are not detected early, so a bad password takes ≈48 s to give up.
  - After 3 timeouts, the device enters BLE provisioning, but it keeps retrying the old network in the background.
- **NTP:** `configTime(0, 0, "pool.ntp.org", "time.nist.gov")`. There is **no NTP timeout**: if NTP is blocked, the device stays in NTP_SYNCING and discards all windows.
- **Device ID:** derived inside `wifiInit()`, format `ESP32_XXXXXX`, and printed on serial as `[WIFI] Device ID: …`.

### 6.8 BLE provisioning logic (`ble_provisioner.cpp`)

- **Stack setup:** NimBLE, device name `CardiacMon`, TX power +6 dBm, preferred MTU 128, one connection at a time, no pairing or encryption.
- **Boot mode:**
  - If NVS namespace `cardiac` has a non-empty `wifi_ssid`, the board boots in `BOOT_WIFI`: it connects and advertises slowly (every 1 s).
  - Otherwise it boots in `BOOT_PROVISIONING`: fast advertising (100–150 ms) and the LED flashes.
- **Commands** are written to FF03 and queued from the BLE task to the main loop:
  - **`0x01` CONNECT**, using the SSID and password previously written to FF01 and FF02:
    1. Save them to NVS. This happens *before* testing them.
    2. Send status `0x01`.
    3. Set the in-memory credentials and reconnect.
    - The firmware then reports `0x04` (NTP sync) and `0x05` (ready), or `0x03` (failure) after 3 timeouts.
  - **`0x02` CLEAR_CREDS:**
    1. Erase NVS.
    2. Send status `0x06`, then immediately `0x00`.
    3. Enter provisioning.
    - The current WiFi connection is **not** dropped until reboot.
  - **`0x03` WIFI_SCAN:** asynchronous scan with a 10 s timeout. Results are sent on FF05, one network per notification, 30 ms apart, at most 20. A **0-byte** notification marks the end.
- **On disconnect,** the board restarts advertising.

### 6.9 Serial interface

**Commands** (single character at 115200 baud):

| Key | Effect |
|---|---|
| `t` | Text mode (default) |
| `p` | Plotter mode: prints `ECG:<v>,HR:<hr>,SpO2:<s>` on every loop pass. Unthrottled; useful for the Arduino Serial Plotter. |
| `b` | Clears the WiFi credentials stored in NVS and enters BLE provisioning. **Caveat:** the in-memory credentials remain, so the board reconnects to the same network until it is rebooted. After a reboot it starts in provisioning mode. |

**Typical log lines (text mode):**

```
============================================
  ESP32 Cardiac Monitor - Phase 4
============================================
  Mode: WiFi+BLE
[SENSOR] MAX30100 disabled (MAX30100_ENABLED=0): HR derived from ECG by the server.
[SENSOR] AD8232 ECG ready on GPIO34.
[BLE] No stored credentials -> BOOT_PROVISIONING
[BLE] Advertising as "CardiacMon" (fast)
[MAIN] No WiFi credentials. Waiting for BLE provisioning...
[MAIN] Use nRF Connect or the Flutter app to configure WiFi.
[WIFI] Device ID: ESP32_21E5F0
[WIFI] No credentials set, skipping connect.
[SEND] Background task started on Core 0
Attach ECG electrodes.
--------------------------------------------
[ECG] Leads OFF - reattach electrodes!
HR: --.- bpm  |  SpO2: ---%  |  Beats: 0
[WINDOW] WiFi not ready, data discarded.
# … after the app provisions WiFi:
[BLE] Client connected: xx:xx:xx:xx:xx:xx
[BLE] SSID received: <ssid>
[BLE] Password received
[BLE] Connect command: SSID=<ssid>
[BLE] Credentials saved to NVS for SSID: <ssid>
[WIFI] Connected! IP: 192.168.x.x, RSSI: -72 dBm
[WIFI] Starting NTP sync...
[WIFI] NTP synced: 2026-10-10 21:14:22 UTC
[BLE] Operational mode (slow advertising)
[WIFI] State: READY
[WINDOW] Queued 2500 samples for send
[SEND] Payload: 12687 bytes, 2500 samples, 0 beats
[SEND] HTTP 200
[SEND] Risk: low (score=0.243, conf=0.902)
[RISK] low (score=0.243, confidence=0.902)
```

When leads are off, the server stores the window as `lead_off`. No prediction is made, so no `Risk` lines appear.

### 6.10 MAX30100 library note

`firmware/lib/MAX30100lib/` is a vendored, patched copy, but it is **not what gets compiled**. That copy is missing `CircularBuffer.tpp`, so PlatformIO builds the registry copy from `lib_deps` instead. The stock library's `begin()` sets I2C to 400 kHz, which is why `sensor_manager.cpp` re-applies 100 kHz after it. This only matters if you re-enable the MAX30100.

### 6.11 Timing and memory summary

| Item | Value |
|---|---|
| Arduino loop task | Core 1, 8 KB stack |
| Upload task | Core 0, 12 KB stack |
| ECG sample period | 4 ms |
| Window | 10 s (2,500 samples) |
| BLE vitals / ECG notify | 1 s / 200 ms |
| HTTP timeout / attempts | 10 s / 3 |
| WiFi connect timeout / backoff | 15 s / 1–30 s |
| RAM used for ECG buffers | ≈30 KB: live buffer, static window, static enqueue job, 2-deep queue, task job |

---

## 7. BLE protocol reference

All UUIDs follow the pattern `0000XXXX-1234-5678-9ABC-DEF012345678`. Both services are advertised. Device name: **`CardiacMon`**.

### 7.1 Provisioning service `0000FF00-…`

| Char | UUID | Properties | Payload |
|---|---|---|---|
| SSID | `0000FF01-…` | Write | Raw bytes of the SSID (≤32) |
| Password | `0000FF02-…` | Write | Raw bytes of the password (≤63) |
| Command | `0000FF03-…` | Write | 1 byte: `0x01` connect, `0x02` clear credentials, `0x03` WiFi scan |
| Status | `0000FF04-…` | Read, Notify | 1 byte (table below) |
| Scan result | `0000FF05-…` | Notify | ASCII `"index,total,rssi,encType,ssid"`, one network per notification. A **0-byte** notification ends the list. `encType` is the ESP-IDF auth mode (0 open, 1 WEP, 2 WPA, 3 WPA2, 4 WPA/WPA2, 5 WPA2-Enterprise, …). |

**Provisioning status codes**, as sent by the firmware:

| Code | Meaning |
|---|---|
| `0x00` | Idle |
| `0x01` | Connecting to WiFi |
| `0x02` | WiFi OK (defined, never sent) |
| `0x03` | WiFi failed (after 3 timeouts) |
| `0x04` | NTP time sync |
| `0x05` | Ready (online, uploading) |
| `0x06` | Credentials cleared |

> **The app's mapping differs** (`app/cardiac_monitor/lib/config/constants.dart`): it treats `0x02` as NTP sync and `0x04` as "credentials cleared". During NTP sync the app therefore shows "Credentials cleared" for a few seconds before "Device ready!". This is cosmetic; see Section 15.

### 7.2 Cardiac service `0000CC00-…`

| Char | UUID | Props | Encoding |
|---|---|---|---|
| Heart rate | `0000CC01-…` | Read, Notify | `uint16` little-endian = bpm × 10 (truncated). 0 while the MAX30100 is disabled. |
| SpO2 | `0000CC02-…` | Read, Notify | `uint8` percent. 0 while disabled. |
| Risk score | `0000CC03-…` | Read, Notify | `float32` little-endian, range 0–1. Sent after each successful prediction. |
| Risk label | `0000CC04-…` | Read, Notify | ASCII/UTF-8 string, ≤15 chars: `normal`, `low`, `moderate`, `elevated`, `high` |
| Device status | `0000CC05-…` | Read, Notify | `uint8` bitmask: `0x01` sensor OK, `0x02` WiFi ready, `0x04` ECG lead-off, `0x08` "API ready" (currently identical to `0x02`) |
| ECG | `0000CC06-…` | Notify | 1–60 × `uint16` little-endian samples, oldest first, 4 ms apart (≈50 per 200 ms). No header or sequence number. Values 0–4095, baseline 2048, 0 = lead-off. Needs a negotiated MTU of at least 123; the app requests 128. |

### 7.3 Provisioning sequence

```
App                                   ESP32 (BOOT_PROVISIONING, fast advertising)
 │  scan for service 0000FF00 ────────►│
 │  connect, request MTU 128 ─────────►│
 │  subscribe FF04, FF05, CC01..CC06 ─►│
 │  write FF03 = 0x03 (scan) ─────────►│  WiFi.scanNetworks(async)
 │◄──── FF05 "0,5,-61,3,Home"  …  FF05 <empty>  (end)
 │  write FF01 = "<ssid>" ────────────►│
 │  write FF02 = "<password>" ────────►│
 │  write FF03 = 0x01 (connect) ──────►│  save to NVS, connect
 │◄──── FF04 0x01  (connecting)
 │◄──── FF04 0x04  (NTP sync)
 │◄──── FF04 0x05  (ready) — switches to slow advertising, starts uploading
 │◄──── CC05 status every 1 s, CC06 ECG every 200 ms, CC03/CC04 after each prediction
```

Any BLE tool can drive this, for example **nRF Connect**: write the SSID and password, then `01` to FF03.

---

## 8. Backend API (FastAPI)

### 8.1 Stack

- **Runtime:** Python 3.11 in a `python:3.11-slim` Docker image.
- **Web:** FastAPI 0.131.0 + Uvicorn 0.41.0.
- **Database driver:** Motor 3.7.1 (async MongoDB) with PyMongo 4.9.2.
- **Settings and models:** Pydantic 2.12, with pydantic-settings for configuration.
- **Auth:** python-jose (JWT HS256) and bcrypt 5.0.
- **ML:** PyTorch 2.10.0 (CPU wheel, installed in the Dockerfile), XGBoost 3.2.0, scikit-learn 1.8.0, NeuroKit2 0.2.12, NumPy 1.26.4, SciPy 1.14.1.
- **Pinning:**
  - `requirements.txt` pins all 58 packages: the exact set the deployed image was verified with.
  - Edit `requirements.in`, then regenerate with:
    ```bash
    uv pip compile requirements.in --python-version 3.11 --python-platform x86_64-manylinux_2_28 --no-header --no-annotate -o requirements.txt
    ```

Source layout (`backend/app/`):

| File | Purpose |
|---|---|
| `main.py` | App, CORS (`*`), routers, lifespan |
| `config.py` | Settings from environment / `.env` |
| `database.py` | Motor client + index creation |
| `middleware/auth.py` | Password hashing, JWT, API-key check, current user |
| `models/{user,device,vitals,prediction}.py` | Pydantic request/response schemas |
| `routes/{health,auth,devices,vitals,predictions}.py` | Endpoints |
| `services/signal_quality.py` | ECG quality gate |
| `services/ml_service.py` | Model loading + ensemble prediction |
| `services/shared_devices.py` | Devices visible to every account |
| `services/feature_extractor.py` | Unused; the real extractor is `ml_src/feature_extractor.py` |

### 8.2 Configuration (environment variables)

| Variable | Default | Required in production | Meaning |
|---|---|---|---|
| `MONGODB_URI` | `mongodb://localhost:27017` | **yes** (secret) | Atlas connection string `mongodb+srv://user:pass@cluster…/` |
| `DATABASE_NAME` | `cardiac_monitor` | no | Database name |
| `JWT_SECRET` | `changeme` | **yes** (secret) | HMAC key for app login tokens |
| `JWT_ALGORITHM` | `HS256` | no | |
| `JWT_EXPIRY_HOURS` | `24` | no | Token lifetime |
| `API_KEY` | `dev-api-key` | **yes** (secret) | Device upload key. Must match the firmware's `secrets.h`. |
| `SHARED_DEVICE_IDS` | `""` | no (Space *variable*) | Comma-separated device IDs visible to every account; `*` adds every non-playback device that has sent data. Live value: `ESP32_21E5F0,PLAYBACK_DEVICE_REC,*`. |

Locally these are read from `backend/.env`. The `.env` file is resolved relative to the working directory, so run the server from `backend/`. A template is in `backend/.env.example`. On Hugging Face, set them as Space **secrets** (the first three) and **variables** (the rest).

### 8.3 Startup (lifespan)

1. `connect_db()` creates the Motor client (5 s server-selection timeout, TLS with the certifi CA bundle) and the indexes.
   - **Any failure is caught:** the API still starts, and `/health` reports `"db": "disconnected"`.
   - This matters because a paused Atlas cluster makes its DNS record disappear.
2. `ensure_shared_device_docs()` upserts an unowned `devices` record for each shared ID. This is insert-only; existing records are never changed.
3. `load_models()` loads ECGFounder and XGBoost from `ml_models/`. A failure is logged, and the server runs without predictions.

### 8.4 Authentication

| Client | Mechanism |
|---|---|
| **App / user** | `POST /auth/register` or `/auth/login` with JSON `{email, password}`. The response is `{access_token, token_type:"bearer"}`; send it as `Authorization: Bearer <token>`. JWT payload `{sub: <user id>, exp}`, HS256, 24 h, no refresh token. Passwords are bcrypt-hashed. |
| **Device** | `X-API-Key: <API_KEY>` header on `POST /vitals`. One global key for all devices. A wrong key returns 401; a missing header returns 422. |

On every authenticated request, `get_current_user` loads the user and replaces `user.device_ids` with **own devices first, then shared devices**. All ownership checks and `/auth/me` use this merged list.

### 8.5 Endpoint reference

All paths are prefixed with `https://sanuka0523-cardiac-monitor-api.hf.space`. The interactive version is at `/docs`.

| Method | Path | Auth | Request | Response / behaviour |
|---|---|---|---|---|
| GET | `/` | – | – | 307 redirect to `/docs` |
| GET | `/dashboard` | – (page signs in with JWT) | – | Web dashboard HTML (`app/static/dashboard.html`). Not in the OpenAPI schema. |
| GET | `/api/v1/health` | – | – | `{"status":"ok","db":"connected"\|"disconnected","version":"1.0.0"}`. Always 200. |
| POST | `/api/v1/auth/register` | – | `{email (5–100), password (6–100), name (1–100)}` | `{access_token, token_type}`. 400 "Email already registered". |
| POST | `/api/v1/auth/login` | – | JSON `{email, password}` (not form data) | `{access_token, token_type}`. 401 "Invalid email or password". |
| GET | `/api/v1/auth/me` | JWT | – | `{id, email, name, device_ids[], profile, created_at}` (device_ids includes shared devices) |
| PUT | `/api/v1/auth/profile` | JWT | **Flat** `HealthProfile`: `age 1–120, sex male\|female\|other, height_cm 50–300, weight_kg 10–500, is_diabetic, is_hypertensive, is_smoker, family_history, known_conditions[], medications[]` | Replaces the whole profile and returns the user |
| POST | `/api/v1/devices/register` | JWT | `{device_id (1–50), name?}` | Device record. **Shared device:** returns the record and never claims ownership. Owned by someone else: 400 "Device already registered to another user". Otherwise sets the owner and adds the device to the user's list. |
| GET | `/api/v1/devices` | JWT | – | List of `{device_id, name, owner_user_id, last_seen, registered_at}` for own and shared devices (max 100) |
| POST | `/api/v1/vitals` | **X-API-Key** | `VitalsCreate` (below) | `VitalsResponse` plus `prediction` (Section 8.7) |
| GET | `/api/v1/vitals/me/latest` | JWT | `?include_ecg=false` | Newest window (by device timestamp) across own and shared devices, with its prediction. 404 if none. |
| GET | `/api/v1/vitals/me/history` | JWT | `?limit=50 (1–500)&offset=0` | `{vitals: [...], total}`. ECG omitted; `prediction` is null in this list. |
| GET | `/api/v1/vitals/{device_id}/latest` | JWT | `?include_ecg=false` | Newest window for one device, with its prediction. 403 if not your device. |
| GET | `/api/v1/vitals/{device_id}` | JWT | `?limit&offset` | `{vitals, total}` for one device |
| GET | `/api/v1/predictions/me/latest` | JWT | – | Newest prediction (by created_at) across own and shared devices |
| GET | `/api/v1/predictions/me/history` | JWT | `?limit (≤500)&offset` | `{predictions: [...], total}` |
| GET | `/api/v1/predictions/{device_id}/latest` | JWT | – | Newest prediction for one device |
| GET | `/api/v1/predictions/{device_id}` | JWT | `?limit&offset` | `{predictions, total}` |

**`VitalsCreate` (device upload body)**

| Field | Type | Rule |
|---|---|---|
| `device_id` | str | 1–50, required |
| `timestamp` | int | Unix seconds, required |
| `window_ms` | int | 1000–60000, default 10000 |
| `sample_rate_hz` | int | 50–1000, default 100 |
| `heart_rate_bpm` | float | 0–300, required (0 = unknown) |
| `spo2_percent` | int | 0–100, required (0 = unknown) |
| `ecg_lead_off` | bool | default false |
| `ecg_samples` | int[] | **100–6000 items**, required |
| `beat_timestamps_ms` | int[] | default [] |
| `source` | str? | ≤120 chars. Label for playback data, e.g. `"PTB-XL #8473 · label: myocardial infarction"`. |

**`VitalsResponse`:** `id, device_id, timestamp, heart_rate_bpm, heart_rate_source ("sensor"|"ecg"|null), spo2_percent, ecg_lead_off, sample_count, ecg_samples?, sample_rate_hz, prediction? {risk_score, risk_label, confidence}, signal_quality ("good"|"poor"|"lead_off"), source, created_at`.

**`PredictionResponse`:** `id, vitals_id, device_id, risk_score, risk_label, confidence, features{10 HRV/morphology values}, model_version, created_at`.

Datetimes are UTC but serialised **without a timezone suffix**, e.g. `2026-10-10T21:15:20`. Clients must treat them as UTC.

The `/me/...` routes are declared before `/{device_id}/...` on purpose. Otherwise `/me/latest` would match `/{device_id}/latest` with `device_id="me"`.

### 8.6 MongoDB data model (database `cardiac_monitor`)

| Collection | Fields | Indexes |
|---|---|---|
| `users` | `email, password_hash, name, device_ids[], profile{}, created_at` | `email` unique |
| `devices` | `device_id, name, owner_user_id (string id or null), last_seen, registered_at` | `device_id` unique |
| `vitals` | `device_id, user_id (owner at upload time or null), timestamp, window_ms, sample_rate_hz, heart_rate_bpm, heart_rate_source, spo2_percent, ecg_lead_off, ecg_samples[], beat_timestamps_ms[], signal_quality, signal_quality_reason, source, created_at` | `(device_id, timestamp −1)`, `(user_id, timestamp −1)` |
| `predictions` | `vitals_id (string), device_id, user_id, risk_score, risk_label, confidence, features{}, model_version, created_at` | `(device_id, created_at −1)`, `(user_id, created_at −1)` |

### 8.7 Upload pipeline (`POST /api/v1/vitals`)

1. Check the API key.
2. Look up the device record. `user_id` = its `owner_user_id`, or null. Unregistered and shared devices upload with `user_id = null`.
3. **Quality gate:**
   - If `ecg_lead_off` is true, quality is `lead_off`.
   - Otherwise run `assess_ecg_quality(samples, sample_rate_hz)`, which gives `good` or `poor` plus a reason.
   - If the check itself errors, quality is `poor` with reason `quality_check_error`.
4. Insert the vitals document and update the device's `last_seen`.
5. **Only if quality is `good`:**
   1. If the device has an owner, compute 24 h and 7 d baselines and load the owner's profile. These are currently not fed to the model (Section 15).
   2. Run `predict()`.
   3. If `heart_rate_bpm <= 0`, store the heart rate measured from the ECG (`features.mean_hr_ecg`, accepted if 30–220 bpm) with `heart_rate_source = "ecg"`.
   4. Insert the prediction document.
6. Return the window plus `prediction`. Poor and lead-off windows are stored too, with `prediction: null`.

### 8.8 Signal-quality gate (`services/signal_quality.py`)

The gate was built to stop the model from scoring noise. Unattached electrodes produced rail-to-rail mains noise that the old pipeline scored as "high risk". The thresholds were tuned on PTB-XL lead II (scaled to 1 mV = 400 counts, at 250 Hz and 100 Hz), on synthetic noise, and on real no-electrode windows from this device. Rules are checked in order, and the first failure gives the `reason`:

| # | Check | Rejects when | Reason |
|---|---|---|---|
| 0 | Duration | < 4 s | `too_short` |
| 1 | Finite values | any NaN/inf | `invalid_samples` |
| 2 | Samples within 2 counts of 0 or 4095 | > 1% | `saturated` |
| 3 | Longest run of identical samples | > 1 s | `flat_segment` |
| 4 | p99−p1 of 0.5–40 Hz band-passed signal | < 40 counts | `low_amplitude` |
| 5 | Power ≥40 Hz ÷ power 0.5–40 Hz | > 0.5 | `high_frequency_noise` |
| 6 | Power 5–40 Hz ÷ power 0.5–40 Hz | < 0.03 | `no_qrs_content` (pure sine waves) |
| 7 | √(largest beat energy ÷ typical) | > 10 | `transient_artifact` (steps, electrode pops) |
| 8 | Detected beats | < 4 | `too_few_beats` |
| 9 | 60 / median RR | outside 30–200 bpm | `hr_out_of_range` |
| 10 | Beat energy ÷ energy between beats | < 5 | `no_distinct_qrs` |
| 11 | QRS slope symmetry | < 0.25 | `step_artifact` |
| 12 | Median beat-to-template correlation | < 0.5 | `inconsistent_beats` |
| 13 | RR coefficient of variation | > 0.8 (lenient so AF passes) | `irregular_rr` |
| – | All passed | | `good` / `ok` |

- **Beat detection:** 5–15 Hz band-pass → squared derivative → 150 ms moving average → peaks ≥250 ms apart. A beat is any peak ≥30% of the 4th-largest peak.
- **Measured performance:**

  | Data | Result |
  |---|---|
  | PTB-XL test fold, NORM | 99.7% pass |
  | PTB-XL test fold, MI | 96–97% pass |
  | PTB-XL test fold, AF | 97% pass |
  | Synthetic garbage | 100% rejected |
  | Device no-electrode windows | 55 of 57 rejected (the 2 that pass are a simulated ECG from a test script) |
  | Runtime | ≈1 ms per window |

- **Note:** the gate's internal heart-rate estimate over-counts on some morphologies, so it is not stored. Heart rate comes from the model's feature extractor instead.

### 8.9 Shared devices

`SHARED_DEVICE_IDS` makes chosen devices visible to every logged-in account. This is useful when one demo board is used by several people.

- Shared devices are added to every user's `device_ids` and `/devices` list, and they pass ownership checks.
- All `/me/...` queries use `{$or: [{user_id: me}, {device_id: {$in: shared}}]}`.
- Registering a shared device is read-only: it never creates or claims ownership.
- At startup an unowned record is upserted for each shared ID, so `last_seen` updates.
- Unset `SHARED_DEVICE_IDS` (or leave it empty) for the original per-user behaviour.

**`*` (all devices).** The entry `*` also shares every device that has uploaded at least one window (`db.vitals.distinct("device_id")`, which uses the `device_id` index). A new board therefore appears for every account as soon as it sends data; nobody has to register it.

- Devices whose ID starts with `PLAYBACK_` are excluded from `*`. They hold recorded or dataset ECG, so they are shared only when listed by name (as `PLAYBACK_DEVICE_REC` is).
- With `*`, the `/me/...` filter uses the account's full visible device list: `{$or: [{user_id: me}, {device_id: {$in: visible}}]}`.
- Device order in `/auth/me`: the account's own devices, then named shared devices, then the other uploading devices (A–Z). The app shows the first one; the web dashboard opens on whichever uploaded most recently.
- Privacy: every account can read every shared device's ECG. That suits a single demo prototype. Remove `*` before real patients use the system.

**Web dashboard (`/dashboard`).** A single HTML file served by the API (`app/static/dashboard.html`), styled like the app. Users sign in or register on the Login / Register tabs, and the page calls the JSON API with their JWT. It polls every 5 s: `GET /api/v1/vitals/{id}/latest?include_ecg=true` and `GET /api/v1/predictions/{id}?limit=30`. It shows the ECG window, ECG-derived heart rate, the risk assessment, a 30-point risk trend and device status. Playback devices are labelled **RECORDED · NOT LIVE**. `?api=<base URL>` points the page at another API.

### 8.10 Scripts (`backend/scripts/`)

| Script | Purpose | Example |
|---|---|---|
| `playback_ptbxl.py` | Sends real, labelled PTB-XL ECGs (test fold, seeded random sample, NORM and MI alternating) through the API as device **`PLAYBACK_PTBXL`**. Each window is converted exactly like device data: lead II resampled to 250 Hz, 1 mV = 400 counts, centred at 2048. Prints true label vs predicted risk. | `API_KEY=… uv run --no-project --python 3.11 --with wfdb --with pandas --with httpx --with 'neurokit2>=0.2.7' --with 'numpy==1.26.4' --with 'scipy==1.14.1' python scripts/playback_ptbxl.py --ptbxl ../ml/data/ptb-xl --api <URL> --per-label 5 [--email … --password …] [--ids 4354,8473] [--interval 10]` |
| `replay_recording.py` | Replays a raw ESP32 capture (`D:` lines from `ecg_diag`, or JSON `{sample_rate_hz:250, samples:[…]}`) through the API. Each 10 s window is processed exactly as the firmware does (`firmware_ecg.py`) and sent as **`PLAYBACK_DEVICE_REC`** with a `--label`. `--start-time` keeps the original recording times. | `API_KEY=… uv run --no-project --python 3.11 --with httpx python scripts/replay_recording.py rec.raw --api <URL> --label "Recorded on this device · 2026-10-11 · healthy adult at rest" --start-time 2026-10-11T01:50:38+05:30` |
| `firmware_ecg.py` | Python port of the firmware ECG chain (notch → LPF → DC removal → ×0.5 → +2048, reset each window). Used by the replay script and tests. | (library) |

Playback data is always labelled: `PLAYBACK_*` device IDs and a `source` field. Never present it as live data.

### 8.11 Tests

Run from `backend/` with the pinned requirements and pytest:

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt pytest          # torch not needed for tests
python -m pytest tests/ -v                       # 61 tests, ~1 s
flake8 app/ tests/ scripts/ --max-line-length=120 --extend-ignore=E203,W503
```

| File | Covers |
|---|---|
| `test_signal_quality.py` (46) | PTB-XL pass rates, garbage rejection, real device noise, route wiring with a fake DB/model |
| `test_firmware_ecg.py` (4) | Firmware filter port, 0.5 scaling keeps peaks off the rails |
| `test_shared_devices.py` (4) | Parsing, ordering, Mongo scope filter |
| `test_vitals_source.py` (3) | `source` field |
| `test_ecg_heart_rate.py` (2) | ECG-derived HR bounds |
| `test_database.py` (2) | API starts and reports `disconnected` when the Atlas host can't be resolved |

The fixtures (`tests/fixtures/`) are a small PTB-XL extract (40 records, CC BY 4.0) and 8 real no-electrode device windows. Their generator scripts are next to them.

### 8.12 Running the backend locally

```bash
cd backend
cp .env.example .env            # fill in MONGODB_URI, JWT_SECRET, API_KEY
git lfs install && git lfs pull # real model files (otherwise backend/ml_models holds 134-byte pointers)
pip install torch==2.10.0 --index-url https://download.pytorch.org/whl/cpu
pip install -r requirements.txt
uvicorn app.main:app --reload --port 7860
# → http://localhost:7860/docs
```

> **Caution from experience:** never point a local test server at the production database by accident. If an environment file fails to load, pydantic-settings silently falls back to `backend/.env`. For throwaway tests:
> - run from a copy of `backend/` that has **no** `.env`, and
> - use a separate `DATABASE_NAME`.

---

## 9. ML models: inference

### 9.1 Models

| Model | File | What it is |
|---|---|---|
| **ECGFounder** (fine-tuned) | `backend/ml_models/ecgfounder_best.pt` (123 MB, Git LFS) | 1-D CNN (`Net1D`): SE-ResNet-style stages, filters [64, 160, 160, 400, 400, 1024, 1024], blocks [2, 2, 2, 3, 3, 4, 4], kernel 16, stride 2, groups width 16, Swish activations, global average pooling → 1 logit. Starts from the public single-lead ECGFounder weights (`PKUDigitalHealth/ECGFounder`, file `1_lead_ECGFounder.pth`, MIT). |
| **XGBoost** | `backend/ml_models/xgboost_cardiac.joblib` (770 KB, Git LFS) | Gradient-boosted trees on 25 handcrafted ECG features |

Both predict **P(abnormal ECG)**, where "abnormal" is any of the PTB-XL superclasses MI, STTC, CD or HYP versus NORM (Section 10.2).

### 9.2 Prediction (`services/ml_service.py`)

1. **ECGFounder path:**
   1. Resample the window to exactly **5,000 samples** (FFT resample).
   2. Z-score it: (x − mean) / std.
   3. Run it as a tensor of shape (1, 1, 5000).
   4. `p_ecg = sigmoid(logit)`.
2. **XGBoost path:**
   1. Extract features with NeuroKit2 at the device sample rate (clean → R-peaks → HRV, delineation, statistics). If fewer than 3 R-peaks are found, fixed fallback values are used.
   2. `p_xgb = predict_proba(features)[1]`.
   3. The **25 features** are listed below.
3. **Ensemble:** combine the two scores (table below).
4. **Risk labels:** map the score to a label (table below).

**XGBoost features**

| Group | Features |
|---|---|
| HRV | `mean_rr, sdnn, rmssd, pnn50, mean_hr_ecg, hr_std, rr_range` |
| Morphology | `qrs_duration, r_amplitude, r_amplitude_std, qt_interval, qtc, st_level, t_amplitude, p_wave_ratio` |
| Statistics | `rms, entropy, zero_crossing_rate, kurtosis, skewness, snr` |
| Device | `heart_rate_sensor` (sensor HR, or `mean_hr_ecg` if 0), `spo2` (97 if 0), `hr_sensor_ecg_diff`, `ecg_quality` |

**Ensemble**

| Models available | Score | Confidence | `model_version` |
|---|---|---|---|
| Both | `0.60 × p_ecg + 0.40 × p_xgb` | `1 − |p_ecg − p_xgb|` | `v1.0-ensemble` |
| ECGFounder only | `p_ecg` | 0.7 | `v1.0-ecgfounder-only` |
| XGBoost only | `p_xgb` | 0.6 | `v1.0-xgboost-only` |

**Risk labels**

| Score | Label |
|---|---|
| < 0.2 | normal |
| < 0.4 | low |
| < 0.6 | moderate |
| < 0.8 | elevated |
| otherwise | high |

The response's `features` holds the first 10 features (HRV and morphology). The ECG-derived heart rate is `features.mean_hr_ecg`.

---

## 10. ML models: training

Training code is in `ml/`. It runs offline; nothing in `ml/data` or `ml/models` is committed.

### 10.1 Dataset

- **PTB-XL v1.0.3** (PhysioNet): 21,799 10-second 12-lead ECGs from 18,869 patients, CC BY 4.0.
- **Download:** `wfdb.dl_database("ptb-xl", "ml/data/ptb-xl")`, which `train_all.py` does automatically (3.2 GB).
- **Files used:**
  - `ptbxl_database.csv`: `scp_codes`, `strat_fold`, `filename_hr`/`filename_lr`.
  - `records500/` (500 Hz) and `records100/` (100 Hz).
- **Splits:** the standard stratified folds. Folds 1–8 are train (16,209 records after filtering), fold 9 validation (2,023), fold 10 test (2,037). The test set is 54.6% abnormal.

### 10.2 Labels

- **Mapping:** SCP codes are mapped to five superclasses (NORM, MI, STTC, CD, HYP) with a hard-coded table in `ml/src/data_loader.py`. Only codes with likelihood ≥50 count.
- **Superclass:** the one with the highest summed likelihood wins.
- **Binary target:** **0 = NORM, 1 = any other superclass**. Records with no qualifying code are dropped (1,530 records).
- **Caveat:** the hard-coded table differs slightly from the official `scp_statements.csv`. It omits e.g. ISCAS, ANEUR, EL, ILBBB, ISCAN and IPMI, and includes a few non-diagnostic codes.

### 10.3 Pre-processing

- **Lead II only** (`p_signal[:, 1]`).
- **Per-record z-score**, with no band-pass filter.
- **Two copies are saved:**
  - 500 Hz × 5,000 samples, for ECGFounder: `ml/data/processed/ptbxl_500hz.npz`.
  - 100 Hz × 1,000 samples, for XGBoost: `ptbxl_100hz.npz`.

### 10.4 ECGFounder fine-tuning (`ml/src/finetune_ecgfounder.py`)

- **Starting weights:** `hf_hub_download("PKUDigitalHealth/ECGFounder", "1_lead_ECGFounder.pth")`. The `dense.*` head is dropped and the rest loaded with `strict=False`.
- **Loss:** `BCEWithLogitsLoss(pos_weight = n_neg / n_pos)`.
- **Phase 1:** backbone frozen, head only, Adam lr 1e-3, 5 epochs.
- **Phase 2:** everything unfrozen, Adam lr 1e-4, weight decay 1e-5, `ReduceLROnPlateau` on validation AUC (factor 0.5, patience 5), early stopping (patience 10), up to 25 more epochs.
- **Batch size:** 64.
- **Device:** CUDA, then MPS, then CPU. No random seed is set.
- **Outputs:**
  - The best validation AUC checkpoint goes to `ml/models/ecgfounder_best.pt`.
  - Test-set predictions go to `ecgfounder_test_preds.npz`.

### 10.5 XGBoost (`ml/src/train_xgboost.py`)

- **Input:** the 25 features (Section 9.2), extracted from z-scored 100 Hz lead II.
- **Parameters:** `XGBClassifier(n_estimators=500, max_depth=6, learning_rate=0.05, objective="binary:logistic", eval_metric="auc", tree_method="hist", random_state=42, early_stopping_rounds=30, scale_pos_weight=n_neg/n_pos)`. The validation set is used for early stopping.
- **Output:** `ml/models/xgboost_cardiac.joblib`.

### 10.6 Evaluation (`ml/src/evaluate.py`) and results

The ensemble is 0.6 × ECGFounder + 0.4 × XGBoost. Results on the **held-out test fold (2,037 records)**:

| Model | AUC-ROC | Accuracy @0.5 | Precision | Recall (sensitivity) | Specificity |
|---|---|---|---|---|---|
| ECGFounder | **0.917** | 0.844 | 0.902 | 0.802 | 0.895 |
| XGBoost | 0.883 | 0.800 | 0.870 | 0.746 | 0.866 |
| Ensemble | 0.915 | 0.838 | 0.901 | 0.789 | 0.896 |
| Ensemble at Youden threshold 0.417 | – | 0.846 | – | 0.833 | 0.862 |

- The Youden threshold was chosen on the test set, so it is optimistic. The backend does not use it; it uses fixed bins at 0.2/0.4/0.6/0.8.
- ROC and PR curves are written to `ml/models/roc_curves.png` and `pr_curves.png`.

### 10.7 Reproduce training

```bash
cd ml
pip install -r requirements.txt
python3 train_all.py                 # download + preprocess + ECGFounder + XGBoost + evaluation
# options: --skip-download, --xgboost-only, --ecgfounder-only, --epochs 30, --batch-size 64
cp models/ecgfounder_best.pt models/xgboost_cardiac.joblib ../backend/ml_models/   # then commit via Git LFS
```

A GPU is strongly recommended for ECGFounder fine-tuning.

### 10.8 Train/serve differences to be aware of

- **ECGFounder:** preprocessing matches training (resample to 5,000, z-score).
- **XGBoost:** trained on **z-scored** PTB-XL at 100 Hz with constant SpO2 = 97, but served on **raw device counts at 250 Hz**. Amplitude features (`r_amplitude`, `rms`, `st_level`, `t_amplitude`) are therefore on a different scale.
- **Despite these differences,** on a real 5.5-minute recording from this device every clean window came out *normal* or *low*, and PTB-XL heart-attack (MI) records came out *elevated* or *high* (Section 17).

---

## 11. Mobile app (Flutter)

### 11.1 Stack and project settings

| Item | Value |
|---|---|
| Location | `app/cardiac_monitor/` |
| App version | `1.1.0+2` |
| Dart SDK | `^3.11.0` (needs **Flutter ≥ 3.38**) |
| Android package | `com.cardiacmonitor.cardiac_monitor` |
| iOS bundle ID | `com.cardiacmonitor.cardiacMonitor` (iOS 13+) |
| Dependencies | `provider` (state), `flutter_blue_plus` 1.36 (BLE), `dio` 5.9 (HTTP), `flutter_secure_storage` (JWT), `shared_preferences` (settings), `fl_chart` (charts), `google_fonts` (Plus Jakarta Sans), `permission_handler`, `intl`, `flutter_animate`, `shimmer`, `phosphor_flutter` (icons) |
| Android permissions | `BLUETOOTH`/`BLUETOOTH_ADMIN` (≤ API 30), `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `INTERNET` |
| iOS keys | `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription`, `NSLocationWhenInUseUsageDescription` |
| Release signing | The Android release build is signed with the **debug** key. Fine for sideloading, not for the Play Store. |

### 11.2 Architecture

`main.dart` creates the services and wraps the app in a `MultiProvider`:

| Layer | Class | Role |
|---|---|---|
| Service | `ApiService` | Dio client. Base URL is read from settings on every call. A JWT interceptor adds `Authorization: Bearer`. |
| Service | `BleService` | flutter_blue_plus wrapper: scan, connect, subscribe, parse notifications, provisioning writes |
| Service | `AuthStorage` | Secure storage for `access_token` |
| Service | `SettingsService` | SharedPreferences `api_base_url` (default `https://sanuka0523-cardiac-monitor-api.hf.space`) |
| Provider | `AuthProvider` | Login, register and auto-login. Holds `user` and `deviceIds`. |
| Provider | `BleProvider` | Connection state, live vitals, provisioning status, WiFi list, live ECG buffer (last 1,250 samples) |
| Provider | `VitalsProvider` | History lists (`/vitals/me/history`, `/predictions/me/history`) |
| Provider | `ProfileProvider`, `ThemeProvider` | Health profile save; light/dark/system theme |

Constants are in `lib/config/constants.dart`: BLE UUIDs, command codes, API paths and storage keys.

### 11.3 Screens and navigation

| Screen | Reached from | Shows | Data source |
|---|---|---|---|
| Splash / auth gate | App start | Auto-login with the stored token | API `/auth/me` |
| Login / Register | No valid token | Email, password, name | API `/auth/login`, `/auth/register` |
| **Device Setup** (3 steps) | After login if the account has **no** devices; Dashboard "Connect Device"; Settings "Add Device" | **1 Scan:** find boards advertising the provisioning service. **2 WiFi:** scan networks via the board, pick one, enter the password, "Connect Device". **3 Status:** connecting → ready, then type the device ID (`ESP32_XXXXXX`, printed on the board's serial log) and "Register & Continue". | BLE + API `/devices/register` |
| **Dashboard** ("Monitor" tab) | Home | Greeting, BLE chip, Heart-rate and SpO2 cards, Risk Assessment, ECG waveform (LIVE over BLE, otherwise the latest stored window every 12 s), device status (Sensor/WiFi/ECG/API) | HR, SpO2, risk and status come **only from BLE**. ECG comes from BLE or API `/vitals/{first device}/latest?include_ecg=true`. |
| **History** ("Trends" tab) | Tab | 24h / 7d / 30d tabs, average HR, average SpO2, readings count, HR/SpO2/risk charts | API `/vitals/me/history` + `/predictions/me/history`, filtered by time in the app |
| Profile | Tab | Age, sex, height, weight, risk factors, conditions, medications | API `PUT /auth/profile` (has a bug; Section 15) |
| Settings | Tab | Theme, **API server URL**, BLE connect/disconnect, device list, logout | Local settings + API `/devices` |

With shared devices enabled, every account already has devices. A new account therefore skips Device Setup and lands on the Dashboard. To set up WiFi, tap **Connect Device** on the Dashboard while not connected.

### 11.4 BLE client details

1. **Permissions:** requests Bluetooth scan/connect and location before scanning. The results are not checked.
2. **Scan:** `startScan(timeout: 10 s, withServices: [0000FF00-…])`, so devices are found by the provisioning service UUID, not by name.
3. **Connect** (10 s timeout), then `requestMtu(128)` (needed for 60-sample ECG batches; **Android-only API**), then service discovery, then subscriptions:
   - FF04 provisioning status
   - FF05 WiFi scan results
   - every notifiable characteristic in the cardiac service
4. **Parsing** matches Section 7:
   - HR: `uint16 LE / 10`
   - SpO2: `uint8`
   - Risk: `float32 LE`
   - Label: bytes → string
   - Status: bitmask
   - ECG: list of `uint16 LE`
5. **Provisioning writes**, all with response:
   - `FF03 ← 0x03` (scan)
   - `FF01 ← SSID`
   - `FF02 ← password`
   - `FF03 ← 0x01` (connect)
6. **WiFi scan results** (FF05 `index,total,rssi,enc,ssid`) are de-duplicated by SSID and sorted by signal strength. An empty notification ends the scan.
7. **Reconnection:** there is none automatically. After a disconnect, use Dashboard → Connect Device again.

### 11.5 Build and run

```bash
cd app/cardiac_monitor
flutter pub get
flutter run                                   # on a physical Android phone (BLE does not work in emulators)
flutter build apk --release                   # → build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

To use a different backend, open **Settings → API Server URL** in the app and enter e.g. `https://<your-space>.hf.space`. There must be no trailing `/`. Plain `http://` URLs are blocked by default on Android and iOS.

A work-in-progress app improvement is saved in `git stash@{0}` (local only, not pushed). It contains:

- UTC timestamp parsing
- a peak-preserving ECG chart
- 250 Hz BLE ECG axis
- a labelled playback card
- a poor-signal notice

Its dashboard file is incomplete and does not compile as stashed.

---

## 12. Deployment and CI/CD

### 12.1 Hosting overview

| Component | Where | Notes |
|---|---|---|
| API | Hugging Face Space `Sanuka0523/Cardiac_Monitor_API` (Docker SDK, CPU basic, port 7860) | Free Spaces **sleep after ~48 h without traffic** and wake on the next request (slow first call). A Space can also get stuck in "Runtime error" and need a manual **Restart**. |
| Database | MongoDB Atlas, free M0 cluster, database `cardiac_monitor` | Free clusters **pause after 60 days without connections**. While paused the cluster's DNS disappears and the API reports `db: disconnected`. Resume it from the Atlas dashboard; data is kept. |
| Model files | Git LFS in the GitHub repo (`backend/ml_models/`) | During the Docker build on HF, LFS files arrive as pointers. The Dockerfile then downloads them from `media.githubusercontent.com` (uses GitHub LFS bandwidth). |
| APK + firmware binaries | GitHub Releases | Built by `release.yml` on version tags |

### 12.2 Dockerfile (backend)

```dockerfile
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir torch==2.10.0 --index-url https://download.pytorch.org/whl/cpu
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ app/
COPY ml_src/ ml_src/
COPY ml_models/ ml_models/
# If the model files are Git LFS pointers (<1000 bytes), download the real files from GitHub
RUN MODEL_SIZE=$(wc -c < ml_models/ecgfounder_best.pt) && if [ "$MODEL_SIZE" -lt 1000 ]; then \
      apt-get update && apt-get install -y --no-install-recommends curl && \
      curl -L -o ml_models/ecgfounder_best.pt     "https://media.githubusercontent.com/media/Sanuka23/cardiac-monitor/main/backend/ml_models/ecgfounder_best.pt" && \
      curl -L -o ml_models/xgboost_cardiac.joblib "https://media.githubusercontent.com/media/Sanuka23/cardiac-monitor/main/backend/ml_models/xgboost_cardiac.joblib" && \
      apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*; fi
ENV PYTHONUNBUFFERED=1
EXPOSE 7860
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-7860}
```

The Space's `backend/README.md` front matter configures the Space: `sdk: docker`, `app_port: 7860`, title "Cardiac Monitor API".

### 12.3 Deploying the API

**Option A — release workflow.** Push a tag `v*`. The `deploy-hf-spaces` job:

1. clones the Space using the repo secret `HF_TOKEN`;
2. `rsync --delete`s `backend/` into it;
3. force-pushes.

It runs with `continue-on-error`, so check the job log.

**Option B — manual upload** (what was used in October 2026). This needs a Hugging Face **write** token, passed as an environment variable and never committed:

```bash
cd cardiac-monitor
HF_TOKEN=hf_xxx python - <<'PY'
from huggingface_hub import HfApi
api = HfApi()
repo = "Sanuka0523/Cardiac_Monitor_API"
api.upload_folder(folder_path="backend", repo_id=repo, repo_type="space",
    ignore_patterns=["ml_models/*", ".env", ".env.*", "**/__pycache__/*", "*.pyc", ".DS_Store"],
    commit_message="Deploy <git sha>")
PY
```

`ml_models/*` is excluded on purpose. A local checkout without `git lfs pull` holds 134-byte pointer files, which would overwrite the real models already in the Space.

Watch the build at `https://huggingface.co/spaces/Sanuka0523/Cardiac_Monitor_API`, or poll `https://huggingface.co/api/spaces/Sanuka0523/Cardiac_Monitor_API/runtime` until the stage is `RUNNING`. Then check `/api/v1/health`.

**Space secrets** (Settings → Variables and secrets):

| Kind | Names |
|---|---|
| Secrets | `MONGODB_URI`, `JWT_SECRET`, `API_KEY` |
| Variable | `SHARED_DEVICE_IDS` |

`API_KEY` must equal the firmware's `secrets.h` value. Rotating it means updating both and re-flashing the board.

**Atlas setup:**

1. Create an M0 cluster.
2. Add a database user.
3. Under Network Access, add `0.0.0.0/0`, because Hugging Face has no fixed outbound IP.
4. Copy the `mongodb+srv://` URI into `MONGODB_URI`.

### 12.4 GitHub Actions

| Workflow | Trigger | Does |
|---|---|---|
| `firmware-ci.yml` | push/PR to `main` touching `firmware/**` | `pio run -e esp32dev`. Builds with the `secrets.example.h` placeholder. Uploads `firmware.bin` as an artifact. |
| `backend-ci.yml` | tag `v*` | flake8 + `pytest tests/` + Docker build (no push) |
| `flutter-ci.yml` | tag `v*` | analyze, test, `flutter build apk --release` |
| `release.yml` | tag `v*` | APK + firmware `.bin` attached to a GitHub Release, Docker image artifact, HF Space deploy (secret `HF_TOKEN`) |
| `security-scan.yml` | push/PR to `main` + weekly | CodeQL (Python), Bandit, pip-audit, dependency review |

**Make a release:**

```bash
git tag v1.2.0
git push origin v1.2.0
```

---

## 13. Rebuild from scratch: step-by-step

Follow these steps in order. Each step lists how to check it worked before moving on.

### Step 1 — Accounts and tools
- **Accounts:**
  - GitHub
  - Hugging Face (free)
  - MongoDB Atlas (free)
- **Tools:**
  - Git + Git LFS
  - Python 3.11
  - PlatformIO
  - Flutter ≥ 3.38 with the Android SDK
  - `uv` (optional, used by the scripts)
- **Get the code:**
  ```bash
  git clone https://github.com/Sanuka23/cardiac-monitor.git && cd cardiac-monitor
  git lfs install && git lfs pull    # real model files in backend/ml_models (≈124 MB)
  ```
  ✅ `ls -l backend/ml_models` shows ≈123 MB and ≈0.77 MB files, not 134-byte pointers.

### Step 2 — Hardware
1. Build the circuit in Section 5.
2. Flash the ECG bench test and check the AD8232 (Section 14.2):
   ```bash
   pio run -d firmware/tools/ecg_diag -t upload
   ```
   ✅ With no electrodes, both LO pins read "driven HIGH (lead off)".
   ✅ With electrodes on, both read "driven LOW (lead on)" and the plot shows clear heartbeats.

### Step 3 — Database
1. Create an Atlas M0 cluster.
2. Create a database user.
3. Under Network Access, allow `0.0.0.0/0`.
4. Copy the `mongodb+srv://…` URI.

✅ `mongosh "<uri>" --eval 'db.runCommand({ping:1})'` returns `ok: 1`.

### Step 4 — Backend locally
1. Configure:
   ```bash
   cd backend && cp .env.example .env
   # MONGODB_URI=<uri>   JWT_SECRET=$(openssl rand -hex 32)   API_KEY=cm-$(openssl rand -hex 24)
   ```
2. Install and run:
   ```bash
   pip install torch==2.10.0 --index-url https://download.pytorch.org/whl/cpu && pip install -r requirements.txt pytest
   python -m pytest tests/ -q                    # 61 passed
   uvicorn app.main:app --port 7860
   ```

✅ `curl localhost:7860/api/v1/health` returns `"db":"connected"`, and the log shows `[ML] ECGFounder loaded` and `[ML] XGBoost loaded`.

### Step 5 — (Optional) Retrain the models
Run Section 10.7, then copy the two files into `backend/ml_models/` and commit them through LFS.

✅ `ml/models/evaluation_results.npz` reports an ensemble AUC of about 0.91.

### Step 6 — Deploy the API
1. Create a Hugging Face Space: SDK **Docker**, hardware CPU basic.
2. Add the Space **secrets** `MONGODB_URI`, `JWT_SECRET` and `API_KEY` (same values as `.env`).
3. Add the Space **variable** `SHARED_DEVICE_IDS`. Optional; set it to your board's ID after Step 7.
4. Upload `backend/`, either by pushing a `v*` tag (release workflow; needs the repo secret `HF_TOKEN`) or with the manual upload in Section 12.3.
5. If you use a different Space name, update `API_BASE_URL` in `firmware/include/config.h` and the app's default URL in `lib/config/constants.dart`, or set it in the app's Settings.

✅ `https://<space>.hf.space/api/v1/health` returns `connected`, and `/docs` opens.

### Step 7 — Firmware
1. Create the secrets file:
   ```bash
   cp firmware/include/secrets.example.h firmware/include/secrets.h
   # set:  #define API_KEY "<exactly the server's API_KEY>"   (leave WIFI_DEFAULT_* commented out)
   ```
2. Build, flash and open the serial monitor:
   ```bash
   pio run -d firmware -t upload && pio device monitor -b 115200
   ```
3. Note the `Device ID: ESP32_XXXXXX` line.

✅ The serial log shows `BOOT_PROVISIONING` and `Advertising as "CardiacMon" (fast)`.

### Step 8 — App
1. Build and install:
   ```bash
   cd app/cardiac_monitor && flutter pub get && flutter build apk --release
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```
2. Open the app, register an account, and if needed set **Settings → API Server URL**.

✅ Login works and the Dashboard opens.

### Step 9 — Provision and register the board
In the app, go to **Connect Device**, then:
1. Scan and pick `CardiacMon`.
2. **Scan for Networks**, pick a **2.4 GHz** network and enter its password.
3. Tap **Connect Device**.
4. Wait for "Device ready!".
5. Type the device ID from Step 7 and tap **Register & Continue**.

To share the board with every account instead, put its ID (or `*`) in `SHARED_DEVICE_IDS`; registration is then optional.

✅ Serial shows `[WIFI] State: READY`, then `[SEND] HTTP 200` every 10 s.
✅ With electrodes on, the server returns predictions, and the app shows the risk label and the live ECG.

### Step 10 — Verify the whole pipeline
- Run the PTB-XL playback (Section 14.5). ✅ NORM records come out normal/low and MI records come out elevated/high.
- `GET /api/v1/vitals/me/history` (with a JWT) lists your windows with `signal_quality` and `heart_rate_source: "ecg"`.

---

## 14. Testing, diagnostics and demo tools

### 14.1 Serial capture (`firmware/tools/serial_capture.py`)

```bash
~/.platformio/penv/bin/python firmware/tools/serial_capture.py /dev/cu.usbserial-0001 30 out.raw            # reset + 30 s
~/.platformio/penv/bin/python firmware/tools/serial_capture.py /dev/cu.usbserial-0001 20 out.raw --send=5:p  # plotter at 5 s
```

### 14.2 ECG bench test (`firmware/tools/ecg_diag/`)

This sketch streams **raw, unfiltered** 250 Hz samples (`D:v,v,…` lines). Once per second it reports whether each lead-off pin is actively driven or floating. It works this out by toggling the pin's internal pull-up and pull-down: a driven pin keeps its level, a floating pin follows the pull.

```bash
pio run -d firmware/tools/ecg_diag -t upload
~/.platformio/penv/bin/python firmware/tools/serial_capture.py /dev/cu.usbserial-0001 20 ecg.raw
uv run --no-project --python 3.11 --with numpy --with 'scipy==1.14.1' --with matplotlib \
    python firmware/tools/ecg_analyze.py ecg.raw ecg.png        # stats, quality verdict, plot
pio run -d firmware -t upload                                   # restore the main firmware afterwards
```

| Situation | LO+/LO− | ADC | Meaning |
|---|---|---|---|
| No electrodes | driven HIGH | mostly 0, bursts 0–4095 | Normal |
| Electrodes on, good contact | driven LOW | baseline ≈1,800, sharp spikes each beat | **Working** |
| `FLOATING`, ≈100 toggles/s | – | – | AD8232 unpowered or LO wires disconnected |
| Leads on but flat ≈500, no beats | – | flat | OUTPUT wire or electrodes not making contact |
| Rail-to-rail noise with leads on | – | 0–4095 | Mains interference: unplug the charger, check pads |

For a longer recording (demo or validation): attach the electrodes, sit still, and capture for 330 s. A 5.5-minute recording from 2026-10-11 is stored outside git in `ml/data/device_recordings/2026-10-11_wear_5min/`. It is personal health data; do not commit it.

### 14.3 MAX30100 I2C check (`firmware/tools/i2c_scan/`)

Every 2 s it prints the SDA/SCL idle levels with and without the internal pull-ups, then scans the bus at 100 kHz, at 10 kHz, and with SDA/SCL swapped.

| Result | Meaning |
|---|---|
| `0x57` every time | Wiring OK |
| Lines read 0 without internal pull-up | External 3.3 V pull-ups missing |
| Nothing at any speed | Module unpowered, wires not reaching it, or a dead module |
| Found only when swapped | SDA and SCL wires are crossed |
| Comes and goes | Loose connection: solder the headers |

### 14.4 Quick API checks

```bash
API=https://sanuka0523-cardiac-monitor-api.hf.space
curl $API/api/v1/health
TOKEN=$(curl -s -X POST $API/api/v1/auth/login -H 'Content-Type: application/json' \
        -d '{"email":"you@example.com","password":"..."}' | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
curl -H "Authorization: Bearer $TOKEN" $API/api/v1/auth/me
curl -H "Authorization: Bearer $TOKEN" "$API/api/v1/vitals/me/history?limit=5"
curl -H "Authorization: Bearer $TOKEN" "$API/api/v1/predictions/me/latest"
```

### 14.5 Demonstrating detection honestly (playback)

A live wearer cannot produce an abnormal ECG on demand. Detection is therefore demonstrated with **real, labelled hospital ECGs** sent through exactly the same API and model, and always labelled as playback.

```bash
cd backend
API_KEY=<server key> uv run --no-project --python 3.11 --with wfdb --with pandas --with httpx \
  --with 'neurokit2>=0.2.7' --with 'numpy==1.26.4' --with 'scipy==1.14.1' \
  python scripts/playback_ptbxl.py --ptbxl ../ml/data/ptb-xl --api https://sanuka0523-cardiac-monitor-api.hf.space --per-label 5
```

Output from 2026-10-11, on the live API:

```
 ecg_id  truth     HR  quality     risk  label
   4354  NORM    67.6  good       0.145  normal
   6230  MI      63.4  good       0.781  elevated
   6951  NORM    78.9  good       0.254  low
   8473  MI      71.3  good       0.993  high
   8492  NORM    76.5  good       0.193  normal
  13405  MI      70.5  good       0.605  elevated
  12310  NORM    88.2  good       0.294  low
  19877  MI      90.1  good       0.910  high
  18661  NORM    60.6  good       0.347  low
  20079  MI      87.5  good       0.912  high
```

To replay the device recording as a labelled session, use `replay_recording.py` (Section 8.10).

The app cannot yet label playback data. That is why `PLAYBACK_PTBXL` is **not** in `SHARED_DEVICE_IDS`: its heart-attack (MI) windows would appear in users' own history.

### 14.6 Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `/health` returns 503 "space is in error" | HF Space crashed or was evicted | Space page → **Restart** (or factory rebuild). Logs are under the Space's "Logs" tab. |
| `/health` returns `"db":"disconnected"` | Atlas cluster paused (60 days idle) or wrong URI | Resume the cluster in Atlas, then restart the Space |
| Board never gets past "Waiting for BLE provisioning" | No WiFi saved | Provision from the app (Step 9) |
| `Connection timeout` ×3, then provisioning | Wrong password, 5 GHz-only network, or out of range | Re-provision with a **2.4 GHz** network. Check RSSI (better than about −75 dBm is good). |
| Stuck after `Starting NTP sync...` | NTP blocked on the network | Use another network. The firmware has no NTP timeout. |
| `[SEND] HTTP 401` | Firmware `API_KEY` ≠ server `API_KEY` | Fix `secrets.h` and re-flash, or fix the Space secret |
| `[SEND] HTTP 422` | Malformed payload (e.g. <100 samples) | Check the firmware window size |
| Uploads OK but never a `Risk` line | Leads off, or the window is classed `poor` | Check `signal_quality` in `/vitals/me/history`. Attach electrodes, sit still, unplug the charger. |
| App can't find the board | Board not advertising, or phone BLE/location off | Check serial shows `Advertising`. Enable Bluetooth and Location. Only one phone can connect at a time. |
| App connects on Android but not iPhone | `requestMtu` is Android-only (Section 15) | Use an Android phone |
| App status shows "Credentials cleared" during setup | App/firmware status-code mismatch | Cosmetic. Wait for "Device ready!". |
| HR/SpO2 cards show `--` | MAX30100 disabled | Expected. Heart rate is in History (ECG-derived). |
| History "30d" says "Could not load data" | App requests `limit=1000`; the API max is 500 | Use 24h/7d (Section 15) |
| ECG has noisy rail-to-rail bursts | Mains interference or dry pads | Power bank, fresh pads, keep away from cables |
| MAX30100 init FAILED / Error 263 | Pull-ups or a loose connection | Section 5.5 and 14.3 |

---

## 15. Known issues and limitations

Ordered by impact on a demo. **Bold** items affect what people will see.

### App
1. **iOS cannot connect.** `BleService.connect()` calls `requestMtu(128)`, which flutter_blue_plus only supports on Android, so the call throws on iOS. Use Android, or guard the call with `Platform.isAndroid`.
2. **Provisioning status codes differ from the firmware.** The app treats `0x02` as NTP and `0x04` as cleared; the firmware sends `0x04` for NTP and `0x06` for cleared. As a result, "Credentials cleared" flashes during NTP sync.
3. **HR and SpO2 cards are BLE-only and show `--`** while the MAX30100 is disabled. The server's ECG-derived HR is not shown on the Dashboard. A small firmware change could forward it over BLE CC01 (not done).
4. **History has three problems:**
   - The 30d tab always fails, because it sends `limit=1000` and the API maximum is 500.
   - 24h and 7d fetch only the newest 200 or 500 windows (≈33 or ≈83 minutes of uploads) and then filter by time in the app.
5. **Saving the profile wipes it.**
   - The app sends `{"health_profile": {...}}`, but the API expects a flat body.
   - The field names also differ: the app uses `diabetic`/`hypertensive`/`smoker`, the API uses `is_diabetic`/`is_hypertensive`/`is_smoker`.
6. **Timestamps are read as local time.** The API sends UTC without a `Z`, so charts and times are shifted by the phone's UTC offset (+5:30 in Sri Lanka).
7. **The ECG chart can miss heartbeats.**
   - It keeps every Nth sample (about 200 points), which can drop QRS peaks.
   - It also draws live BLE ECG (250 Hz) with a 100 Hz time axis.

   Fixes for 6 and 7 are in `git stash@{0}`.
8. **Login and registration error messages can be lost on first launch.** Separately, launching offline logs the user out, because any network error deletes the token.
9. **The Dashboard uses only the first device ID for its ECG fallback.** With shared devices, that is the real board.
10. Other app gaps:
    - BLE errors are never shown to the user.
    - The scan state can stay on "Scanning…" after the 10 s timeout.
    - There is no auto-reconnect.
    - The device ID must be typed by hand.
    - There is no "forget WiFi" button.
    - The release build uses the debug signing key.

### Firmware
11. **The serial `b` command and BLE CLEAR (`0x02`) wipe NVS but keep the in-memory WiFi credentials.** The board stays online until it reboots, then starts in provisioning mode.
12. **Open (password-less) networks break after a reboot.** An empty stored password is treated as "no credentials", so the board neither connects nor enters provisioning. Use a secured network.
13. **WiFi failure handling is slow:**
    - A wrong password is only detected through 3 × 15 s timeouts (≈48 s).
    - There is no NTP timeout.
    - After 3 failures the board enters provisioning but keeps retrying the old network.
14. **No offline buffering.** Windows are discarded unless the board is online. Only 2 windows can wait in the upload queue.
15. **Each window starts with a ≈1.5 s settling transient,** because the filters reset at every window and on every lead-off sample. The lead-off flag only reflects the state at the window's end.
16. **ECG timing can drift.** Samples are timed with `millis()` and lost samples are not recovered; long blocking operations reduce the effective rate, but the payload still says 250 Hz.
17. **The device status byte is uninformative.** Bit 0 is effectively always 1, and bit 3 duplicates bit 1.
18. **The vendored MAX30100 library is not compiled** (Section 6.10). The MAX30100 path also has an unbounded SpO2 lookup index, which explains odd 37%/48% readings seen in February.

### Backend
19. **An owned device whose owner saved a profile without height/weight loses its XGBoost score** (`TypeError` on `None/100`). The prediction falls back to "ECGFounder only" and the ECG-derived HR is not filled in. Shared or unowned devices are not affected.
20. **Profile and 24 h/7 d history features are computed but never used by the model.** The baselines also average HR = 0 from sensorless uploads.
21. **NeuroKit fallback values can masquerade as data.** When NeuroKit finds fewer than 3 R-peaks, the fallback `mean_hr_ecg = 75` could be stored as an ECG-derived HR.
22. The `entropy` feature is randomised (no seed), so the same window can score slightly differently.
23. **Failed model loads are not retried.** `_models_loaded` is set even when loading fails. With LFS pointers instead of real models, predictions silently never appear.
24. **`/health` always returns 200,** even when the database is down. Platform health checks therefore don't notice.
25. Request handling limits:
    - Model inference runs synchronously inside an async route (single worker).
    - One global device API key, compared with a non-constant-time check.
    - Passwords over 72 bytes cause a 500 (bcrypt 5).
    - A missing `X-API-Key` header returns 422, not 401.
26. **Outdated docs:**
    - `backend/README.md`: says login is form data, the profile body is wrapped, and there are "14 features"; it also lists wrong file names.
    - `backend/ml_src/README.md`: says 1000 samples, band-pass, 128-dimensional embedding.
    - `firmware/README.md`: wrong status codes, 100 Hz, nonexistent files.
    - `docs/README.md`: pre-WiFi.

    This guide supersedes them.

### ML and science
27. **Not clinically validated.** The model was trained and tested on PTB-XL hospital recordings. On this device it was checked with **one healthy adult (5.5 minutes)** plus PTB-XL playback. That is a sanity check, not a validation study.
28. **"Abnormal" is broad.** It means any of MI, STTC (ST/T change), CD (conduction disturbance) or HYP (hypertrophy), not heart attack specifically.
29. **Label mapping differs from the official PTB-XL classes** (Section 10.2), and the Youden threshold is not used.
30. **XGBoost train/serve skew:** z-scored 100 Hz in training versus raw counts at 250 Hz in serving (Section 10.8).

---

## 16. Security notes

- **Secrets are never committed:**
  - `firmware/include/secrets.h` (API key) and `backend/.env` are git-ignored.
  - Production values live in Hugging Face Space secrets.
- **Git history contains old secrets.** An earlier API key and a WiFi password were once committed in `config.h`. The API key was rotated in October 2026 and the old key is now rejected. The WiFi password remains in history, so change it on that network.
- **Rotate the API key** by changing the Space secret, updating `secrets.h`, re-flashing the board, and passing the new key to the scripts via `API_KEY=…`.
- **Device → API traffic:** HTTPS, but the firmware does not verify the server certificate (`setInsecure()`), so a man-in-the-middle could read the API key. Pinning the HF certificate chain would fix this.
- **BLE has no pairing or encryption.** Anyone in range can read vitals or overwrite the WiFi credentials during provisioning.
- **API:**
  - CORS allows `*`.
  - JWTs last 24 h with no revocation.
  - One shared device key for all devices.
- **Sensitive data handling:**
  - The app's debug logs print the first 20 characters of the JWT.
  - Personal ECG recordings live only in the git-ignored `ml/data/device_recordings/`.
- **Never paste tokens into chat or commit them.** Revoke any Hugging Face token that was shared.

---

## 17. Validation evidence

| Check | Result |
|---|---|
| Model on the PTB-XL held-out test fold (2,037 ECGs) | ECGFounder AUC **0.917**, XGBoost 0.883, ensemble **0.915**. At 0.5: precision 0.90, sensitivity 0.79, specificity 0.90. |
| Quality gate on PTB-XL test fold | NORM 99.7% pass, MI 96–97%, AF 97%. Synthetic noise 100% rejected. Device no-electrode windows 55/57 rejected (the other 2 are a test script's simulated ECG). |
| **Real device recording**, 2026-10-11, healthy adult at rest, 5.5 min, 250 Hz | Leads on for all 329 s. HR 67–76 bpm (ECG-derived). With the firmware's 0.5 scaling: **32/32 windows `good`**, risk **22 low + 10 normal**, maximum 0.40. Never elevated or high. Without the scaling, 20/32 were rejected as saturated. |
| **PTB-XL playback through the live API**, 2026-10-11 | 5/5 NORM came out normal or low. 5/5 MI came out elevated or high (records in Section 14.5). |
| Library-version consistency | 10 stored February predictions were replayed with the pinned versions; scores matched within 0.008. |
| End-to-end live device | 2026-10-11: board on 2.4 GHz WiFi, uploading 2,500-sample windows every 10 s, HTTP 200, stored as `lead_off` when no electrodes were attached. |

These results support "the pipeline works and does not raise false alarms on one healthy wearer". They do not establish diagnostic accuracy.

---

## 18. Project history

| Date | Milestone |
|---|---|
| 2026-02-22 | ESP32 + MAX30100 monitor; AD8232 ECG added; FastAPI backend ("Phase 1") |
| 2026-02-23 | ML pipeline (ECGFounder + XGBoost); WiFi upload; BLE provisioning; Flutter app; CI/CD; HF Spaces deploy; 250 Hz ECG + digital filters. Releases v0.0.1 and v1.0.1. |
| 2026-02-24 – 02-27 | Hardware tests (serial log `firmware/monitor_20260224_120724.log`). The ECG leads were off in most sessions, which later showed the need for a quality gate. |
| 2026-03-10 | HF Space crashed (runtime error, no logs). Atlas cluster later auto-paused. |
| 2026-10-09 | **PR #1** — startup fix for an unreachable DB, ECG signal-quality gate, pinned dependencies, unbuffered logs, PTB-XL playback, pytest in CI, 250 Hz stack-overflow fix, secrets moved to `secrets.h` and the API key rotated |
| 2026-10-10 | **PR #2** — ECG-only firmware (MAX30100 disabled), 0.5 output scaling, ECG-derived heart rate, `source` labels, recording replay. **PR #3** — shared devices for any account; replay with original timestamps. **PR #4** — BLE-first WiFi provisioning by default. |
| 2026-10-11 | 5.5-minute real ECG recording and evaluation; board provisioned and uploading live |

---

## 19. Glossary

| Term | Meaning |
|---|---|
| ECG | Electrocardiogram: the heart's electrical activity over time |
| Lead II | A standard ECG view (right arm → left leg); the single lead used here |
| AD8232 | Analog Devices single-lead ECG front-end IC (amplifier and filters), with lead-off detection |
| P / QRS / T | ECG waves: atrial depolarisation, ventricular depolarisation (sharp spike; R = its peak), and repolarisation |
| R-peak, RR interval | Top of the QRS spike; the time between consecutive R-peaks (heart rate = 60 / RR) |
| PTB-XL | Public dataset of 21,799 clinical 12-lead ECGs with cardiologist labels |
| NORM / MI / STTC / CD / HYP | PTB-XL superclasses: normal, myocardial infarction (heart attack), ST/T change, conduction disturbance, hypertrophy |
| ECGFounder | Large pretrained ECG foundation model (Peking University), fine-tuned here |
| XGBoost | Gradient-boosted decision trees |
| AUC-ROC | Area under the ROC curve: 0.5 = chance, 1.0 = perfect ranking |
| BLE, GATT | Bluetooth Low Energy; its service/characteristic data model |
| MTU | Maximum BLE packet size negotiated between phone and board |
| Notify | BLE push from the board to the phone |
| NVS | ESP32 non-volatile storage (survives power-off and re-flashing) |
| NTP | Network time protocol; gives the board real UTC time for timestamps |
| JWT | Signed login token the app sends as `Authorization: Bearer` |
| Git LFS | Git Large File Storage, used for the model files |
| HF Space | Hugging Face hosting for the Docker API |
| Signal-quality gate | Server check that rejects noisy or non-ECG windows before the model runs |
| Playback | Sending recorded (not live) ECG through the API, always labelled as such |

---

## Appendix A — Where to change things

| To change… | Edit |
|---|---|
| API URL the board uploads to | `firmware/include/config.h` → `API_BASE_URL` |
| Device API key | `firmware/include/secrets.h` and the Space secret `API_KEY` |
| ECG rate, window, scaling | `firmware/include/config.h` (`ECG_*`), and keep `backend/scripts/firmware_ecg.py` in sync |
| Turn the MAX30100 back on | `config.h` → `MAX30100_ENABLED 1` (fix the wiring first) |
| BLE name or UUIDs | `config.h` *and* `app/cardiac_monitor/lib/config/constants.dart` |
| Which devices every account sees | Space variable `SHARED_DEVICE_IDS` (then restart the Space) |
| Risk label thresholds or ensemble weights | `backend/app/services/ml_service.py` |
| Quality-gate thresholds | `backend/app/services/signal_quality.py` (re-run `tests/test_signal_quality.py`) |
| App default API URL | `app/cardiac_monitor/lib/config/constants.dart` → `defaultApiBaseUrl` (or Settings in the app) |
