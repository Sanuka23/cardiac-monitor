import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ble_vitals.dart';
import '../models/wifi_scan_result.dart';
import '../services/ble_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Bridges [BleService] to the widget tree via Provider.
///
/// Exposes BLE connection state, scan results, live vitals data,
/// and WiFi provisioning status. Automatically subscribes to BLE
/// streams and calls [notifyListeners] on updates.
class BleProvider extends ChangeNotifier {
  final BleService _ble;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleVitals _vitals = BleVitals();
  int _provStatus = 0;
  List<ScanResult> _scanResults = [];
  String? _error;
  List<WifiScanResult> _wifiNetworks = [];
  bool _wifiScanning = false;
  List<int> _ecgBuffer = [];
  static const int _ecgBufferMaxSamples = 1250; // 5 seconds at 250Hz

  StreamSubscription? _vitalsSub;
  StreamSubscription? _connSub;
  StreamSubscription? _provSub;
  StreamSubscription? _scanSub;
  StreamSubscription? _wifiScanSub;
  StreamSubscription? _wifiScanCompleteSub;
  StreamSubscription? _ecgSub;

  BleProvider(this._ble) {
    _connSub = _ble.connectionStream.listen((state) {
      _connectionState = state;
      notifyListeners();
    });
    _vitalsSub = _ble.vitalsStream.listen((v) {
      _vitals = v;
      notifyListeners();
    });
    _provSub = _ble.provisioningStatusStream.listen((s) {
      _provStatus = s;
      notifyListeners();
    });
    _wifiScanSub = _ble.wifiScanStream.listen((result) {
      // Deduplicate by SSID, keep strongest signal
      final idx = _wifiNetworks.indexWhere((n) => n.ssid == result.ssid);
      if (idx >= 0) {
        if (result.rssi > _wifiNetworks[idx].rssi) {
          _wifiNetworks[idx] = result;
        }
      } else {
        _wifiNetworks.add(result);
      }
      // Sort by signal strength (strongest first)
      _wifiNetworks.sort((a, b) => b.rssi.compareTo(a.rssi));
      notifyListeners();
    });
    _wifiScanCompleteSub = _ble.wifiScanCompleteStream.listen((_) {
      _wifiScanning = false;
      notifyListeners();
    });
    _ecgSub = _ble.ecgStream.listen((batch) {
      _ecgBuffer.addAll(batch);
      if (_ecgBuffer.length > _ecgBufferMaxSamples) {
        _ecgBuffer = _ecgBuffer.sublist(
          _ecgBuffer.length - _ecgBufferMaxSamples,
        );
      }
      notifyListeners();
    });
  }

  BleConnectionState get connectionState => _connectionState;
  BleVitals get vitals => _vitals;
  int get provisioningStatus => _provStatus;
  List<ScanResult> get scanResults => _scanResults;
  List<WifiScanResult> get wifiNetworks => _wifiNetworks;
  bool get isWifiScanning => _wifiScanning;
  String? get error => _error;
  bool get isConnected => _connectionState == BleConnectionState.connected;
  List<int> get ecgBuffer => _ecgBuffer;
  bool get hasEcgData => _ecgBuffer.isNotEmpty;

  Future<void> startScan() async {
    _error = null;
    _scanResults = [];
    notifyListeners();

    _scanSub?.cancel();
    _scanSub = _ble.scan().listen((result) {
      final idx = _scanResults.indexWhere(
          (r) => r.device.remoteId == result.device.remoteId);
      if (idx >= 0) {
        _scanResults[idx] = result;
      } else {
        _scanResults.add(result);
      }
      notifyListeners();
    });
  }

  Future<void> stopScan() async {
    _scanSub?.cancel();
    await _ble.stopScan();
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    _error = null;
    notifyListeners();
    try {
      await _ble.connect(device);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> sendWifiCredentials(String ssid, String password) async {
    try {
      await _ble.sendWifiCredentials(ssid, password);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> requestWifiScan() async {
    _wifiNetworks = [];
    _wifiScanning = true;
    notifyListeners();
    try {
      await _ble.requestWifiScan();
    } catch (e) {
      _wifiScanning = false;
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _ble.disconnect();
    _vitals = BleVitals();
    _wifiNetworks = [];
    _wifiScanning = false;
    _ecgBuffer = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _vitalsSub?.cancel();
    _connSub?.cancel();
    _provSub?.cancel();
    _scanSub?.cancel();
    _wifiScanSub?.cancel();
    _wifiScanCompleteSub?.cancel();
    _ecgSub?.cancel();
    super.dispose();
  }
}
