#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

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
#define MAX_INIT_RETRIES        5
#define INIT_RETRY_DELAY_MS     1000
#define IR_LED_CURRENT          MAX30100_LED_CURR_7_6MA
#define STALL_TIMEOUT_MS        10000
#define HR_REPORT_PERIOD_MS     1000

// ============================================================
//  ECG SAMPLING CONFIG
// ============================================================
#define ECG_SAMPLE_RATE_HZ      100
#define ECG_SAMPLE_PERIOD_MS    (1000 / ECG_SAMPLE_RATE_HZ)     // 10ms
#define ECG_WINDOW_MS           10000                            // 10 seconds
#define ECG_SAMPLES_PER_WINDOW  (ECG_SAMPLE_RATE_HZ * ECG_WINDOW_MS / 1000)  // 1000
#define ECG_TEXT_DIVISOR         10      // Text mode: print every 10th sample (10Hz)
#define MAX_BEATS_PER_WINDOW    30      // Max ~180bpm for 10s

// ============================================================
//  WIFI CONFIGURATION (hardcoded for Phase 3)
// ============================================================
#define WIFI_SSID               "YOUR_WIFI_SSID"
#define WIFI_PASSWORD           "YOUR_WIFI_PASSWORD"
#define WIFI_CONNECT_TIMEOUT_MS 15000
#define WIFI_RECONNECT_BASE_MS  1000
#define WIFI_RECONNECT_MAX_MS   30000

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
#define API_BASE_URL            "https://your-server.com"
#define API_VITALS_PATH         "/api/v1/vitals"
#define API_KEY                 "esp32-cardiac-device-key-2026"
#define API_TIMEOUT_MS          10000
#define API_MAX_RETRIES         2

#endif // CONFIG_H
