import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Servicio de comunicación entre Flutter y el módulo nativo RoomPlan de iOS
/// (`ios/Runner/RoomPlanBridge.swift`, registrado en `AppDelegate.swift`).
///
/// NOTA: no hay un módulo nativo Android equivalente (RoomPlan es una API
/// exclusiva de Apple/LiDAR), así que en Android este canal no está
/// registrado a propósito. Antes eso hacía que cualquier llamada lanzara una
/// `MissingPluginException` sin capturar (el `catch` original solo atrapaba
/// `PlatformException`, que es un tipo distinto), tanto en Android como en
/// cualquier iOS donde el canal no estuviera registrado — que era el caso en
/// los dos, porque `AppDelegate.swift` nunca llegó a registrar el bridge.
/// Ahora se captura cualquier excepción y se degrada de forma controlada.
class RoomPlanService {
  static const MethodChannel _channel = MethodChannel('com.example.roomplan');

  /// Verifica si el dispositivo cuenta con soporte para RoomPlan (iOS 16+ y sensor LiDAR).
  static Future<bool> isSupported() async {
    try {
      final bool supported = await _channel.invokeMethod('isSupported');
      return supported;
    } catch (e) {
      debugPrint('RoomPlan no disponible en esta plataforma/dispositivo: $e');
      return false;
    }
  }

  /// Inicia el flujo de escaneo nativo de RoomPlan y retorna el Map JSON procesado.
  static Future<Map<String, dynamic>?> startScanning() async {
    try {
      final String? jsonResult = await _channel.invokeMethod('startScanning');
      if (jsonResult != null && jsonResult.isNotEmpty) {
        return jsonDecode(jsonResult) as Map<String, dynamic>;
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('Error en escaneo RoomPlan: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Cancela manualmente la sesión de escaneo activa.
  static Future<void> stopScanning() async {
    try {
      await _channel.invokeMethod('stopScanning');
    } catch (e) {
      debugPrint('Error al detener escaneo: $e');
    }
  }
}