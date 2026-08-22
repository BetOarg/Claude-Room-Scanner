import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:room_scanner_core/room_scanner_core.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/floor_plan_provider.dart';

/// Capa de I/O de exportación/importación: resuelve directorios, selecciona
/// archivos, comparte e imprime. Todo el cálculo (JSON, nombre de archivo,
/// SVG del plano, armado del PDF) vive en
/// `PlanExportBuilder` (`room_scanner_core`) y no se duplica acá.
class ImportExportService {
  /// Exporta el proyecto como un archivo JSON real y abre el menú para
  /// compartirlo o guardarlo en el dispositivo.
  static Future<void> exportToJson(
    List<RoomModel> rooms,
    String projectName,
  ) async {
    final data = PlanExportBuilder.buildJsonData(rooms, projectName);
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    final fileName = PlanExportBuilder.buildJsonFileName(projectName);
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
      if (fileContent == null) {
        return false;
      }

      final parsed = PlanExportBuilder.parseProjectJson(fileContent);
      if (parsed == null) {
        return false;
      }

      await provider.loadExistingRooms(parsed.rooms, parsed.projectName);
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
    final pdfFileName = PlanExportBuilder.buildPdfFileName(projectName);
    final pdf = PlanExportBuilder.buildPdfDocument(
      rooms,
      projectName,
      measurementSystem,
      languageCode: Platform.localeName,
    );

    await Printing.layoutPdf(
      name: pdfFileName,
      onLayout: (format) async => pdf.save(),
    );
  }
}
