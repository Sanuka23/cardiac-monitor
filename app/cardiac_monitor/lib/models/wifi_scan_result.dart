/// A WiFi network discovered during ESP32 scan.
class WifiScanResult {
  final String ssid;
  final int rssi;
  final int encryptionType;

  const WifiScanResult({
    required this.ssid,
    required this.rssi,
    required this.encryptionType,
  });

  /// Number of signal bars (1-4) based on RSSI.
  int get signalBars {
    if (rssi > -50) return 4;
    if (rssi > -65) return 3;
    if (rssi > -80) return 2;
    return 1;
  }

  /// Whether the network is open (no encryption).
  bool get isOpen => encryptionType == 0;

  /// Human-readable security label.
  String get securityLabel {
    switch (encryptionType) {
      case 0:
        return 'Open';
      case 1:
        return 'WEP';
      case 2:
        return 'WPA';
      case 3:
        return 'WPA2';
      case 4:
        return 'WPA/WPA2';
      case 5:
        return 'WPA2 Enterprise';
      default:
        return 'Secured';
    }
  }
}
