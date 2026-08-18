import 'package:flutter/foundation.dart';

import '../utils/measurement_units.dart';

class MeasurementSettingsProvider
    extends ChangeNotifier {
  MeasurementSystem _system =
      MeasurementSystem.metric;

  MeasurementSystem get system =>
      _system;

  void setSystem(
    MeasurementSystem system,
  ) {
    if (_system == system) {
      return;
    }

    _system = system;
    notifyListeners();
  }
}