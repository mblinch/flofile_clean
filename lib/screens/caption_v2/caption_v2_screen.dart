import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../theme/ff_tokens.dart';
import '../../widgets/admin_screen.dart';
import '../../widgets/caption_layout_builder_dialog.dart';
import '../../widgets/flo_chrome_header.dart';
import '../../widgets/preferences_dialog.dart';
import 'caption_v2_shortcuts.dart';
import 'data/caption_transfer_payload.dart';
import 'data/caption_v2_controller.dart';
import 'layout/caption_v2_search.dart';
import 'layout/caption_v2_startup_screen.dart';
import 'layout/desktop_drum_picker.dart';
import 'layout/frame_review_route.dart';
import 'layout/photo_column.dart';
import 'layout/roster_column.dart';
import 'layout/verbs_column.dart';
import 'widgets/caption_strip.dart';
import 'widgets/transmit_dock.dart';

/// Caption V2 screen — full layout + behaviour behind `CAPTION_V2`.
class CaptionV2Screen extends StatefulWidget {
  const CaptionV2Screen({super.key});

  @override
  State<CaptionV2Screen> createState() => _CaptionV2ScreenState();
}

class _CaptionV2ScreenState extends State<CaptionV2Screen> {
  final _controller = CaptionV2Controller();
  final _searchFocus = FocusNode();
  final _searchText = TextEditingController();
  final _rootFocus = FocusNode();
  static const _jerseyShortcutChannel =
      MethodChannel('caption_writer/jersey_shortcuts');
  PageController? _pageController;
  String? _lastObservedStatus;
  double? _photoWidth;
  Timer? _jerseyBufferTimer;
  String _jerseyBuffer = '';
  bool? _jerseyBufferIsHome;

  static const double _desktopBreakpoint = 1100;
  static double get _gap => 8;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
    _controller.addListener(_onController);
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus) {
        _controller.setSearchOpen(true);
      }
      if (mounted) setState(() {});
    });
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    FocusManager.instance.addListener(_syncNativeJerseyShortcuts);
    _jerseyShortcutChannel.setMethodCallHandler(_handleNativeShortcut);
    _syncNativeJerseyShortcuts();
    _controller.bootstrap();
  }

  void _onController() {
    if (!mounted) return;
    if (_controller.searchQuery.isEmpty && _searchText.text.isNotEmpty) {
      _searchText.clear();
    }
    final status = _controller.statusMessage;
    if (status != _lastObservedStatus) {
      _lastObservedStatus = status;
      if (status != null && _isErrorStatus(status)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger
            ?..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(status),
                behavior: SnackBarBehavior.floating,
              ),
            );
        });
      }
    }
    setState(() {});
  }

  static bool _isErrorStatus(String message) {
    final value = message.toLowerCase();
    return value.startsWith('no ') ||
        value.startsWith('select ') ||
        value.startsWith('nothing ') ||
        value.startsWith('invalid ') ||
        value.startsWith('could not ') ||
        value.contains('not enabled') ||
        value.contains(' failed') ||
        value.endsWith('failed');
  }

  Future<void> _onStartupComplete(CaptionV2StartupResult result) async {
    await _controller.applyStartup(
      sport: result.sport,
      homeTeam: result.homeTeam,
      awayTeam: result.awayTeam,
      folderPath: result.folderPath,
      burstDetectionEnabled: result.burstDetectionEnabled,
      homeRosterOverride: result.homeRoster,
      awayRosterOverride: result.awayRoster,
    );
  }

  @override
  void dispose() {
    _jerseyBufferTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    FocusManager.instance.removeListener(_syncNativeJerseyShortcuts);
    _jerseyShortcutChannel.setMethodCallHandler(null);
    unawaited(_setNativeJerseyShortcutsEnabled(true));
    _controller.removeListener(_onController);
    _controller.dispose();
    _searchFocus.dispose();
    _searchText.dispose();
    _rootFocus.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _setNativeJerseyShortcutsEnabled(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _jerseyShortcutChannel.invokeMethod<void>('setEnabled', enabled);
    } on MissingPluginException {
      // Widget tests and non-native embedders do not install this channel.
    } on PlatformException {
      // Keyboard shortcuts continue through Flutter's shortcut manager.
    }
  }

  void _syncNativeJerseyShortcuts() {
    unawaited(
      _setNativeJerseyShortcutsEnabled(!captionV2FocusIsEditable()),
    );
  }

  Future<void> _handleNativeShortcut(MethodCall call) async {
    if (!mounted || captionV2FocusIsEditable()) return;
    final args = call.arguments;
    if (args is! Map) return;
    final digit = int.tryParse(args['digit']?.toString() ?? '');
    if (digit == null || digit < 0 || digit > 9) return;
    if (call.method == 'verbDigit') {
      _applyShiftNumber(digit == 0 ? 10 : digit);
    } else if (call.method == 'jerseyDigit') {
      _queueJerseyDigit(digit, isHome: args['isHome'] == true);
    }
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (_controller.searchOpen) return false;
    if (event is! KeyUpEvent || _jerseyBuffer.isEmpty) return false;
    final key = event.logicalKey;
    final modifierReleased = key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.altGraph;
    if (modifierReleased) _flushJerseyBuffer();
    return false;
  }

  void _queueJerseyDigit(int digit, {required bool isHome}) {
    if (_jerseyBufferIsHome != null && _jerseyBufferIsHome != isHome) {
      _flushJerseyBuffer();
    }
    _jerseyBufferIsHome = isHome;
    _jerseyBuffer += '$digit';
    _jerseyBufferTimer?.cancel();
    _jerseyBufferTimer = Timer(
      const Duration(milliseconds: 650),
      _flushJerseyBuffer,
    );
  }

  void _flushJerseyBuffer() {
    _jerseyBufferTimer?.cancel();
    final jersey = _jerseyBuffer;
    final isHome = _jerseyBufferIsHome;
    _jerseyBuffer = '';
    _jerseyBufferIsHome = null;
    if (!mounted || jersey.isEmpty || isHome == null) return;
    final roster = isHome ? _controller.homeRoster : _controller.awayRoster;
    final matches =
        roster.where((player) => player.jerseyNumber?.trim() == jersey);
    if (matches.isEmpty) return;
    _controller.selectPlayer(matches.first, isHome: isHome);
    _setColumnFocus(isHome ? 0 : 2);
  }

  void _applyShiftNumber(int number) {
    final selected = _controller.selectedVerb;
    if (selected == 'Home Run' && number >= 1 && number <= 4) {
      if (number == 4 && _controller.verbDefinition('Grand Slam') != null) {
        _controller.selectVerb('Grand Slam');
      } else {
        _controller.setRbi(number);
      }
      return;
    }
    if (selected != null &&
        _controller.verbNeedsRbi(selected) &&
        number >= 1 &&
        number <= 3) {
      _controller.setRbi(number);
      return;
    }
    if (selected != null &&
        _controller.verbNeedsBase(selected) &&
        number >= 1 &&
        number <= 4) {
      _controller.setSelectedBase(
        const {1: '1B', 2: '2B', 3: '3B', 4: 'Home'}[number],
      );
      return;
    }
    final verbs = _controller.verbsInCategory;
    if (number >= 1 && number <= verbs.length) {
      _controller.selectVerb(verbs[number - 1]);
    }
  }

  void _setColumnFocus(int col) {
    _controller.setColumnFocus(col);
    final width = MediaQuery.sizeOf(context).width;
    if (width < _desktopBreakpoint && _pageController != null) {
      _pageController!.animateToPage(
        col,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _openSearch() {
    _controller.setSearchOpen(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchText.clear();
    _controller.setSearchQuery('');
    _controller.setSearchOpen(false);
    _searchFocus.unfocus();
    _rootFocus.requestFocus();
  }

  void _handleDigit(int digit) {
    if (_controller.searchOpen &&
        (_controller.searchQuery.isNotEmpty || _controller.searchGuided)) {
      _controller.applySearchHitByNumber(digit);
      if (!_controller.searchGuided) {
        _closeSearch();
      } else {
        _searchText.clear();
        _controller.setSearchQuery('');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocus.requestFocus();
        });
      }
      return;
    }
  }

  Future<void> _openFrameReview() async {
    if (_controller.imagePaths.isEmpty) {
      await _controller.pickImageFolder();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: Theme.of(context),
          child: FrameReviewRoute(
            controller: _controller,
            onSavePrevious: _saveAndPrevious,
            onSaveNext: _saveAndNext,
          ),
        ),
      ),
    );
  }

  Future<void> _copySelection() async {
    final payload = CaptionTransferPayload(
      caption: _controller.buildCaptionSentence(),
      personality: _controller.personality,
    );
    await Clipboard.setData(ClipboardData(text: payload.encode()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Caption copied')),
    );
  }

  Future<void> _pasteSelection() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final payload = CaptionTransferPayload.decode(data?.text ?? '');
    if (!mounted) return;
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No caption found on clipboard')),
      );
      return;
    }
    _controller.applyTransferredCaption(payload);
  }

  void _pastePreviousSelection() {
    if (!_controller.applyPreviousCaption()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous caption available')),
      );
    }
  }

  Future<void> _saveAndNext() async {
    await _saveInDirection(next: true);
  }

  Future<void> _saveAndPrevious() async {
    await _saveInDirection(next: false);
  }

  Future<void> _saveTransmitAndNext() async {
    await _saveInDirection(next: true, transmit: true);
  }

  Future<void> _transmitSaved(CaptionSaveResult result) async {
    for (final path in result.succeededPaths) {
      await _controller.transmitPath(path);
    }
  }

  Future<void> _saveInDirection({
    required bool next,
    bool transmit = false,
  }) async {
    final selected = _controller.orderedSelectedImagePaths;
    if (selected.length >= 2) {
      final result = await _controller.savePaths(selected);
      if (!mounted) return;
      if (transmit) await _transmitSaved(result);
      if (!mounted) return;
      _controller.setSelectedImagePaths(result.failedPaths);
      return;
    }

    final chain = _controller.forwardBurstChain;
    if (_controller.burstDetectionEnabled && chain.length > 1) {
      final decision = await _showBurstSaveDialog(chain);
      if (!mounted || decision == null) return;
      if (decision.currentOnly) {
        final result = await _controller.savePaths([chain.first]);
        if (transmit) await _transmitSaved(result);
        if (result.anySucceeded && mounted) {
          next ? _controller.nextFrame() : _controller.prevFrame();
        }
        return;
      }

      final result = await _controller.savePaths(decision.paths);
      if (transmit) await _transmitSaved(result);
      if (result.anySucceeded && mounted) {
        _controller.advancePastHandledChain(chain);
      }
      return;
    }

    final path = _controller.currentPath;
    if (path == null) {
      await _controller.savePaths(const []);
      return;
    }
    final result = await _controller.savePaths([path]);
    if (transmit) await _transmitSaved(result);
    if (result.anySucceeded && mounted) {
      next ? _controller.nextFrame() : _controller.prevFrame();
    }
  }

  Future<_BurstSaveDecision?> _showBurstSaveDialog(
    List<String> chain,
  ) {
    final selected = <String>{...chain};
    return showDialog<_BurstSaveDecision>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final t =
            Theme.of(dialogContext).extension<FfTokens>() ?? FfTokens.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
            backgroundColor: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              side: BorderSide(color: t.divider),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 480,
                maxWidth: 620,
                maxHeight: 620,
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Burst detected',
                      style: t.labelStyle.copyWith(fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Apply this caption to the current frame only, or choose '
                      'frames from the forward burst?',
                      style: t.secondaryLabelStyle,
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.sunken,
                          borderRadius:
                              BorderRadius.circular(FfTokens.radiusCard),
                          border: Border.all(color: t.divider),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: chain.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: t.divider),
                          itemBuilder: (context, index) {
                            final path = chain[index];
                            final checked = selected.contains(path);
                            return CheckboxListTile(
                              dense: true,
                              value: checked,
                              activeColor: t.accent,
                              checkColor: t.bg,
                              title: Text(
                                p.basename(path),
                                style: t.monoMetaStyle.copyWith(color: t.text),
                              ),
                              subtitle: index == 0
                                  ? Text('Current frame', style: t.metaStyle)
                                  : null,
                              onChanged: (value) => setDialogState(() {
                                value == true
                                    ? selected.add(path)
                                    : selected.remove(path);
                              }),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(
                            dialogContext,
                            _BurstSaveDecision.current(),
                          ),
                          child: const Text('Current only'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () => Navigator.pop(
                                    dialogContext,
                                    _BurstSaveDecision.burst(
                                      chain.where(selected.contains).toList(),
                                    ),
                                  ),
                          child: Text('Save selected (${selected.length})'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _withChrome(Widget body, {bool sessionActive = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopChrome(
          controller: sessionActive ? _controller : null,
          onResetSession: sessionActive ? _controller.resetToStartup : null,
        ),
        Expanded(child: body),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final c = _controller;

    if (!c.sessionReady) {
      if (c.sessionLoading) {
        return Scaffold(
          backgroundColor: t.bg,
          body: _withChrome(
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.accent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    c.sessionLoadingLabel ?? 'Loading…',
                    style: t.secondaryLabelStyle,
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return Scaffold(
        backgroundColor: t.bg,
        body: _withChrome(
          CaptionV2StartupScreen(onComplete: _onStartupComplete),
        ),
      );
    }

    return Shortcuts(
      shortcuts: buildCaptionV2Shortcuts(),
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenSearchIntent: CallbackAction<OpenSearchIntent>(
            onInvoke: (_) {
              c.searchOpen ? _closeSearch() : _openSearch();
              return null;
            },
          ),
          CloseSearchIntent: CallbackAction<CloseSearchIntent>(
            onInvoke: (_) {
              if (c.searchOpen || c.searchQuery.isNotEmpty) _closeSearch();
              return null;
            },
          ),
          SaveNextIntent: CaptionV2GuardedAction<SaveNextIntent>(
            onInvoke: (_) {
              unawaited(_saveAndNext());
              return null;
            },
          ),
          SaveTransmitNextIntent:
              CaptionV2GuardedAction<SaveTransmitNextIntent>(
            onInvoke: (_) {
              unawaited(_saveTransmitAndNext());
              return null;
            },
          ),
          PastePreviousIntent: CaptionV2GuardedAction<PastePreviousIntent>(
            onInvoke: (_) {
              _pastePreviousSelection();
              return null;
            },
          ),
          SearchHitIntent: CaptionV2GuardedAction<SearchHitIntent>(
            enabledWhen: () =>
                c.searchOpen && (c.searchQuery.isNotEmpty || c.searchGuided),
            onInvoke: (intent) {
              _handleDigit(intent.digit);
              return null;
            },
          ),
          TransmitIntent: CaptionV2GuardedAction<TransmitIntent>(
            onInvoke: (_) {
              unawaited(c.transmitQueued());
              return null;
            },
          ),
          ApplyLastComboIntent: CaptionV2GuardedAction<ApplyLastComboIntent>(
            onInvoke: (_) {
              c.applyLastUsed();
              unawaited(_saveAndNext());
              return null;
            },
          ),
          NavigateFrameIntent: CaptionV2GuardedAction<NavigateFrameIntent>(
            onInvoke: (intent) {
              c.clearSelectedImagePaths();
              intent.delta < 0 ? c.prevFrame() : c.nextFrame();
              return null;
            },
          ),
          CycleColumnIntent: CaptionV2GuardedAction<CycleColumnIntent>(
            onInvoke: (intent) {
              const columns = 4;
              _setColumnFocus(
                (c.columnFocus + intent.delta + columns) % columns,
              );
              return null;
            },
          ),
          ShiftNumberIntent: CaptionV2GuardedAction<ShiftNumberIntent>(
            onInvoke: (intent) {
              _applyShiftNumber(intent.number);
              return null;
            },
          ),
          JerseyDigitIntent: CaptionV2GuardedAction<JerseyDigitIntent>(
            onInvoke: (intent) {
              _queueJerseyDigit(intent.digit, isHome: intent.isHome);
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          child: Scaffold(
            backgroundColor: t.bg,
            body: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= _desktopBreakpoint) {
                  return _withChrome(
                    _buildDesktopWorkspace(c, t, constraints.maxWidth),
                    sessionActive: true,
                  );
                }
                return _withChrome(
                  _buildMobileWorkspace(c, t),
                  sessionActive: true,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopWorkspace(
    CaptionV2Controller c,
    FfTokens t,
    double workspaceWidth,
  ) {
    final defaultPhotoWidth = (workspaceWidth * 0.33).clamp(460.0, 760.0);
    final minPhotoWidth = workspaceWidth * 0.34;
    final maxPhotoWidth = workspaceWidth * 0.45;
    final photoWidth =
        (_photoWidth ?? defaultPhotoWidth).clamp(minPhotoWidth, maxPhotoWidth);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: photoWidth,
            child: PhotoColumn(
              key: const ValueKey('photo-column-preview-60'),
              controller: c,
              focused: c.columnFocus == 3,
              onSavePrevious: _saveAndPrevious,
              onSaveNext: _saveAndNext,
            ),
          ),
          _WorkspaceResizeHandle(
            tokens: t,
            onDrag: (delta) => setState(() {
              _photoWidth =
                  (photoWidth + delta).clamp(minPhotoWidth, maxPhotoWidth);
            }),
            onReset: () => setState(() => _photoWidth = null),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCaptionStrip(c),
                const SizedBox(height: 8),
                _buildSearchBlock(c),
                SizedBox(height: _gap),
                Expanded(
                  child: _DesktopBody(
                    controller: c,
                    gap: _gap,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileWorkspace(CaptionV2Controller c, FfTokens t) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCaptionStrip(c),
          const SizedBox(height: 8),
          _buildSearchBlock(c),
          SizedBox(height: _gap),
          Expanded(
            child: _MobileBody(
              controller: c,
              pageController: _pageController!,
              onOpenFrame: _openFrameReview,
              onPageChanged: (i) => c.setColumnFocus(i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBlock(CaptionV2Controller c) {
    return SizedBox(
      height: 32,
      child: CaptionV2ActionRow(
        onSavePrevious: _saveAndPrevious,
        onCopy: _copySelection,
        onPaste: _pasteSelection,
        onPastePrevious: _pastePreviousSelection,
        pasteEnabled: true,
        onSaveNext: _saveAndNext,
        onTransmit: c.transmitQueued,
        transmitEnabled: c.savedNotSentCount > 0 || c.currentPath != null,
      ),
    );
  }

  Widget _buildCaptionStrip(CaptionV2Controller c) {
    final isBaseball = c.sport.toLowerCase() == 'baseball';
    return CaptionStrip(
      leading: '',
      chips: const [],
      trailing: '',
      fullCaption: c.manualCaptionOverride ??
          (c.selectedPlayer != null || c.hasVerbSelection
              ? c.buildCaptionSentence()
              : (c.originalCaption.isEmpty
                  ? 'No caption embedded in image.'
                  : c.originalCaption)),
      personality: c.personality,
      onPersonalityChanged: c.showPersonalityField ? c.setPersonality : null,
      headline: c.headline,
      onHeadlineChanged: c.showHeadlineField ? c.setHeadline : null,
      keywords: c.keywords,
      onKeywordsChanged: c.showKeywordsField ? c.setKeywords : null,
      onEditTap: () => _openCaptionStyleEditor(c),
      footer: SizedBox(
        height: c.searchOpen ? 80 : 38,
        child: CaptionV2SearchBar(
          controller: c,
          focusNode: _searchFocus,
          textController: _searchText,
          onActivate: _openSearch,
          onExit: _closeSearch,
        ),
      ),
      inningLabel: c.inningLabel,
      inning: c.inning,
      regulationCount: c.timingRegulationCount,
      maxInning: c.timingMaxInning,
      extraLabel: c.sport.toLowerCase() == 'soccer'
          ? 'ET'
          : (c.sport.toLowerCase() == 'baseball' ? 'X' : 'OT'),
      onInningSelected: c.setInning,
      preSelected: c.preGame,
      postSelected: c.postGame,
      onInningDecrement: () => c.bumpInning(-1),
      onInningIncrement: () => c.bumpInning(1),
      inningDisabled: c.preGame || c.postGame,
      onInningActivate: c.activateInning,
      onPreTap: () => c.setPre(!c.preGame),
      onPostTap: () => c.setPost(!c.postGame),
      mlbTimestampVisible: isBaseball && c.mlbTimestampAvailable,
      mlbTimestampEnabled: c.mlbTimestampEnabled,
      mlbTimestampLoading: c.mlbTimestampLoading,
      mlbTimestampMatched: c.mlbTimestampMatched,
      onMlbTimestampTap: c.toggleMlbTimestamp,
    );
  }

  Future<void> _openCaptionStyleEditor(CaptionV2Controller c) async {
    await CaptionLayoutBuilderDialog.show(context);
    if (!mounted) return;
    await c.reloadCaptionStyle();
  }
}

class _BurstSaveDecision {
  const _BurstSaveDecision._({
    required this.currentOnly,
    this.paths = const [],
  });

  factory _BurstSaveDecision.current() =>
      const _BurstSaveDecision._(currentOnly: true);

  factory _BurstSaveDecision.burst(List<String> paths) =>
      _BurstSaveDecision._(currentOnly: false, paths: paths);

  final bool currentOnly;
  final List<String> paths;
}

class _WorkspaceResizeHandle extends StatelessWidget {
  const _WorkspaceResizeHandle({
    required this.tokens,
    required this.onDrag,
    required this.onReset,
  });

  final FfTokens tokens;
  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        onDoubleTap: onReset,
        child: SizedBox(
          width: 14,
          child: Center(
            child: Container(
              width: 4,
              height: 54,
              decoration: BoxDecoration(
                color: tokens.text.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  const _TopChrome({
    this.controller,
    this.onResetSession,
  });

  final CaptionV2Controller? controller;
  final VoidCallback? onResetSession;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final c = controller;

    return Container(
      height: 30,
      padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          if (c != null)
            Expanded(
              child: _TopPictureInfo(
                controller: c,
                tokens: t,
              ),
            )
          else
            const Spacer(),
          if (c?.rostersLoading == true) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.accent,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (onResetSession != null) ...[
            TextButton(
              onPressed: onResetSession,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Text(
                'Start New Session',
                style: t.metaStyle.copyWith(color: t.accent),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (AdminService.isCurrentUserAdminSync()) ...[
            const AdminBadgeButton(child: _TopAdminBadge()),
            if (defaultTargetPlatform == TargetPlatform.macOS) ...[
              const SizedBox(width: 4),
              _AdminWindowSizeDropdown(tokens: t),
            ],
            const SizedBox(width: 6),
          ],
          if (AuthService.instance.isSignedIn)
            FloHeaderSignedInAs(
              foreground: t.text,
              foregroundMuted: t.textSecondary,
            ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => const PreferencesDialog(),
            ),
            icon: Icon(
              Icons.settings_outlined,
              size: 17,
              color: t.textSecondary,
            ),
            tooltip: 'Options',
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
        ],
      ),
    );
  }
}

class _TopPictureInfo extends StatelessWidget {
  const _TopPictureInfo({
    required this.controller,
    required this.tokens,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;

  String _meta(List<String> keys) {
    for (final key in keys) {
      final value = controller.currentIptcMeta[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  String _formatDateTime(String raw) {
    final match = RegExp(
      r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(raw);
    if (match == null) return raw;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = int.tryParse(match.group(2)!) ?? 0;
    final monthLabel =
        month >= 1 && month <= 12 ? months[month - 1] : match.group(2)!;
    final day = int.tryParse(match.group(3)!) ?? 0;
    return '$monthLabel $day, ${match.group(1)} '
        '${match.group(4)}:${match.group(5)}:${match.group(6)}';
  }

  String _formatShutter(String raw) {
    if (raw.isEmpty || raw.contains('/')) return raw;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return raw;
    return value < 1
        ? '1/${(1 / value).round()}s'
        : '${value.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final path = controller.currentPath;
    final total = controller.imagePaths.length;
    if (path == null || total == 0) {
      return Text('— / —', style: tokens.monoMetaStyle);
    }

    final date = _meta(const [
      'DateTimeOriginal',
      'CreateDate',
      'ModifyDate',
    ]);
    final make = _meta(const ['Make']);
    final model = _meta(const ['Model']);
    final lens = _meta(const ['LensModel', 'Lens', 'LensID']);
    final shutter = _formatShutter(_meta(const ['ShutterSpeed']));
    final fNumber = double.tryParse(_meta(const ['FNumber']));
    final focalRaw =
        _meta(const ['FocalLength']).replaceAll(RegExp(r'm+$'), '').trim();
    final focal = double.tryParse(focalRaw);
    final iso = _meta(const ['ISO']);

    final exposureDetails = <String>[
      if (iso.isNotEmpty) 'ISO $iso',
      if (shutter.isNotEmpty) shutter,
      if (fNumber != null) 'f/${fNumber.toStringAsFixed(1)}',
      if (focalRaw.isNotEmpty)
        focal == null ? '${focalRaw}mm' : '${focal.toInt()}mm',
    ];
    final dateLabel = date.isEmpty ? '' : _formatDateTime(date);
    final remainingSpans = <InlineSpan>[];
    void addRemainingDetail(String value) {
      if (value.isEmpty) return;
      if (remainingSpans.isNotEmpty) {
        remainingSpans.add(
          TextSpan(
            text: '  ·  ',
            style: TextStyle(
              color: tokens.textSecondary.withValues(alpha: 0.55),
            ),
          ),
        );
      }
      remainingSpans.add(
        TextSpan(
          text: value,
          style: TextStyle(color: tokens.textSecondary),
        ),
      );
    }

    addRemainingDetail('$make $model'.trim());
    addRemainingDetail(lens);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: tokens.selectedFill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${controller.currentIndex + 1}/$total',
            style: tokens.monoMetaStyle.copyWith(
              color: tokens.accent,
              fontSize: tokens.textSizeMicro,
              fontWeight: FfTokens.weightMedium,
            ),
          ),
        ),
        const SizedBox(width: 6),
        if (exposureDetails.isNotEmpty) ...[
          Text(
            exposureDetails.join(' · '),
            maxLines: 1,
            style: tokens.metaStyle.copyWith(
              color: tokens.accent,
              fontSize: tokens.textSizeMicro,
              fontWeight: FfTokens.weightMedium,
            ),
          ),
        ],
        if (dateLabel.isNotEmpty || remainingSpans.isNotEmpty) ...[
          const SizedBox(width: 6),
          Container(
            width: 1,
            height: 14,
            color: tokens.accent.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 6),
        ],
        if (dateLabel.isNotEmpty)
          Text(
            dateLabel,
            maxLines: 1,
            style: tokens.metaStyle.copyWith(
              color: tokens.textSecondary,
              fontSize: tokens.textSizeMicro,
            ),
          ),
        if (dateLabel.isNotEmpty && remainingSpans.isNotEmpty) ...[
          const SizedBox(width: 6),
          Container(
            width: 1,
            height: 14,
            color: tokens.accent.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 6),
        ],
        if (remainingSpans.isNotEmpty)
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: tokens.metaStyle.copyWith(
                  fontSize: tokens.textSizeMicro,
                ),
                children: remainingSpans,
              ),
            ),
          ),
        const SizedBox(width: 6),
      ],
    );
  }
}

class _TopAdminBadge extends StatelessWidget {
  const _TopAdminBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x59E8C547),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE8C547)),
      ),
      child: const Text(
        'Admin',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: Color(0xFFFFF3C4),
          height: 1,
        ),
      ),
    );
  }
}

class _AdminWindowSizeDropdown extends StatelessWidget {
  const _AdminWindowSizeDropdown({required this.tokens});

  static const MethodChannel _windowChannel = MethodChannel('window_control');
  static const _compact = '1280x800';
  static const _standard = '1400x900';
  static const _large = '1600x1000';

  final FfTokens tokens;

  Future<void> _resize(BuildContext context, String value) async {
    final parts = value.split('x');
    if (parts.length != 2) return;
    try {
      await _windowChannel.invokeMethod<void>('setContentSize', {
        'width': int.parse(parts[0]),
        'height': int.parse(parts[1]),
      });
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resize window: ${error.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final value = size.width >= 1500 && size.height >= 950
        ? _large
        : size.width < 1340 || size.height < 850
            ? _compact
            : _standard;
    return Container(
      width: 124,
      height: 22,
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(
        color: tokens.sunken,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          dropdownColor: tokens.surface,
          icon: Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: tokens.textSecondary,
          ),
          style: tokens.monoMetaStyle.copyWith(
            color: tokens.text,
            fontSize: tokens.textSizeMicro,
          ),
          items: const [
            DropdownMenuItem(value: _compact, child: Text('1280 × 800')),
            DropdownMenuItem(value: _standard, child: Text('1400 × 900')),
            DropdownMenuItem(value: _large, child: Text('1600 × 1000')),
          ],
          onChanged: (next) {
            if (next != null) _resize(context, next);
          },
        ),
      ),
    );
  }
}

class _DesktopBody extends StatefulWidget {
  const _DesktopBody({
    required this.controller,
    required this.gap,
  });

  final CaptionV2Controller controller;
  final double gap;

  @override
  State<_DesktopBody> createState() => _DesktopBodyState();
}

class _DesktopBodyState extends State<_DesktopBody> {
  /// Default picker view (scroll list). Null returns to the classic columns.
  DrumPickerMode? _drumMode = DrumPickerMode.scroll;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (_drumMode != null && !controller.searchOpen) {
      return DesktopDrumPicker(
        controller: controller,
        mode: _drumMode!,
        onModeChanged: (mode) => setState(() => _drumMode = mode),
        onExit: () => setState(() => _drumMode = null),
      );
    }

    final laneRow = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: controller.searchOpen ? 4 : 1,
          child: RosterColumn(
            controller: controller,
            isHome: true,
            focused: controller.columnFocus == 0,
            onDrumRequested: () =>
                setState(() => _drumMode = DrumPickerMode.scroll),
            onInfiniteRequested: () =>
                setState(() => _drumMode = DrumPickerMode.infinite),
          ),
        ),
        SizedBox(width: widget.gap),
        Expanded(
          flex: controller.searchOpen ? 5 : 1,
          child: VerbsColumn(
            controller: controller,
            focused: controller.columnFocus == 1,
            onDrumRequested: () =>
                setState(() => _drumMode = DrumPickerMode.scroll),
            onInfiniteRequested: () =>
                setState(() => _drumMode = DrumPickerMode.infinite),
          ),
        ),
        SizedBox(width: widget.gap),
        Expanded(
          flex: controller.searchOpen ? 4 : 1,
          child: RosterColumn(
            controller: controller,
            isHome: false,
            focused: controller.columnFocus == 2,
            onDrumRequested: () =>
                setState(() => _drumMode = DrumPickerMode.scroll),
            onInfiniteRequested: () =>
                setState(() => _drumMode = DrumPickerMode.infinite),
          ),
        ),
      ],
    );
    if (!controller.searchOpen) return laneRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: laneRow),
        _FirebarMatchFooter(controller: controller),
      ],
    );
  }
}

class _MobileBody extends StatelessWidget {
  const _MobileBody({
    required this.controller,
    required this.pageController,
    required this.onOpenFrame,
    required this.onPageChanged,
  });

  final CaptionV2Controller controller;
  final PageController pageController;
  final VoidCallback onOpenFrame;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final focus = controller.columnFocus;

    return Column(
      children: [
        MobileFrameThumb(controller: controller, onOpen: onOpenFrame),
        const SizedBox(height: 10),
        Row(
          children: [
            _MobileTab(
              label: controller.homeAbbr,
              selected: focus == 0,
              tokens: t,
              onTap: () {
                onPageChanged(0);
                pageController.animateToPage(
                  0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                );
              },
            ),
            _MobileTab(
              label: 'VERBS',
              selected: focus == 1,
              tokens: t,
              onTap: () {
                onPageChanged(1);
                pageController.animateToPage(
                  1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                );
              },
            ),
            _MobileTab(
              label: controller.awayAbbr,
              selected: focus == 2,
              tokens: t,
              onTap: () {
                onPageChanged(2);
                pageController.animateToPage(
                  2,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: PageView(
            controller: pageController,
            onPageChanged: onPageChanged,
            children: [
              RosterColumn(
                controller: controller,
                isHome: true,
                focused: focus == 0,
              ),
              VerbsColumn(
                controller: controller,
                focused: focus == 1,
              ),
              RosterColumn(
                controller: controller,
                isHome: false,
                focused: focus == 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: focus == i ? t.accent : t.badgeFill,
                ),
              ),
          ],
        ),
        if (controller.searchOpen) _FirebarMatchFooter(controller: controller),
      ],
    );
  }
}

class _FirebarMatchFooter extends StatelessWidget {
  const _FirebarMatchFooter({required this.controller});

  final CaptionV2Controller controller;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final query = controller.searchQuery.trim();
    return Container(
      height: 28,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: query.isEmpty
          ? const SizedBox.shrink()
          : Text.rich(
              TextSpan(
                style: tokens.metaStyle.copyWith(
                  color: tokens.textSecondary,
                  fontSize: 12,
                ),
                children: [
                  const TextSpan(text: 'Matching '),
                  TextSpan(
                    text: query,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        ' — ${controller.firebarMatchedCount} of ${controller.firebarTotalCount}',
                  ),
                ],
              ),
            ),
    );
  }
}

class _MobileTab extends StatelessWidget {
  const _MobileTab({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? tokens.accent : tokens.divider,
                width: selected ? 2 : 1,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: tokens.labelStyle.copyWith(
              color: selected ? tokens.text : tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
