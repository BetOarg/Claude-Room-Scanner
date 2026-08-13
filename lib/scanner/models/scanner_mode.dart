/// Modos de captura disponibles en Scanner Engine.
///
/// AR:
/// Utiliza ARCore en Android o ARKit en iOS.
///
/// BASIC:
/// Utiliza cámara, sensores y calibración sin depender de AR.
///
/// MANUAL:
/// Permite introducir y corregir medidas manualmente.
enum ScannerMode {
  ar,
  basic,
  manual,
}