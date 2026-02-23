import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ble_vitals.dart';
import '../services/ble_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleProvider extends ChangeNotifier {
  final BleService _ble;

  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleVitals _vitals = BleVitals();
  int _provStatus = 0;
  List<ScanResult> _scanResults = [];
  String? _error;

  StreamSubscription? _vitalsSub;
  StreamSubscription? _connSub;
  StreamSubscription? _provSub;
  StreamSubscription? _scanSub;

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
  }

  BleConnectionState get connectionState => _connectionState;
  BleVitals get vitals => _vitals;
  int get provisioningStatus => _provStatus;
  List<ScanResult> get scanResults => _scanResults;
  String? get error => _error;
  bool get isConnected => _connectionState == BleConnectionState.connected;

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

  Future<void> disconnect() async {
    await _ble.disconnect();
    _vitals = BleVitals();
    notifyListeners();
  }

  @override
  void dispose() {
    _vitalsSub?.cancel();
    _connSub?.cancel();
    _provSub?.cancel();
    _scanSub?.cancel();
    super.dispose();
  }
}
