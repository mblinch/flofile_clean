import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/mobile/mobile_phone_frame.dart';

void main() {
  testWidgets('mouse drag on PageView changes the page', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    var page = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 400,
            child: ScrollConfiguration(
              behavior: const MobileDragScrollBehavior(),
              child: PageView(
                controller: controller,
                onPageChanged: (i) => page = i,
                children: const [
                  ColoredBox(
                    key: Key('page-home'),
                    color: Colors.red,
                    child: Center(child: Text('Home')),
                  ),
                  ColoredBox(
                    key: Key('page-actions'),
                    color: Colors.green,
                    child: Center(child: Text('Actions')),
                  ),
                  ColoredBox(
                    key: Key('page-away'),
                    color: Colors.blue,
                    child: Center(child: Text('Away')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('page-home')), findsOneWidget);
    expect(page, 0);

    // Click-and-drag left with a mouse — default desktop ScrollBehavior
    // would ignore this without MobileDragScrollBehavior.
    await tester.drag(
      find.byType(PageView),
      const Offset(-320, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();

    expect(page, 1);
    expect(find.text('Actions'), findsOneWidget);
  });
}
