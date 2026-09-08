import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/burst_groups.dart';

void main() {
  test('burst chain starts at anchor and only walks forward', () {
    final paths = ['/one.jpg', '/two.jpg', '/three.jpg', '/four.jpg'];
    final start = DateTime(2026, 9, 7, 12);
    final captures = {
      '/one.jpg': start,
      '/two.jpg': start.add(const Duration(seconds: 1)),
      '/three.jpg': start.add(const Duration(seconds: 2)),
      '/four.jpg': start.add(const Duration(seconds: 5)),
    };

    expect(
      burstChainFromAnchor(paths, '/two.jpg', captures),
      ['/two.jpg', '/three.jpg'],
    );
  });

  test('burst chain stops when adjacent capture metadata is missing', () {
    final paths = ['/one.jpg', '/two.jpg', '/three.jpg'];
    final captures = {
      '/one.jpg': DateTime(2026, 9, 7, 12),
      '/three.jpg': DateTime(2026, 9, 7, 12, 0, 1),
    };

    expect(
      burstChainFromAnchor(paths, '/one.jpg', captures),
      ['/one.jpg'],
    );
  });
}
