#ifndef SECRETS_H
#define SECRETS_H

// Template for include/secrets.h (git-ignored). Copy this file to secrets.h
// and fill in real values. Builds without secrets.h (e.g. CI) use these placeholders.

// Optional fallback WiFi, used only when no network was provisioned over BLE.
// Leave undefined so the board starts in BLE provisioning mode and the app sets WiFi.
// #define WIFI_DEFAULT_SSID       "your-ssid"
// #define WIFI_DEFAULT_PASS       "your-password"

// Must match the backend's API_KEY secret
#define API_KEY                 "change-me"

#endif // SECRETS_H
