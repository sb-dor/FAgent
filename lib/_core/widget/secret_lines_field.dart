import 'package:flutter_code_agent/_core/design/app_colors.dart';
import 'package:flutter_code_agent/_core/design/app_text.dart';
import 'package:flutter_code_agent/_core/design/app_theme.dart';
import 'package:flutter_code_agent/_core/localization/localization.dart';
import 'package:material_ui/material_ui.dart';

const String _mask = '••••••';

/// Shows [text] line by line with every value replaced by bullets.
///
/// A line keeps what comes before its first [separator] (and the spaces after the separator); a
/// line without the separator shows as bullets alone.
String maskSecretLines(String text, String separator) {
  return text
      .split('\n')
      .map((line) {
        final at = line.indexOf(separator);
        if (at < 0) return _mask;
        var end = at + separator.length;
        while (end < line.length && line[end] == ' ') {
          end++;
        }
        return '${line.substring(0, end)}$_mask';
      })
      .join('\n');
}

/// {@template secret_lines_field}
/// A multi-line field of `KEY<separator>value` lines whose values are secrets.
///
/// Flutter's `obscureText` needs a single line, so the field starts as a read-only masked view
/// (when the [controller] has text) with a Show button; shown, it is the plain editable field.
/// Under it, always, a note that the values are kept unencrypted.
/// {@endtemplate}
class SecretLinesField extends StatefulWidget {
  /// {@macro secret_lines_field}
  const SecretLinesField({
    required this.controller,
    required this.separator,
    required this.label,
    this.hint,
    this.errorText,
    this.onChanged,
    this.maxLines = 4,
    super.key,
  });

  /// The lines, edited when the field is shown.
  final TextEditingController controller;

  /// What splits a line into its key and its secret value, such as `=` or `:`.
  final String separator;

  /// The floating label.
  final String label;

  /// A hint under the field.
  final String? hint;

  /// Why the lines were refused; `null` when they are fine.
  final String? errorText;

  /// Called after every edit.
  final VoidCallback? onChanged;

  /// How many lines the field grows to.
  final int maxLines;

  @override
  State<SecretLinesField> createState() => _SecretLinesFieldState();
}

class _SecretLinesFieldState extends State<SecretLinesField> {
  late bool _hidden = widget.controller.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    final colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      borderSide: BorderSide(color: color),
    );
    final mono = AppText.mono(context, size: 13);
    final toggle = IconButton(
      tooltip: _hidden ? localization.secretShow : localization.secretHide,
      iconSize: 18,
      color: colors.muted,
      icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => setState(() => _hidden = !_hidden),
    );
    final field = _hidden
        ? InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: widget.hint,
              helperMaxLines: 2,
              errorText: widget.errorText,
              errorMaxLines: 3,
              enabled: false,
              suffixIcon: toggle,
              disabledBorder: border(colors.border),
              errorBorder: border(colors.danger),
            ),
            child: Text(
              maskSecretLines(widget.controller.text, widget.separator),
              style: mono.copyWith(color: colors.muted),
              maxLines: widget.maxLines,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : TextField(
            controller: widget.controller,
            minLines: 2,
            maxLines: widget.maxLines,
            style: mono.copyWith(color: colors.text),
            cursorColor: colors.accent,
            onChanged: (_) => widget.onChanged?.call(),
            decoration: InputDecoration(
              labelText: widget.label,
              helperText: widget.hint,
              helperMaxLines: 2,
              errorText: widget.errorText,
              errorMaxLines: 3,
              suffixIcon: toggle,
              enabledBorder: border(colors.border),
              focusedBorder: border(colors.accent),
              errorBorder: border(colors.danger),
              focusedErrorBorder: border(colors.danger),
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        field,
        const SizedBox(height: 4),
        Text(
          localization.secretsStoredUnencrypted,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: colors.muted),
        ),
      ],
    );
  }
}
