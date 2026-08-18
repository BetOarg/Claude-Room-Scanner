enum MeasurementSystem {
  metric,
  imperial,
}

class ImperialLength {
  final int feet;
  final double inches;

  const ImperialLength({
    required this.feet,
    required this.inches,
  });
}

class MeasurementUnits {
  MeasurementUnits._();

  static const double metersPerInch = 0.0254;
  static const double inchesPerFoot = 12.0;
  static const double metersPerFoot =
      metersPerInch * inchesPerFoot;

  static double inchesToMeters(
    double inches,
  ) {
    return inches * metersPerInch;
  }

  static double metersToInches(
    double meters,
  ) {
    return meters / metersPerInch;
  }

  static double feetAndInchesToMeters({
    required double feet,
    required double inches,
  }) {
    return feet * metersPerFoot +
        inchesToMeters(inches);
  }

  static ImperialLength metersToFeetAndInches(
    double meters, {
    int inchDecimals = 2,
  }) {
    if (!meters.isFinite || meters < 0) {
      throw ArgumentError.value(
        meters,
        'meters',
        'La longitud debe ser un número finito mayor o igual que cero.',
      );
    }

    final totalInches =
        metersToInches(meters);
    var feet =
        totalInches ~/ inchesPerFoot;
    final factor =
        _decimalFactor(inchDecimals);
    var inches =
        ((totalInches - feet * inchesPerFoot) * factor)
            .roundToDouble() /
        factor;

    if (inches >= inchesPerFoot) {
      feet++;
      inches = 0;
    }

    return ImperialLength(
      feet: feet,
      inches: inches,
    );
  }

  static double? parseLocalizedNumber(
    String value,
  ) {
    final normalized = value
        .trim()
        .replaceAll(' ', '')
        .replaceAll(',', '.');

    if (normalized.isEmpty) {
      return null;
    }

    final parsed =
        double.tryParse(normalized);

    if (parsed == null ||
        !parsed.isFinite) {
      return null;
    }

    return parsed;
  }

  static double? metricInputToMeters(
    String metersInput,
  ) {
    final meters =
        parseLocalizedNumber(metersInput);

    if (meters == null || meters < 0) {
      return null;
    }

    return meters;
  }

  static double? imperialInputToMeters({
    required String feetInput,
    required String inchesInput,
  }) {
    final normalizedFeet = feetInput.trim();
    final normalizedInches = inchesInput.trim();

    if (normalizedFeet.isEmpty &&
        normalizedInches.isEmpty) {
      return null;
    }

    final feet = normalizedFeet.isEmpty
        ? 0.0
        : parseLocalizedNumber(normalizedFeet);
    final inches = normalizedInches.isEmpty
        ? 0.0
        : parseLocalizedNumber(normalizedInches);

    if (feet == null ||
        inches == null ||
        feet < 0 ||
        inches < 0) {
      return null;
    }

    return feetAndInchesToMeters(
      feet: feet,
      inches: inches,
    );
  }

  static double _decimalFactor(
    int decimals,
  ) {
    if (decimals < 0 || decimals > 6) {
      throw RangeError.range(
        decimals,
        0,
        6,
        'inchDecimals',
      );
    }

    var factor = 1.0;

    for (var index = 0;
        index < decimals;
        index++) {
      factor *= 10;
    }

    return factor;
  }
}