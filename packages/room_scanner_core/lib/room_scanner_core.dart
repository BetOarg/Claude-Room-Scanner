/// Núcleo de dominio de Claude Room Scanner.
///
/// Modelos de datos (incluidas las colecciones Isar), motores de geometría
/// (ambientes y paredes compartidas), utilidades de medición/validación y
/// construcción de exportaciones JSON/PDF. Sin UI, sin widgets, sin
/// controladores de hardware: es un paquete Dart puro, consumido por
/// `room_scanner_app`.
library room_scanner_core;

export 'src/models/room_model.dart';
export 'src/models/isar_models.dart';

export 'src/geometry/geometry_service.dart';
export 'src/geometry/shared_wall_service.dart';

export 'src/persistence/local_database_service.dart';

export 'src/export/plan_export_builder.dart';

export 'src/utils/measurement_units.dart';
export 'src/utils/scan_validator.dart';
