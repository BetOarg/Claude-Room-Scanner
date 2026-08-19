import 'package:flutter_test/flutter_test.dart';
import 'package:room_scanner_ar/models/room_model.dart';
import 'package:room_scanner_ar/services/import_export_service.dart';
import 'package:room_scanner_ar/utils/measurement_units.dart';

void main() {
  test('JSON exporta versión, unidad y medidas verticales', () {
    final room = RoomModel(
      id: 'room-1',
      name: 'Dormitorio',
      type: RoomType.dormitorio,
      points: [
        ARPoint(x: 0, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 0),
        ARPoint(x: 3, y: 0, z: 3),
      ],
      features: [
        WallFeature(
          id: 'window-1',
          type: FeatureType.window,
          start: ARPoint(x: 0.5, y: 0, z: 0),
          end: ARPoint(x: 1.7, y: 0, z: 0),
          openingHeightMeters: 1.1,
          sillHeightMeters: 0.85,
        ),
      ],
      isClosed: true,
    );

    final data = ImportExportService.buildJsonData(
      [room],
      'Casa',
    );
    final rooms = data['rooms'] as List<dynamic>;
    final roomJson = rooms.single as Map<String, dynamic>;
    final features = roomJson['features'] as List<dynamic>;
    final feature = features.single as Map<String, dynamic>;

    expect(data['formatVersion'], 2);
    expect(data['lengthUnit'], 'meters');
    expect(feature['openingHeightMeters'], closeTo(1.1, 0.000001));
    expect(feature['sillHeightMeters'], closeTo(0.85, 0.000001));
  });

  group('nombre del archivo JSON', () {
    test('conserva un nombre normal y agrega la extensión', () {
      expect(
        ImportExportService.buildJsonFileName('Casa familiar'),
        'Casa familiar.json',
      );
    });

    test('reemplaza caracteres inválidos para archivos', () {
      expect(
        ImportExportService.buildJsonFileName('Casa: planta/alta?'),
        'Casa_ planta_alta_.json',
      );
    });

    test('usa un nombre seguro cuando el proyecto está vacío', () {
      expect(
        ImportExportService.buildJsonFileName('   '),
        'Plano 2D.json',
      );
    });
  });

  group('nombre del archivo PDF', () {
    test('conserva un nombre normal y agrega la extensión PDF', () {
      expect(
        ImportExportService.buildPdfFileName('Casa familiar'),
        'Casa familiar.pdf',
      );
    });

    test('reutiliza la normalización segura del nombre JSON', () {
      expect(
        ImportExportService.buildPdfFileName('Casa: planta/alta?'),
        'Casa_ planta_alta_.pdf',
      );
    });

    test('usa un nombre seguro cuando el proyecto está vacío', () {
      expect(
        ImportExportService.buildPdfFileName('   '),
        'Plano 2D.pdf',
      );
    });
  });

  group('plano geométrico del PDF', () {
    test('dibuja ambientes, puertas y ventanas', () {
      final room = RoomModel(
        id: 'room-svg',
        name: 'Estar principal',
        type: RoomType.living,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 0),
          ARPoint(x: 4, y: 0, z: 3),
          ARPoint(x: 0, y: 0, z: 3),
        ],
        features: [
          WallFeature(
            id: 'door-svg',
            type: FeatureType.door,
            start: ARPoint(x: 0.8, y: 0, z: 0),
            end: ARPoint(x: 1.7, y: 0, z: 0),
          ),
          WallFeature(
            id: 'window-svg',
            type: FeatureType.window,
            start: ARPoint(x: 4, y: 0, z: 0.8),
            end: ARPoint(x: 4, y: 0, z: 2.0),
          ),
        ],
        isClosed: true,
      );

      final svg = ImportExportService.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );

      expect(svg, contains('<polygon'));
      expect(svg, contains('Estar principal'));
      expect(svg, contains('data-feature-id="door-svg"'));
      expect(svg, contains('data-feature-id="window-svg"'));
      expect(svg, contains('#F57C00'));
      expect(svg, contains('#C2185B'));
    });

    test('no duplica una abertura compartida entre ambientes', () {
      final sharedDoor = WallFeature(
        id: 'shared-door',
        type: FeatureType.door,
        start: ARPoint(x: 2, y: 0, z: 0.8),
        end: ARPoint(x: 2, y: 0, z: 1.7),
      );
      final rooms = [
        RoomModel(
          id: 'room-a',
          name: 'Ambiente A',
          type: RoomType.living,
          points: [
            ARPoint(x: 0, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 2, y: 0, z: 2.5),
            ARPoint(x: 0, y: 0, z: 2.5),
          ],
          features: [sharedDoor],
          isClosed: true,
        ),
        RoomModel(
          id: 'room-b',
          name: 'Ambiente B',
          type: RoomType.cocina,
          points: [
            ARPoint(x: 2, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 0),
            ARPoint(x: 4, y: 0, z: 2.5),
            ARPoint(x: 2, y: 0, z: 2.5),
          ],
          features: [sharedDoor],
          isClosed: true,
        ),
      ];

      final svg = ImportExportService.buildFloorPlanSvg(
        rooms,
        MeasurementSystem.metric,
      );
      final occurrences = RegExp(
        'data-feature-id="shared-door"',
      ).allMatches(svg).length;

      expect(occurrences, 1);
    });

    test('incluye cotas métricas de paredes y aberturas', () {
      final room = RoomModel(
        id: 'dimensions-room',
        name: 'Estudio',
        type: RoomType.dormitorio,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 0),
          ARPoint(x: 3, y: 0, z: 2),
          ARPoint(x: 0, y: 0, z: 2),
        ],
        features: [
          WallFeature(
            id: 'dimension-door',
            type: FeatureType.door,
            start: ARPoint(x: 0.5, y: 0, z: 0),
            end: ARPoint(x: 1.4, y: 0, z: 0),
          ),
        ],
        isClosed: true,
      );

      final svg = ImportExportService.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );

      expect(svg, contains('3 m'));
      expect(svg, contains('2 m'));
      expect(svg, contains('0,9 m'));
    });

    test('las cotas del plano respetan el sistema imperial', () {
      final room = RoomModel(
        id: 'imperial-room',
        name: 'Office',
        type: RoomType.dormitorio,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 3.048, y: 0, z: 0),
          ARPoint(x: 3.048, y: 0, z: 2),
        ],
        isClosed: true,
      );

      final svg = ImportExportService.buildFloorPlanSvg(
        [room],
        MeasurementSystem.imperial,
      );

      expect(svg, contains('ft'));
      expect(svg, contains('in'));
    });

    test('reubica cotas coincidentes para evitar superposición', () {
      final room = RoomModel(
        id: 'compact-room',
        name: 'Ambiente pequeño',
        type: RoomType.pasillo,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 1, y: 0, z: 0),
          ARPoint(x: 1, y: 0, z: 1),
          ARPoint(x: 0, y: 0, z: 1),
        ],
        features: [
          WallFeature(
            id: 'full-width-door',
            type: FeatureType.door,
            start: ARPoint(x: 0, y: 0, z: 0),
            end: ARPoint(x: 1, y: 0, z: 0),
          ),
        ],
        isClosed: true,
      );

      final svg = ImportExportService.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );
      final matches = RegExp(
        r'data-dimension-label="1 m" data-layout-index="(\d+)" '
        r'x="([\d.]+)" y="([\d.]+)"',
      ).allMatches(svg).toList();
      final positions = matches
          .map((match) => '${match.group(2)}:${match.group(3)}')
          .toSet();

      expect(matches.length, greaterThanOrEqualTo(2));
      expect(positions.length, matches.length);
    });

    test('traduce la leyenda del plano al inglés', () {
      final room = RoomModel(
        id: 'english-room',
        name: 'Custom room name',
        type: RoomType.cocina,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 2, y: 0, z: 0),
          ARPoint(x: 2, y: 0, z: 2),
        ],
        isClosed: true,
      );

      final svg = ImportExportService.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
        languageCode: 'en',
      );

      expect(svg, contains('Wall'));
      expect(svg, contains('Door'));
      expect(svg, contains('Window'));
      expect(svg, isNot(contains('Pared')));
      expect(svg, contains('Kitchen'));
      expect(svg, contains('Custom room name'));
    });

    test('mantiene la leyenda española por defecto', () {
      final room = RoomModel(
        id: 'spanish-room',
        name: 'Nombre personalizado',
        type: RoomType.living,
        points: [
          ARPoint(x: 0, y: 0, z: 0),
          ARPoint(x: 2, y: 0, z: 0),
          ARPoint(x: 2, y: 0, z: 2),
        ],
        isClosed: true,
      );

      final svg = ImportExportService.buildFloorPlanSvg(
        [room],
        MeasurementSystem.metric,
      );

      expect(svg, contains('Pared'));
      expect(svg, contains('Puerta'));
      expect(svg, contains('Ventana'));
      expect(svg, contains('Nombre personalizado'));
    });
  });
}