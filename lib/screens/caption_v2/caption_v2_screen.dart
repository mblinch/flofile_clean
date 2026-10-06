import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../services/mlb_api_service.dart';
import '../../theme/ff_glow.dart';
import '../../theme/ff_tokens.dart';
import '../../widgets/admin_screen.dart';
import '../../widgets/app_styled_dialogs.dart';
import '../../widgets/caption_layout_builder_dialog.dart';
import '../../widgets/flo_chrome_header.dart';
import '../../widgets/oriented_file_preview.dart';
import '../../widgets/preferences_dialog.dart';
import 'caption_v2_flag.dart';
import 'caption_v2_shortcuts.dart';
import 'data/caption_transfer_payload.dart';
import 'data/caption_v2_controller.dart';
import 'layout/duplicate_jersey_dialog.dart';
import 'layout/caption_v2_search.dart';
import 'layout/caption_v2_startup_screen.dart';
import 'layout/desktop_drum_picker.dart';
import 'layout/frame_review_route.dart';
import 'layout/photo_column.dart';
import 'layout/roster_column.dart';
import 'layout/roster_import_dialog.dart';
import 'layout/verbs_column.dart';
import 'widgets/caption_strip.dart';
import 'widgets/ftp_history_dialog.dart';
import 'widgets/transmit_dock.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

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
  bool _burstSaveDialogOpen = false;
  VoidCallback? _confirmBurstSaveSelected;

  static const double _desktopBreakpoint = 1100;
  static double get _gap => 8;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
    _controller.addListener(_onController);
    _controller.onSaveTransmit = ({required bool transmit}) async {
      await _saveInDirection(next: true, transmit: transmit);
    };
    _controller.confirmRetransmit = (alreadySent) async {
      if (!mounted || alreadySent.isEmpty) return false;
      final single = alreadySent.length == 1;
      final ok = await showAppConfirmDialog(
        context: context,
        title: 'Already uploaded',
        message: single
            ? 'You have already uploaded this, do you want to upload it again?'
            : 'You have already uploaded ${alreadySent.length} of these. Upload them again?',
        cancelLabel: 'Cancel',
        confirmLabel: 'Upload again',
      );
      return ok == true;
    };
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
      if (status != null && (_isErrorStatus(status) || _isFtpStatus(status))) {
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
        value.startsWith('configure ') ||
        value.startsWith('ftp ') ||
        value.contains('not enabled') ||
        value.contains(' failed') ||
        value.contains('incomplete') ||
        value.endsWith('failed');
  }

  static bool _isFtpStatus(String message) {
    final value = message.toLowerCase();
    return value.startsWith('ftp ') ||
        value.startsWith('sent ') ||
        value.startsWith('configure ') ||
        value.contains('ftp');
  }

  Future<void> _onStartupComplete(CaptionV2StartupResult result) async {
    await _controller.applyStartup(
      sport: result.sport,
      homeTeam: result.homeTeam,
      awayTeam: result.awayTeam,
      folderPath: result.folderPath,
      homeRosterOverride: result.homeRoster,
      awayRosterOverride: result.awayRoster,
      singleTeamMode: result.singleTeamMode,
    );
    if (!mounted) return;
    await _confirmLoadedDuplicateJerseys(result);
  }

  Future<void> _confirmLoadedDuplicateJerseys(
    CaptionV2StartupResult result,
  ) async {
    List<Player>? home;
    List<Player>? away;
    if (result.homeRoster == null && _controller.homeRoster.isNotEmpty) {
      home = await confirmDuplicateJerseys(
        context,
        players: _controller.homeRoster,
        teamName: _controller.homeTeam,
        sportId: _controller.sport,
      );
      if (!mounted) return;
    }
    final awayWasLoaded = !result.singleTeamMode && result.awayRoster == null;
    if (awayWasLoaded && _controller.awayRoster.isNotEmpty) {
      away = await confirmDuplicateJerseys(
        context,
        players: _controller.awayRoster,
        teamName: _controller.awayTeam,
        sportId: _controller.sport,
      );
      if (!mounted) return;
    }
    if (home == null && away == null) return;
    _controller.replaceLoadedRosters(home: home, away: away);
  }

  @override
  void dispose() {
    _jerseyBufferTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    FocusManager.instance.removeListener(_syncNativeJerseyShortcuts);
    _jerseyShortcutChannel.setMethodCallHandler(null);
    unawaited(_setNativeJerseyShortcutsEnabled(true));
    _controller.onSaveTransmit = null;
    _controller.confirmRetransmit = null;
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
    if (_handleSaveShortcut(event)) return true;

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

  /// Global ⌘S / Ctrl+S / Shift+Enter / ⌘⇧Enter — same reliability as V1.
  ///
  /// Flutter [Shortcuts] only fire when focus is inside that subtree; this
  /// handler still works when focus is in a text field, drum lane, or lost.
  bool _handleSaveShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final keys = HardwareKeyboard.instance;
    final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    final isS = event.logicalKey == LogicalKeyboardKey.keyS;

    // Burst picker: Enter / ⌘S confirm "Save selected" even if focus left
    // the dialog Shortcuts subtree (e.g. landed on Cancel).
    if (_burstSaveDialogOpen) {
      final confirmSelected = isEnter &&
          !keys.isShiftPressed &&
          !keys.isMetaPressed &&
          !keys.isControlPressed &&
          !keys.isAltPressed;
      final confirmCmdS = isS &&
          (keys.isMetaPressed || keys.isControlPressed) &&
          !keys.isShiftPressed &&
          !keys.isAltPressed;
      if (confirmSelected || confirmCmdS) {
        _confirmBurstSaveSelected?.call();
        return true;
      }
      return false;
    }

    if (!_controller.sessionReady || _controller.sessionLoading) return false;

    final saveTransmit = isEnter &&
        keys.isShiftPressed &&
        (keys.isMetaPressed || keys.isControlPressed);
    if (saveTransmit) {
      if (_controller.searchOpen &&
          (_controller.firebarCanQuickSavePlayer ||
              _controller.firebarCanQuickSaveVerb)) {
        _controller.commitSelectedFirebarResult();
        _searchText.clear();
      }
      if (_controller.ftpModeEnabled) {
        unawaited(_saveTransmitAndNext());
      } else {
        unawaited(_saveAndNext());
      }
      return true;
    }

    final shiftEnter = isEnter &&
        keys.isShiftPressed &&
        !keys.isMetaPressed &&
        !keys.isControlPressed &&
        !keys.isAltPressed;
    final cmdS = isS &&
        (keys.isMetaPressed || keys.isControlPressed) &&
        !keys.isShiftPressed &&
        !keys.isAltPressed;
    if (!shiftEnter && !cmdS) return false;

    // Firebar: Shift+Enter commits the highlighted player before save, or
    // picks Save from the destination chips (which already triggers save).
    if (shiftEnter && _controller.searchOpen) {
      if (_controller.firebarShowShiftEnterSaveHint) {
        final fullyHandled = _controller.commitFirebarForShiftEnterSave();
        _searchText.clear();
        if (fullyHandled) return true;
      }
    }

    unawaited(_saveAndNext());
    return true;
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
      caption: _controller.displayedCaption,
      personality: _controller.personality,
      headline: _controller.headline,
      keywords: _controller.keywords,
      photographerName: _controller.photographerName,
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
    await _controller.applyTransferredCaption(payload);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Caption pasted')),
    );
  }

  Future<void> _pastePreviousSelection() async {
    if (!await _controller.applyPreviousCaption()) {
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

  /// Save current (with burst UI if needed) and FTP, without changing frames.
  Future<void> _saveAndFtpCurrent() async {
    await _saveInDirection(next: true, transmit: true, advance: false);
  }

  Future<void> _transmitSaved(CaptionSaveResult result) async {
    for (final path in result.succeededPaths) {
      await _controller.transmitPath(path);
    }
  }

  Future<void> _saveInDirection({
    required bool next,
    bool transmit = false,
    bool advance = true,
  }) async {
    // Avoid stacking another burst picker while one is already open
    // (e.g. ⌘S while the dialog is visible).
    if (_burstSaveDialogOpen) return;

    final keepFirebar = _controller.searchOpen;

    void restoreFirebarFocus() {
      if (!keepFirebar || !mounted) return;
      _searchText.clear();
      if (!_controller.searchOpen) {
        _controller.setSearchOpen(true);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }

    final selected = _controller.orderedSelectedImagePaths;
    if (selected.length >= 2) {
      final burstGroup = _controller.burstGroupOverlapping(selected);
      final alreadySaved = selected.every(_controller.savedImages.contains);
      if (burstGroup != null && !alreadySaved) {
        final decision = await _showBurstSaveDialog(
          burstGroup,
          initiallySelected: selected.toSet(),
        );
        if (!mounted || decision == null) return;
        if (decision.currentOnly) {
          final result = await _controller.savePaths(selected);
          if (!mounted) return;
          if (transmit) await _transmitSaved(result);
          if (!mounted) return;
          _controller.setSelectedImagePaths(result.failedPaths);
          restoreFirebarFocus();
          return;
        }
        final result = await _controller.savePaths(decision.paths);
        if (!mounted) return;
        if (transmit) await _transmitSaved(result);
        if (!mounted) return;
        _controller.setSelectedImagePaths(result.failedPaths);
        if (result.anySucceeded && advance) {
          _controller.advanceAfterBurstSelection(
            chain: burstGroup,
            savedPaths: decision.paths,
            keepSearchOpen: keepFirebar,
          );
          restoreFirebarFocus();
        }
        return;
      }

      final result = await _controller.savePaths(selected);
      if (!mounted) return;
      if (transmit) await _transmitSaved(result);
      if (!mounted) return;
      _controller.setSelectedImagePaths(result.failedPaths);
      restoreFirebarFocus();
      return;
    }

    final chain = _controller.forwardBurstChain;
    final anchorAlreadySaved =
        chain.isNotEmpty && _controller.savedImages.contains(chain.first);
    if (chain.length > 1 && !anchorAlreadySaved) {
      final decision = await _showBurstSaveDialog(chain);
      if (!mounted || decision == null) return;
      if (decision.currentOnly) {
        final result = await _controller.savePaths([chain.first]);
        if (transmit) await _transmitSaved(result);
        if (result.anySucceeded && mounted && advance) {
          next
              ? _controller.nextFrame(keepSearchOpen: keepFirebar)
              : _controller.prevFrame(keepSearchOpen: keepFirebar);
          restoreFirebarFocus();
        }
        return;
      }

      final result = await _controller.savePaths(decision.paths);
      if (transmit) await _transmitSaved(result);
      if (result.anySucceeded && mounted && advance) {
        _controller.advanceAfterBurstSelection(
          chain: chain,
          savedPaths: decision.paths,
          keepSearchOpen: keepFirebar,
        );
        restoreFirebarFocus();
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
    if (result.anySucceeded && mounted && advance) {
      next
          ? _controller.nextFrame(keepSearchOpen: keepFirebar)
          : _controller.prevFrame(keepSearchOpen: keepFirebar);
      restoreFirebarFocus();
    }
  }

  Future<_BurstSaveDecision?> _showBurstSaveDialog(
    List<String> chain, {
    Set<String>? initiallySelected,
  }) async {
    final fromSelection = initiallySelected != null;
    final selected = <String>{
      ...(initiallySelected == null
          ? chain
          : chain.where(initiallySelected.contains)),
    };
    if (selected.isEmpty) selected.addAll(chain);

    _burstSaveDialogOpen = true;
    try {
      return await showDialog<_BurstSaveDecision>(
        context: context,
        barrierDismissible: true,
        useRootNavigator: true,
        builder: (dialogContext) {
          final t =
              Theme.of(dialogContext).extension<FfTokens>() ?? FfTokens.dark;

          var closed = false;
          void closeWith(_BurstSaveDecision? decision) {
            if (closed) return;
            closed = true;
            _confirmBurstSaveSelected = null;
            _burstSaveDialogOpen = false;
            final nav = Navigator.of(dialogContext, rootNavigator: true);
            if (nav.canPop()) nav.pop(decision);
          }

          return StatefulBuilder(
            builder: (context, setDialogState) {
              void saveSelected() {
                if (selected.isEmpty || closed) return;
                closeWith(
                  _BurstSaveDecision.burst(
                    chain.where(selected.contains).toList(),
                  ),
                );
              }

              void saveCurrentOnly() {
                if (closed) return;
                closeWith(_BurstSaveDecision.current());
              }

              _confirmBurstSaveSelected = saveSelected;

              // Enter / ⌘S are handled by the screen hardware key handler so we
              // do not also bind them here (that double-popped the root nav).
              return Dialog(
                backgroundColor: t.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                  side: BorderSide(color: t.divider),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 480,
                    maxWidth: math.min(
                      720,
                      MediaQuery.sizeOf(dialogContext).width * 0.92,
                    ),
                    maxHeight: math.min(
                      640,
                      MediaQuery.sizeOf(dialogContext).height * 0.85,
                    ),
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
                          fromSelection
                              ? 'Your selection is part of a ${chain.length}-frame '
                                  'burst. Save the selection only, or choose frames '
                                  'from the full burst?'
                              : 'Apply this caption to the current frame only, or '
                                  'choose frames from the forward burst?',
                          style: t.secondaryLabelStyle,
                        ),
                        const SizedBox(height: 14),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: t.sunken,
                              borderRadius: BorderRadius.circular(
                                FfTokens.radiusCard,
                              ),
                              border: Border.all(color: t.divider),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                const spacing = 8.0;
                                final n = chain.length;
                                final cols = math
                                    .min(
                                      4,
                                      math.max(1, math.sqrt(n).ceil()),
                                    )
                                    .toInt();
                                final cellW = (constraints.maxWidth -
                                        (cols - 1) * spacing) /
                                    cols;
                                final cacheW = (cellW *
                                        MediaQuery.devicePixelRatioOf(
                                          context,
                                        ))
                                    .round()
                                    .clamp(96, 512);
                                return GridView.builder(
                                  shrinkWrap: true,
                                  itemCount: n,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    crossAxisSpacing: spacing,
                                    mainAxisSpacing: spacing,
                                    childAspectRatio: 1,
                                  ),
                                  itemBuilder: (context, index) {
                                    final path = chain[index];
                                    final checked = selected.contains(path);
                                    final isCurrent =
                                        !fromSelection && index == 0;
                                    return Tooltip(
                                      message: isCurrent
                                          ? '${p.basename(path)} — current frame'
                                          : p.basename(path),
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: GestureDetector(
                                          onTap: () => setDialogState(() {
                                            checked
                                                ? selected.remove(path)
                                                : selected.add(path);
                                          }),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 120,
                                            ),
                                            decoration: BoxDecoration(
                                              color: t.bg,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                FfTokens.radiusTile,
                                              ),
                                              border: Border.all(
                                                color: checked
                                                    ? (isCurrent
                                                        ? t.accent
                                                        : t.accent.withValues(
                                                            alpha: 0.7,
                                                          ))
                                                    : t.divider,
                                                width: checked || isCurrent
                                                    ? 2
                                                    : 1,
                                              ),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                FfTokens.radiusTile - 1,
                                              ),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  ColoredBox(color: t.bg),
                                                  OrientedFilePreview(
                                                    path: path,
                                                    version: _controller
                                                        .imageContentStamp(
                                                            path),
                                                    fit: BoxFit.cover,
                                                    cacheWidth: cacheW,
                                                    filterQuality:
                                                        FilterQuality.medium,
                                                  ),
                                                  if (!checked)
                                                    ColoredBox(
                                                      color: Colors.black
                                                          .withValues(
                                                        alpha: 0.45,
                                                      ),
                                                    ),
                                                  if (isCurrent)
                                                    Positioned(
                                                      left: 6,
                                                      top: 6,
                                                      child: Material(
                                                        color: t.accent,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                          FfTokens.radiusChip,
                                                        ),
                                                        child: InkWell(
                                                          onTap:
                                                              saveCurrentOnly,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                            FfTokens.radiusChip,
                                                          ),
                                                          child: Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                              horizontal: 5,
                                                              vertical: 2,
                                                            ),
                                                            child: Text(
                                                              'Current',
                                                              style: t.metaStyle
                                                                  .copyWith(
                                                                color: t.bg,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontSize: 10,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  Positioned(
                                                    right: 6,
                                                    bottom: 6,
                                                    child: Container(
                                                      width: 22,
                                                      height: 22,
                                                      decoration: BoxDecoration(
                                                        color: checked
                                                            ? t.accent
                                                            : t.surface
                                                                .withValues(
                                                                alpha: 0.9,
                                                              ),
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: checked
                                                              ? t.accent
                                                              : t.divider,
                                                        ),
                                                      ),
                                                      child: Icon(
                                                        checked
                                                            ? PhosphorIconsRegular.check
                                                            : PhosphorIconsRegular.x,
                                                        size: 14,
                                                        color: checked
                                                            ? t.bg
                                                            : t.textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => closeWith(null),
                              child: const Text('Cancel'),
                            ),
                            const Spacer(),
                            OutlinedButton(
                              onPressed: saveCurrentOnly,
                              child: Text(
                                fromSelection
                                    ? 'Selection only'
                                    : 'Current only',
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: selected.isEmpty ? null : saveSelected,
                              child: Text(
                                'Save selected (${selected.length})',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _burstSaveDialogOpen = false;
      _confirmBurstSaveSelected = null;
    }
  }

  Future<void> _editRosters() async {
    final c = _controller;
    final result = await showRosterImportDialog(
      context,
      sport: c.sport,
      homeTeamLabel: c.homeTeam,
      awayTeamLabel: c.singleTeamMode ? null : c.awayTeam,
      homePlayers: c.homeRoster,
      awayPlayers: c.singleTeamMode ? null : c.awayRoster,
      title: 'Edit rosters',
      saveLabel: 'Save',
      subtitle: 'Rename teams, paste a new roster, or add players.',
    );
    if (!mounted || result == null) return;
    c.applyRosterEdits(
      homeTeamName: result.homeTeamName,
      homePlayers: result.homePlayers,
      awayTeamName: result.awayTeamName,
      awayPlayers: result.awayPlayers,
    );
  }

  Widget _withChrome(
    Widget body, {
    bool sessionActive = false,
    String? title,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopChrome(
          controller: sessionActive ? _controller : null,
          onResetSession: sessionActive ? _controller.resetToStartup : null,
          title: title,
        ),
        Expanded(child: body),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final c = _controller;

    if (c.sessionLoading) {
      return Scaffold(
        backgroundColor: t.bg,
        body: _withChrome(
          _SessionLoadingPane(
            tokens: t,
            label: c.sessionLoadingLabel ?? 'Loading…',
          ),
          title: c.sessionReady ? 'Loading folder' : 'New Session',
        ),
      );
    }

    if (!c.sessionReady) {
      return Scaffold(
        backgroundColor: t.bg,
        body: _withChrome(
          CaptionV2StartupScreen(onComplete: _onStartupComplete),
          title: 'New Session',
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
          // Save shortcuts stay active in text fields (like ⌘S in any editor).
          SaveNextIntent: CallbackAction<SaveNextIntent>(
            onInvoke: (_) {
              unawaited(_saveAndNext());
              return null;
            },
          ),
          SaveTransmitNextIntent: CallbackAction<SaveTransmitNextIntent>(
            onInvoke: (_) {
              if (!c.ftpModeEnabled) return null;
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
            enabledWhen: () => c.ftpModeEnabled && !c.transmitting,
            onInvoke: (_) {
              unawaited(_saveAndFtpCurrent());
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
              if (!c.singleTeamMode) {
                const columns = 4;
                _setColumnFocus(
                  (c.columnFocus + intent.delta + columns) % columns,
                );
                return null;
              }
              // Home → verbs → thumbnails (skip away).
              const order = [0, 1, 3];
              var i = order.indexOf(c.columnFocus);
              if (i < 0) i = 1;
              final next =
                  order[(i + intent.delta + order.length) % order.length];
              _setColumnFocus(next);
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
              if (c.singleTeamMode && !intent.isHome) return null;
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
                final useMobile = kCaptionV2MobilePreview ||
                    constraints.maxWidth < _desktopBreakpoint;
                if (!useMobile) {
                  return _withChrome(
                    _buildDesktopWorkspace(c, t, constraints.maxWidth),
                    sessionActive: true,
                  );
                }
                final mobile = _withChrome(
                  _buildMobileWorkspace(c, t),
                  sessionActive: true,
                );
                if (!kCaptionV2MobilePreview) return mobile;
                // Phone-width frame so desktop can preview the swipe layout.
                return ColoredBox(
                  color: t.bg,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 390,
                        maxHeight: 844,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: t.divider),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: mobile,
                        ),
                      ),
                    ),
                  ),
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
                    onEditRosters: _editRosters,
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
          MobileFrameBanner(
            controller: c,
            onOpen: _openFrameReview,
          ),
          const SizedBox(height: 8),
          _buildCaptionStrip(c, inningStepperOnly: true),
          const SizedBox(height: 8),
          _buildSearchBlock(c),
          SizedBox(height: _gap),
          Expanded(
            child: _MobileBody(
              controller: c,
              pageController: _pageController!,
              onPageChanged: (i) => c.setColumnFocus(i),
              onEditRosters: _editRosters,
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
        onTransmit: () => unawaited(_saveAndFtpCurrent()),
        transmitLabel: c.ftpButtonLabel,
        transmitEnabled: !c.transmitting &&
            (c.savedNotSentCount > 0 || c.currentPath != null),
        showTransmit: c.ftpModeEnabled,
        onFtpHistory: c.ftpModeEnabled
            ? () => showFtpHistoryDialog(context, c)
            : null,
      ),
    );
  }

  Widget _buildCaptionStrip(
    CaptionV2Controller c, {
    bool inningStepperOnly = false,
  }) {
    final isBaseball = c.sport.toLowerCase() == 'baseball';
    final hasLiveCaption = c.manualCaptionOverride != null ||
        c.selectedPlayer != null ||
        (c.hasVerbSelection && !c.pinDefersCaptionUntilPlayer) ||
        c.originalCaption.trim().isNotEmpty;
    final captionText = c.displayedCaption;
    return CaptionStrip(
      leading: '',
      chips: const [],
      trailing: '',
      fullCaption: captionText,
      highlightPhrases: c.firebarInsertedHighlights,
      captionHint: hasLiveCaption
          ? 'Caption will appear here as you add players and a verb.'
          : 'No caption embedded in image.',
      onCaptionChanged: c.setManualCaption,
      personality: c.personality,
      onPersonalityChanged: c.showPersonalityField ? c.setPersonality : null,
      headline: c.headline,
      onHeadlineChanged: c.showHeadlineField ? c.setHeadline : null,
      keywords: c.keywords,
      onKeywordsChanged: c.showKeywordsField ? c.setKeywords : null,
      onEditTap: () => _openCaptionStyleEditor(c),
      footer: SizedBox(
        height: c.searchOpen ? 72 : 32,
        child: CaptionV2SearchBar(
          controller: c,
          focusNode: _searchFocus,
          textController: _searchText,
          onActivate: _openSearch,
          onExit: _closeSearch,
        ),
      ),
      inningLabel: c.inningLabel,
      timingUnitLabel: c.timingUnitTitle,
      inning: c.inning,
      regulationCount: c.timingRegulationCount,
      maxInning: c.timingMaxInning,
      segmentPrefix: c.supportsTimingHalves ? 'Q' : null,
      selectedHalf: c.timingHalf,
      onHalfSelected:
          inningStepperOnly || !c.supportsTimingHalves ? null : c.setTimingHalf,
      extraLabel: c.sport.toLowerCase() == 'soccer'
          ? 'ET'
          : (c.sport.toLowerCase() == 'baseball' ? 'X' : 'OT'),
      onInningSelected: inningStepperOnly ? null : c.setInning,
      preSelected: c.preGame,
      postSelected: c.postGame,
      onInningDecrement: () => c.bumpInning(-1),
      onInningIncrement: () => c.bumpInning(1),
      inningDisabled: c.preGame || c.postGame,
      onInningActivate: c.activateInning,
      timingPhraseEnabled: c.includeTimingPhrase,
      onTimingPhraseEnabledChanged: c.setIncludeTimingPhrase,
      onPreTap: inningStepperOnly ? null : () => c.setPre(!c.preGame),
      onPostTap: inningStepperOnly ? null : () => c.setPost(!c.postGame),
      inningStepperOnly: inningStepperOnly,
      mlbTimestampVisible:
          !inningStepperOnly && isBaseball && c.mlbTimestampAvailable,
      mlbTimestampEnabled: c.mlbTimestampEnabled,
      mlbTimestampLoading: c.mlbTimestampLoading,
      mlbTimestampMatched: c.mlbTimestampMatched,
      onMlbTimestampTap: c.toggleMlbTimestamp,
    );
  }

  Future<void> _openCaptionStyleEditor(CaptionV2Controller c) async {
    final applied = await CaptionLayoutBuilderDialog.show(context);
    if (!mounted) return;
    if (applied != null) {
      c.captionTemplate = applied;
      await c.reloadCaptionStyle();
      return;
    }
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
    this.title,
  });

  final CaptionV2Controller? controller;
  final VoidCallback? onResetSession;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final c = controller;
    final headerTitle = title?.trim();

    return Container(
      height: 38,
      padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          if (onResetSession != null)
            Tooltip(
              message: 'Start a new caption session',
              waitDuration: const Duration(milliseconds: 400),
              child: Material(
                color: t.elevated,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: onResetSession,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: t.accentEdge),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PhosphorIcon(PhosphorIconsRegular.arrowClockwise,
                          size: 15,
                          color: t.text,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'Start New Session',
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                            height: 1,
                            color: t.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (headerTitle != null && headerTitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: FfGlow(
                // Keep the spotlight centre on the letters — a tall ellipse
                // drops the bright core well below a single-line title.
                glowX: -0.20,
                glowY: -1.10,
                glowW: 168,
                glowH: 40,
                child: Text(
                  headerTitle,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    height: 1,
                    color: t.text,
                  ),
                ),
              ),
            ),
          const Spacer(),
          if (c != null) ...[
            FtpModeToggle(
              enabled: c.ftpModeEnabled,
              tokens: t,
              onChanged: c.setFtpModeEnabled,
            ),
            const SizedBox(width: 8),
          ],
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
          if (AdminService.isCurrentUserAdminSync() &&
              defaultTargetPlatform == TargetPlatform.macOS) ...[
            const SizedBox(width: 4),
            _AdminWindowSizeDropdown(tokens: t),
          ],
          if (AuthService.instance.isSignedIn) ...[
            const SizedBox(width: 4),
            FloHeaderSignedInAs(
              foreground: t.text,
              foregroundMuted: t.textSecondary,
            ),
          ],
          if (AdminService.isCurrentUserAdminSync()) ...[
            const SizedBox(width: 4),
            const AdminBadgeButton(child: _TopAdminBadge()),
          ],
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => const PreferencesDialog(),
            ),
            icon: PhosphorIcon(PhosphorIconsRegular.gear,
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

class _TopAdminBadge extends StatelessWidget {
  const _TopAdminBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: FfTokens.gold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Admin',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: FfTokens.inkOnGold,
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
        color: tokens.elevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          isExpanded: true,
          dropdownColor: tokens.surface,
          icon: PhosphorIcon(PhosphorIconsRegular.caretDown,
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
    required this.onEditRosters,
  });

  final CaptionV2Controller controller;
  final double gap;
  final VoidCallback onEditRosters;

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
      return DrumPicker(
        controller: controller,
        layout: DrumLayout.sideBySide,
        mode: _drumMode!,
        onModeChanged: (mode) => setState(() => _drumMode = mode),
        onExit: () => setState(() => _drumMode = null),
        onEditRosters: widget.onEditRosters,
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
            onEditRosters: widget.onEditRosters,
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
        if (!controller.singleTeamMode) ...[
          SizedBox(width: widget.gap),
          Expanded(
            flex: controller.searchOpen ? 4 : 1,
            child: RosterColumn(
              controller: controller,
              isHome: false,
              focused: controller.columnFocus == 2,
              onEditRosters: widget.onEditRosters,
              onDrumRequested: () =>
                  setState(() => _drumMode = DrumPickerMode.scroll),
              onInfiniteRequested: () =>
                  setState(() => _drumMode = DrumPickerMode.infinite),
            ),
          ),
        ],
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
    required this.onPageChanged,
    required this.onEditRosters,
  });

  final CaptionV2Controller controller;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onEditRosters;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final single = controller.singleTeamMode;
    final focus = controller.columnFocus.clamp(0, 2);
    final pageCount = single ? 2 : 3;

    return Column(
      children: [
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
            if (!single)
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
          child: DrumPicker(
            controller: controller,
            layout: DrumLayout.paged,
            mode: DrumPickerMode.infinite,
            pageController: pageController,
            onPageChanged: onPageChanged,
            onEditRosters: onEditRosters,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pageCount; i++)
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

/// Full-session gate while rosters, folder scan, saved/uploaded marks, and
/// preview EXIF finish — so the photo card never flashes empty chrome.
class _SessionLoadingPane extends StatelessWidget {
  const _SessionLoadingPane({
    required this.tokens,
    required this.label,
  });

  final FfTokens tokens;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: tokens.accent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Preparing session',
                textAlign: TextAlign.center,
                style: tokens.labelStyle.copyWith(
                  fontSize: tokens.textSizeBody,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: tokens.secondaryLabelStyle.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Photo details and saved / uploaded status load before the workspace opens.',
                textAlign: TextAlign.center,
                style: tokens.metaStyle.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
