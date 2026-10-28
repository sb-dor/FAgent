import 'package:flutter/material.dart';
import 'package:flutter_code_agent/src/common/design/app_colors.dart';
import 'package:flutter_code_agent/src/common/localization/localization.dart';

/// {@template bypass_gate_banner}
/// The chat's mode is `bypassPermissions` (from the user's Claude settings):
/// prompts stay blocked until the user allows it for this chat.
/// {@endtemplate}
class BypassGateBanner extends StatelessWidget {
  /// {@macro bypass_gate_banner}
  const BypassGateBanner({required this.onAllow, super.key});

  /// Allows bypass for the chat.
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    final localization = Localization.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: context.colors.dangerSoft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded, color: context.colors.danger),
                  const SizedBox(width: 10),
                  Expanded(child: Text(localization.bypassInherited)),
                  const SizedBox(width: 10),
                  FilledButton(onPressed: onAllow, child: Text(localization.bypassAllow)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
