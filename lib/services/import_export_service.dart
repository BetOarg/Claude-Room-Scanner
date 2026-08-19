import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';
import '../utils/measurement_units.dart';
import 'geometry_service.dart';

class ImportExportService {
  /// Exporta el proyecto como un archivo JSON real y abre el menú para
  /// compartirlo o guardarlo en el dispositivo.
  static Future<void> exportToJson(
    List<RoomModel> rooms,
    String projectName,
  ) async {
    final data = buildJsonData(rooms, projectName);
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final fileName = buildJsonFileName(projectName);
    final temporaryDirectory = await getTemporaryDirectory();
    final file = File('${temporaryDirectory.path}/$fileName');

    await file.writeAsString(
      jsonString,
      encoding: utf8,
      flush: true,
    );

    await Share.shareXFiles(
      [
        XFile(
          file.path,
          mimeType: 'application/json',
          name: fileName,
        ),
      ],
      subject: '$projectName - Plano 2D',
    );
  }

  static Map<String, dynamic> buildJsonData(
    List<RoomModel> rooms,
    String projectName,
  ) {
    return {
      'formatVersion': 2,
      'lengthUnit': 'meters',
      'projectName': projectName,
      'rooms': rooms.map((r) => r.toJson()).toList(),
    };
  }

  /// Construye un nombre de archivo válido para Android, iOS y los destinos
  /// habituales del menú de compartir.
  static String buildJsonFileName(String projectName) {
    var safeName = projectName.trim();

    safeName = safeName.replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
    safeName = safeName.replaceAll(RegExp(r'\s+'), ' ');
    safeName = safeName.replaceAll(RegExp(r'[. ]+$'), '');

    if (safeName.isEmpty) {
      safeName = 'Plano 2D';
    }

    if (safeName.length > 80) {
      safeName = safeName.substring(0, 80).trimRight();
    }

    return '$safeName.json';
  }

  /// Importa un archivo JSON seleccionado desde el dispositivo.
  ///
  /// Admite tanto selectores que entregan el contenido en memoria como los
  /// que entregan una ruta local, manteniendo compatibilidad en Android e iOS.
  static Future<bool> importFromJson(FloorPlanProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return false;
      }

      final fileContent = await _readSelectedJson(result.files.single);
      if (fileContent == null || fileContent.trim().isEmpty) {
        return false;
      }

      final decoded = jsonDecode(fileContent);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      final roomsData = decoded['rooms'];
      if (roomsData is! List) {
        return false;
      }

      final projectName =
          decoded['projectName'] as String? ?? 'Proyecto Importado';
      final rooms = roomsData
          .map(
            (room) => RoomModel.fromJson(
              Map<String, dynamic>.from(room as Map),
            ),
          )
          .toList();

      await provider.loadExistingRooms(rooms, projectName);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _readSelectedJson(PlatformFile selectedFile) async {
    final bytes = selectedFile.bytes;
    if (bytes != null) {
      return utf8.decode(bytes);
    }

    final path = selectedFile.path;
    if (path == null || path.trim().isEmpty) {
      return null;
    }

    return File(path).readAsString(encoding: utf8);
  }

  /// Genera un informe técnico del plano y abre la vista previa/impresión.
  static Future<void> exportToPdf(
    List<RoomModel> rooms,
    String projectName,
    MeasurementSystem measurementSystem,
  ) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('Plano arquitectónico: $projectName'),
            ),
            pw.Text(
              'Ambientes relevados: ${rooms.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 16),
            ...rooms.map(
              (room) => _buildRoomReport(
                room,
                measurementSystem,
              ),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  static pw.Widget _buildRoomReport(
    RoomModel room,
    MeasurementSystem measurementSystem,
  ) {
    final area = GeometryService.calculateArea(room.points);
    final perimeter = GeometryService.calculatePerimeter(room.points);

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 18),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${room.name} · ${room.type.displayName}',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'Superficie: ${_formatArea(area, measurementSystem)} · '
            'Perímetro: ${_formatLength(perimeter, measurementSystem)}',
          ),
          pw.Text('Esquinas registradas: ${room.points.length}'),
          pw.SizedBox(height: 8),
          pw.Text(
            'Puertas y ventanas',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (room.features.isEmpty)
            pw.Text('No hay aberturas registradas.')
          else
            ...room.features.map(
              (feature) => pw.Bullet(
                text: _featureDescription(
                  feature,
                  measurementSystem,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _featureDescription(
    WallFeature feature,
    MeasurementSystem measurementSystem,
  ) {
    final width = GeometryService.calculateDistance(
      feature.start,
      feature.end,
    );
    final type = feature.type == FeatureType.door
        ? 'Puerta'
        : 'Ventana';
    final parts = <String>[
      '$type: ${_formatLength(width, measurementSystem)} de ancho',
      '${_formatLength(feature.openingHeightMeters, measurementSystem)} de alto',
    ];

    if (feature.type == FeatureType.window) {
      parts.add(
        '${_formatLength(feature.sillHeightMeters, measurementSystem)} '
        'desde el piso',
      );
      parts.add(
        width >= feature.openingHeightMeters
            ? 'orientación horizontal'
            : 'orientación vertical',
      );
    }

    return parts.join(' · ');
  }

  static String _formatLength(
    double meters,
    MeasurementSystem measurementSystem,
  ) {
    return MeasurementUnits.formatLength(
      meters,
      measurementSystem,
      metersLabel: 'metros',
      feetLabel: 'pies',
      inchesLabel: 'pulgadas',
      decimalSeparator: ',',
    );
  }

  static String _formatArea(
    double squareMeters,
    MeasurementSystem measurementSystem,
  ) {
    if (measurementSystem == MeasurementSystem.metric) {
      return '${squareMeters.toStringAsFixed(2).replaceAll('.', ',')} '
          'metros cuadrados';
    }

    final squareFeet =
        MeasurementUnits.squareMetersToSquareFeet(squareMeters);
    return '${squareFeet.toStringAsFixed(2).replaceAll('.', ',')} '
        'pies cuadrados';
  }
}