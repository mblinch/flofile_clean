import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../services/auth_service.dart';
import '../../../services/preferences_service.dart';
import '../../../widgets/preferences_dialog.dart';
import '../caption_v2_flag.dart';
import '../data/caption_v2_controller.dart';
import 'mobile_design.dart';
import 'mobile_phone_frame.dart';

/// Phone settings — layout from `design/mobile/screens/Settings.dc.html`.
class MobileSettingsPage extends StatefulWidget {
  const MobileSettingsPage({
    super.key,
    this.controller,
  });

  final CaptionV2Controller? controller;

  static Future<void> open(
    BuildContext context, {
    CaptionV2Controller? controller,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileSettingsPage(controller: controller),
      ),
    );
  }

  @override
  State<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

class _MobileSettingsPageState extends State<MobileSettingsPage> {
  PreferencesService? _prefs;
  bool _ftp = true;
  bool _rename = false;
  bool _burst = true;
  bool _ocr = false;
  bool _serial = false;
  bool _hideFirebar = true;
  bool _crash = true;
  int _lowRes = 3000;
  late final TextEditingController _lowResCtrl;

  @override
  void initState() {
    super.initState();
    _lowResCtrl = TextEditingController(text: '$_lowRes');
    _load();
  }

  @override
  void dispose() {
    _lowResCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await PreferencesService.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
    });
    final ftp = await prefs.getFtpModeEnabled();
    final rename = await prefs.getFileRenamingEnabled();
    final burst = await prefs.getBurstDetectionEnabled();
    final ocr = await prefs.getJerseyOcrEnabled();
    final serial = await prefs.getSerialNumberBylines();
    final hide = await prefs.getHideFirebar();
    final crash = await prefs.getSendCrashReports();
    final low = await prefs.getResolutionWarningThreshold();
    if (!mounted) return;
    setState(() {
      _ftp = ftp;
      _rename = rename;
      _burst = burst;
      _ocr = ocr;
      _serial = serial;
      _hideFirebar = hide;
      _crash = crash;
      _lowRes = low;
      _lowResCtrl.text = '$low';
    });
  }

  Future<void> _reloadController() async {
    await widget.controller?.reloadApplicationModes();
  }

  @override
  Widget build(BuildContext context) {
    final email = AuthService.instance.currentUser?.email ?? '';
    final body = ColoredBox(
      color: MobileDesign.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: MobileDesign.divider),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to captioning',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      PhosphorIconsRegular.caretLeft,
                      color: MobileDesign.text,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Settings',
                      style: TextStyle(
                        fontFamily: MobileDesign.font,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: MobileDesign.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
              children: [
                _section('ACCOUNT', [
                  SizedBox(
                    height: 50,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Signed in',
                                  style: TextStyle(
                                    fontFamily: MobileDesign.font,
                                    fontSize: 15,
                                    color: MobileDesign.text,
                                  ),
                                ),
                                Text(
                                  email.isEmpty ? '—' : email,
                                  style: const TextStyle(
                                    fontFamily: MobileDesign.font,
                                    fontSize: 12,
                                    color: MobileDesign.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              await AuthService.instance.signOut();
                              if (mounted) {
                                Navigator.of(context).maybePop();
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: MobileDesign.text,
                              side: const BorderSide(
                                color: MobileDesign.otherBorder,
                              ),
                              minimumSize: const Size(0, 34),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Sign out',
                              style: TextStyle(
                                fontFamily: MobileDesign.font,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                _section('MODES', [
                  _toggle('FTP mode', _ftp, (v) async {
                    setState(() => _ftp = v);
                    await _prefs?.saveFtpModeEnabled(v);
                    await _reloadController();
                  }),
                  _toggle('File renaming', _rename, (v) async {
                    setState(() => _rename = v);
                    await _prefs?.saveFileRenamingEnabled(v);
                    await _reloadController();
                  }),
                  _toggle('Burst detection', _burst, (v) async {
                    setState(() => _burst = v);
                    await _prefs?.saveBurstDetectionEnabled(v);
                    await _reloadController();
                  }),
                  _toggle('Text recognition', _ocr, (v) async {
                    setState(() => _ocr = v);
                    await _prefs?.saveJerseyOcrEnabled(v);
                    await _reloadController();
                  }),
                  _toggle('Serial number byline', _serial, (v) async {
                    setState(() => _serial = v);
                    await _prefs?.saveSerialNumberBylines(v);
                    await _reloadController();
                  }),
                  _toggle('Firebar', !_hideFirebar, (v) async {
                    setState(() => _hideFirebar = !v);
                    await _prefs?.saveHideFirebar(!v);
                    await _reloadController();
                  }),
                  _toggle('Send crash reports', _crash, (v) async {
                    setState(() => _crash = v);
                    await _prefs?.saveSendCrashReports(v);
                  }),
                ]),
                const SizedBox(height: 18),
                _section('SET UP', [
                  _link('FTP profiles', 'Open', () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const PreferencesDialog(),
                    );
                  }),
                  _link(
                    'Actions (verbs)',
                    widget.controller?.sport.isNotEmpty == true
                        ? widget.controller!.sport[0].toUpperCase() +
                            widget.controller!.sport.substring(1)
                        : '—',
                    () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => const PreferencesDialog(openVerbs: true),
                      );
                    },
                  ),
                  _link(
                    'Caption template',
                    widget.controller?.isGettyWire == true ? 'Getty' : 'Wire',
                    () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => const PreferencesDialog(),
                      );
                    },
                  ),
                  _link('Rosters', 'Open', () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const PreferencesDialog(),
                    );
                  }),
                ]),
                const SizedBox(height: 18),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    'WARNINGS',
                    style: TextStyle(
                      fontFamily: MobileDesign.font,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08 * 11,
                      color: MobileDesign.textSecondary,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: MobileDesign.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: MobileDesign.surfaceBorder),
                  ),
                  child: SizedBox(
                    height: 50,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Low-resolution warning',
                              style: TextStyle(
                                fontFamily: MobileDesign.font,
                                fontSize: 15,
                                color: MobileDesign.text,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 64,
                            height: 32,
                            child: TextField(
                              controller: _lowResCtrl,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                fontFamily: MobileDesign.font,
                                fontSize: 14,
                                color: MobileDesign.text,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: MobileDesign.input,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              onSubmitted: (raw) async {
                                final n = int.tryParse(raw.trim()) ?? 0;
                                setState(() => _lowRes = n);
                                await _prefs
                                    ?.saveResolutionWarningThreshold(n);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
                  child: Text(
                    'Flags photos smaller than this on the long side, in pixels. 0 turns it off.',
                    style: TextStyle(
                      fontFamily: MobileDesign.font,
                      fontSize: 12,
                      color: MobileDesign.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (captionV2ForceMobilePreview.value || kCaptionV2MobileDefine) {
      return Scaffold(
        backgroundColor: MobileDesign.bg,
        body: MobilePhoneFrame(child: body),
      );
    }
    return body;
  }

  Widget _section(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: MobileDesign.font,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08 * 11,
              color: MobileDesign.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: MobileDesign.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MobileDesign.surfaceBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: MobileDesign.surfaceBorder,
                  ),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _toggle(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: MobileDesign.font,
                  fontSize: 15,
                  color: MobileDesign.text,
                ),
              ),
            ),
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: MobileDesign.statusCaptioned,
              side: const BorderSide(color: MobileDesign.otherBorder),
            ),
          ],
        ),
      ),
    );
  }

  Widget _link(String label, String detail, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: MobileDesign.font,
                    fontSize: 15,
                    color: MobileDesign.text,
                  ),
                ),
              ),
              Text(
                detail,
                style: const TextStyle(
                  fontFamily: MobileDesign.font,
                  fontSize: 13,
                  color: MobileDesign.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                PhosphorIconsRegular.caretRight,
                size: 14,
                color: MobileDesign.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
