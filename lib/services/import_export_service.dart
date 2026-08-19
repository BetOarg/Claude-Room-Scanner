import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
            if (rooms.any((room) => room.points.length >= 2)) ...[
              pw.Text(
                'Plano general',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                height: 390,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.6),
                ),
                child: pw.SvgImage(
                  svg: buildFloorPlanSvg(
                    rooms,
                    measurementSystem,
                  ),
                ),
              ),
              pw.SizedBox(height: 18),
            ],
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

  /// Construye el dibujo vectorial del plano completo para incorporarlo al
  /// PDF. Mantiene las coordenadas globales y ajusta la escala a la página.
  static String buildFloorPlanSvg(
    List<RoomModel> rooms,
    MeasurementSystem measurementSystem,
  ) {
    const canvasWidth = 760.0;
    const canvasHeight = 500.0;
    const padding = 42.0;

    final points = <ARPoint>[
      for (final room in rooms) ...room.points,
      for (final room in rooms)
        for (final feature in room.features) ...[
          feature.start,
          feature.end,
        ],
    ];

    if (points.isEmpty) {
      return '<svg xmlns="http://www.w3.org/2000/svg" '
          'viewBox="0 0 760 500"></svg>';
    }

    var minX = points.first.x;
    var maxX = points.first.x;
    var minZ = points.first.z;
    var maxZ = points.first.z;

    for (final point in points.skip(1)) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minZ = math.min(minZ, point.z);
      maxZ = math.max(maxZ, point.z);
    }

    final planWidth = math.max(maxX - minX, 0.01);
    final planHeight = math.max(maxZ - minZ, 0.01);
    final availableWidth = canvasWidth - (padding * 2);
    final availableHeight = canvasHeight - (padding * 2);
    final scale = math.min(
      availableWidth / planWidth,
      availableHeight / planHeight,
    );
    final offsetX =
        padding + (availableWidth - (planWidth * scale)) / 2.0;
    final offsetY =
        padding + (availableHeight - (planHeight * scale)) / 2.0;

    _SvgPoint transform(ARPoint point) {
      return _SvgPoint(
        offsetX + ((point.x - minX) * scale),
        canvasHeight - offsetY - ((point.z - minZ) * scale),
      );
    }

    final svg = StringBuffer()
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 $canvasWidth $canvasHeight">',
      )
      ..writeln('<rect width="760" height="500" fill="white"/>');

    final drawnWallKeys = <String>{};
    for (final room in rooms) {
      if (room.points.length < 2) {
        continue;
      }

      final transformed = room.points.map(transform).toList();
      final polygonPoints = transformed
          .map((point) => '${_svgNumber(point.x)},${_svgNumber(point.y)}')
          .join(' ');

      svg.writeln(
        '<polygon points="$polygonPoints" fill="#E3F2FD" '
        'fill-opacity="0.34" stroke="#1565C0" stroke-width="3" '
        'stroke-linejoin="round"/>',
      );

      final centerX = transformed
              .map((point) => point.x)
              .reduce((value, element) => value + element) /
          transformed.length;
      final centerY = transformed
              .map((point) => point.y)
              .reduce((value, element) => value + element) /
          transformed.length;
      final area = GeometryService.calculateArea(room.points);

      svg
        ..writeln(
          '<text x="${_svgNumber(centerX)}" '
          'y="${_svgNumber(centerY - 4)}" text-anchor="middle" '
          'font-family="Helvetica" font-size="13" font-weight="bold" '
          'fill="#1F2937">${_escapeSvg(room.name)}</text>',
        )
        ..writeln(
          '<text x="${_svgNumber(centerX)}" '
          'y="${_svgNumber(centerY + 13)}" text-anchor="middle" '
          'font-family="Helvetica" font-size="10" fill="#374151">'
          '${area.toStringAsFixed(2)} m²</text>',
        );

      for (var index = 0; index < room.points.length; index++) {
        final first = room.points[index];
        final second = room.points[(index + 1) % room.points.length];
        if (!drawnWallKeys.add(_wallKey(first, second))) {
          continue;
        }

        _writeDimensionSvg(
          svg: svg,
          start: transform(first),
          end: transform(second),
          label: _formatCompactLength(
            GeometryService.calculateDistance(first, second),
            measurementSystem,
          ),
          color: '#1565C0',
          center: _SvgPoint(centerX, centerY),
          offset: 13,
        );
      }
    }

    final drawnFeatureIds = <String>{};
    for (final room in rooms) {
      for (final feature in room.features) {
        if (!drawnFeatureIds.add(feature.id)) {
          continue;
        }

        final start = transform(feature.start);
        final end = transform(feature.end);
        svg.writeln(
          '<g data-feature-id="${_escapeSvg(feature.id)}">',
        );

        if (feature.type == FeatureType.door) {
          _writeDoorSvg(svg, feature, start, end);
        } else {
          _writeWindowSvg(svg, start, end);
        }

        _writeDimensionSvg(
          svg: svg,
          start: start,
          end: end,
          label: _formatCompactLength(
            GeometryService.calculateDistance(feature.start, feature.end),
            measurementSystem,
          ),
          color: feature.type == FeatureType.door
              ? '#F57C00'
              : '#C2185B',
          offset: 11,
        );

        svg.writeln('</g>');
      }
    }

    svg
      ..writeln(
        '<g font-family="Helvetica" font-size="10" fill="#374151">',
      )
      ..writeln(
        '<line x1="42" y1="476" x2="66" y2="476" '
        'stroke="#1565C0" stroke-width="3"/>',
      )
      ..writeln('<text x="72" y="480">Pared</text>')
      ..writeln(
        '<line x1="126" y1="476" x2="150" y2="476" '
        'stroke="#F57C00" stroke-width="3"/>',
      )
      ..writeln('<text x="156" y="480">Puerta</text>')
      ..writeln(
        '<line x1="214" y1="476" x2="238" y2="476" '
        'stroke="#C2185B" stroke-width="3"/>',
      )
      ..writeln('<text x="244" y="480">Ventana</text>')
      ..writeln('</g>')
      ..writeln('</svg>');

    return svg.toString();
  }

  static void _writeDoorSvg(
    StringBuffer svg,
    WallFeature feature,
    _SvgPoint start,
    _SvgPoint end,
  ) {
    final hinge = feature.doorHingeSide == DoorHingeSide.start
        ? start
        : end;
    final closedEnd = feature.doorHingeSide == DoorHingeSide.start
        ? end
        : start;
    final dx = closedEnd.x - hinge.x;
    final dy = closedEnd.y - hinge.y;
    final direction = feature.doorSwingSide == DoorSwingSide.left
        ? -1.0
        : 1.0;
    final openEnd = _SvgPoint(
      hinge.x + (direction * -dy),
      hinge.y + (direction * dx),
    );
    final radius = math.sqrt((dx * dx) + (dy * dy));
    final sweep = direction > 0 ? 1 : 0;

    svg
      ..writeln(
        '<line x1="${_svgNumber(start.x)}" y1="${_svgNumber(start.y)}" '
        'x2="${_svgNumber(end.x)}" y2="${_svgNumber(end.y)}" '
        'stroke="white" stroke-width="8"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(hinge.x)}" '
        'y1="${_svgNumber(hinge.y)}" '
        'x2="${_svgNumber(openEnd.x)}" '
        'y2="${_svgNumber(openEnd.y)}" '
        'stroke="#F57C00" stroke-width="2.5"/>',
      )
      ..writeln(
        '<path d="M ${_svgNumber(closedEnd.x)} ${_svgNumber(closedEnd.y)} '
        'A ${_svgNumber(radius)} ${_svgNumber(radius)} 0 0 $sweep '
        '${_svgNumber(openEnd.x)} ${_svgNumber(openEnd.y)}" '
        'fill="none" stroke="#F57C00" stroke-width="1.4" '
        'stroke-dasharray="4 3"/>',
      )
      ..writeln(
        '<circle cx="${_svgNumber(hinge.x)}" '
        'cy="${_svgNumber(hinge.y)}" r="2.4" fill="#F57C00"/>',
      );
  }

  static void _writeWindowSvg(
    StringBuffer svg,
    _SvgPoint start,
    _SvgPoint end,
  ) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final length = math.max(math.sqrt((dx * dx) + (dy * dy)), 0.01);
    final normalX = (-dy / length) * 2.4;
    final normalY = (dx / length) * 2.4;

    svg
      ..writeln(
        '<line x1="${_svgNumber(start.x)}" y1="${_svgNumber(start.y)}" '
        'x2="${_svgNumber(end.x)}" y2="${_svgNumber(end.y)}" '
        'stroke="white" stroke-width="8"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(start.x + normalX)}" '
        'y1="${_svgNumber(start.y + normalY)}" '
        'x2="${_svgNumber(end.x + normalX)}" '
        'y2="${_svgNumber(end.y + normalY)}" '
        'stroke="#C2185B" stroke-width="2"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(start.x - normalX)}" '
        'y1="${_svgNumber(start.y - normalY)}" '
        'x2="${_svgNumber(end.x - normalX)}" '
        'y2="${_svgNumber(end.y - normalY)}" '
        'stroke="#C2185B" stroke-width="2"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(start.x + normalX)}" '
        'y1="${_svgNumber(start.y + normalY)}" '
        'x2="${_svgNumber(start.x - normalX)}" '
        'y2="${_svgNumber(start.y - normalY)}" '
        'stroke="#C2185B" stroke-width="2"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(end.x + normalX)}" '
        'y1="${_svgNumber(end.y + normalY)}" '
        'x2="${_svgNumber(end.x - normalX)}" '
        'y2="${_svgNumber(end.y - normalY)}" '
        'stroke="#C2185B" stroke-width="2"/>',
      );
  }

  static void _writeDimensionSvg({
    required StringBuffer svg,
    required _SvgPoint start,
    required _SvgPoint end,
    required String label,
    required String color,
    required double offset,
    _SvgPoint? center,
  }) {
    final dx = end.x - start.x;
    final dy = end.y - start.y;
    final length = math.max(math.sqrt((dx * dx) + (dy * dy)), 0.01);
    var normalX = -dy / length;
    var normalY = dx / length;
    final middleX = (start.x + end.x) / 2.0;
    final middleY = (start.y + end.y) / 2.0;

    if (center != null) {
      final towardCenterX = center.x - middleX;
      final towardCenterY = center.y - middleY;
      if ((normalX * towardCenterX) + (normalY * towardCenterY) > 0) {
        normalX = -normalX;
        normalY = -normalY;
      }
    }

    final labelX = middleX + (normalX * offset);
    final labelY = middleY + (normalY * offset);
    final labelWidth = math.max(28.0, (label.length * 5.6) + 8.0);

    svg
      ..writeln(
        '<line x1="${_svgNumber(start.x)}" y1="${_svgNumber(start.y)}" '
        'x2="${_svgNumber(start.x + (normalX * (offset - 3)))}" '
        'y2="${_svgNumber(start.y + (normalY * (offset - 3)))}" '
        'stroke="$color" stroke-width="0.7"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(end.x)}" y1="${_svgNumber(end.y)}" '
        'x2="${_svgNumber(end.x + (normalX * (offset - 3)))}" '
        'y2="${_svgNumber(end.y + (normalY * (offset - 3)))}" '
        'stroke="$color" stroke-width="0.7"/>',
      )
      ..writeln(
        '<rect x="${_svgNumber(labelX - (labelWidth / 2))}" '
        'y="${_svgNumber(labelY - 7)}" width="${_svgNumber(labelWidth)}" '
        'height="12" rx="2" fill="white" fill-opacity="0.9"/>',
      )
      ..writeln(
        '<text x="${_svgNumber(labelX)}" y="${_svgNumber(labelY + 2)}" '
        'text-anchor="middle" font-family="Helvetica" font-size="8.5" '
        'font-weight="bold" fill="$color">${_escapeSvg(label)}</text>',
      );
  }

  static String _wallKey(ARPoint first, ARPoint second) {
    String pointKey(ARPoint point) =>
        '${point.x.toStringAsFixed(4)}:${point.z.toStringAsFixed(4)}';
    final firstKey = pointKey(first);
    final secondKey = pointKey(second);
    return firstKey.compareTo(secondKey) <= 0
        ? '$firstKey|$secondKey'
        : '$secondKey|$firstKey';
  }

  static String _formatCompactLength(
    double meters,
    MeasurementSystem measurementSystem,
  ) {
    return MeasurementUnits.formatLength(
      meters,
      measurementSystem,
      metersLabel: 'm',
      feetLabel: 'ft',
      inchesLabel: 'in',
      decimalSeparator: ',',
    );
  }

  static String _svgNumber(double value) => value.toStringAsFixed(2);

  static String _escapeSvg(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
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
            ),          ),
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

class _SvgPoint {
  final double x;
  final double y;

  const _SvgPoint(this.x, this.y);
}