import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/room_model.dart';
import '../providers/floor_plan_provider.dart';

class ImportExportService {
  /// Exporta el proyecto a un archivo JSON y abre el menú para compartir
  static Future<void> exportToJson(List<RoomModel> rooms, String projectName) async {
    final data = {
      'projectName': projectName,
      'rooms': rooms.map((r) => r.toJson()).toList(),
    };
    final jsonString = jsonEncode(data);
    await Share.share(jsonString, subject: '$projectName - Plano 2D');
  }

  /// Importa un archivo JSON seleccionado desde el dispositivo
  static Future<bool> importFromJson(FloorPlanProvider provider) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.bytes != null) {
        final fileContent = utf8.decode(result.files.single.bytes!);
        final data = jsonDecode(fileContent) as Map<String, dynamic>;

        final projectName = data['projectName'] as String? ?? 'Proyecto Importado';
        final roomsData = data['rooms'] as List;
        final rooms = roomsData.map((r) => RoomModel.fromJson(r as Map<String, dynamic>)).toList();

        await provider.loadExistingRooms(rooms, projectName);
        return true;
      }
    } catch (e) {
      // Error al leer el archivo
    }
    return false;
  }

  /// Genera un PDF básico del plano y abre la vista previa/impresión
  static Future<void> exportToPdf(List<RoomModel> rooms, String projectName) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, // <-- Corregido para el paquete pdf
            children: [
              pw.Header(level: 0, child: pw.Text('Plano Arquitectónico: $projectName')),
              pw.SizedBox(height: 20),
              pw.Text('Resumen de Ambientes:'),
              pw.SizedBox(height: 10),
              ...rooms.map((room) => pw.Bullet(text: '${room.name}: ${room.points.length} vértices')),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }
}