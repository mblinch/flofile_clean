import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ensureSemantics enables labels while the returned handle is held',
    (tester) async {
      // Dart-side: main() keeps this handle for the process lifetime.
      // macOS also needs FlutterEngine.semanticsEnabled (see
      // MainFlutterWindow._enableFlutterSemantics) — framework-only
      // ensureSemantics does not populate the native AX tree.
      final handle = SemanticsBinding.instance.ensureSemantics();
      expect(SemanticsBinding.instance.semanticsEnabled, isTrue);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Semantics(
            label: 'Save & Next',
            button: true,
            child: const SizedBox(width: 40, height: 20),
          ),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('Save & Next'), findsOneWidget);

      handle.dispose();
    },
  );
}
