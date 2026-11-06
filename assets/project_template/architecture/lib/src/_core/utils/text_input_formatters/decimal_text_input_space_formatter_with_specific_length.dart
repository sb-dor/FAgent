import 'package:flutter/services.dart';
import 'package:{{package}}/src/_core/utils/text_input_formatters/text_input_config.dart';

class DecimalTextInputSpaceFormatterWithSpecificLength extends TextInputFormatter {
  DecimalTextInputSpaceFormatterWithSpecificLength(this.maxValue);

  final double maxValue;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final rawText = newValue.text.replaceAll(' ', '');

    final regEx = RegExp(r'^\d*\.?\d{0,2}$');
    if (!regEx.hasMatch(rawText)) {
      return oldValue;
    }

    final numericValue = double.tryParse(rawText);
    if (numericValue != null && numericValue > maxValue) {
      return oldValue;
    }

    final parts = rawText.split('.');
    final intPart = parts[0];
    final decimalPart = parts.length > 1 ? parts[1] : null;

    final formattedIntPart = separateNumbersRegex(int.tryParse(intPart));

    var formattedText = formattedIntPart ?? '';
    if (decimalPart != null) {
      formattedText += '.$decimalPart';
    }

    final diff = formattedText.length - newValue.text.length;
    final newOffset = (newValue.selection.end + diff).clamp(0, formattedText.length);

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
