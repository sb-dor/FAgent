import 'package:flutter/services.dart';

class YearInputFormatter extends TextInputFormatter {
  YearInputFormatter({required this.minYear, required this.maxYear});

  final int minYear;
  final int maxYear;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final newText = newValue.text;

    final regEx = RegExp(r'^\d{0,4}$');
    if (!regEx.hasMatch(newText)) {
      return oldValue;
    }

    if (newText.length == 4) {
      final year = int.tryParse(newText);
      if (year != null && (year < minYear || year > maxYear)) {
        return oldValue;
      }
    }

    return newValue;
  }
}
