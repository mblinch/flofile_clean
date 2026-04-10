import 'package:flutter/material.dart';
import '../app_update_notes.dart';

/// One-shot “What’s new” after [package_info_plus] build increases.
class UpdateNotesDialog extends StatelessWidget {
  const UpdateNotesDialog({
    super.key,
    required this.versionLabel,
  });

  final String versionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: theme.colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kAppUpdateNotesTitle,
              style: theme.textTheme.titleLarge,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                versionLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                kAppUpdateNotesBody.trim(),
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
