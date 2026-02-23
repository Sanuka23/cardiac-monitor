#ifndef BLE_PROVISIONER_H
#define BLE_PROVISIONER_H

#include <Arduino.h>

// Boot mode determined by NVS credential check
enum BleBootMode {
    BOOT_PROVISIONING,      // No stored credentials, BLE advertising for provisioning
    BOOT_WIFI               // Stored credentials found, try WiFi connect
};

// Initialize NimBLE, create GATT services, check NVS for stored credentials.
// Returns BOOT_WIFI if credentials exist, BOOT_PROVISIONING otherwise.
BleBootMode bleInit();

// Process queued BLE events (non-blocking, call from loop).
void        bleUpdate();

// Force re-enter provisioning mode (fast advertising, LED blink).
void        bleEnterProvisioning();

// Switch to slow advertising after WiFi connects.
void        bleSetOperationalMode();

// NVS credential access
bool        bleHasStoredCredentials();
bool        bleGetStoredSSID(char* buf, size_t bufLen);
bool        bleGetStoredPassword(char* buf, size_t bufLen);
bool        bleSaveCredentials(const char* ssid, const char* password);
bool        bleClearCredentials();

// Vitals notifications (called from main loop)
void        bleNotifyHeartRate(float hr);
void        bleNotifySpO2(uint8_t spo2);
void        bleNotifyRisk(float score, const char* label);
void        bleNotifyDeviceStatus(uint8_t statusBits);

// Update provisioning status characteristic
void        bleSetProvisioningStatus(uint8_t status);

// WiFi scan processing (called from main loop)
void        bleProcessWifiScan();

// State queries
bool        bleIsClientConnected();
bool        bleIsProvisioning();

#endif // BLE_PROVISIONER_H
