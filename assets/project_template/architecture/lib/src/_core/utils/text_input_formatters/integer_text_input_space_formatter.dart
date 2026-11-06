import 'package:flutter/services.dart';
import 'package:{{package}}/src/_core/utils/text_input_formatters/text_input_config.dart';

/// A [TextInputFormatter] for integers that:
/// - allows only digits (no decimals or negative signs)
/// - adds thousands separators automatically (e.g. `1 000 000`)
class IntegerTextInputSpaceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // remove all spaces first to get the raw numeric input
    final rawText = newValue.text.replaceAll(' ', '');

    // validate — only digits allowed
    final regEx = RegExp(r'^\d*$');
    if (!regEx.hasMatch(rawText)) {
      return oldValue;
    }

    // format with grouping (using your existing global function)
    final formattedText = separateNumbersRegex(int.tryParse(rawText)) ?? '';

    // adjust the cursor position
    final diff = formattedText.length - newValue.text.length;
    final newOffset = (newValue.selection.end + diff).clamp(0, formattedText.length);

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
