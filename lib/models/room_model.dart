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
  other,
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
      case RoomType.other:
        return 'Otro espacio';
    }
  }
}

enum FeatureType {
  door,
  window,
}

/// Extremo de la puerta en el que se ubica la bisagra.
enum DoorHingeSide {
  start,
  end,
}

/// Lado hacia el que gira la hoja respecto de start → end.
enum DoorSwingSide {
  left,
  right,
}

/// Indica si la hoja abre hacia el interior o el exterior de la vivienda.
enum DoorOpeningDirection {
  interior,
  exterior,
}

/// Lado de la abertura en el que se encuentra el ambiente por escanear.
///
/// Se interpreta observando la abertura desde [WallFeature.start] hacia
/// [WallFeature.end]. Esta convención permite reconstruir la orientación
/// elegida aunque el proyecto se cierre y vuelva a abrirse.
enum OpeningConnectionSide {
  left,
  right,
}

/// Extremo de la abertura desde el que comienza el nuevo relevamiento.
enum ContinuationStartEndpoint {
  start,
  end,
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
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
    );
  }
}

/// Representa una puerta o ventana sobre una pared.
///
/// Cuando la abertura se utiliza para continuar el escaneo, ambos ambientes
/// conservan el mismo [id]. [connectedRoomId] identifica el ambiente situado
/// al otro lado y [connectionSide] registra el lado elegido por el usuario.
class WallFeature {
  final String id;
  final FeatureType type;
  final ARPoint start;
  final ARPoint end;
  final String? connectedRoomId;
  final OpeningConnectionSide? connectionSide;
  final DoorHingeSide doorHingeSide;
  final DoorSwingSide doorSwingSide;
  final DoorOpeningDirection doorOpeningDirection;
  final double openingHeightMeters;
  final double sillHeightMeters;

  WallFeature({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    this.connectedRoomId,
    this.connectionSide,
    this.doorHingeSide = DoorHingeSide.start,
    this.doorSwingSide = DoorSwingSide.left,
    this.doorOpeningDirection = DoorOpeningDirection.interior,
    double? openingHeightMeters,
    double? sillHeightMeters,
  })  : openingHeightMeters = openingHeightMeters ??
            (type == FeatureType.door ? 2.10 : 1.20),
        sillHeightMeters = sillHeightMeters ??
            (type == FeatureType.door ? 0.0 : 0.90);

  bool get isConnected =>
      connectedRoomId != null && connectedRoomId!.trim().isNotEmpty;

  WallFeature copyWith({
    String? id,
    FeatureType? type,
    ARPoint? start,
    ARPoint? end,
    String? connectedRoomId,
    OpeningConnectionSide? connectionSide,
    DoorHingeSide? doorHingeSide,
    DoorSwingSide? doorSwingSide,
    DoorOpeningDirection? doorOpeningDirection,
    double? openingHeightMeters,
    double? sillHeightMeters,
  }) {
    return WallFeature(
      id: id ?? this.id,
      type: type ?? this.type,
      start: start ?? this.start,
      end: end ?? this.end,
      connectedRoomId: connectedRoomId ?? this.connectedRoomId,
      connectionSide: connectionSide ?? this.connectionSide,
      doorHingeSide: doorHingeSide ?? this.doorHingeSide,
      doorSwingSide: doorSwingSide ?? this.doorSwingSide,
      doorOpeningDirection:
          doorOpeningDirection ?? this.doorOpeningDirection,
      openingHeightMeters:
          openingHeightMeters ?? this.openingHeightMeters,
      sillHeightMeters: sillHeightMeters ?? this.sillHeightMeters,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'start': start.toJson(),
      'end': end.toJson(),
      if (connectedRoomId != null)
        'connectedRoomId': connectedRoomId,
      if (connectionSide != null)
        'connectionSide': connectionSide!.name,
      'doorHingeSide': doorHingeSide.name,
      'doorSwingSide': doorSwingSide.name,
      'doorOpeningDirection': doorOpeningDirection.name,
      'openingHeightMeters': openingHeightMeters,
      'sillHeightMeters': sillHeightMeters,
    };
  }

  factory WallFeature.fromJson(
    Map<String, dynamic> json,
  ) {
    final sideName = json['connectionSide'] as String?;
    final hingeName = json['doorHingeSide'] as String?;
    final swingName = json['doorSwingSide'] as String?;
    final openingDirectionName =
        json['doorOpeningDirection'] as String?;

    OpeningConnectionSide? side;

    if (sideName != null) {
      for (final candidate in OpeningConnectionSide.values) {
        if (candidate.name == sideName) {
          side = candidate;
          break;
        }
      }
    }

    return WallFeature(
      id: json['id'] as String,
      type: FeatureType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      start: ARPoint.fromJson(
        json['start'] as Map<String, dynamic>,
      ),
      end: ARPoint.fromJson(
        json['end'] as Map<String, dynamic>,
      ),
      connectedRoomId: json['connectedRoomId'] as String?,
      connectionSide: side,
      doorHingeSide: DoorHingeSide.values.firstWhere(
        (candidate) => candidate.name == hingeName,
        orElse: () => DoorHingeSide.start,
      ),
      doorSwingSide: DoorSwingSide.values.firstWhere(
        (candidate) => candidate.name == swingName,
        orElse: () => DoorSwingSide.left,
      ),
      doorOpeningDirection: DoorOpeningDirection.values.firstWhere(
        (candidate) => candidate.name == openingDirectionName,
        orElse: () => DoorOpeningDirection.interior,
      ),
      openingHeightMeters:
          (json['openingHeightMeters'] as num?)?.toDouble(),
      sillHeightMeters:
          (json['sillHeightMeters'] as num?)?.toDouble(),
    );
  }
}

/// Referencia global utilizada para continuar un escaneo desde una abertura.
///
/// Esta clase es independiente del tipo de scanner. El plano 2D la crea y
/// [ArCheckService] la entrega al Basic Scanner o al scanner AR disponible.
/// En Basic Scanner sus extremos globales permiten iniciar el ambiente ya
/// alineado. En ARCore/ARKit se conservan como destino global mientras el
/// usuario vuelve a marcar ambos extremos en la nueva sesión AR.
class ScanContinuationReference {
  final String sourceRoomId;
  final String featureId;
  final FeatureType featureType;
  final ARPoint globalStart;
  final ARPoint globalEnd;
  final OpeningConnectionSide side;
  final ContinuationStartEndpoint startEndpoint;

  const ScanContinuationReference({
    required this.sourceRoomId,
    required this.featureId,
    required this.featureType,
    required this.globalStart,
    required this.globalEnd,
    required this.side,
    required this.startEndpoint,
  });

  factory ScanContinuationReference.fromFeature({
    required String sourceRoomId,
    required WallFeature feature,
    required OpeningConnectionSide side,
    required ContinuationStartEndpoint startEndpoint,
  }) {
    return ScanContinuationReference(
      sourceRoomId: sourceRoomId,
      featureId: feature.id,
      featureType: feature.type,
      globalStart: feature.start,
      globalEnd: feature.end,
      side: side,
      startEndpoint: startEndpoint,
    );
  }

  ARPoint get midpoint {
    return ARPoint(
      x: (globalStart.x + globalEnd.x) / 2.0,
      y: (globalStart.y + globalEnd.y) / 2.0,
      z: (globalStart.z + globalEnd.z) / 2.0,
    );
  }

  /// Punto global que se utiliza como origen local del nuevo escaneo.
  ARPoint get origin =>
      startEndpoint == ContinuationStartEndpoint.start
          ? globalStart
          : globalEnd;

  double get width {
    final dx = globalEnd.x - globalStart.x;
    final dy = globalEnd.y - globalStart.y;
    final dz = globalEnd.z - globalStart.z;

    return vector.Vector3(dx, dy, dz).length;
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
      features: features ?? this.features,
      isClosed: isClosed ?? this.isClosed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'points': points.map((p) => p.toJson()).toList(),
      'features': features.map((f) => f.toJson()).toList(),
      'isClosed': isClosed,
    };
  }

  factory RoomModel.fromJson(
    Map<String, dynamic> json,
  ) {
    return RoomModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: RoomType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RoomType.living,
      ),
      points: (json['points'] as List)
          .map(
            (p) => ARPoint.fromJson(
              p as Map<String, dynamic>,
            ),
          )
          .toList(),
      features: json['features'] != null
          ? (json['features'] as List)
              .map(
                (f) => WallFeature.fromJson(
                  f as Map<String, dynamic>,
                ),
              )
              .toList()
          : [],
      isClosed: json['isClosed'] as bool? ?? false,
    );
  }
}