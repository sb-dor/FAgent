import 'package:flutter/services.dart';

class DecimalTextInputFormatterWithSpecificLength extends TextInputFormatter {
  DecimalTextInputFormatterWithSpecificLength({required this.minValue, required this.maxValue});

  final double minValue;
  final double maxValue;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final regEx = RegExp(r'^\d*\.?\d*$');
    final newText = newValue.text;

    if (!regEx.hasMatch(newText)) {
      return oldValue;
    }

    final numericValue = double.tryParse(newText);
    if (numericValue != null && numericValue > maxValue) {
      return oldValue;
    }
    if (numericValue != null && numericValue < minValue) {
      return oldValue;
    }

    return newValue;
  }
}
