import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/utils/measurement_units.dart';

void main() {
  group('MeasurementUnits', () {
    test('convierte pulgadas a metros', () {
      expect(
        MeasurementUnits.inchesToMeters(1),
        closeTo(0.0254, 0.0000001),
      );
    });

    test('convierte metros a pulgadas', () {
      expect(
        MeasurementUnits.metersToInches(1),
        closeTo(39.37007874, 0.0000001),
      );
    });

    test('convierte pies y pulgadas a metros', () {
      expect(
        MeasurementUnits.feetAndInchesToMeters(
          feet: 10,
          inches: 8,
        ),
        closeTo(3.2512, 0.0000001),
      );
    });

    test('convierte metros a pies y pulgadas', () {
      final result =
          MeasurementUnits.metersToFeetAndInches(
        3.2512,
      );

      expect(result.feet, 10);
      expect(result.inches, closeTo(8, 0.001));
    });

    test('normaliza doce pulgadas al pie siguiente', () {
      final result =
          MeasurementUnits.metersToFeetAndInches(
        0.30479,
        inchDecimals: 2,
      );

      expect(result.feet, 1);
      expect(result.inches, 0);
    });

    test('acepta coma decimal en metros', () {
      expect(
        MeasurementUnits.metricInputToMeters('3,25'),
        3.25,
      );
    });

    test('acepta pies y pulgadas con coma decimal', () {
      expect(
        MeasurementUnits.imperialInputToMeters(
          feetInput: '10',
          inchesInput: '8,5',
        ),
        closeTo(3.2639, 0.0000001),
      );
    });

    test('permite ingresar solamente pulgadas', () {
      expect(
        MeasurementUnits.imperialInputToMeters(
          feetInput: '',
          inchesInput: '128',
        ),
        closeTo(3.2512, 0.0000001),
      );
    });

    test('rechaza valores negativos', () {
      expect(
        MeasurementUnits.imperialInputToMeters(
          feetInput: '-1',
          inchesInput: '2',
        ),
        isNull,
      );
    });

    test('rechaza entradas vacías', () {
      expect(
        MeasurementUnits.imperialInputToMeters(
          feetInput: '',
          inchesInput: '',
        ),
        isNull,
      );
    });
  });
}