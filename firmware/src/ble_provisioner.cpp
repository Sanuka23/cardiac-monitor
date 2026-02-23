#include "ble_provisioner.h"
#include "config.h"
#include "wifi_manager.h"

#include <NimBLEDevice.h>
#include <Preferences.h>

#if WIFI_MODE_ENABLED
#include <WiFi.h>
#endif

// ============================================================
//  Event Ring Buffer (single-producer single-consumer, ISR-safe)
// ============================================================
enum BleEventType {
    BLE_EVT_NONE = 0,
    BLE_EVT_CMD_CONNECT,
    BLE_EVT_CMD_CLEAR,
    BLE_EVT_CMD_WIFI_SCAN,
    BLE_EVT_CLIENT_CONNECTED,
    BLE_EVT_CLIENT_DISCONNECTED
};

#define BLE_EVT_QUEUE_SIZE 8
static volatile BleEventType _evtQueue[BLE_EVT_QUEUE_SIZE];
static volatile uint8_t _evtHead = 0;
static volatile uint8_t _evtTail = 0;

static void evtPush(BleEventType evt) {
    uint8_t next = (_evtHead + 1) % BLE_EVT_QUEUE_SIZE;
    if (next != _evtTail) {
        _evtQueue[_evtHead] = evt;
        _evtHead = next;
    }
}

static BleEventType evtPoll() {
    if (_evtTail == _evtHead) return BLE_EVT_NONE;
    BleEventType evt = _evtQueue[_evtTail];
    _evtTail = (_evtTail + 1) % BLE_EVT_QUEUE_SIZE;
    return evt;
}

// ============================================================
//  Internal State
// ============================================================
static char _stagedSSID[33] = {0};
static char _stagedPass[64] = {0};

static bool _provisioning = false;
static bool _clientConnected = false;
static NimBLEServer* _pServer = nullptr;

// Characteristic pointers for notifications
static NimBLECharacteristic* _pProvStatusChar = nullptr;
static NimBLECharacteristic* _pScanResultChar = nullptr;
static NimBLECharacteristic* _pHrChar = nullptr;
static NimBLECharacteristic* _pSpo2Char = nullptr;
static NimBLECharacteristic* _pRiskChar = nullptr;
static NimBLECharacteristic* _pLabelChar = nullptr;
static NimBLECharacteristic* _pDevStatusChar = nullptr;

// WiFi scan state machine
enum WifiScanState { WSCAN_IDLE, WSCAN_RUNNING, WSCAN_SENDING };
static WifiScanState _wScanState = WSCAN_IDLE;
static uint32_t _wScanStartMs = 0;
static int16_t _wScanTotal = 0;
static int16_t _wScanIdx = 0;
static uint32_t _wScanLastNotifyMs = 0;

static Preferences _prefs;

// ============================================================
//  NimBLE Callbacks (run in NimBLE FreeRTOS task — keep fast)
// ============================================================
class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
        _clientConnected = true;
        evtPush(BLE_EVT_CLIENT_CONNECTED);
        Serial.printf("[BLE] Client connected: %s\n",
                      connInfo.getAddress().toString().c_str());
    }

    void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
        _clientConnected = false;
        evtPush(BLE_EVT_CLIENT_DISCONNECTED);
        Serial.printf("[BLE] Client disconnected (reason=%d)\n", reason);
        NimBLEDevice::getAdvertising()->start();
    }
};

class ProvCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
        NimBLEUUID uuid = pChar->getUUID();
        std::string value = pChar->getValue();

        if (uuid == NimBLEUUID(BLE_PROV_SSID_UUID)) {
            size_t len = value.length();
            if (len > sizeof(_stagedSSID) - 1) len = sizeof(_stagedSSID) - 1;
            memcpy(_stagedSSID, value.c_str(), len);
            _stagedSSID[len] = '\0';
            Serial.printf("[BLE] SSID received: %s\n", _stagedSSID);

        } else if (uuid == NimBLEUUID(BLE_PROV_PASS_UUID)) {
            size_t len = value.length();
            if (len > sizeof(_stagedPass) - 1) len = sizeof(_stagedPass) - 1;
            memcpy(_stagedPass, value.c_str(), len);
            _stagedPass[len] = '\0';
            Serial.println("[BLE] Password received");

        } else if (uuid == NimBLEUUID(BLE_PROV_CMD_UUID)) {
            if (value.length() > 0) {
                uint8_t cmd = (uint8_t)value[0];
                if (cmd == BLE_CMD_CONNECT) {
                    evtPush(BLE_EVT_CMD_CONNECT);
                } else if (cmd == BLE_CMD_CLEAR_CREDS) {
                    evtPush(BLE_EVT_CMD_CLEAR);
                } else if (cmd == BLE_CMD_WIFI_SCAN) {
                    evtPush(BLE_EVT_CMD_WIFI_SCAN);
                }
            }
        }
    }
};

static ServerCallbacks _serverCb;
static ProvCallbacks   _provCb;

// ============================================================
//  NVS Functions
// ============================================================
bool bleHasStoredCredentials() {
    _prefs.begin(NVS_NAMESPACE, true);
    String ssid = _prefs.getString(NVS_KEY_SSID, "");
    _prefs.end();
    return ssid.length() > 0;
}

bool bleGetStoredSSID(char* buf, size_t bufLen) {
    _prefs.begin(NVS_NAMESPACE, true);
    String ssid = _prefs.getString(NVS_KEY_SSID, "");
    _prefs.end();
    if (ssid.length() == 0) return false;
    strncpy(buf, ssid.c_str(), bufLen - 1);
    buf[bufLen - 1] = '\0';
    return true;
}

bool bleGetStoredPassword(char* buf, size_t bufLen) {
    _prefs.begin(NVS_NAMESPACE, true);
    String pass = _prefs.getString(NVS_KEY_PASSWORD, "");
    _prefs.end();
    if (pass.length() == 0) return false;
    strncpy(buf, pass.c_str(), bufLen - 1);
    buf[bufLen - 1] = '\0';
    return true;
}

bool bleSaveCredentials(const char* ssid, const char* password) {
    _prefs.begin(NVS_NAMESPACE, false);
    _prefs.putString(NVS_KEY_SSID, ssid);
    _prefs.putString(NVS_KEY_PASSWORD, password);
    _prefs.end();
    Serial.printf("[BLE] Credentials saved to NVS for SSID: %s\n", ssid);
    return true;
}

bool bleClearCredentials() {
    _prefs.begin(NVS_NAMESPACE, false);
    _prefs.remove(NVS_KEY_SSID);
    _prefs.remove(NVS_KEY_PASSWORD);
    _prefs.end();
    Serial.println("[BLE] Credentials cleared from NVS");
    return true;
}

// ============================================================
//  Provisioning Status
// ============================================================
void bleSetProvisioningStatus(uint8_t status) {
    if (!_pProvStatusChar) return;
    uint8_t val = status;
    _pProvStatusChar->setValue(&val, 1);
    if (_clientConnected) {
        _pProvStatusChar->notify();
    }
}

// ============================================================
//  Vitals Notifications
// ============================================================
void bleNotifyHeartRate(float hr) {
    if (!_pHrChar || !_clientConnected) return;
    uint16_t hrx10 = (uint16_t)(hr * 10.0f);
    _pHrChar->setValue(hrx10);
    _pHrChar->notify();
}

void bleNotifySpO2(uint8_t spo2) {
    if (!_pSpo2Char || !_clientConnected) return;
    _pSpo2Char->setValue(&spo2, 1);
    _pSpo2Char->notify();
}

void bleNotifyRisk(float score, const char* label) {
    if (!_clientConnected) return;
    if (_pRiskChar) {
        uint8_t buf[4];
        memcpy(buf, &score, 4);
        _pRiskChar->setValue(buf, 4);
        _pRiskChar->notify();
    }
    if (_pLabelChar) {
        _pLabelChar->setValue(label);
        _pLabelChar->notify();
    }
}

void bleNotifyDeviceStatus(uint8_t statusBits) {
    if (!_pDevStatusChar || !_clientConnected) return;
    _pDevStatusChar->setValue(&statusBits, 1);
    _pDevStatusChar->notify();
}

// ============================================================
//  Mode Switching
// ============================================================
void bleEnterProvisioning() {
    _provisioning = true;
    memset(_stagedSSID, 0, sizeof(_stagedSSID));
    memset(_stagedPass, 0, sizeof(_stagedPass));
    bleSetProvisioningStatus(BLE_STATUS_IDLE);

    NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
    pAdv->stop();
    pAdv->setMinInterval(BLE_ADV_FAST_MIN);
    pAdv->setMaxInterval(BLE_ADV_FAST_MAX);
    pAdv->start();

    Serial.println("[BLE] Entered provisioning mode (fast advertising)");
}

void bleSetOperationalMode() {
    _provisioning = false;

    NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
    pAdv->stop();
    pAdv->setMinInterval(BLE_ADV_SLOW_MIN);
    pAdv->setMaxInterval(BLE_ADV_SLOW_MAX);
    pAdv->start();

    Serial.println("[BLE] Operational mode (slow advertising)");
}

bool bleIsClientConnected() { return _clientConnected; }
bool bleIsProvisioning()    { return _provisioning; }

// ============================================================
//  Init
// ============================================================
BleBootMode bleInit() {
    // 1. Initialize NimBLE
    NimBLEDevice::init(BLE_DEVICE_NAME);
    NimBLEDevice::setPower(ESP_PWR_LVL_P6);
    NimBLEDevice::setMTU(128);

    // 2. Create server
    _pServer = NimBLEDevice::createServer();
    _pServer->setCallbacks(&_serverCb);

    // 3. WiFi Provisioning Service
    NimBLEService* pProvSvc = _pServer->createService(BLE_PROV_SERVICE_UUID);

    pProvSvc->createCharacteristic(BLE_PROV_SSID_UUID, NIMBLE_PROPERTY::WRITE)
        ->setCallbacks(&_provCb);

    pProvSvc->createCharacteristic(BLE_PROV_PASS_UUID, NIMBLE_PROPERTY::WRITE)
        ->setCallbacks(&_provCb);

    pProvSvc->createCharacteristic(BLE_PROV_CMD_UUID, NIMBLE_PROPERTY::WRITE)
        ->setCallbacks(&_provCb);

    _pProvStatusChar = pProvSvc->createCharacteristic(
        BLE_PROV_STATUS_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );
    uint8_t idle = BLE_STATUS_IDLE;
    _pProvStatusChar->setValue(&idle, 1);

    _pScanResultChar = pProvSvc->createCharacteristic(
        BLE_PROV_SCAN_RESULT_UUID,
        NIMBLE_PROPERTY::NOTIFY
    );

    pProvSvc->start();

    // 4. Cardiac Monitor Service
    NimBLEService* pCardSvc = _pServer->createService(BLE_CARDIAC_SERVICE_UUID);

    _pHrChar = pCardSvc->createCharacteristic(
        BLE_CARDIAC_HR_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    _pSpo2Char = pCardSvc->createCharacteristic(
        BLE_CARDIAC_SPO2_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    _pRiskChar = pCardSvc->createCharacteristic(
        BLE_CARDIAC_RISK_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    _pLabelChar = pCardSvc->createCharacteristic(
        BLE_CARDIAC_LABEL_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    _pDevStatusChar = pCardSvc->createCharacteristic(
        BLE_CARDIAC_STATUS_UUID,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    pCardSvc->start();

    // 5. Check NVS for stored credentials
    BleBootMode mode;
    if (bleHasStoredCredentials()) {
        mode = BOOT_WIFI;
        _provisioning = false;
        Serial.println("[BLE] Stored credentials found -> BOOT_WIFI");
    } else {
        mode = BOOT_PROVISIONING;
        _provisioning = true;
        Serial.println("[BLE] No stored credentials -> BOOT_PROVISIONING");
    }

    // 6. Start advertising
    NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
    pAdv->addServiceUUID(BLE_PROV_SERVICE_UUID);
    pAdv->addServiceUUID(BLE_CARDIAC_SERVICE_UUID);
    pAdv->setName(BLE_DEVICE_NAME);
    pAdv->enableScanResponse(true);

    if (_provisioning) {
        pAdv->setMinInterval(BLE_ADV_FAST_MIN);
        pAdv->setMaxInterval(BLE_ADV_FAST_MAX);
    } else {
        pAdv->setMinInterval(BLE_ADV_SLOW_MIN);
        pAdv->setMaxInterval(BLE_ADV_SLOW_MAX);
    }
    pAdv->start();

    Serial.printf("[BLE] Advertising as \"%s\" (%s)\n",
        BLE_DEVICE_NAME, _provisioning ? "fast" : "slow");

    return mode;
}

// ============================================================
//  Update (non-blocking event processor, call from loop)
// ============================================================
void bleUpdate() {
    BleEventType evt;
    while ((evt = evtPoll()) != BLE_EVT_NONE) {
        switch (evt) {
            case BLE_EVT_CMD_CONNECT:
                if (strlen(_stagedSSID) > 0) {
                    Serial.printf("[BLE] Connect command: SSID=%s\n", _stagedSSID);
                    bleSaveCredentials(_stagedSSID, _stagedPass);
                    bleSetProvisioningStatus(BLE_STATUS_CONNECTING);
                    wifiSetCredentials(_stagedSSID, _stagedPass);
                    wifiResetBootFailCount();
                    wifiReconnect();
                    // wifiUpdate() in main loop will pick up and start connecting
                    _provisioning = false;
                } else {
                    Serial.println("[BLE] Connect command but no SSID staged!");
                }
                break;

            case BLE_EVT_CMD_CLEAR:
                Serial.println("[BLE] Clear credentials command");
                bleClearCredentials();
                bleSetProvisioningStatus(BLE_STATUS_CLEARED);
                bleEnterProvisioning();
                break;

            case BLE_EVT_CMD_WIFI_SCAN:
#if WIFI_MODE_ENABLED
                if (_wScanState == WSCAN_IDLE) {
                    Serial.println("[BLE] WiFi scan requested");
                    WiFi.scanDelete();
                    WiFi.scanNetworks(true);  // async
                    _wScanState = WSCAN_RUNNING;
                    _wScanStartMs = millis();
                } else {
                    Serial.println("[BLE] Scan already in progress, ignoring");
                }
#endif
                break;

            case BLE_EVT_CLIENT_DISCONNECTED:
                // Abort any active scan
                if (_wScanState != WSCAN_IDLE) {
                    _wScanState = WSCAN_IDLE;
#if WIFI_MODE_ENABLED
                    WiFi.scanDelete();
#endif
                    Serial.println("[BLE] Scan aborted (client disconnected)");
                }
                break;

            default:
                break;
        }
    }
}

// ============================================================
//  WiFi Scan Processing (call from main loop)
// ============================================================
void bleProcessWifiScan() {
#if WIFI_MODE_ENABLED
    if (_wScanState == WSCAN_IDLE) return;

    if (_wScanState == WSCAN_RUNNING) {
        int16_t result = WiFi.scanComplete();
        if (result == WIFI_SCAN_RUNNING) {
            // Still scanning, check timeout
            if (millis() - _wScanStartMs > WIFI_SCAN_TIMEOUT_MS) {
                Serial.println("[BLE] WiFi scan timeout");
                WiFi.scanDelete();
                // Send empty end marker
                if (_pScanResultChar && _clientConnected) {
                    _pScanResultChar->setValue((uint8_t*)"", 0);
                    _pScanResultChar->notify();
                }
                _wScanState = WSCAN_IDLE;
            }
            return;
        }
        if (result == WIFI_SCAN_FAILED || result < 0) {
            Serial.println("[BLE] WiFi scan failed");
            WiFi.scanDelete();
            if (_pScanResultChar && _clientConnected) {
                _pScanResultChar->setValue((uint8_t*)"", 0);
                _pScanResultChar->notify();
            }
            _wScanState = WSCAN_IDLE;
            return;
        }
        // Scan complete
        _wScanTotal = min((int16_t)result, (int16_t)WIFI_SCAN_MAX_RESULTS);
        _wScanIdx = 0;
        _wScanLastNotifyMs = 0;
        Serial.printf("[BLE] WiFi scan done: %d networks found\n", result);

        if (_wScanTotal == 0) {
            // No networks, send end marker
            if (_pScanResultChar && _clientConnected) {
                _pScanResultChar->setValue((uint8_t*)"", 0);
                _pScanResultChar->notify();
            }
            WiFi.scanDelete();
            _wScanState = WSCAN_IDLE;
            return;
        }
        _wScanState = WSCAN_SENDING;
    }

    if (_wScanState == WSCAN_SENDING) {
        if (!_clientConnected) {
            WiFi.scanDelete();
            _wScanState = WSCAN_IDLE;
            return;
        }

        // Pace notifications
        if (millis() - _wScanLastNotifyMs < WIFI_SCAN_NOTIFY_INTERVAL_MS) return;
        _wScanLastNotifyMs = millis();

        if (_wScanIdx < _wScanTotal) {
            // Format: "index,total,rssi,encType,ssid"
            char buf[128];
            String ssid = WiFi.SSID(_wScanIdx);
            int32_t rssi = WiFi.RSSI(_wScanIdx);
            uint8_t encType = WiFi.encryptionType(_wScanIdx);
            snprintf(buf, sizeof(buf), "%d,%d,%d,%u,%s",
                     _wScanIdx, _wScanTotal, rssi, encType, ssid.c_str());

            if (_pScanResultChar) {
                _pScanResultChar->setValue((uint8_t*)buf, strlen(buf));
                _pScanResultChar->notify();
            }
            _wScanIdx++;
        } else {
            // All sent, send empty end marker
            if (_pScanResultChar) {
                _pScanResultChar->setValue((uint8_t*)"", 0);
                _pScanResultChar->notify();
            }
            WiFi.scanDelete();
            _wScanState = WSCAN_IDLE;
            Serial.println("[BLE] WiFi scan results sent");
        }
    }
#endif
}
