import 'dart:math';
import '../models/room_model.dart';

class GeometryService {
  /// Calcula la distancia euclidiana 3D entre dos puntos en metros
  static double calculateDistance(ARPoint p1, ARPoint p2) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final dz = p2.z - p1.z;
    return sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// Calcula el perímetro total de una habitación en metros
  static double calculatePerimeter(List<ARPoint> points) {
    if (points.length < 2) return 0.0;
    double perimeter = 0.0;

    for (int i = 0; i < points.length; i++) {
      final nextIndex = (i + 1) % points.length;
      perimeter += calculateDistance(points[i], points[nextIndex]);
    }
    return perimeter;
  }

  /// Calcula el área del piso usando la fórmula Shoelace (proyección en X, Z)
  static double calculateArea(List<ARPoint> points) {
    if (points.length < 3) return 0.0;

    double area = 0.0;
    int j = points.length - 1;

    for (int i = 0; i < points.length; i++) {
      area += (points[j].x + points[i].x) * (points[j].z - points[i].z);
      j = i;
    }

    return (area.abs()) / 2.0;
  }

  /// Estima la altura promedio del techo si se escanean puntos superiores
  static double estimateWallHeight(List<ARPoint> floorPoints, List<ARPoint> ceilingPoints) {
    if (floorPoints.isEmpty || ceilingPoints.isEmpty) return 2.40;

    double totalHeight = 0.0;
    int minLength = min(floorPoints.length, ceilingPoints.length);

    for (int i = 0; i < minLength; i++) {
      totalHeight += (ceilingPoints[i].y - floorPoints[i].y).abs();
    }

    return totalHeight / minLength;
  }

  /// Algoritmo Ray-Casting para verificar si un toque del usuario está dentro del área de la habitación
  static bool isPointInPolygon(ARPoint point, List<ARPoint> polygon) {
    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      if ((polygon[i].z > point.z) != (polygon[j].z > point.z) &&
          (point.x < (polygon[j].x - polygon[i].x) * (point.z - polygon[i].z) / 
          (polygon[j].z - polygon[i].z) + polygon[i].x)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }
}