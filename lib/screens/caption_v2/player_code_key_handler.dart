import 'dart:async';

import 'package:flutter/services.dart';

import 'data/caption_v2_controller.dart';

/// Types `h34` / `v88` (or `hh` / `vv`) to select a roster player.
///
/// Designed for [HardwareKeyboard] so it still works when Firebar has focus
/// but is idle (empty query) — those keys must not become search text.
class PlayerCodeKeyHandler {
  PlayerCodeKeyHandler({
    required this.controller,
    required this.onSelected,
    this.onBufferChanged,
    this.onErrorChanged,
  });

  final CaptionV2Controller controller;
  final void Function({required bool isHome}) onSelected;
  final void Function(String buffer)? onBufferChanged;
  final void Function(String? message)? onErrorChanged;

  Timer? _timer;
  Timer? _errorTimer;
  String _buffer = '';
  String? _error;

  String get buffer => _buffer;
  String? get errorMessage => _error;

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _errorTimer?.cancel();
    _errorTimer = null;
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) return;
    _buffer = '';
    onBufferChanged?.call(_buffer);
  }

  /// Whether this handler should steal keys from the focused field.
  ///
  /// Idle Firebar (focused, empty query) is fair game so jersey codes work
  /// without an extra click away from the action/search strip. Other text
  /// fields (caption, etc.) keep their keys — caption uses setManualCaption.
  bool shouldCapture({
    required bool sessionReady,
    required bool sessionLoading,
    required bool searchFocused,
    required String searchQuery,
    required bool editableFocused,
    required bool photoEditing,
  }) {
    if (!sessionReady || sessionLoading || photoEditing) return false;
    if (searchFocused) {
      return searchQuery.trim().isEmpty;
    }
    if (editableFocused) return false;
    return true;
  }

  bool handle(
    KeyEvent event, {
    required bool sessionReady,
    required bool sessionLoading,
    required bool searchFocused,
    required String searchQuery,
    required bool editableFocused,
    required bool photoEditing,
  }) {
    if (event is! KeyDownEvent) return false;
    if (!shouldCapture(
      sessionReady: sessionReady,
      sessionLoading: sessionLoading,
      searchFocused: searchFocused,
      searchQuery: searchQuery,
      editableFocused: editableFocused,
      photoEditing: photoEditing,
    )) {
      return false;
    }

    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed ||
        keys.isControlPressed ||
        keys.isAltPressed ||
        keys.isShiftPressed) {
      return false;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_buffer.isEmpty) return false;
      clear();
      return true;
    }
    if (key == LogicalKeyboardKey.backspace) {
      if (_buffer.isNotEmpty) {
        _buffer = _buffer.substring(0, _buffer.length - 1);
        if (_buffer.isEmpty) {
          clear();
        } else {
          onBufferChanged?.call(_buffer);
          _restartTimer();
        }
        return true;
      }
      // No text field / empty code box: remove last player (codes or clicks).
      if (searchFocused || editableFocused) return false;
      return controller.removeLastSelectedPlayer();
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_buffer.isEmpty) return false;
      _flush();
      return true;
    }

    final letter = _letter(key, event.character);
    if (letter != null) {
      _clearError();
      if (_buffer.isEmpty) {
        _setBuffer(letter);
        return true;
      }
      if (RegExp(r'^[hv]$').hasMatch(_buffer) && _buffer == letter) {
        _setBuffer('$letter$letter');
        return true;
      }
      if (!_buffer.toLowerCase().startsWith(letter)) {
        _setBuffer(letter);
        return true;
      }
      return false;
    }

    final digit = _digit(key);
    if (digit != null) {
      if (_buffer.isEmpty) return false;
      if (!RegExp(r'^[hv]{1,2}\d{0,2}$', caseSensitive: false)
          .hasMatch(_buffer)) {
        return false;
      }
      _clearError();
      _setBuffer('$_buffer$digit');
      return true;
    }

    if (_buffer.isNotEmpty) {
      clear();
    }
    return false;
  }

  void _setBuffer(String value) {
    _buffer = value;
    onBufferChanged?.call(_buffer);
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 650), _flush);
  }

  void _flush() {
    _timer?.cancel();
    _timer = null;
    final code = _buffer;
    _buffer = '';
    onBufferChanged?.call(_buffer);
    if (code.isEmpty) return;
    if (!RegExp(r'^[hv]{1,2}\d{1,3}$', caseSensitive: false).hasMatch(code)) {
      return;
    }
    final isHome = code.toLowerCase().startsWith('h');
    final jersey = RegExp(r'\d{1,3}').firstMatch(code)?.group(0) ?? '';
    if (controller.selectPlayerByCode(code)) {
      _clearError();
      onSelected(isHome: isHome);
      return;
    }
    _showError(isHome ? 'No home #$jersey' : 'No visitor #$jersey');
  }

  void _showError(String message) {
    _errorTimer?.cancel();
    _error = message;
    onErrorChanged?.call(_error);
    _errorTimer = Timer(const Duration(seconds: 2), _clearError);
  }

  void _clearError() {
    _errorTimer?.cancel();
    _errorTimer = null;
    if (_error == null) return;
    _error = null;
    onErrorChanged?.call(null);
  }

  static String? _letter(LogicalKeyboardKey key, String? character) {
    final ch = character?.toLowerCase();
    if (key == LogicalKeyboardKey.keyH || ch == 'h') return 'h';
    if (key == LogicalKeyboardKey.keyV || ch == 'v') return 'v';
    return null;
  }

  static const _digitKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static const _numpadKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  static int? _digit(LogicalKeyboardKey key) {
    for (var i = 0; i <= 9; i++) {
      if (key == _digitKeys[i] || key == _numpadKeys[i]) return i;
    }
    return null;
  }
}
