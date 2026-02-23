/// ML risk prediction result from the backend ensemble model.
///
/// Each prediction contains a [riskScore] (0-1), human-readable [riskLabel],
/// and model [confidence]. Returned by `GET /predict/history/{device_id}`.
class Prediction {
  final String? id;
  final String deviceId;
  final double riskScore;
  final String riskLabel;
  final double confidence;
  final DateTime timestamp;

  Prediction({
    this.id,
    required this.deviceId,
    required this.riskScore,
    required this.riskLabel,
    required this.confidence,
    required this.timestamp,
  });

  factory Prediction.fromJson(Map<String, dynamic> json) => Prediction(
        id: json['id'] ?? json['_id'],
        deviceId: json['device_id'] ?? '',
        riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0,
        riskLabel: json['risk_label'] ?? 'unknown',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      );
}
