import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/providers/measurement_settings_provider.dart';
import 'package:room_scanner_core/room_scanner_core.dart';

class _FakeMeasurementSettingsStorage
    implements MeasurementSettingsStorage {
  MeasurementSystem? storedSystem;
  bool throwOnRead = false;
  bool throwOnWrite = false;

  _FakeMeasurementSettingsStorage({
    this.storedSystem,
  });

  @override
  Future<MeasurementSystem?> readSystem() async {
    if (throwOnRead) {
      throw StateError('Error de lectura simulado');
    }

    return storedSystem;
  }

  @override
  Future<void> writeSystem(
    MeasurementSystem system,
  ) async {
    if (throwOnWrite) {
      throw StateError('Error de escritura simulado');
    }

    storedSystem = system;
  }
}

void main() {
  group('MeasurementSettingsProvider', () {
    test('inicia en metros sin preferencia guardada', () async {
      final provider =
          MeasurementSettingsProvider(
        storage:
            _FakeMeasurementSettingsStorage(),
      );

      await provider.load();

      expect(
        provider.system,
        MeasurementSystem.metric,
      );
      expect(provider.isLoaded, isTrue);
    });

    test('restaura pies y pulgadas', () async {
      final provider =
          MeasurementSettingsProvider(
        storage:
            _FakeMeasurementSettingsStorage(
          storedSystem:
              MeasurementSystem.imperial,
        ),
      );

      await provider.load();

      expect(
        provider.system,
        MeasurementSystem.imperial,
      );
    });

    test('guarda una nueva preferencia', () async {
      final storage =
          _FakeMeasurementSettingsStorage();
      final provider =
          MeasurementSettingsProvider(
        storage: storage,
      );

      await provider.load();
      await provider.setSystem(
        MeasurementSystem.imperial,
      );

      expect(
        storage.storedSystem,
        MeasurementSystem.imperial,
      );
      expect(
        provider.system,
        MeasurementSystem.imperial,
      );
    });

    test('continúa funcionando si falla la lectura', () async {
      final storage =
          _FakeMeasurementSettingsStorage()
            ..throwOnRead = true;
      final provider =
          MeasurementSettingsProvider(
        storage: storage,
      );

      await provider.load();

      expect(
        provider.system,
        MeasurementSystem.metric,
      );
      expect(provider.isLoaded, isTrue);
    });

    test('conserva la selección si falla la escritura', () async {
      final storage =
          _FakeMeasurementSettingsStorage()
            ..throwOnWrite = true;
      final provider =
          MeasurementSettingsProvider(
        storage: storage,
      );

      await provider.load();
      await provider.setSystem(
        MeasurementSystem.imperial,
      );

      expect(
        provider.system,
        MeasurementSystem.imperial,
      );
    });
  });
}