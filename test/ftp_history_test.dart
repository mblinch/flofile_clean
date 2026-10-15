import 'package:quick_cap/screens/caption_v2/data/ftp_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseProcessEtime reads ps elapsed formats', () {
    expect(
      parseProcessEtime('03:21'),
      const Duration(minutes: 3, seconds: 21),
    );
    expect(
      parseProcessEtime('  01:03:21'),
      const Duration(hours: 1, minutes: 3, seconds: 21),
    );
    expect(
      parseProcessEtime('2-01:03:21'),
      const Duration(days: 2, hours: 1, minutes: 3, seconds: 21),
    );
    expect(parseProcessEtime(''), isNull);
    expect(parseProcessEtime('nope'), isNull);
  });
}
