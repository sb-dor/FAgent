import 'package:flutter/services.dart';
import 'package:{{package}}/src/_core/utils/text_input_formatters/text_input_config.dart';

class DecimalTextInputSpaceFormatter extends TextInputFormatter {
  DecimalTextInputSpaceFormatter({this.suffix});

  final String? suffix;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Удаляем суффикс если он есть
    var textWithoutSuffix = newValue.text;
    if (suffix != null && textWithoutSuffix.endsWith(suffix!)) {
      textWithoutSuffix = textWithoutSuffix
          .substring(0, textWithoutSuffix.length - suffix!.length)
          .trim();
    }

    final rawText = textWithoutSuffix.replaceAll(' ', '');

    final regEx = RegExp(r'^\d*\.?\d{0,2}$');
    if (!regEx.hasMatch(rawText)) {
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

    // Добавляем суффикс если текст не пустой
    if (suffix != null && formattedText.isNotEmpty) {
      formattedText += ' $suffix';
    }

    final diff = formattedText.length - newValue.text.length;

    // Позиция курсора должна быть перед суффиксом
    int newOffset;
    if (suffix != null && formattedText.isNotEmpty) {
      // Вычисляем позицию без суффикса
      final textLengthWithoutSuffix = formattedText.length - suffix!.length - 1; // -1 для пробела
      newOffset = (newValue.selection.end + diff).clamp(0, textLengthWithoutSuffix);
    } else {
      newOffset = (newValue.selection.end + diff).clamp(0, formattedText.length);
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
