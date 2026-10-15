import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/gestures/mac_control_click.dart';

void main() {
  const position = Offset(12, 34);

  PointerDownEvent down({int buttons = kPrimaryButton, int pointer = 1}) {
    return PointerDownEvent(
      pointer: pointer,
      kind: PointerDeviceKind.mouse,
      position: position,
      buttons: buttons,
    );
  }

  test('Control-click becomes a secondary click at the same position', () {
    final promoter = MacControlClickPromoter();
    final mapped = promoter.transform(
      down(),
      macOS: true,
      controlPressed: true,
      metaPressed: false,
    );

    expect(mapped, isA<PointerDownEvent>());
    expect(mapped.buttons, kSecondaryButton);
    expect(mapped.position, position);

    final move = promoter.transform(
      const PointerMoveEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: Offset(13, 35),
        buttons: kPrimaryButton,
      ),
      macOS: true,
      controlPressed: false,
      metaPressed: false,
    );
    expect(move.buttons, kSecondaryButton);
    expect(move.position, const Offset(13, 35));

    final up = promoter.transform(
      const PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        position: position,
        buttons: 0,
      ),
      macOS: true,
      controlPressed: false,
      metaPressed: false,
    );
    expect(up.buttons, kSecondaryButton);
    expect(up.position, position);
  });

  test('Command-click stays a primary click', () {
    final promoter = MacControlClickPromoter();
    final mapped = promoter.transform(
      down(),
      macOS: true,
      controlPressed: true,
      metaPressed: true,
    );
    expect(mapped.buttons, kPrimaryButton);
  });

  test('plain click and non-mac Control-click stay primary', () {
    final promoter = MacControlClickPromoter();
    expect(
      promoter
          .transform(
            down(),
            macOS: true,
            controlPressed: false,
            metaPressed: false,
          )
          .buttons,
      kPrimaryButton,
    );
    expect(
      promoter
          .transform(
            down(pointer: 2),
            macOS: false,
            controlPressed: true,
            metaPressed: false,
          )
          .buttons,
      kPrimaryButton,
    );
  });

  test('an existing right-click is unchanged', () {
    final promoter = MacControlClickPromoter();
    final mapped = promoter.transform(
      down(buttons: kSecondaryButton),
      macOS: true,
      controlPressed: true,
      metaPressed: false,
    );
    expect(mapped.buttons, kSecondaryButton);
  });
}
