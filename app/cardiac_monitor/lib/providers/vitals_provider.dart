import 'package:flutter/material.dart';
import '../models/vitals.dart';
import '../models/prediction.dart';
import '../services/api_service.dart';

class VitalsProvider extends ChangeNotifier {
  final ApiService _api;

  List<Vitals> _vitalsHistory = [];
  List<Prediction> _predictionHistory = [];
  bool _loading = false;
  String? _error;

  VitalsProvider(this._api);

  List<Vitals> get vitalsHistory => _vitalsHistory;
  List<Prediction> get predictionHistory => _predictionHistory;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadHistory(String deviceId, {int limit = 200}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _api.getVitalsHistory(deviceId, limit: limit),
        _api.getPredictionHistory(deviceId, limit: limit),
      ]);
      _vitalsHistory = results[0] as List<Vitals>;
      _predictionHistory = results[1] as List<Prediction>;
    } catch (e) {
      _error = e.toString();
    }

    _loading = false;
    notifyListeners();
  }

  void clear() {
    _vitalsHistory = [];
    _predictionHistory = [];
    _error = null;
    notifyListeners();
  }
}
