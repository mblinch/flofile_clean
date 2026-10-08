import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../caption_style/sport_verb_categories.dart';
import '../theme/ff_icons.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'ff_dropdown.dart';

class VerbSearchHit {
  const VerbSearchHit({
    required this.key,
    required this.category,
    required this.label,
  });

  final String key;
  final String category;
  final String label;
}

/// Compact ghost / danger action used in Category & Verb picker boxes.
class VerbEditorActionButton extends StatelessWidget {
  const VerbEditorActionButton({
    super.key,
    required this.tokens,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.iconOnly = false,
    this.enabled = true,
  });

  final FfTokens tokens;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final bool iconOnly;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onPressed != null;
    final fg = !active
        ? tokens.text.withValues(alpha: 0.28)
        : danger
            ? FfTokens.danger
            : tokens.text.withValues(alpha: 0.78);
    final border = !active
        ? tokens.divider
        : danger
            ? FfTokens.dangerBorder
            : tokens.divider;
    final fill = danger
        ? (active ? Colors.transparent : FfTokens.dangerBg.withValues(alpha: 0.4))
        : (active ? Colors.transparent : tokens.surface.withValues(alpha: 0.4));

    final child = Container(
      height: 26,
      padding: EdgeInsets.symmetric(horizontal: iconOnly ? 6 : 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PhosphorIcon(
            icon,
            size: FfIcons.toolbarSize,
            color: !active
                ? tokens.text.withValues(alpha: 0.28)
                : (danger ? FfTokens.danger : null),
          ),
          if (!iconOnly) ...[
            const SizedBox(width: 5),
            Text(
              label,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: fg,
                height: 1,
              ),
            ),
          ],
        ],
      ),
    );

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: active ? onPressed : null,
        borderRadius: BorderRadius.circular(6),
        child: child,
      ),
    );

    if (iconOnly) {
      return Tooltip(message: label, child: button);
    }
    return button;
  }
}

class VerbEditorIconAction {
  const VerbEditorIconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
}

/// Joined icon buttons that sit beside a dropdown. The name shows on hover.
class VerbEditorIconGroup extends StatelessWidget {
  const VerbEditorIconGroup({
    super.key,
    required this.tokens,
    required this.actions,
  });

  final FfTokens tokens;
  final List<VerbEditorIconAction> actions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.sunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FfTokens.panelOutline, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 18, color: tokens.divider),
            _cell(actions[i]),
          ],
        ],
      ),
    );
  }

  Widget _cell(VerbEditorIconAction action) {
    final enabled = action.onPressed != null;
    final color = !enabled
        ? tokens.text.withValues(alpha: 0.28)
        : action.danger
            ? FfTokens.danger
            : tokens.text.withValues(alpha: 0.82);
    return Tooltip(
      message: action.label,
      child: InkWell(
        onTap: action.onPressed,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 32,
          height: 34,
          child: Center(
            child: PhosphorIcon(action.icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}

class VerbEditorPickerBox extends StatelessWidget {
  const VerbEditorPickerBox({
    super.key,
    required this.tokens,
    required this.label,
    required this.actions,
    required this.child,
  });

  final FfTokens tokens;
  final String label;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: Row(
              children: [
                Text(
                  label,
                  softWrap: false,
                  style: appDialogFieldLabelStyleOf(context),
                ),
                const Spacer(),
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  actions[i],
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

/// Sport left + search right.
class VerbEditorTopBar extends StatelessWidget {
  const VerbEditorTopBar({
    super.key,
    required this.tokens,
    required this.sport,
    required this.sports,
    required this.busy,
    required this.searchController,
    required this.searchFocus,
    required this.searchResults,
    required this.onSportChanged,
    required this.onSearchChanged,
    required this.onPickSearchResult,
    required this.onClearSearch,
  });

  final FfTokens tokens;
  final String sport;
  final List<String> sports;
  final bool busy;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final List<VerbSearchHit> searchResults;
  final ValueChanged<String> onSportChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onPickSearchResult;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final showResults =
        searchFocus.hasFocus && searchController.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Verb Editor',
            style: t.bodyStyle.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sport',
                      style: appDialogFieldLabelStyleOf(context),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 34,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.sunken,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: FfTokens.panelOutline,
                            width: 0.5,
                          ),
                        ),
                        child: FfDropdownButton<String>(
                          value: sport,
                          isExpanded: true,
                          menuColor: t.surface,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          style: t.metaStyle.copyWith(color: t.text),
                          items: [
                            for (final item in sports)
                              DropdownMenuItem(
                                value: item,
                                child: Text(
                                  SportVerbCategories.displayLabel(item),
                                ),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (value) {
                                  if (value != null) onSportChanged(value);
                                },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 34,
                      child: TextField(
                    controller: searchController,
                    focusNode: searchFocus,
                    enabled: !busy,
                    onChanged: onSearchChanged,
                    style: t.metaStyle.copyWith(color: t.text, fontSize: 13),
                    cursorColor: t.accent,
                    decoration: InputDecoration(
                      hintText: 'Search all verbs',
                      hintStyle: t.metaStyle.copyWith(
                        color: t.textSecondary,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: t.sunken,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      prefixIcon: PhosphorIcon(PhosphorIconsRegular.magnifyingGlass,
                        size: 16,
                        color: t.textSecondary,
                      ),
                      suffixIcon: searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              onPressed: onClearSearch,
                              icon: PhosphorIcon(PhosphorIconsRegular.x,
                                size: 14,
                                color: t.textSecondary,
                              ),
                            ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: t.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: t.accent),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: t.divider),
                      ),
                    ),
                  ),
                ),
                if (showResults)
                  Material(
                    color: t.surface,
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: searchResults.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'No matches',
                                style: t.metaStyle.copyWith(
                                  color: t.textSecondary,
                                ),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: searchResults.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: t.divider),
                              itemBuilder: (context, index) {
                                final hit = searchResults[index];
                                return InkWell(
                                  onTap: () => onPickSearchResult(hit.key),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      '${hit.category} / ${hit.label}',
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.metaStyle.copyWith(
                                        color: t.text,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
        ],
      ),
    );
  }
}

class VerbEditorFooter extends StatelessWidget {
  const VerbEditorFooter({
    super.key,
    required this.tokens,
    required this.busy,
    required this.pendingChanges,
    required this.onDiscard,
    required this.onPublish,
    this.personalMode = false,
  });

  final FfTokens tokens;
  final bool busy;
  final int pendingChanges;
  final VoidCallback? onDiscard;
  final VoidCallback? onPublish;
  final bool personalMode;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final status = personalMode
        ? (pendingChanges <= 0
            ? 'Saved to your account only — app defaults are unchanged'
            : '$pendingChanges unsaved change${pendingChanges == 1 ? '' : 's'}')
        : (pendingChanges <= 0
            ? 'Everything is published'
            : '$pendingChanges unpublished change${pendingChanges == 1 ? '' : 's'} — saved as draft, not live until published');
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              status,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: t.microStyle.copyWith(
                fontSize: 11,
                color: t.text.withValues(alpha: 0.55),
              ),
            ),
          ),
          TextButton(
            onPressed: busy || pendingChanges <= 0 ? null : onDiscard,
            child: Text(
              'Discard',
              softWrap: false,
              style: t.metaStyle.copyWith(
                color: (busy || pendingChanges <= 0)
                    ? t.text.withValues(alpha: 0.28)
                    : t.text.withValues(alpha: 0.70),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedGreyButton(
            label: busy
                ? (personalMode ? 'Saving…' : 'Publishing…')
                : (personalMode ? 'Save' : 'Publish default'),
            fontSize: 11,
            isPrimary: true,
            isAdmin: !personalMode,
            onPressed: pendingChanges <= 0 ? null : onPublish,
          ),
        ],
      ),
    );
  }
}

/// Result of the v3 delete-category dialog.
class VerbEditorDeleteCategoryChoice {
  const VerbEditorDeleteCategoryChoice._({
    required this.deleteAll,
    required this.destination,
    required this.count,
  });

  const VerbEditorDeleteCategoryChoice.move({
    required String destination,
    required int count,
  }) : this._(deleteAll: false, destination: destination, count: count);

  const VerbEditorDeleteCategoryChoice.deleteAll({required int count})
      : this._(deleteAll: true, destination: null, count: count);

  final bool deleteAll;
  final String? destination;
  final int count;
}

Future<VerbEditorDeleteCategoryChoice?> showVerbEditorDeleteCategoryDialog({
  required BuildContext context,
  required FfTokens tokens,
  required String category,
  required List<String> verbLabels,
  required List<String> destinations,
}) {
  return showDialog<VerbEditorDeleteCategoryChoice>(
    context: context,
    builder: (context) => _DeleteCategoryV3Dialog(
      tokens: tokens,
      category: category,
      verbLabels: verbLabels,
      destinations: destinations,
    ),
  );
}

class _DeleteCategoryV3Dialog extends StatefulWidget {
  const _DeleteCategoryV3Dialog({
    required this.tokens,
    required this.category,
    required this.verbLabels,
    required this.destinations,
  });

  final FfTokens tokens;
  final String category;
  final List<String> verbLabels;
  final List<String> destinations;

  @override
  State<_DeleteCategoryV3Dialog> createState() =>
      _DeleteCategoryV3DialogState();
}

class _DeleteCategoryV3DialogState extends State<_DeleteCategoryV3Dialog> {
  late bool _keepVerbs;
  late String? _destination;

  @override
  void initState() {
    super.initState();
    _keepVerbs = widget.destinations.isNotEmpty;
    _destination =
        widget.destinations.isEmpty ? null : widget.destinations.first;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final n = widget.verbLabels.length;
    final canKeep = widget.destinations.isNotEmpty;
    return AppDialogFfStyle(
      enabled: true,
      child: Theme(
        data: Theme.of(context).copyWith(extensions: <ThemeExtension<dynamic>>[t]),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 440,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              border: Border.all(color: t.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Delete category “${widget.category}”?',
                          style: TextStyle(
                            fontFamily: FfTokens.labelFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: PhosphorIcon(PhosphorIconsRegular.x, size: 18, color: t.textSecondary),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'This category has $n verb${n == 1 ? '' : 's'}. What should happen to them?',
                    style: t.metaStyle.copyWith(
                      color: t.text.withValues(alpha: 0.70),
                      height: 1.35,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (canKeep)
                        _radioCard(
                          selected: _keepVerbs,
                          danger: false,
                          title: 'Keep the verbs — move them to another category',
                          onTap: () => setState(() => _keepVerbs = true),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: t.sunken,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: FfTokens.panelOutline,
                                width: 0.5,
                              ),
                            ),
                            child: FfDropdownButton<String>(
                              value: _destination,
                              isExpanded: true,
                              menuColor: t.surface,
                              style: t.metaStyle.copyWith(color: t.text),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              items: [
                                for (final d in widget.destinations)
                                  DropdownMenuItem(value: d, child: Text(d)),
                              ],
                              onChanged: _keepVerbs
                                  ? (v) => setState(() => _destination = v)
                                  : null,
                            ),
                          ),
                        ),
                      if (canKeep) const SizedBox(height: 8),
                      _radioCard(
                        selected: !_keepVerbs || !canKeep,
                        danger: true,
                        title: 'Delete the category and all $n verbs',
                        onTap: () => setState(() => _keepVerbs = false),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final name in widget.verbLabels)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: FfTokens.dangerBg,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: FfTokens.dangerBorder),
                                ),
                                child: Text(
                                  name,
                                  softWrap: false,
                                  style: t.metaStyle.copyWith(
                                    fontSize: 11,
                                    color: FfTokens.danger,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('Cancel', style: t.metaStyle),
                      ),
                      const SizedBox(width: 8),
                      ElevatedGreyButton(
                        label: (_keepVerbs && canKeep)
                            ? 'Move $n verbs & delete category'
                            : 'Delete category & $n verbs',
                        fontSize: 11,
                        isPrimary: true,
                        isDanger: !(_keepVerbs && canKeep),
                        onPressed: () {
                          if (_keepVerbs && canKeep) {
                            final dest = _destination;
                            if (dest == null) return;
                            Navigator.pop(
                              context,
                              VerbEditorDeleteCategoryChoice.move(
                                destination: dest,
                                count: n,
                              ),
                            );
                          } else {
                            Navigator.pop(
                              context,
                              VerbEditorDeleteCategoryChoice.deleteAll(count: n),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _radioCard({
    required bool selected,
    required bool danger,
    required String title,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final t = widget.tokens;
    return Material(
      color: selected
          ? (danger ? FfTokens.dangerBg : t.selected)
          : t.sunken,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? (danger ? FfTokens.dangerBorder : t.accent)
                  : t.divider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? PhosphorIconsFill.circle
                        : PhosphorIconsRegular.circle,
                    size: 16,
                    color: selected
                        ? (danger ? FfTokens.danger : t.accent)
                        : t.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: t.metaStyle.copyWith(
                        color: danger && selected ? FfTokens.danger : t.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (selected) ...[
                const SizedBox(height: 10),
                child,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> showVerbEditorDeleteVerbDialog({
  required BuildContext context,
  required FfTokens tokens,
  required String verb,
  required String category,
  required String sport,
}) {
  final t = tokens;
  final sportLabel = SportVerbCategories.displayLabel(sport);
  return showDialog<bool>(
    context: context,
    builder: (context) => AppDialogFfStyle(
      enabled: true,
      child: Theme(
        data: Theme.of(context).copyWith(extensions: <ThemeExtension<dynamic>>[t]),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 420,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              border: Border.all(color: t.divider),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Delete “$verb”?',
                  style: TextStyle(
                    fontFamily: FfTokens.labelFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This removes the verb $verb from $category in $sportLabel. '
                  'The $category category stays.',
                  style: t.metaStyle.copyWith(
                    color: t.text.withValues(alpha: 0.75),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Captions you've already written won't change. "
                  'Nothing goes live until you publish.',
                  style: t.metaStyle.copyWith(
                    color: t.text.withValues(alpha: 0.50),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Cancel', style: t.metaStyle),
                    ),
                    const SizedBox(width: 8),
                    ElevatedGreyButton(
                      label: 'Delete verb',
                      fontSize: 11,
                      isPrimary: true,
                      isDanger: true,
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ).then((v) => v == true);
}

Future<String?> showMoveCategoryMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required FfTokens tokens,
  required String verbLabel,
  required List<String> categories,
}) async {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final origin = box.localToGlobal(Offset.zero);
  final size = box.size;
  return showMenu<String>(
    context: context,
    color: tokens.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: tokens.divider),
    ),
    position: RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + size.height + 4,
      origin.dx + size.width,
      origin.dy,
    ),
    items: [
      PopupMenuItem<String>(
        enabled: false,
        height: 32,
        child: Text(
          'Move “$verbLabel” to…',
          style: tokens.metaStyle.copyWith(
            fontWeight: FontWeight.w600,
            color: tokens.text.withValues(alpha: 0.55),
          ),
        ),
      ),
      for (final category in categories)
        PopupMenuItem<String>(
          value: category,
          height: 34,
          child: Text(
            category,
            softWrap: false,
            style: tokens.metaStyle.copyWith(color: tokens.text),
          ),
        ),
    ],
  );
}

/// Inline rename field for category select.
class CategoryRenameField extends StatelessWidget {
  const CategoryRenameField({
    super.key,
    required this.tokens,
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
    this.focusNode,
  });

  final FfTokens tokens;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onCancel,
      },
      child: Focus(
        autofocus: true,
        child: SizedBox(
          height: 34,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.sunken,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.accent),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: true,
                        style: t.metaStyle.copyWith(color: t.text),
                        cursorColor: t.accent,
                        onSubmitted: onSubmit,
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String sportPeriodNoun(String sport) {
  switch (sport.toLowerCase()) {
    case 'hockey':
      return 'period';
    case 'basketball':
    case 'wnba':
      return 'quarter';
    case 'soccer':
      return 'half';
    case 'baseball':
    default:
      return 'inning';
  }
}
