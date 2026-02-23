/// Live vitals received over BLE from the ESP32 Cardiac Monitor characteristic.
///
/// The [deviceStatus] byte is a bitmask: bit 0 = sensor OK, bit 1 = WiFi ready,
/// bit 2 = ECG lead-off, bit 3 = API ready. Convenience getters decode each flag.
class BleVitals {
  final double heartRate;
  final int spo2;
  final double riskScore;
  final String riskLabel;
  final int deviceStatus;

  BleVitals({
    this.heartRate = 0,
    this.spo2 = 0,
    this.riskScore = 0,
    this.riskLabel = '',
    this.deviceStatus = 0,
  });

  bool get sensorOk => (deviceStatus & 0x01) != 0;
  bool get wifiReady => (deviceStatus & 0x02) != 0;
  bool get ecgLeadOff => (deviceStatus & 0x04) != 0;
  bool get apiReady => (deviceStatus & 0x08) != 0;

  BleVitals copyWith({
    double? heartRate,
    int? spo2,
    double? riskScore,
    String? riskLabel,
    int? deviceStatus,
  }) =>
      BleVitals(
        heartRate: heartRate ?? this.heartRate,
        spo2: spo2 ?? this.spo2,
        riskScore: riskScore ?? this.riskScore,
        riskLabel: riskLabel ?? this.riskLabel,
        deviceStatus: deviceStatus ?? this.deviceStatus,
      );
}
