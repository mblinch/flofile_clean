import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/caption_style/verb_sort_mode.dart';

void main() {
  test('VerbSortMode defaults unknown storage to alphabetical', () {
    expect(VerbSortModeX.fromStorage(null), VerbSortMode.alphabetical);
    expect(VerbSortModeX.fromStorage(''), VerbSortMode.alphabetical);
    expect(VerbSortModeX.fromStorage('nope'), VerbSortMode.alphabetical);
  });

  test('VerbSortMode round-trips storage values', () {
    for (final mode in VerbSortMode.values) {
      expect(VerbSortModeX.fromStorage(mode.storageValue), mode);
    }
  });

  test('menu labels are user-facing', () {
    expect(VerbSortMode.alphabetical.menuLabel, 'Sort A–Z');
    expect(VerbSortMode.mostUsed.menuLabel, 'Sort by most used');
    expect(VerbSortMode.custom.menuLabel, 'Custom arrange');
  });
}
