import '../models/scanner_mode.dart';
import 'scanner_capabilities.dart';

class ScannerModeResolver {
  const ScannerModeResolver();

  ScannerMode resolve(ScannerCapabilities capabilities) {
    if (capabilities.supportsAR) {
      return ScannerMode.ar;
    }

    if (capabilities.supportsBasicScanner) {
      return ScannerMode.basic;
    }

    return ScannerMode.manual;
  }
}