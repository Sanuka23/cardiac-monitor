import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../config/constants.dart';
import '../models/ble_vitals.dart';

enum BleConnectionState { disconnected, scanning, connecting, connected }

class BleService {
  BluetoothDevice? _device;
  final _vitalsController = StreamController<BleVitals>.broadcast();
  final _provStatusController = StreamController<int>.broadcast();
  final _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final List<StreamSubscription> _subscriptions = [];

  BleVitals _currentVitals = BleVitals();
  BleConnectionState _connectionState = BleConnectionState.disconnected;

  Stream<BleVitals> get vitalsStream => _vitalsController.stream;
  Stream<int> get provisioningStatusStream => _provStatusController.stream;
  Stream<BleConnectionState> get connectionStream =>
      _connectionController.stream;
  BleVitals get currentVitals => _currentVitals;
  BleConnectionState get connectionState => _connectionState;
  BluetoothDevice? get connectedDevice => _device;

  void _setState(BleConnectionState state) {
    _connectionState = state;
    _connectionController.add(state);
  }

  // --- Scan for CardiacMon devices ---
  Stream<ScanResult> scan({Duration timeout = const Duration(seconds: 10)}) {
    _setState(BleConnectionState.scanning);
    FlutterBluePlus.startScan(
      timeout: timeout,
      withNames: [bleDeviceNamePrefix],
    );
    return FlutterBluePlus.scanResults.expand((list) => list);
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    if (_connectionState == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
  }

  // --- Connect and discover services ---
  Future<void> connect(BluetoothDevice device) async {
    _setState(BleConnectionState.connecting);
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;

      // Listen for disconnection
      final sub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _setState(BleConnectionState.disconnected);
          _cancelSubscriptions();
          _device = null;
        }
      });
      _subscriptions.add(sub);

      await device.requestMtu(128);
      final services = await device.discoverServices();
      _subscribeToNotifications(services);
      _setState(BleConnectionState.connected);
    } catch (e) {
      _setState(BleConnectionState.disconnected);
      rethrow;
    }
  }

  // --- Subscribe to BLE notifications ---
  void _subscribeToNotifications(List<BluetoothService> services) {
    for (final svc in services) {
      final svcUuid = svc.uuid.toString().toLowerCase();

      if (svcUuid == BleUuids.provService) {
        for (final c in svc.characteristics) {
          final uuid = c.uuid.toString().toLowerCase();
          if (uuid == BleUuids.provStatus && c.properties.notify) {
            c.setNotifyValue(true);
            _subscriptions.add(c.onValueReceived.listen((value) {
              if (value.isNotEmpty) {
                _provStatusController.add(value[0]);
              }
            }));
          }
        }
      }

      if (svcUuid == BleUuids.cardiacService) {
        for (final c in svc.characteristics) {
          final uuid = c.uuid.toString().toLowerCase();
          if (!c.properties.notify) continue;

          c.setNotifyValue(true);
          _subscriptions.add(c.onValueReceived.listen((value) {
            _handleCardiacNotification(uuid, value);
          }));
        }
      }
    }
  }

  void _handleCardiacNotification(String uuid, List<int> value) {
    if (value.isEmpty) return;

    if (uuid == BleUuids.cardiacHr && value.length >= 2) {
      final raw = ByteData.sublistView(Uint8List.fromList(value));
      final hrx10 = raw.getUint16(0, Endian.little);
      _currentVitals = _currentVitals.copyWith(heartRate: hrx10 / 10.0);
    } else if (uuid == BleUuids.cardiacSpo2) {
      _currentVitals = _currentVitals.copyWith(spo2: value[0]);
    } else if (uuid == BleUuids.cardiacRisk && value.length >= 4) {
      final raw = ByteData.sublistView(Uint8List.fromList(value));
      final score = raw.getFloat32(0, Endian.little);
      _currentVitals = _currentVitals.copyWith(riskScore: score);
    } else if (uuid == BleUuids.cardiacLabel) {
      final label = String.fromCharCodes(value);
      _currentVitals = _currentVitals.copyWith(riskLabel: label);
    } else if (uuid == BleUuids.cardiacStatus) {
      _currentVitals = _currentVitals.copyWith(deviceStatus: value[0]);
    }

    _vitalsController.add(_currentVitals);
  }

  // --- WiFi Provisioning ---
  Future<void> sendWifiCredentials(String ssid, String password) async {
    if (_device == null) throw Exception('Not connected');
    final services = await _device!.discoverServices();

    BluetoothCharacteristic? ssidChar, passChar, cmdChar;
    for (final svc in services) {
      if (svc.uuid.toString().toLowerCase() != BleUuids.provService) continue;
      for (final c in svc.characteristics) {
        final uuid = c.uuid.toString().toLowerCase();
        if (uuid == BleUuids.provSsid) ssidChar = c;
        if (uuid == BleUuids.provPass) passChar = c;
        if (uuid == BleUuids.provCmd) cmdChar = c;
      }
    }

    if (ssidChar == null || passChar == null || cmdChar == null) {
      throw Exception('Provisioning characteristics not found');
    }

    await ssidChar.write(ssid.codeUnits, withoutResponse: false);
    await passChar.write(password.codeUnits, withoutResponse: false);
    await cmdChar.write([BleCmds.connect], withoutResponse: false);
  }

  Future<void> clearCredentials() async {
    if (_device == null) throw Exception('Not connected');
    final services = await _device!.discoverServices();

    for (final svc in services) {
      if (svc.uuid.toString().toLowerCase() != BleUuids.provService) continue;
      for (final c in svc.characteristics) {
        if (c.uuid.toString().toLowerCase() == BleUuids.provCmd) {
          await c.write([BleCmds.clearCreds], withoutResponse: false);
          return;
        }
      }
    }
  }

  // --- Disconnect ---
  Future<void> disconnect() async {
    _cancelSubscriptions();
    await _device?.disconnect();
    _device = null;
    _currentVitals = BleVitals();
    _setState(BleConnectionState.disconnected);
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  void dispose() {
    _cancelSubscriptions();
    _vitalsController.close();
    _provStatusController.close();
    _connectionController.close();
  }
}
