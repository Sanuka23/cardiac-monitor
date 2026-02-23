#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include <Arduino.h>

enum WifiState {
    WIFI_STATE_DISCONNECTED,
    WIFI_STATE_CONNECTING,
    WIFI_STATE_CONNECTED,
    WIFI_STATE_NTP_SYNCING,
    WIFI_STATE_READY            // Connected + NTP synced
};

void        wifiInit();
WifiState   wifiUpdate();
WifiState   wifiGetState();
bool        wifiIsReady();
const char* wifiGetDeviceId();
time_t      wifiGetTimestamp();
int         wifiGetRSSI();
void        wifiReconnect();

// Phase 4: Runtime credential management
void        wifiSetCredentials(const char* ssid, const char* password);
bool        wifiHasCredentials();
uint8_t     wifiGetBootFailCount();
void        wifiResetBootFailCount();

#endif // WIFI_MANAGER_H
