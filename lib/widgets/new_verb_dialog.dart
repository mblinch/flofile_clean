import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../theme/ff_tokens.dart';
import '../utils/verb_name_casing.dart';
import 'app_styled_dialogs.dart';

/// Category and title collected before a new verb is created.
class NewVerbPrompt {
  const NewVerbPrompt({
    required this.category,
    required this.title,
    required this.createdCategory,
  });

  final String category;
  final String title;
  final bool createdCategory;
}

/// Asks for a category (or a new one), then the verb title.
Future<NewVerbPrompt?> showNewVerbDialog({
  required BuildContext context,
  required FfTokens tokens,
  required List<String> categories,
  required Set<String> existingVerbNames,
}) {
  return showDialog<NewVerbPrompt>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _NewVerbDialog(
      tokens: tokens,
      categories: categories,
      existingVerbNames: existingVerbNames,
    ),
  );
}

class _NewVerbDialog extends StatefulWidget {
  const _NewVerbDialog({
    required this.tokens,
    required this.categories,
    required this.existingVerbNames,
  });

  final FfTokens tokens;
  final List<String> categories;
  final Set<String> existingVerbNames;

  @override
  State<_NewVerbDialog> createState() => _NewVerbDialogState();
}

class _NewVerbDialogState extends State<_NewVerbDialog> {
  final _categoryName = TextEditingController();
  final _title = TextEditingController();
  final _titleFocus = FocusNode();
  String? _selected;
  bool _adding = false;

  @override
  void dispose() {
    _categoryName.dispose();
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  String get _normalizedCategory {
    final parts = _categoryName.text.trim().split(RegExp(r'\s+'));
    return parts
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String? get _categoryError {
    if (!_adding) return null;
    final name = _normalizedCategory;
    if (name.isEmpty) return null;
    if (name == 'Favorites' || name == 'All') return 'That name is reserved.';
    final taken = widget.categories.any(
      (category) => category.toLowerCase() == name.toLowerCase(),
    );
    if (taken) return 'That category already exists.';
    return null;
  }

  String? get _chosenCategory {
    if (_adding) {
      final name = _normalizedCategory;
      if (name.isEmpty || _categoryError != null) return null;
      return name;
    }
    return _selected;
  }

  bool get _createdCategory => _adding && _chosenCategory != null;

  String get _titleText => titleCaseVerbName(_title.text);

  String? get _titleError {
    final title = _titleText;
    if (title.isEmpty) return null;
    if (widget.existingVerbNames.contains(title.toLowerCase())) {
      return 'A verb with that title already exists.';
    }
    return null;
  }

  void _selectExisting(String category) {
    setState(() {
      _adding = false;
      _selected = category;
      _categoryName.clear();
    });
    _focusTitle();
  }

  void _startAddCategory() {
    setState(() {
      _adding = true;
      _selected = null;
    });
  }

  void _focusTitle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _chosenCategory == null) return;
      _titleFocus.requestFocus();
    });
  }

  void _submit() {
    final category = _chosenCategory;
    final title = _titleText;
    if (category == null || title.isEmpty || _titleError != null) return;
    Navigator.pop(
      context,
      NewVerbPrompt(
        category: category,
        title: title,
        createdCategory: _createdCategory,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final category = _chosenCategory;
    final titleError = _titleError;
    final categoryError = _categoryError;
    final canCreate =
        category != null && _titleText.isNotEmpty && titleError == null;

    return AppDialogFfStyle(
      enabled: true,
      child: Theme(
        data: Theme.of(context).copyWith(
          extensions: <ThemeExtension<dynamic>>[t],
        ),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 380,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              border: Border.all(color: t.divider),
              boxShadow: [
                BoxShadow(
                  color: t.bg.withValues(alpha: 0.55),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'New verb',
                            style: TextStyle(
                              fontFamily: FfTokens.labelFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: t.text,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cancel',
                          onPressed: () => Navigator.pop(context),
                          icon: PhosphorIcon(
                            PhosphorIconsRegular.x,
                            size: 16,
                            color: t.text.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: t.divider),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Category',
                          style: t.metaStyle.copyWith(
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (final name in widget.categories)
                                _CategoryChoice(
                                  label: name,
                                  selected: !_adding && _selected == name,
                                  tokens: t,
                                  onTap: () => _selectExisting(name),
                                ),
                              _CategoryChoice(
                                label: 'Add category',
                                selected: _adding,
                                tokens: t,
                                icon: PhosphorIconsRegular.plus,
                                onTap: _startAddCategory,
                              ),
                            ],
                          ),
                        ),
                        if (_adding) ...[
                          const SizedBox(height: 8),
                          AppDialogLabeledField(
                            label: 'Category name',
                            bottomGap: 4,
                            child: AppDialogControlShell(
                              child: TextField(
                                controller: _categoryName,
                                autofocus: true,
                                style: t.metaStyle.copyWith(
                                  fontSize: 11,
                                  color: t.text,
                                  height: 1.25,
                                ),
                                cursorColor: t.accent,
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _focusTitle(),
                                decoration: appDialogBareFieldDecoration(),
                              ),
                            ),
                          ),
                          if (categoryError != null)
                            Text(
                              categoryError,
                              style: t.metaStyle.copyWith(
                                fontSize: 11,
                                color: FfTokens.danger,
                              ),
                            ),
                        ],
                        if (category != null) ...[
                          const SizedBox(height: 14),
                          AppDialogLabeledField(
                            label: 'Title',
                            bottomGap: 4,
                            child: AppDialogControlShell(
                              child: TextField(
                                controller: _title,
                                focusNode: _titleFocus,
                                style: t.metaStyle.copyWith(
                                  fontSize: 11,
                                  color: t.text,
                                  height: 1.25,
                                ),
                                cursorColor: t.accent,
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _submit(),
                                decoration: appDialogBareFieldDecoration(),
                              ),
                            ),
                          ),
                          if (titleError != null)
                            Text(
                              titleError,
                              style: t.metaStyle.copyWith(
                                fontSize: 11,
                                color: FfTokens.danger,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Row(
                      children: [
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: t.metaStyle.copyWith(
                              color: t.text.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedGreyButton(
                          label: 'Create',
                          fontSize: 11,
                          isPrimary: true,
                          onPressed: canCreate ? _submit : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? tokens.hover : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              if (icon != null) ...[
                PhosphorIcon(icon!, size: 13, color: tokens.accent),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.metaStyle.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? tokens.text : tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
