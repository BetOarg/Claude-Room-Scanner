import 'dart:math';
import '../models/room_model.dart';

class ValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? warningMessage;
  final ARPoint? suggestedPoint;

  const ValidationResult._({
    required this.isValid,
    this.errorMessage,
    this.warningMessage,
    this.suggestedPoint,
  });

  static const ValidationResult valid = ValidationResult._(isValid: true);

  static ValidationResult invalid(String message) =>
      ValidationResult._(isValid: false, errorMessage: message);

  static ValidationResult warning(String message, {ARPoint? suggestion}) =>
      ValidationResult._(isValid: true, warningMessage: message, suggestedPoint: suggestion);
}

/// Distancia euclidiana 2D (plano XZ, ignora altura) entre dos puntos.
double _distanceXZ(ARPoint a, ARPoint b) {
  final dx = b.x - a.x;
  final dz = b.z - a.z;
  return sqrt(dx * dx + dz * dz);
}

class ScanValidator {
  ScanValidator._();

  static const double minCornerDistance = 0.35;
  static const double duplicateThreshold = 0.20;
  static const double autoCloseThreshold = 0.60;
  static const double minArea = 0.5;

  /// Valida si un nuevo punto puede añadirse sin romper la geometría.
  static ValidationResult validateNewPoint(ARPoint candidate, List<ARPoint> existing) {
    final int count = existing.length;
    if (count == 0) return ValidationResult.valid;

    final last = existing.last;
    final double dxLast = candidate.x - last.x;
    final double dzLast = candidate.z - last.z;
    final double lastDistSq = (dxLast * dxLast) + (dzLast * dzLast);

    if (lastDistSq < (minCornerDistance * minCornerDistance)) {
      return ValidationResult.invalid(
        'Demasiado cerca del punto anterior (${sqrt(lastDistSq).toStringAsFixed(2)} m). Mínimo: $minCornerDistance m.',
      );
    }

    final double dupThreshSq = duplicateThreshold * duplicateThreshold;
    for (int i = 0; i < count - 1; i++) {
      final p = existing[i];
      final dx = candidate.x - p.x;
      final dz = candidate.z - p.z;
      if ((dx * dx + dz * dz) < dupThreshSq) {
        return ValidationResult.invalid('Punto duplicado detectado (cerca de esquina ${i + 1}).');
      }
    }

    if (count >= 3) {
      final double newMinX = min(last.x, candidate.x);
      final double newMaxX = max(last.x, candidate.x);
      final double newMinZ = min(last.z, candidate.z);
      final double newMaxZ = max(last.z, candidate.z);

      for (int i = 0; i < count - 2; i++) {
        final segA = existing[i];
        final segB = existing[i + 1];

        if (max(segA.x, segB.x) < newMinX || min(segA.x, segB.x) > newMaxX ||
            max(segA.z, segB.z) < newMinZ || min(segA.z, segB.z) > newMaxZ) {
          continue;
        }

        if (_segmentsIntersect(
          segA.x, segA.z, segB.x, segB.z,
          last.x, last.z, candidate.x, candidate.z,
        )) {
          return ValidationResult.invalid('Autointersección detectada: el tramo cruza una pared.');
        }
      }
    }

    final first = existing.first;
    final double dxFirst = candidate.x - first.x;
    final double dzFirst = candidate.z - first.z;
    final double distToFirstSq = (dxFirst * dxFirst) + (dzFirst * dzFirst);

    if (count >= 3 && distToFirstSq < (autoCloseThreshold * autoCloseThreshold)) {
      return ValidationResult.warning(
        'A ${sqrt(distToFirstSq).toStringAsFixed(2)} m del inicio. ¿Deseas cerrar el recinto?',
        suggestion: first,
      );
    }

    return ValidationResult.valid;
  }

  /// Valida que mover un vértice existente a [updated] no genere autointersección
  /// ni segmentos degenerados. [movingIndex] es el índice del vértice que se mueve.
  static ValidationResult validatePointUpdate(
    int movingIndex,
    ARPoint updated,
    List<ARPoint> points,
    bool isClosed,
  ) {
    final n = points.length;
    if (n < 3) return ValidationResult.valid;

    final prevIdx = (movingIndex - 1 + n) % n;
    final nextIdx = (movingIndex + 1) % n;

    // Distancia mínima a vecinos
    final distPrev = _distanceXZ(updated, points[prevIdx]);
    final distNext = _distanceXZ(updated, points[nextIdx]);
    if (distPrev < minCornerDistance) {
      return ValidationResult.invalid('Demasiado cerca del vértice anterior.');
    }
    if (distNext < minCornerDistance) {
      return ValidationResult.invalid('Demasiado cerca del vértice siguiente.');
    }

    // Verificar duplicados (excluyendo el propio índice movido)
    final dupThreshSq = duplicateThreshold * duplicateThreshold;
    for (int i = 0; i < n; i++) {
      if (i == movingIndex) continue;
      final dx = updated.x - points[i].x;
      final dz = updated.z - points[i].z;
      if ((dx * dx + dz * dz) < dupThreshSq) {
        return ValidationResult.invalid('Posición duplicada con vértice ${i + 1}.');
      }
    }

    // CORRECCIÓN PUNTO 10:
    // Se verifican TODOS los segmentos del polígono, sin omitir extremos.
    // En polígono abierto hay n-1 segmentos; en cerrado, n.
    // Solo se saltan los dos segmentos adyacentes al vértice movido.
    final int segmentCount = isClosed ? n : n - 1;

    for (int i = 0; i < segmentCount; i++) {
      final a1 = points[i];
      final a2 = points[(i + 1) % n];

      // Saltar segmentos adyacentes al vértice movido:
      // - i == movingIndex  → segmento (movingIndex → nextIdx)
      // - i == prevIdx      → segmento (prevIdx → movingIndex)
      if (i == movingIndex || i == prevIdx) continue;

      // Segmento prev -> updated
      if (_segmentsIntersect(
        points[prevIdx].x, points[prevIdx].z,
        updated.x, updated.z,
        a1.x, a1.z, a2.x, a2.z,
      )) {
        return ValidationResult.invalid('Movimiento genera autointersección.');
      }

      // Segmento updated -> next
      if (_segmentsIntersect(
        updated.x, updated.z,
        points[nextIdx].x, points[nextIdx].z,
        a1.x, a1.z, a2.x, a2.z,
      )) {
        return ValidationResult.invalid('Movimiento genera autointersección.');
      }
    }

    return ValidationResult.valid;
  }

  /// Algoritmo robusto de intersección de segmentos incluyendo colinealidad.
  static bool _segmentsIntersect(
    double p1x, double p1z, double p2x, double p2z,
    double p3x, double p3z, double p4x, double p4z,
  ) {
    final d1 = _ccw(p3x, p3z, p4x, p4z, p1x, p1z);
    final d2 = _ccw(p3x, p3z, p4x, p4z, p2x, p2z);
    final d3 = _ccw(p1x, p1z, p2x, p2z, p3x, p3z);
    final d4 = _ccw(p1x, p1z, p2x, p2z, p4x, p4z);

    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }

    if (d1 == 0 && _onSegment(p3x, p3z, p4x, p4z, p1x, p1z)) return true;
    if (d2 == 0 && _onSegment(p3x, p3z, p4x, p4z, p2x, p2z)) return true;
    if (d3 == 0 && _onSegment(p1x, p1z, p2x, p2z, p3x, p3z)) return true;
    if (d4 == 0 && _onSegment(p1x, p1z, p2x, p2z, p4x, p4z)) return true;

    return false;
  }

  static double _ccw(double ax, double az, double bx, double bz, double cx, double cz) {
    return (bx - ax) * (cz - az) - (cx - ax) * (bz - az);
  }

  static bool _onSegment(double sx, double sz, double ex, double ez, double px, double pz) {
    const double epsilon = 1e-9;
    final bool withinBounds =
        min(sx, ex) <= px && px <= max(sx, ex) &&
        min(sz, ez) <= pz && pz <= max(sz, ez);
    if (!withinBounds) return false;

    final bool isStart = (px - sx).abs() < epsilon && (pz - sz).abs() < epsilon;
    final bool isEnd   = (px - ex).abs() < epsilon && (pz - ez).abs() < epsilon;
    return !isStart && !isEnd;
  }

  static ValidationResult validateClosure(List<ARPoint> points) {
    if (points.length < 3) {
      return ValidationResult.invalid('Se necesitan al menos 3 esquinas.');
    }

    double doubleArea = 0.0;
    final int n = points.length;
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      doubleArea += (points[i].x * points[j].z) - (points[j].x * points[i].z);
    }
    final double area = doubleArea.abs() / 2.0;

    if (area < minArea) {
      return ValidationResult.invalid('Área insuficiente (${area.toStringAsFixed(2)} m²).');
    }

    return ValidationResult.valid;
  }

  static bool hasSelfIntersections(List<ARPoint> points) {
    final n = points.length;
    if (n < 4) return false;

    for (int i = 0; i < n; i++) {
      final a1 = points[i];
      final a2 = points[(i + 1) % n];

      for (int j = i + 2; j < n; j++) {
        if (i == 0 && j == n - 1) continue;

        final b1 = points[j];
        final b2 = points[(j + 1) % n];

        if (max(a1.x, a2.x) < min(b1.x, b2.x) || min(a1.x, a2.x) > max(b1.x, b2.x) ||
            max(a1.z, a2.z) < min(b1.z, b2.z) || min(a1.z, a2.z) > max(b1.z, b2.z)) {
          continue;
        }

        if (_segmentsIntersect(
          a1.x, a1.z, a2.x, a2.z,
          b1.x, b1.z, b2.x, b2.z,
        )) {
          return true;
        }
      }
    }
    return false;
  }
}
