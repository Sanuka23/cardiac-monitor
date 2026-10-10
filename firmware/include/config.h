#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// WiFi fallback credentials + device API key. secrets.h is git-ignored;
// builds without it (e.g. CI) use the placeholder template.
#if __has_include("secrets.h")
#include "secrets.h"
#else
#include "secrets.example.h"
#endif

// ============================================================
//  BUILD MODE
// ============================================================
//   1 = WiFi operational (connect WiFi, POST to API)
//   0 = Serial debug only (original behavior)
#ifndef WIFI_MODE_ENABLED
#define WIFI_MODE_ENABLED       1
#endif

// ============================================================
//  PIN ASSIGNMENTS
// ============================================================
// MAX30100 (I2C)
#define PIN_I2C_SDA             21
#define PIN_I2C_SCL             22
#define PIN_MAX30100_INT        19

// AD8232 ECG
#define PIN_ECG_OUTPUT          34      // ADC1_CH6, input-only
#define PIN_ECG_LO_PLUS         32      // Lead-off detection (+)
#define PIN_ECG_LO_MINUS        33      // Lead-off detection (-)

// Indicators
#define PIN_BEAT_LED            2       // Onboard LED

// ============================================================
//  MAX30100 SENSOR CONFIG
// ============================================================
//   0 = MAX30100 not used: no I2C, HR/SpO2 sent as 0 and the server
//       derives HR from the ECG. 1 = read HR/SpO2 from the MAX30100.
#ifndef MAX30100_ENABLED
#define MAX30100_ENABLED        0
#endif

#define MAX_INIT_RETRIES        5
#define INIT_RETRY_DELAY_MS     1000
#define IR_LED_CURRENT          MAX30100_LED_CURR_27_1MA
#define STALL_TIMEOUT_MS        10000
#define HR_REPORT_PERIOD_MS     1000

// ============================================================
//  ECG SAMPLING CONFIG
// ============================================================
#define ECG_SAMPLE_RATE_HZ      250
#define ECG_SAMPLE_PERIOD_MS    (1000 / ECG_SAMPLE_RATE_HZ)     // 4ms
#define ECG_WINDOW_MS           10000                            // 10 seconds
#define ECG_SAMPLES_PER_WINDOW  (ECG_SAMPLE_RATE_HZ * ECG_WINDOW_MS / 1000)  // 2500
#define ECG_TEXT_DIVISOR         25      // Text mode: print every 25th sample (10Hz)
#define ECG_OVERSAMPLE_COUNT    4       // Read ADC 4x and average per sample
#define ECG_OUTPUT_SCALE        0.5f    // Scale filtered ECG before re-centring at 2048 so
                                        // R-peaks (AD8232 gain ~1100) stay below 4095
#define MAX_BEATS_PER_WINDOW    30      // Max ~180bpm for 10s

// ============================================================
//  WIFI CONFIGURATION (Phase 4: credentials from NVS via BLE)
// ============================================================
// Optional fallback WiFi (WIFI_DEFAULT_SSID/PASS) can be set in secrets.h; without it
// the board waits for WiFi provisioning from the app over BLE

#define WIFI_CONNECT_TIMEOUT_MS 15000
#define WIFI_RECONNECT_BASE_MS  1000
#define WIFI_RECONNECT_MAX_MS   30000
#define WIFI_BOOT_MAX_RETRIES   3       // Fail count before entering provisioning

// ============================================================
//  NVS STORAGE CONFIGURATION
// ============================================================
#define NVS_NAMESPACE           "cardiac"
#define NVS_KEY_SSID            "wifi_ssid"
#define NVS_KEY_PASSWORD        "wifi_pass"

// ============================================================
//  NTP CONFIGURATION
// ============================================================
#define NTP_SERVER_1            "pool.ntp.org"
#define NTP_SERVER_2            "time.nist.gov"
#define NTP_GMT_OFFSET_SEC      0
#define NTP_DAYLIGHT_OFFSET_SEC 0

// ============================================================
//  API CONFIGURATION
// ============================================================
#define API_BASE_URL            "https://sanuka0523-cardiac-monitor-api.hf.space"
#define API_VITALS_PATH         "/api/v1/vitals"
// API_KEY is in secrets.h
#define API_TIMEOUT_MS          10000
#define API_MAX_RETRIES         2

// Background data sender task (FreeRTOS)
#define DATA_SEND_TASK_STACK    12288   // 12KB stack for HTTPS + JSON + TLS
#define DATA_SEND_TASK_PRIORITY 1       // Low priority (sensor loop is higher)
#define DATA_SEND_TASK_CORE     0       // Core 0 (Arduino loop runs on Core 1)
#define DATA_SEND_QUEUE_DEPTH   2       // Buffer up to 2 windows

// ============================================================
//  BLE CONFIGURATION
// ============================================================
#define BLE_DEVICE_NAME         "CardiacMon"

// WiFi Provisioning Service
#define BLE_PROV_SERVICE_UUID   "0000FF00-1234-5678-9ABC-DEF012345678"
#define BLE_PROV_SSID_UUID      "0000FF01-1234-5678-9ABC-DEF012345678"
#define BLE_PROV_PASS_UUID      "0000FF02-1234-5678-9ABC-DEF012345678"
#define BLE_PROV_CMD_UUID       "0000FF03-1234-5678-9ABC-DEF012345678"
#define BLE_PROV_STATUS_UUID    "0000FF04-1234-5678-9ABC-DEF012345678"
#define BLE_PROV_SCAN_RESULT_UUID "0000FF05-1234-5678-9ABC-DEF012345678"

// Cardiac Monitor Service
#define BLE_CARDIAC_SERVICE_UUID "0000CC00-1234-5678-9ABC-DEF012345678"
#define BLE_CARDIAC_HR_UUID      "0000CC01-1234-5678-9ABC-DEF012345678"
#define BLE_CARDIAC_SPO2_UUID    "0000CC02-1234-5678-9ABC-DEF012345678"
#define BLE_CARDIAC_RISK_UUID    "0000CC03-1234-5678-9ABC-DEF012345678"
#define BLE_CARDIAC_LABEL_UUID   "0000CC04-1234-5678-9ABC-DEF012345678"
#define BLE_CARDIAC_STATUS_UUID  "0000CC05-1234-5678-9ABC-DEF012345678"
#define BLE_CARDIAC_ECG_UUID     "0000CC06-1234-5678-9ABC-DEF012345678"

// BLE Provisioning commands (written to CMD characteristic)
#define BLE_CMD_CONNECT         0x01
#define BLE_CMD_CLEAR_CREDS     0x02
#define BLE_CMD_WIFI_SCAN       0x03

// BLE Provisioning status codes (read/notified from STATUS characteristic)
#define BLE_STATUS_IDLE         0x00
#define BLE_STATUS_CONNECTING   0x01
#define BLE_STATUS_WIFI_OK      0x02
#define BLE_STATUS_WIFI_FAIL    0x03
#define BLE_STATUS_NTP_SYNC     0x04
#define BLE_STATUS_READY        0x05
#define BLE_STATUS_CLEARED      0x06

// BLE Advertising intervals (in 0.625ms units per BLE spec)
#define BLE_ADV_FAST_MIN        160     // 100ms (provisioning mode)
#define BLE_ADV_FAST_MAX        240     // 150ms
#define BLE_ADV_SLOW_MIN        1600    // 1000ms (operational mode)
#define BLE_ADV_SLOW_MAX        1600    // 1000ms

// BLE Vitals notification interval
#define BLE_VITALS_NOTIFY_MS    1000

// BLE ECG streaming
#define ECG_BLE_NOTIFY_MS        200     // Send ECG batch every 200ms
#define ECG_BLE_BATCH_MAX        60      // Max samples per notification (60*2=120 < 123 MTU)

// WiFi Scan Configuration
#define WIFI_SCAN_TIMEOUT_MS        10000
#define WIFI_SCAN_NOTIFY_INTERVAL_MS 30
#define WIFI_SCAN_MAX_RESULTS       20

#endif // CONFIG_H
