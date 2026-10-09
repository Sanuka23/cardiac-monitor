#ifndef SECRETS_H
#define SECRETS_H

// Template for include/secrets.h (git-ignored). Copy this file to secrets.h
// and fill in real values. Builds without secrets.h (e.g. CI) use these placeholders.

// Fallback WiFi credentials for testing (used when NVS is empty)
#define WIFI_DEFAULT_SSID       "your-ssid"
#define WIFI_DEFAULT_PASS       "your-password"

// Must match the backend's API_KEY secret
#define API_KEY                 "change-me"

#endif // SECRETS_H
