# Changelog — room_scanner_core

## 1.0.0

- Extracción inicial desde `room_scanner_ar` (monorepo `claude-room-scanner`).
- Modelos de dominio (`RoomModel`, `ARPoint`, `WallFeature`) y colecciones
  Isar (`IsarProject`, `IsarRoom`) con sus mapeadores.
- `GeometryService` y `SharedWallService`.
- `LocalDatabaseService`, ahora recibiendo el directorio de persistencia por
  parámetro en vez de resolverlo con `path_provider`.
- `PlanExportBuilder`, extraído de la parte pura de `ImportExportService`
  (construcción de JSON, nombre de archivo, SVG del plano y documento PDF).
- `MeasurementUnits` y `ScanValidator`.
