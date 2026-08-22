import 'package:flutter/foundation.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class MeasurementSettingsStorage {
  Future<MeasurementSystem?> readSystem();

  Future<void> writeSystem(
    MeasurementSystem system,
  );
}

class SharedPreferencesMeasurementSettingsStorage
    implements MeasurementSettingsStorage {
  static const String _systemKey =
      'measurement_system';

  final SharedPreferencesAsync _preferences;

  SharedPreferencesMeasurementSettingsStorage({
    SharedPreferencesAsync? preferences,
  }) : _preferences =
            preferences ?? SharedPreferencesAsync();

  @override
  Future<MeasurementSystem?> readSystem() async {
    final storedValue =
        await _preferences.getString(
      _systemKey,
    );

    for (final system
        in MeasurementSystem.values) {
      if (system.name == storedValue) {
        return system;
      }
    }

    return null;
  }

  @override
  Future<void> writeSystem(
    MeasurementSystem system,
  ) async {
    await _preferences.setString(
      _systemKey,
      system.name,
    );
  }
}

class MeasurementSettingsProvider
    extends ChangeNotifier {
  final MeasurementSettingsStorage
      _storage;

  MeasurementSystem _system =
      MeasurementSystem.metric;

  bool _isLoaded = false;

  MeasurementSettingsProvider({
    MeasurementSettingsStorage? storage,
  }) : _storage = storage ??
            SharedPreferencesMeasurementSettingsStorage();

  MeasurementSystem get system =>
      _system;

  bool get isLoaded => _isLoaded;

  Future<void> load() async {
    try {
      final storedSystem =
          await _storage.readSystem();

      if (storedSystem != null) {
        _system = storedSystem;
      }
    } catch (error) {
      debugPrint(
        'No se pudo cargar el sistema de medición: '
        '$error',
      );
    }

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setSystem(
    MeasurementSystem system,
  ) async {
    if (_system == system) {
      return;
    }

    _system = system;
    notifyListeners();

    try {
      await _storage.writeSystem(system);
    } catch (error) {
      debugPrint(
        'No se pudo guardar el sistema de medición: '
        '$error',
      );
    }
  }
}