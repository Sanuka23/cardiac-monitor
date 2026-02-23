#include "data_sender.h"
#include "config.h"

#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/queue.h>

#if WIFI_MODE_ENABLED
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#endif

static int _lastHttpCode = 0;
static uint32_t _successCount = 0;
static uint32_t _failCount = 0;

// FreeRTOS async sending
static QueueHandle_t _sendQueue = nullptr;
static QueueHandle_t _resultQueue = nullptr;
static TaskHandle_t  _sendTaskHandle = nullptr;

void dataSenderInit() {
    _lastHttpCode = 0;
    _successCount = 0;
    _failCount = 0;
}

SendResult dataSenderPost(const SensorWindow& window,
                          const char* deviceId,
                          time_t timestamp,
                          PredictionResult& prediction) {
    prediction.valid = false;

#if !WIFI_MODE_ENABLED
    return SEND_NOT_READY;
#else

    // --- Build JSON payload ---
    JsonDocument doc;

    doc["device_id"] = deviceId;
    doc["timestamp"] = (long long)timestamp;
    doc["window_ms"] = ECG_WINDOW_MS;
    doc["sample_rate_hz"] = ECG_SAMPLE_RATE_HZ;
    doc["heart_rate_bpm"] = round(window.heartRateBpm * 10.0f) / 10.0f;
    doc["spo2_percent"] = window.spo2Percent;
    doc["ecg_lead_off"] = window.ecgLeadOff;

    JsonArray ecgArr = doc["ecg_samples"].to<JsonArray>();
    for (uint16_t i = 0; i < window.ecgSampleCount; i++) {
        ecgArr.add(window.ecgSamples[i]);
    }

    JsonArray beatArr = doc["beat_timestamps_ms"].to<JsonArray>();
    for (uint8_t i = 0; i < window.beatCount; i++) {
        beatArr.add(window.beatTimestampsMs[i]);
    }

    // Serialize to String
    String jsonPayload;
    size_t jsonSize = measureJson(doc);
    if (!jsonPayload.reserve(jsonSize + 1)) {
        Serial.println("[SEND] JSON allocation failed!");
        _failCount++;
        return SEND_JSON_ERROR;
    }
    serializeJson(doc, jsonPayload);

    Serial.printf("[SEND] Payload: %u bytes, %u samples, %u beats\n",
                  jsonPayload.length(), window.ecgSampleCount, window.beatCount);

    // Free JsonDocument before HTTP
    doc.clear();

    // --- HTTPS POST ---
    WiFiClientSecure client;
    client.setInsecure();  // Skip TLS cert verification (dev mode)

    HTTPClient http;
    String url = String(API_BASE_URL) + API_VITALS_PATH;

    if (!http.begin(client, url)) {
        Serial.println("[SEND] HTTP begin failed!");
        _failCount++;
        return SEND_NETWORK_ERROR;
    }

    http.setTimeout(API_TIMEOUT_MS);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-API-Key", API_KEY);

    int httpCode = http.POST(jsonPayload);
    _lastHttpCode = httpCode;

    // Free payload before parsing response
    jsonPayload = "";

    if (httpCode <= 0) {
        Serial.printf("[SEND] POST failed: %s\n", http.errorToString(httpCode).c_str());
        http.end();
        _failCount++;
        return SEND_NETWORK_ERROR;
    }

    Serial.printf("[SEND] HTTP %d\n", httpCode);

    if (httpCode == 200 || httpCode == 201) {
        String response = http.getString();
        http.end();

        JsonDocument respDoc;
        DeserializationError err = deserializeJson(respDoc, response);
        if (err) {
            Serial.printf("[SEND] Response parse error: %s\n", err.c_str());
        } else if (respDoc["prediction"].is<JsonObject>()) {
            JsonObject pred = respDoc["prediction"];
            prediction.riskScore = pred["risk_score"] | 0.0f;
            prediction.confidence = pred["confidence"] | 0.0f;
            const char* label = pred["risk_label"] | "unknown";
            strncpy(prediction.riskLabel, label, sizeof(prediction.riskLabel) - 1);
            prediction.riskLabel[sizeof(prediction.riskLabel) - 1] = '\0';
            prediction.valid = true;

            Serial.printf("[SEND] Risk: %s (score=%.3f, conf=%.3f)\n",
                prediction.riskLabel, prediction.riskScore, prediction.confidence);
        }

        _successCount++;
        return SEND_OK;
    } else {
        String errorBody = http.getString();
        http.end();
        Serial.printf("[SEND] Server error: %s\n", errorBody.c_str());
        _failCount++;
        return SEND_HTTP_ERROR;
    }

#endif // WIFI_MODE_ENABLED
}

int      dataSenderGetLastHttpCode() { return _lastHttpCode; }
uint32_t dataSenderGetSuccessCount() { return _successCount; }
uint32_t dataSenderGetFailCount()    { return _failCount; }

// ============================================================
//  FreeRTOS Background Task
// ============================================================
static void dataSenderTaskFn(void* param) {
    DataSendJob job;
    while (true) {
        if (xQueueReceive(_sendQueue, &job, portMAX_DELAY) == pdTRUE) {
            PredictionResult prediction;
            prediction.valid = false;
            SendResult result = SEND_NOT_READY;

            for (int attempt = 0; attempt <= API_MAX_RETRIES; attempt++) {
                if (attempt > 0) {
                    Serial.printf("[SEND] Retry %d/%d...\n", attempt, API_MAX_RETRIES);
                    vTaskDelay(pdMS_TO_TICKS(500));
                }
                result = dataSenderPost(job.window, job.deviceId, job.timestamp, prediction);
                if (result == SEND_OK || result == SEND_JSON_ERROR || result == SEND_NOT_READY) break;
            }

            DataSendResult res = { prediction, result };
            xQueueOverwrite(_resultQueue, &res);
        }
    }
}

void dataSenderStartTask() {
    _sendQueue = xQueueCreate(DATA_SEND_QUEUE_DEPTH, sizeof(DataSendJob));
    _resultQueue = xQueueCreate(1, sizeof(DataSendResult));

    xTaskCreatePinnedToCore(
        dataSenderTaskFn,
        "DataSender",
        DATA_SEND_TASK_STACK,
        nullptr,
        DATA_SEND_TASK_PRIORITY,
        &_sendTaskHandle,
        DATA_SEND_TASK_CORE
    );
    Serial.println("[SEND] Background task started on Core 0");
}

bool dataSenderEnqueue(const SensorWindow& window, const char* deviceId, time_t timestamp) {
    if (!_sendQueue) return false;
    DataSendJob job;
    job.window = window;
    strncpy(job.deviceId, deviceId, sizeof(job.deviceId) - 1);
    job.deviceId[sizeof(job.deviceId) - 1] = '\0';
    job.timestamp = timestamp;

    if (xQueueSend(_sendQueue, &job, 0) != pdTRUE) {
        Serial.println("[SEND] Queue full, window dropped");
        return false;
    }
    return true;
}

bool dataSenderPollResult(DataSendResult& out) {
    if (!_resultQueue) return false;
    return xQueueReceive(_resultQueue, &out, 0) == pdTRUE;
}

bool dataSenderIsBusy() {
    if (!_sendQueue) return false;
    return uxQueueMessagesWaiting(_sendQueue) > 0;
}
