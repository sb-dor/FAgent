extension ExtensionsForString on String {
  String limit(int length) => length < this.length ? substring(0, length) : this;

  String capitalizeFirstLetter() {
    if (isEmpty) return '';
    return '${this[0].toUpperCase()}${substring(1).toLowerCase()}';
  }

  String toSnakeCase() => trim()
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp('_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  double? get fixRound {
    if (double.tryParse(this) == null) return null;
    return double.parse(this).fixRound;
  }

  String get fixRoundString {
    final rounded = double.parse(this);
    return rounded.fixRoundString;
  }

  String get serverTrimmedDatetime {
    if (!contains('T')) {
      return split('.')[0];
    }
    final parts = split('T');
    final timePart = parts[1].split(RegExp('[.+]'))[0];
    return '${parts[0]} $timePart';
  }
}

extension NumExtensionAlt on num {
  double? get fixRound {
    if (double.tryParse(toStringAsFixed(2)) == null) return null;

    final rounded = double.parse(toStringAsFixed(2));

    return rounded;
  }

  String get fixRoundString {
    final rounded = double.parse(toStringAsFixed(2));

    if (rounded == rounded.toInt()) {
      return rounded.toInt().toString();
    }

    return rounded.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}

extension DateTimeEx on DateTime? {
  String? get datetimeTrimmed {
    if (this == null) return null;
    return toString().substring(0, 16);
  }
}
