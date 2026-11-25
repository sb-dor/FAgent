import 'package:flutter_code_agent/_core/design/app_colors.dart';
import 'package:flutter_code_agent/_core/design/app_text.dart';
import 'package:flutter_code_agent/_core/design/app_theme.dart';
import 'package:flutter_code_agent/_core/widget/preview_badge.dart';
import 'package:material_ui/material_ui.dart';

/// A label over a control with the hint or the errors under it.
class CreationField extends StatelessWidget {
  const CreationField({
    required this.label,
    required this.child,
    this.messages = const <Widget>[],
    super.key,
  });

  final String label;
  final Widget child;
  final List<Widget> messages;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: context.colors.muted, fontWeight: FontWeight.w600),
        ),
      ),
      child,
      for (final message in messages)
        Padding(padding: const EdgeInsets.only(top: 4), child: message),
    ],
  );
}

/// A line under a field: a muted hint or a red error.
class CreationMessage extends StatelessWidget {
  const CreationMessage.hint(this.text, {super.key}) : error = false;

  const CreationMessage.error(this.text, {super.key}) : error = true;

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall!
        .copyWith(fontSize: 11, color: error ? context.colors.danger : context.colors.muted),
  );
}

/// A single-line monospace field with the border of the dialog.
class CreationTextInput extends StatelessWidget {
  const CreationTextInput({
    required this.fieldKey,
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
    required this.error,
    this.autofocus = false,
    super.key,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool error;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.medium - 2),
      borderSide: BorderSide(color: color),
    );
    return TextField(
      key: fieldKey,
      controller: controller,
      autofocus: autofocus,
      style: AppText.mono(context, size: 13).copyWith(color: colors.text),
      cursorColor: colors.accent,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        enabledBorder: border(error ? colors.danger : colors.border),
        focusedBorder: border(error ? colors.danger : colors.accent),
      ),
    );
  }
}

/// One of the template radio cards.
class CreationTemplateCard extends StatelessWidget {
  const CreationTemplateCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    this.preview = false,
    this.enabled = true,
    super.key,
  });

  final String title;
  final String description;
  final bool selected;
  final bool preview;
  final VoidCallback onTap;

  /// Whether the card can be chosen; a disabled one is muted and ignores taps.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.medium);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: enabled,
      child: Material(
        color: selected ? colors.accentSoft : colors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: selected ? colors.accent : colors.border),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 16,
                    color: selected ? colors.accent : colors.muted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: textTheme.bodyMedium!.copyWith(
                          color: enabled ? colors.text : colors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(description, style: textTheme.bodySmall!.copyWith(color: colors.muted)),
                    ],
                  ),
                ),
                if (preview) ...<Widget>[const SizedBox(width: 8), const PreviewBadge()],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
