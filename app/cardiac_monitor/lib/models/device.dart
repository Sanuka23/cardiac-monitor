/// Registered ESP32 device linked to a user account.
///
/// Returned by `GET /devices/` and created via `POST /devices/register`.
class Device {
  final String deviceId;
  final String? label;
  final DateTime? registeredAt;

  Device({required this.deviceId, this.label, this.registeredAt});

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        deviceId: json['device_id'] ?? '',
        label: json['label'],
        registeredAt: json['registered_at'] != null
            ? DateTime.tryParse(json['registered_at'])
            : null,
      );
}
