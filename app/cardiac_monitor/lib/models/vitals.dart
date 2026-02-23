/// Single vitals reading stored by the backend from an ESP32 device.
///
/// Returned by `GET /vitals/history/{device_id}` for chart display.
class Vitals {
  final String? id;
  final String deviceId;
  final double heartRate;
  final int spo2;
  final bool ecgLeadOff;
  final int ecgSampleCount;
  final int beatCount;
  final DateTime timestamp;

  Vitals({
    this.id,
    required this.deviceId,
    required this.heartRate,
    required this.spo2,
    required this.ecgLeadOff,
    required this.ecgSampleCount,
    required this.beatCount,
    required this.timestamp,
  });

  factory Vitals.fromJson(Map<String, dynamic> json) => Vitals(
        id: json['id'] ?? json['_id'],
        deviceId: json['device_id'] ?? '',
        heartRate: (json['heart_rate_bpm'] as num?)?.toDouble() ?? 0,
        spo2: json['spo2_percent'] ?? 0,
        ecgLeadOff: json['ecg_lead_off'] ?? false,
        ecgSampleCount: json['ecg_sample_count'] ?? 0,
        beatCount: json['beat_count'] ?? 0,
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      );
}
