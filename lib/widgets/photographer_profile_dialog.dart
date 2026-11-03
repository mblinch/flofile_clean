import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../services/current_user_service.dart';
import '../services/ftp_rename_template.dart';
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';

/// Blocking Name + Initials setup used on first launch / missing profile.
class PhotographerProfileDialog extends StatefulWidget {
  const PhotographerProfileDialog({
    super.key,
    this.initialName = '',
    this.initialInitials = '',
  });

  final String initialName;
  final String initialInitials;

  /// Returns `true` when the profile was saved.
  static Future<bool?> show(
    BuildContext context, {
    String initialName = '',
    String initialInitials = '',
  }) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          extensions: <ThemeExtension<dynamic>>[tokens],
        ),
        child: AppDialogFfStyle(
          enabled: true,
          child: PhotographerProfileDialog(
            initialName: initialName,
            initialInitials: initialInitials,
          ),
        ),
      ),
    );
  }

  @override
  State<PhotographerProfileDialog> createState() =>
      _PhotographerProfileDialogState();
}

class _PhotographerProfileDialogState extends State<PhotographerProfileDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _initialsCtrl;
  bool _saving = false;
  bool _initialsEdited = false;

  @override
  void initState() {
    super.initState();
    final name = widget.initialName.trim();
    final initials = widget.initialInitials.trim();
    _nameCtrl = TextEditingController(text: name);
    _initialsCtrl = TextEditingController(
      text: initials.isNotEmpty
          ? initials
          : FtpRenameTemplate.initialsFromName(name),
    );
    _nameCtrl.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    if (_initialsEdited || !mounted) return;
    final derived = FtpRenameTemplate.initialsFromName(_nameCtrl.text);
    if (_initialsCtrl.text != derived) {
      _initialsCtrl.text = derived;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _initialsCtrl.dispose();
    super.dispose();
  }

  bool get _canSave {
    final name = _nameCtrl.text.trim();
    final initials = _initialsCtrl.text.trim();
    return name.isNotEmpty && initials.isNotEmpty && !_saving;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final name = _nameCtrl.text.trim();
    final initials = _initialsCtrl.text.trim().toUpperCase();
    try {
      final prefs = await PreferencesService.getInstance();
      await prefs.savePhotographerName(name);
      await prefs.saveRenameInitials(initials);
      CurrentUserService.setPhotographerNameOverride(name);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  InputDecoration _fieldDecoration(FfTokens t) {
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: t.sunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: t.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: t.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: t.accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Material(
          color: t.surface,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
            side: BorderSide(color: t.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border(bottom: BorderSide(color: t.divider)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'YOUR PROFILE',
                        style: FfTokens.railLabel.copyWith(
                          color: t.text.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                    PhosphorIcon(
                      PhosphorIconsRegular.user,
                      size: 16,
                      color: t.textTertiary,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  'Set the name used in caption bylines and the initials used when renaming files. This is saved to your account.',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    height: 1.35,
                    color: t.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Name',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: t.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameCtrl,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 14,
                        color: t.text,
                      ),
                      decoration: _fieldDecoration(t),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Initials',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: t.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _initialsCtrl,
                      textCapitalization: TextCapitalization.characters,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9]'),
                        ),
                        LengthLimitingTextInputFormatter(8),
                        TextInputFormatter.withFunction((oldValue, newValue) {
                          return newValue.copyWith(
                            text: newValue.text.toUpperCase(),
                            selection: newValue.selection,
                          );
                        }),
                      ],
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: t.text,
                      ),
                      decoration: _fieldDecoration(t),
                      onChanged: (_) {
                        _initialsEdited = true;
                        setState(() {});
                      },
                      onSubmitted: (_) {
                        if (_canSave) _save();
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedGreyButton(
                      label: _saving ? 'Saving…' : 'Continue',
                      fontSize: 11,
                      isPrimary: true,
                      onPressed: _canSave ? _save : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ensures Name + Initials exist before showing [child].
class PhotographerProfileGate extends StatefulWidget {
  const PhotographerProfileGate({super.key, required this.child});

  final Widget child;

  @override
  State<PhotographerProfileGate> createState() =>
      _PhotographerProfileGateState();
}

class _PhotographerProfileGateState extends State<PhotographerProfileGate> {
  bool _ready = false;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureProfile());
  }

  Future<void> _ensureProfile() async {
    if (!mounted || _prompting) return;
    final prefs = await PreferencesService.getInstance();
    var name = (await prefs.getPhotographerName()).trim();
    var initials = (await prefs.getRenameInitials()).trim();

    if (name.isNotEmpty) {
      CurrentUserService.setPhotographerNameOverride(name);
    }

    if (name.isNotEmpty && initials.isNotEmpty) {
      if (mounted) setState(() => _ready = true);
      return;
    }

    final fallbackName =
        name.isNotEmpty ? name : (CurrentUserService.currentDisplayName() ?? '');
    final fallbackInitials = initials.isNotEmpty
        ? initials
        : FtpRenameTemplate.initialsFromName(fallbackName);

    _prompting = true;
    final saved = await PhotographerProfileDialog.show(
      context,
      initialName: fallbackName == CurrentUserService.placeholderName
          ? ''
          : fallbackName,
      initialInitials: fallbackInitials,
    );
    _prompting = false;

    if (!mounted) return;
    if (saved == true) {
      setState(() => _ready = true);
      return;
    }

    // Dialog was dismissed without save — re-check (shouldn’t happen with
    // barrierDismissible: false, but keep the gate from hanging).
    name = (await prefs.getPhotographerName()).trim();
    initials = (await prefs.getRenameInitials()).trim();
    if (name.isNotEmpty && initials.isNotEmpty) {
      CurrentUserService.setPhotographerNameOverride(name);
      if (mounted) setState(() => _ready = true);
      return;
    }
    // Prompt again next frame if still incomplete.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureProfile());
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Scaffold(
      backgroundColor: t.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: t.groundWash),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: t.accent,
            ),
          ),
        ),
      ),
    );
  }
}
