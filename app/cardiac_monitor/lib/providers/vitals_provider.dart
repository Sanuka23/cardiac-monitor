import 'package:flutter/material.dart';
import '../models/vitals.dart';
import '../models/prediction.dart';
import '../services/api_service.dart';

/// Loads and caches vitals and prediction history from the backend API.
///
/// Used by the History screen to display HR, SpO2, and risk charts.
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

  /// Load history across all user's devices (user-centric).
  Future<void> loadMyHistory({int limit = 200}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _api.getMyVitalsHistory(limit: limit),
        _api.getMyPredictionHistory(limit: limit),
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
