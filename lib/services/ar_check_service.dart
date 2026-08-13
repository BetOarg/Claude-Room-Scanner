import 'dart:io';

import 'package:flutter/material.dart';

class ArCheckService {
  /// Valida que la aplicación esté ejecutándose en una plataforma
  /// compatible con el módulo AR y posteriormente abre el escáner.
  ///
  /// La compatibilidad específica con ARCore/ARKit se valida durante
  /// la inicialización de ARView.
  static Future<void> abrirEscanerConValidacion(
    BuildContext context, {
    required Widget pantallaEscaneoAR,
  }) async {
    try {
      final plataformaCompatible = Platform.isAndroid || Platform.isIOS;

      if (!context.mounted) return;

      if (plataformaCompatible) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => pantallaEscaneoAR,
          ),
        );
      } else {
        _mostrarAvisoNoSoportado(context);
      }
    } catch (_) {
      if (!context.mounted) return;

      _mostrarAvisoNoSoportado(context);
    }
  }

  /// Diálogo mostrado cuando la plataforma no puede ejecutar
  /// el módulo AR de la aplicación.
  static void _mostrarAvisoNoSoportado(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange,
                size: 28,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Realidad Aumentada no disponible',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'Este dispositivo o plataforma no puede ejecutar el módulo '
            'de Realidad Aumentada.\n\n'
            'En Android se requiere compatibilidad con ARCore y en iOS '
            'compatibilidad con ARKit.\n\n'
            'También puedes utilizar la opción '
            '"Dibujar Manual (2D)" para crear tu plano.',
            style: TextStyle(
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }
}