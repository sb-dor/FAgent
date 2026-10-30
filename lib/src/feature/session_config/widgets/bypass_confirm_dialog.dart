import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// Asks whether the agent may act without asking in this chat; `true` when the user agrees.
Future<bool> confirmBypass(BuildContext context) async {
  final localization = Localization.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(localization.bypassTitle),
      content: Text(localization.bypassBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(localization.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(localization.bypassAllow),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
