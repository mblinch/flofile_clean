import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/photo_edit/photo_adjustments.dart';
import 'package:quick_cap/photo_edit/photo_edit_session.dart';

void main() {
  test('photo edit undo and redo restore adjustments', () async {
    final session = PhotoEditSession(onReplaced: (_) async {});
    const path = '/tmp/photo.jpg';

    session.update(path, const PhotoAdjustments(exposure: 1));
    session.checkpoint(path);
    session.update(path, const PhotoAdjustments(exposure: 2));

    expect(session.adjustmentsFor(path).exposure, 2);
    expect(session.canUndo(path), isTrue);

    expect(session.undo(path), isTrue);
    expect(session.adjustmentsFor(path).exposure, 1);
    expect(session.canRedo(path), isTrue);

    expect(session.redo(path), isTrue);
    expect(session.adjustmentsFor(path).exposure, 2);
  });

  test('beginGesture coalesces continuous edits into one undo step', () {
    final session = PhotoEditSession(onReplaced: (_) async {});
    const path = '/tmp/photo.jpg';

    session.beginGesture(path);
    session.update(path, const PhotoAdjustments(contrast: 10));
    session.update(path, const PhotoAdjustments(contrast: 40));
    session.endGesture();

    expect(session.adjustmentsFor(path).contrast, 40);
    expect(session.undo(path), isTrue);
    expect(session.adjustmentsFor(path).contrast, 0);
  });
}
