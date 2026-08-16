import 'package:vector_math/vector_math_64.dart' as vector;

enum RoomType {
  // No cambiar el orden de los tipos históricos:
  // Isar los persiste por posición.
  living,
  cocina,
  bano,
  dormitorio,
  lavadero,
  pasillo,

  // Nuevos tipos agregados al final para conservar compatibilidad.
  comedor,
  comedorDiario,
  patio,
  hall,
  balcon,
  terraza,
  cochera,
  playroom,
}

extension RoomTypeDisplay on RoomType {
  String get displayName {
    switch (this) {
      case RoomType.living:
        return 'Living';
      case RoomType.cocina:
        return 'Cocina';
      case RoomType.bano:
        return 'Baño';
      case RoomType.dormitorio:
        return 'Dormitorio';
      case RoomType.lavadero:
        return 'Lavadero';
      case RoomType.pasillo:
        return 'Pasillo';
      case RoomType.comedor:
        return 'Comedor';
      case RoomType.comedorDiario:
        return 'Comedor diario';
      case RoomType.patio:
        return 'Patio';
      case RoomType.hall:
        return 'Hall';
      case RoomType.balcon:
        return 'Balcón';
      case RoomType.terraza:
        return 'Terraza';
      case RoomType.cochera:
        return 'Cochera';
      case RoomType.playroom:
        return 'Playroom';
    }
  }
}

enum FeatureType {
  door,
  window,
}

/// Punto en el espacio 3D.
class ARPoint {
  final double x;
  final double y;
  final double z;

  ARPoint({
    required this.x,
    required this.y,
    required this.z,
  });

  factory ARPoint.fromVector3(
    vector.Vector3 v,
  ) {
    return ARPoint(
      x: v.x,
      y: v.y,
      z: v.z,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'z': z,
    };
  }

  factory ARPoint.fromJson(
    Map<String, dynamic> json,
  ) {
    return ARPoint(
      x: (json['x'] as num)
          .toDouble(),
      y: (json['y'] as num)
          .toDouble(),
      z: (json['z'] as num)
          .toDouble(),
    );
  }
}

/// Representa una puerta o ventana sobre una pared.
class WallFeature {
  final String id;
  final FeatureType type;
  final ARPoint start;
  final ARPoint end;

  WallFeature({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'start': start.toJson(),
      'end': end.toJson(),
    };
  }

  factory WallFeature.fromJson(
    Map<String, dynamic> json,
  ) {
    return WallFeature(
      id: json['id'] as String,
      type:
          FeatureType.values.firstWhere(
        (e) =>
            e.name ==
            json['type'],
      ),
      start: ARPoint.fromJson(
        json['start']
            as Map<String, dynamic>,
      ),
      end: ARPoint.fromJson(
        json['end']
            as Map<String, dynamic>,
      ),
    );
  }
}

/// Habitación con su contorno y sus elementos.
class RoomModel {
  final String id;
  final String name;
  final RoomType type;
  final List<ARPoint> points;
  final List<WallFeature> features;
  final bool isClosed;

  RoomModel({
    required this.id,
    required this.name,
    required this.type,
    required this.points,
    this.features = const [],
    this.isClosed = false,
  });

  RoomModel copyWith({
    String? id,
    String? name,
    RoomType? type,
    List<ARPoint>? points,
    List<WallFeature>? features,
    bool? isClosed,
  }) {
    return RoomModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      points: points ?? this.points,
      features:
          features ?? this.features,
      isClosed:
          isClosed ?? this.isClosed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'points': points
          .map(
            (p) => p.toJson(),
          )
          .toList(),
      'features': features
          .map(
            (f) => f.toJson(),
          )
          .toList(),
      'isClosed': isClosed,
    };
  }

  factory RoomModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return RoomModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type:
          RoomType.values.firstWhere(
        (e) =>
            e.name ==
            json['type'],
        orElse: () =>
            RoomType.living,
      ),
      points:
          (json['points'] as List)
              .map(
                (p) => ARPoint.fromJson(
                  p as Map<
                      String,
                      dynamic>,
                ),
              )
              .toList(),
      features:
          json['features'] != null
              ? (json['features'] as List)
                  .map(
                    (f) =>
                        WallFeature.fromJson(
                      f as Map<
                          String,
                          dynamic>,
                    ),
                  )
                  .toList()
              : [],
      isClosed:
          json['isClosed']
              as bool? ??
          false,
    );
  }
}