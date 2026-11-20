import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

TextInputType get numberInputType =>
    defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS
    ? const TextInputType.numberWithOptions(decimal: true, signed: true)
    : TextInputType.number;

String? separateNumbersRegex(num? number) {
  if (number == null) return null;
  return number.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]} ',
  );
}

String? separateNumbersRegexFromString(String? number) {
  if (number == null || num.tryParse(number) == null) return null;
  return number.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]} ',
  );
}

String clearSeparatedNumbers(String value) => value.replaceAll(' ', '');
