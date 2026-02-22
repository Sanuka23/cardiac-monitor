#include "wifi_manager.h"
#include "config.h"

#if WIFI_MODE_ENABLED
#include <WiFi.h>
#include <time.h>
#endif

static WifiState _state = WIFI_STATE_DISCONNECTED;
static char _deviceId[20] = {0};
static uint32_t _connectStartMs = 0;
static uint32_t _lastReconnectAttemptMs = 0;
static uint32_t _reconnectDelayMs = WIFI_RECONNECT_BASE_MS;
static bool _ntpSynced = false;

// --- Derive device ID from MAC address ---
static void deriveDeviceId() {
#if WIFI_MODE_ENABLED
    uint8_t mac[6];
    WiFi.macAddress(mac);
    snprintf(_deviceId, sizeof(_deviceId), "ESP32_%02X%02X%02X",
             mac[3], mac[4], mac[5]);
#else
    snprintf(_deviceId, sizeof(_deviceId), "ESP32_DEBUG");
#endif
    Serial.printf("[WIFI] Device ID: %s\n", _deviceId);
}

// --- Start NTP sync ---
static void startNtpSync() {
#if WIFI_MODE_ENABLED
    Serial.println("[WIFI] Starting NTP sync...");
    configTime(NTP_GMT_OFFSET_SEC, NTP_DAYLIGHT_OFFSET_SEC,
               NTP_SERVER_1, NTP_SERVER_2);
    _state = WIFI_STATE_NTP_SYNCING;
#endif
}

// --- Check NTP sync status ---
static bool checkNtpSynced() {
#if WIFI_MODE_ENABLED
    struct tm timeinfo;
    if (getLocalTime(&timeinfo, 0)) {
        if (timeinfo.tm_year + 1900 >= 2024) {
            if (!_ntpSynced) {
                Serial.printf("[WIFI] NTP synced: %04d-%02d-%02d %02d:%02d:%02d UTC\n",
                    timeinfo.tm_year + 1900, timeinfo.tm_mon + 1, timeinfo.tm_mday,
                    timeinfo.tm_hour, timeinfo.tm_min, timeinfo.tm_sec);
                _ntpSynced = true;
            }
            return true;
        }
    }
#endif
    return false;
}

void wifiInit() {
    deriveDeviceId();

#if WIFI_MODE_ENABLED
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(false);

    Serial.printf("[WIFI] Connecting to %s...\n", WIFI_SSID);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    _connectStartMs = millis();
    _state = WIFI_STATE_CONNECTING;
#endif
}

WifiState wifiUpdate() {
#if !WIFI_MODE_ENABLED
    return _state;
#else
    switch (_state) {
        case WIFI_STATE_CONNECTING:
            if (WiFi.status() == WL_CONNECTED) {
                Serial.printf("[WIFI] Connected! IP: %s, RSSI: %d dBm\n",
                    WiFi.localIP().toString().c_str(), WiFi.RSSI());
                _reconnectDelayMs = WIFI_RECONNECT_BASE_MS;
                startNtpSync();
            } else if (millis() - _connectStartMs > WIFI_CONNECT_TIMEOUT_MS) {
                Serial.println("[WIFI] Connection timeout.");
                WiFi.disconnect();
                _state = WIFI_STATE_DISCONNECTED;
                _lastReconnectAttemptMs = millis();
            }
            break;

        case WIFI_STATE_NTP_SYNCING:
            if (WiFi.status() != WL_CONNECTED) {
                _state = WIFI_STATE_DISCONNECTED;
                _ntpSynced = false;
                break;
            }
            if (checkNtpSynced()) {
                _state = WIFI_STATE_READY;
            }
            break;

        case WIFI_STATE_CONNECTED:
            if (WiFi.status() != WL_CONNECTED) {
                _state = WIFI_STATE_DISCONNECTED;
            }
            break;

        case WIFI_STATE_READY:
            if (WiFi.status() != WL_CONNECTED) {
                Serial.println("[WIFI] Connection lost.");
                _state = WIFI_STATE_DISCONNECTED;
                _ntpSynced = false;
            }
            break;

        case WIFI_STATE_DISCONNECTED:
            if (millis() - _lastReconnectAttemptMs >= _reconnectDelayMs) {
                Serial.printf("[WIFI] Reconnecting (backoff %lums)...\n", _reconnectDelayMs);
                WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
                _connectStartMs = millis();
                _state = WIFI_STATE_CONNECTING;
                _reconnectDelayMs = min(_reconnectDelayMs * 2, (uint32_t)WIFI_RECONNECT_MAX_MS);
            }
            break;
    }

    return _state;
#endif
}

WifiState   wifiGetState()      { return _state; }
bool        wifiIsReady()       { return _state == WIFI_STATE_READY; }
const char* wifiGetDeviceId()   { return _deviceId; }

int wifiGetRSSI() {
#if WIFI_MODE_ENABLED
    return WiFi.RSSI();
#else
    return 0;
#endif
}

time_t wifiGetTimestamp() {
    if (!_ntpSynced) return 0;
    time_t now;
    time(&now);
    return now;
}

void wifiReconnect() {
#if WIFI_MODE_ENABLED
    WiFi.disconnect();
    _state = WIFI_STATE_DISCONNECTED;
    _lastReconnectAttemptMs = 0;
    _reconnectDelayMs = WIFI_RECONNECT_BASE_MS;
#endif
}
