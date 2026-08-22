import 'package:room_scanner_core/room_scanner_core.dart';

/// Origen del punto capturado por Scanner Engine.
enum PointSource {
  ar,
  camera,
  manual,
  imported,
}

/// Punto normalizado del Scanner Engine.
///
/// Este modelo NO reemplaza todavía a [ARPoint].
/// Su función es desacoplar el motor de captura de ARCore/ARKit.
class ScannerPoint {
  final double x;
  final double y;
  final double z;

  /// Precisión estimada del punto en metros.
  ///
  /// Ejemplo:
  /// 0.01 = aproximadamente 1 cm
  /// 0.05 = aproximadamente 5 cm
  final double accuracy;

  final PointSource source;

  const ScannerPoint({
    required this.x,
    required this.y,
    required this.z,
    this.accuracy = 0.0,
    this.source = PointSource.manual,
  });

  /// Convierte el punto del Engine al modelo actualmente utilizado
  /// por RoomModel/ScannerProvider.
  ARPoint toARPoint() {
    return ARPoint(
      x: x,
      y: y,
      z: z,
    );
  }

  factory ScannerPoint.fromARPoint(
    ARPoint point, {
    double accuracy = 0.0,
  }) {
    return ScannerPoint(
      x: point.x,
      y: point.y,
      z: point.z,
      accuracy: accuracy,
      source: PointSource.ar,
    );
  }

  ScannerPoint copyWith({
    double? x,
    double? y,
    double? z,
    double? accuracy,
    PointSource? source,
  }) {
    return ScannerPoint(
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
      accuracy: accuracy ?? this.accuracy,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'z': z,
      'accuracy': accuracy,
      'source': source.name,
    };
  }

  factory ScannerPoint.fromJson(Map<String, dynamic> json) {
    return ScannerPoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      source: PointSource.values.firstWhere(
        (value) => value.name == json['source'],
        orElse: () => PointSource.manual,
      ),
    );
  }
}