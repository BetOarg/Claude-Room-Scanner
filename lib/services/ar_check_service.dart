import 'package:flutter/material.dart';

import '../scanner/engine/scanner_capabilities.dart';
import '../scanner/services/device_capabilities_service.dart';
import '../screens/ar_scanner_screen.dart';
import '../screens/basic_scanner_screen.dart';

class ArCheckService {
  ArCheckService._();

  /// Selecciona automáticamente el mejor scanner disponible.
  ///
  /// Prioridad:
  ///
  /// 1. ARCore / ARKit
  /// 2. Cámara básica
  /// 3. Aviso de dispositivo no compatible
  static Future<void> abrirEscanerConValidacion(
    BuildContext context, {
    required String projectUuid,
    required String projectName,
  }) async {
    try {
      final capabilities =
          await DeviceCapabilitiesService.detect();

      if (!context.mounted) return;

      final Widget scannerScreen;

      if (capabilities.supportsAR) {
        scannerScreen = ARScannerScreen(
          projectUuid: projectUuid,
          projectName: projectName,
        );
      } else if (capabilities.supportsBasicScanner) {
        scannerScreen = BasicScannerScreen(
          projectUuid: projectUuid,
          projectName: projectName,
        );
      } else {
        _mostrarAvisoNoSoportado(
          context,
          capabilities,
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => scannerScreen,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;

      _mostrarAvisoNoSoportado(
        context,
        const ScannerCapabilities(),
      );
    }
  }

  static void _mostrarAvisoNoSoportado(
    BuildContext context,
    ScannerCapabilities capabilities,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Scanner no disponible',
                ),
              ),
            ],
          ),
          content: Text(
            capabilities.hasCamera
                ? 'La cámara está disponible, '
                  'pero no fue posible inicializar '
                  'el Scanner Básico.'
                : 'Este dispositivo no tiene una '
                  'cámara disponible para realizar '
                  'el escaneo.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child:
                  const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }
}