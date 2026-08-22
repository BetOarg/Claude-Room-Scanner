import 'dart:math';

import 'package:vector_math/vector_math_64.dart' as vm;

class ARStabilityFilter {
  final double _emaAlpha;
  final double _varianceThreshold;
  final int _windowSize;
  double? _emaX, _emaY, _emaZ;
  final List<vm.Vector3> _history = [];
  bool _isStable = false;

  ARStabilityFilter({
    double emaAlpha = 0.3,
    double varianceThreshold = 0.015,
    int windowSize = 10,
  })  : _emaAlpha = emaAlpha,
        _varianceThreshold = varianceThreshold,
        _windowSize = windowSize;

  bool get isStable => _isStable;

  vm.Vector3? feed(vm.Vector3 raw) => filter(raw);

  vm.Vector3? filter(vm.Vector3 raw) {
    _history.add(raw);
    if (_history.length > _windowSize) _history.removeAt(0);

    if (_emaX == null) {
      _emaX = raw.x; _emaY = raw.y; _emaZ = raw.z;
      _isStable = false;
      return raw;
    }

    _emaX = _emaAlpha * raw.x + (1 - _emaAlpha) * _emaX!;
    _emaY = _emaAlpha * raw.y + (1 - _emaAlpha) * _emaY!;
    _emaZ = _emaAlpha * raw.z + (1 - _emaAlpha) * _emaZ!;

    final filtered = vm.Vector3(_emaX!, _emaY!, _emaZ!);

    if (_history.length >= 3) {
      _isStable = _calculateVariance() < _varianceThreshold;
    }
    return filtered;
  }

  void reset() {
    _emaX = null; _emaY = null; _emaZ = null;
    _history.clear(); _isStable = false;
  }

  double _calculateVariance() {
    if (_history.isEmpty) return double.infinity;
    final n = _history.length;
    double sx = 0, sy = 0, sz = 0;
    for (final p in _history) { sx += p.x; sy += p.y; sz += p.z; }
    final mx = sx / n, my = sy / n, mz = sz / n;
    double vx = 0, vy = 0, vz = 0;
    for (final p in _history) {
      vx += pow(p.x - mx, 2); vy += pow(p.y - my, 2); vz += pow(p.z - mz, 2);
    }
    return (vx + vy + vz) / (3 * n);
  }
}
