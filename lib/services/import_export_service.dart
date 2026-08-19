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

  /// Construye un nombre seguro para guardar o compartir el PDF desde el
  /// diálogo nativo de Android o iOS.
  static String buildPdfFileName(String projectName) {
    final jsonFileName = buildJsonFileName(projectName);
    final baseName = jsonFileName.substring(
      0,
      jsonFileName.length - '.json'.length,
    );
    return '$baseName.pdf';
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
    final labels = _PdfLabels.forLanguage(Platform.localeName);
    final pdfFileName = buildPdfFileName(projectName);
    final pdf = pw.Document(
      title: projectName.trim().isEmpty ? 'Plano 2D' : projectName.trim(),
      author: 'Claude Room Scanner',
      creator: 'Claude Room Scanner',
      subject: labels.documentSubject,
      keywords: labels.documentKeywords,
    );

    pdf.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text('${labels.architecturalPlan}: $projectName'),
            ),
            pw.Text(
              '${labels.surveyedRooms}: ${rooms.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 16),
            if (rooms.any((room) => room.points.length >= 2)) ...[
              pw.Text(
                labels.generalPlan,
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
                    languageCode: labels.languageCode,
                  ),
                ),
              ),
              pw.SizedBox(height: 18),
            ],
            ...rooms.map(
              (room) => _buildRoomReport(
                room,
                measurementSystem,
                labels,
              ),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      name: pdfFileName,
      onLayout: (format) async => pdf.save(),
    );
  }

  /// Construye el dibujo vectorial del plano completo para incorporarlo al
  /// PDF. Mantiene las coordenadas globales y ajusta la escala a la página.
  static String buildFloorPlanSvg(
    List<RoomModel> rooms,
    MeasurementSystem measurementSystem, {
    String languageCode = 'es',
  }) {
    final labels = _PdfLabels.forLanguage(languageCode);
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
    final labelLayout = _SvgLabelLayout(
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      bottomReserved: 34,
    );

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
      final displayArea = measurementSystem == MeasurementSystem.metric
          ? area
          : MeasurementUnits.squareMetersToSquareFeet(area);
      final areaText = displayArea.toStringAsFixed(2).replaceAll(
            '.',
            labels.decimalSeparator,
          );
      final areaUnit = measurementSystem == MeasurementSystem.metric
          ? 'm²'
          : 'ft²';

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
          '${_escapeSvg(labels.roomType(room.type))} · '
          '$areaText $areaUnit</text>',
        );

      for (var index = 0; index < room.points.length; index++) {
        final first = room.points[index];
        final second = room.points[(index + 1) % room.points.length];
        if (!drawnWallKeys.add(_wallKey(first, second))) {
          continue;
        }

        _writeDimensionSvg(
          svg: svg,
          layout: labelLayout,
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
          layout: labelLayout,
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
      ..writeln('<text x="72" y="480">${labels.wall}</text>')
      ..writeln(
        '<line x1="126" y1="476" x2="150" y2="476" '
        'stroke="#F57C00" stroke-width="3"/>',
      )
      ..writeln('<text x="156" y="480">${labels.door}</text>')
      ..writeln(
        '<line x1="214" y1="476" x2="238" y2="476" '
        'stroke="#C2185B" stroke-width="3"/>',
      )
      ..writeln('<text x="244" y="480">${labels.window}</text>')
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
    required _SvgLabelLayout layout,
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

    final labelWidth = math.max(28.0, (label.length * 5.6) + 8.0);
    final placement = layout.place(
      middle: _SvgPoint(middleX, middleY),
      normal: _SvgPoint(normalX, normalY),
      preferredOffset: offset,
      width: labelWidth,
      height: 12,
    );
    final labelX = placement.center.x;
    final labelY = placement.center.y;
    final actualOffset =
        ((labelX - middleX) * normalX) +
        ((labelY - middleY) * normalY);
    final extensionOffset = actualOffset.abs() < 4
        ? 4.0
        : actualOffset - (actualOffset.sign * 3.0);

    svg
      ..writeln(
        '<line x1="${_svgNumber(start.x)}" y1="${_svgNumber(start.y)}" '
        'x2="${_svgNumber(start.x + (normalX * extensionOffset))}" '
        'y2="${_svgNumber(start.y + (normalY * extensionOffset))}" '
        'stroke="$color" stroke-width="0.7"/>',
      )
      ..writeln(
        '<line x1="${_svgNumber(end.x)}" y1="${_svgNumber(end.y)}" '
        'x2="${_svgNumber(end.x + (normalX * extensionOffset))}" '
        'y2="${_svgNumber(end.y + (normalY * extensionOffset))}" '
        'stroke="$color" stroke-width="0.7"/>',
      )
      ..writeln(
        '<rect x="${_svgNumber(labelX - (labelWidth / 2))}" '
        'y="${_svgNumber(labelY - 7)}" width="${_svgNumber(labelWidth)}" '
        'height="12" rx="2" fill="white" fill-opacity="0.9"/>',
      )
      ..writeln(
        '<text data-dimension-label="${_escapeSvg(label)}" '
        'data-layout-index="${placement.index}" '
        'x="${_svgNumber(labelX)}" y="${_svgNumber(labelY + 2)}" '
        'text-anchor="middle" font-family="Helvetica" font-size="8.5" '
        'font-weight="bold" fill="$color">${_escapeSvg(label)}</text>',      );
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
    _PdfLabels labels,
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
            '${room.name} · ${labels.roomType(room.type)}',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            '${labels.area}: '
            '${_formatArea(area, measurementSystem, labels)} · '
            '${labels.perimeter}: '
            '${_formatLength(perimeter, measurementSystem, labels)}',
          ),
          pw.Text('${labels.registeredCorners}: ${room.points.length}'),
          pw.SizedBox(height: 8),
          pw.Text(
            labels.doorsAndWindows,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          if (room.features.isEmpty)
            pw.Text(labels.noOpenings)
          else
            ...room.features.map(
              (feature) => pw.Bullet(
                text: _featureDescription(
                  feature,
                  measurementSystem,
                  labels,
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
    _PdfLabels labels,
  ) {
    final width = GeometryService.calculateDistance(
      feature.start,
      feature.end,
    );
    final type = feature.type == FeatureType.door
        ? labels.door
        : labels.window;
    final parts = <String>[
      '$type: ${_formatLength(width, measurementSystem, labels)} '
          '${labels.wide}',
      '${_formatLength(feature.openingHeightMeters, measurementSystem, labels)} '
          '${labels.high}',
    ];

    if (feature.type == FeatureType.window) {
      parts.add(
        '${_formatLength(feature.sillHeightMeters, measurementSystem, labels)} '
        '${labels.fromFloor}',
      );
      parts.add(
        width >= feature.openingHeightMeters
            ? labels.horizontalOrientation
            : labels.verticalOrientation,
      );
    }

    return parts.join(' · ');
  }

  static String _formatLength(
    double meters,
    MeasurementSystem measurementSystem,
    _PdfLabels labels,
  ) {
    return MeasurementUnits.formatLength(
      meters,
      measurementSystem,
      metersLabel: labels.meters,
      feetLabel: labels.feet,
      inchesLabel: labels.inches,
      decimalSeparator: labels.decimalSeparator,
    );
  }

  static String _formatArea(
    double squareMeters,
    MeasurementSystem measurementSystem,
    _PdfLabels labels,
  ) {
    if (measurementSystem == MeasurementSystem.metric) {
      final value = squareMeters.toStringAsFixed(2).replaceAll(
            '.',
            labels.decimalSeparator,
          );
      return '$value ${labels.squareMeters}';
    }

    final squareFeet =
        MeasurementUnits.squareMetersToSquareFeet(squareMeters);
    final value = squareFeet.toStringAsFixed(2).replaceAll(
          '.',
          labels.decimalSeparator,
        );
    return '$value ${labels.squareFeet}';
  }
}

class _PdfLabels {
  final String languageCode;

  const _PdfLabels._(this.languageCode);

  factory _PdfLabels.forLanguage(String languageCode) {
    return _PdfLabels._(
      languageCode.toLowerCase().startsWith('en') ? 'en' : 'es',
    );
  }

  bool get isEnglish => languageCode == 'en';
  String get decimalSeparator => isEnglish ? '.' : ',';
  String get architecturalPlan =>
      isEnglish ? 'Architectural plan' : 'Plano arquitectónico';
  String get surveyedRooms =>
      isEnglish ? 'Surveyed rooms' : 'Ambientes relevados';
  String get generalPlan => isEnglish ? 'General plan' : 'Plano general';
  String get area => isEnglish ? 'Area' : 'Superficie';
  String get perimeter => isEnglish ? 'Perimeter' : 'Perímetro';
  String get registeredCorners =>
      isEnglish ? 'Registered corners' : 'Esquinas registradas';
  String get doorsAndWindows =>
      isEnglish ? 'Doors and windows' : 'Puertas y ventanas';
  String get noOpenings => isEnglish
      ? 'There are no registered openings.'
      : 'No hay aberturas registradas.';
  String get wall => isEnglish ? 'Wall' : 'Pared';
  String get door => isEnglish ? 'Door' : 'Puerta';
  String get window => isEnglish ? 'Window' : 'Ventana';
  String get wide => isEnglish ? 'wide' : 'de ancho';
  String get high => isEnglish ? 'high' : 'de alto';
  String get fromFloor => isEnglish ? 'from the floor' : 'desde el piso';
  String get horizontalOrientation => isEnglish
      ? 'horizontal orientation'
      : 'orientación horizontal';
  String get verticalOrientation => isEnglish
      ? 'vertical orientation'
      : 'orientación vertical';
  String get meters => isEnglish ? 'meters' : 'metros';
  String get feet => isEnglish ? 'feet' : 'pies';
  String get inches => isEnglish ? 'inches' : 'pulgadas';
  String get squareMeters =>
      isEnglish ? 'square meters' : 'metros cuadrados';
  String get squareFeet =>
      isEnglish ? 'square feet' : 'pies cuadrados';
  String get documentSubject => isEnglish
      ? 'Two-dimensional architectural plan'
      : 'Plano arquitectónico 2D';
  String get documentKeywords => isEnglish
      ? 'plan, rooms, doors, windows, dimensions'
      : 'plano, ambientes, puertas, ventanas, cotas';

  String roomType(RoomType type) {
    if (!isEnglish) {
      return type.displayName;
    }

    switch (type) {
      case RoomType.living:
        return 'Living room';
      case RoomType.cocina:
        return 'Kitchen';
      case RoomType.bano:
        return 'Bathroom';
      case RoomType.dormitorio:
        return 'Bedroom';
      case RoomType.lavadero:
        return 'Laundry room';
      case RoomType.pasillo:
        return 'Hallway';
      case RoomType.comedor:
        return 'Dining room';
      case RoomType.comedorDiario:
        return 'Breakfast room';
      case RoomType.patio:
        return 'Patio';
      case RoomType.hall:
        return 'Hall';
      case RoomType.balcon:
        return 'Balcony';
      case RoomType.terraza:
        return 'Terrace';
      case RoomType.cochera:
        return 'Garage';
      case RoomType.playroom:
        return 'Playroom';
    }
  }
}

class _SvgPoint {
  final double x;
  final double y;

  const _SvgPoint(this.x, this.y);
}

class _SvgLabelPlacement {
  final _SvgPoint center;
  final int index;

  const _SvgLabelPlacement({
    required this.center,
    required this.index,
  });
}

class _SvgLabelRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const _SvgLabelRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  bool overlaps(_SvgLabelRect other) {
    const separation = 2.0;
    return left < other.right + separation &&
        right > other.left - separation &&
        top < other.bottom + separation &&
        bottom > other.top - separation;
  }
}

class _SvgLabelLayout {
  final double canvasWidth;
  final double canvasHeight;
  final double bottomReserved;
  final List<_SvgLabelRect> _occupied = [];
  int _nextIndex = 0;

  _SvgLabelLayout({
    required this.canvasWidth,
    required this.canvasHeight,
    required this.bottomReserved,
  });

  _SvgLabelPlacement place({
    required _SvgPoint middle,
    required _SvgPoint normal,
    required double preferredOffset,
    required double width,
    required double height,
  }) {
    final offsets = <double>[
      preferredOffset,
      -preferredOffset,
      preferredOffset + 14,
      -preferredOffset - 14,
      preferredOffset + 28,
      -preferredOffset - 28,
      preferredOffset + 42,
      -preferredOffset - 42,
    ];

    _SvgPoint? selectedCenter;
    _SvgLabelRect? selectedRect;

    for (final offset in offsets) {
      final candidateCenter = _clampCenter(
        _SvgPoint(
          middle.x + (normal.x * offset),
          middle.y + (normal.y * offset),
        ),
        width,
        height,
      );
      final candidateRect = _rectFor(candidateCenter, width, height);

      if (_occupied.every((rect) => !rect.overlaps(candidateRect))) {
        selectedCenter = candidateCenter;
        selectedRect = candidateRect;
        break;
      }
    }

    selectedCenter ??= _clampCenter(
      _SvgPoint(
        middle.x + (normal.x * offsets.last),
        middle.y + (normal.y * offsets.last),
      ),
      width,
      height,
    );
    selectedRect ??= _rectFor(selectedCenter, width, height);
    _occupied.add(selectedRect);

    return _SvgLabelPlacement(
      center: selectedCenter,
      index: _nextIndex++,
    );
  }

  _SvgPoint _clampCenter(
    _SvgPoint center,
    double width,
    double height,
  ) {
    const margin = 3.0;
    final halfWidth = width / 2.0;
    final halfHeight = height / 2.0;
    return _SvgPoint(
      center.x.clamp(
        margin + halfWidth,
        canvasWidth - margin - halfWidth,
      ).toDouble(),
      center.y.clamp(
        margin + halfHeight,
        canvasHeight - bottomReserved - halfHeight,
      ).toDouble(),
    );
  }

  _SvgLabelRect _rectFor(
    _SvgPoint center,
    double width,
    double height,
  ) {
    return _SvgLabelRect(
      left: center.x - (width / 2.0),
      top: center.y - (height / 2.0),
      right: center.x + (width / 2.0),
      bottom: center.y + (height / 2.0),
    );
  }
}