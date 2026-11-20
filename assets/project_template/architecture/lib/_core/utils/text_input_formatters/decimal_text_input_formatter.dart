import 'package:flutter/services.dart';

class DecimalTextInputFormatter extends TextInputFormatter {
  DecimalTextInputFormatter({this.minValue, this.maxValue});

  final double? minValue;
  final double? maxValue;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final regEx = RegExp(r'^\d*\.?\d{0,2}$');
    final newText = newValue.text;

    if (!regEx.hasMatch(newText)) {
      return oldValue;
    }

    if (newText.isEmpty || newText == '.') {
      return newValue;
    }

    final numericValue = double.tryParse(newText);
    if (numericValue != null) {
      if (maxValue != null && numericValue > maxValue!) {
        return oldValue;
      }
      if (minValue != null && numericValue < minValue!) {
        return oldValue;
      }
    }

    return newValue;
  }
}
