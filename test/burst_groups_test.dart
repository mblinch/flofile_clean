import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/burst_groups.dart';

void main() {
  test('burst chain includes earlier and later frames within the gap', () {
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
      ['/one.jpg', '/two.jpg', '/three.jpg'],
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

  test('equal-timestamp adjacent frames are one burst from any anchor', () {
    final paths = [
      '/73292.jpg',
      '/73293.jpg',
      '/73297.jpg',
      '/73299.jpg',
      '/73300.jpg',
    ];
    final captured = DateTime(2026, 7, 22, 19, 16, 43);
    final captures = {
      for (final path in paths) path: captured,
    };

    const expected = [
      '/73292.jpg',
      '/73293.jpg',
      '/73297.jpg',
      '/73299.jpg',
      '/73300.jpg',
    ];

    expect(burstChainFromAnchor(paths, '/73292.jpg', captures), expected);
    expect(burstChainFromAnchor(paths, '/73293.jpg', captures), expected);
    expect(burstChainFromAnchor(paths, '/73297.jpg', captures), expected);
    expect(burstChainFromAnchor(paths, '/73300.jpg', captures), expected);
  });

  test('save-to-burst defaults from middle include chronological first', () {
    final paths = [
      '/73292.jpg',
      '/73293.jpg',
      '/73297.jpg',
      '/73299.jpg',
      '/73300.jpg',
    ];
    final captured = DateTime(2026, 7, 22, 19, 16, 43);
    final captures = {for (final path in paths) path: captured};
    const current = '/73297.jpg';

    final chain = burstChainFromAnchor(paths, current, captures);
    expect(chain, paths);

    final dock = burstChainForSaveDock(chain, current);
    expect(dock.first, current); // Original = current, not chronological first
    expect(dock, contains('/73292.jpg'));

    final checked = defaultCheckedBurstExtras(dock);
    expect(checked, contains('/73292.jpg'));
    expect(checked.contains(current), isFalse);

    final targets = resolveBurstSaveTargets(
      dockPaths: dock,
      checkedExtras: checked,
    );
    expect(targets, containsAll([current, '/73292.jpg']));
    expect(targets.toSet(), paths.toSet());
    expect(defaultBurstSaveTargetsFromDock(dock).toSet(), paths.toSet());
  });

  test('equal-timestamp group still splits when an adjacent gap exceeds max', () {
    final paths = [
      '/a.jpg',
      '/b.jpg',
      '/c.jpg',
      '/d.jpg',
      '/e.jpg',
    ];
    final start = DateTime(2026, 7, 22, 19, 16, 43);
    final captures = {
      '/a.jpg': start,
      '/b.jpg': start,
      '/c.jpg': start.add(const Duration(seconds: 3)),
      '/d.jpg': start.add(const Duration(seconds: 3)),
      '/e.jpg': start.add(const Duration(seconds: 3)),
    };

    expect(
      burstChainFromAnchor(paths, '/a.jpg', captures),
      ['/a.jpg', '/b.jpg'],
    );
    expect(
      burstChainFromAnchor(paths, '/d.jpg', captures),
      ['/c.jpg', '/d.jpg', '/e.jpg'],
    );
  });
}
