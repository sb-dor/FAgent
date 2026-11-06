// Source - https://stackoverflow.com/a/50530099
// Posted by Jorge Vieira, modified by community. See post 'Timeline' for change history
// Retrieved 2025-12-04, License - CC BY-SA 4.0

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  CurrencyInputFormatter(this.locale);

  final String locale;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.selection.baseOffset == 0) {
      return newValue;
    }

    var value = double.parse(newValue.text);

    final formatter = NumberFormat.simpleCurrency(locale: locale);

    var newText = formatter.format(value / 100);

    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
