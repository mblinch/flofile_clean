import 'ftp_rename_template.dart';
import 'preferences_service.dart';

/// App-wide `{n}` number sequence: digit width + next value.
///
/// Used by FTP rename and any other feature that needs a padded counter.
/// Resets to 1 (`0001`) at the start of each new caption session.
class NumberSequenceService {
  NumberSequenceService._();

  static final NumberSequenceService instance = NumberSequenceService._();

  static const int startValue = 1;

  int? _digits;
  int? _next;

  int get digitsOrDefault =>
      _digits ?? PreferencesService.numberSequenceDigitsDefault;

  int get nextOrDefault => _next ?? startValue;

  Future<void> ensureLoaded() async {
    if (_digits != null && _next != null) return;
    final prefs = await PreferencesService.getInstance();
    _digits = await prefs.getNumberSequenceDigits();
    _next = await prefs.getNumberSequenceNext();
  }

  Future<int> digits() async {
    await ensureLoaded();
    return _digits!;
  }

  Future<int> next() async {
    await ensureLoaded();
    return _next!;
  }

  Future<void> save({required int digits, required int next}) async {
    final prefs = await PreferencesService.getInstance();
    final d = digits.clamp(
      PreferencesService.numberSequenceDigitsMin,
      PreferencesService.numberSequenceDigitsMax,
    );
    final n = next < startValue ? startValue : next;
    await prefs.saveNumberSequenceDigits(d);
    await prefs.saveNumberSequenceNext(n);
    _digits = d;
    _next = n;
  }

  /// New caption session — start the counter at 1 again (`0001`).
  Future<void> resetForNewSession() async {
    await ensureLoaded();
    _next = startValue;
    final prefs = await PreferencesService.getInstance();
    await prefs.saveNumberSequenceNext(startValue);
  }

  /// Formats [value] with the saved digit width (`0042` when width is 4).
  Future<String> format(int value) async {
    final width = await digits();
    return FtpRenameTemplate.formatSequence(value, width: width);
  }

  /// Current next value, zero-padded — does not advance.
  Future<String> peekFormatted() async {
    final n = await next();
    return format(n);
  }

  /// Returns the next integer to use and advances the counter.
  Future<int> consumeValue() async {
    await ensureLoaded();
    final value = _next!;
    _next = value + 1;
    final prefs = await PreferencesService.getInstance();
    await prefs.saveNumberSequenceNext(_next!);
    return value;
  }

  /// Ensure the next counter is at least [minimum] (e.g. after IPTC digits).
  Future<void> ensureNextAtLeast(int minimum) async {
    await ensureLoaded();
    if (minimum <= _next!) return;
    _next = minimum;
    final prefs = await PreferencesService.getInstance();
    await prefs.saveNumberSequenceNext(_next!);
  }
}
