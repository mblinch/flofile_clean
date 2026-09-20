import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_cap/screens/caption_v2/data/caption_v2_controller.dart';
import 'package:quick_cap/screens/caption_v2/layout/drum_picker.dart';
import 'package:quick_cap/services/mlb_api_service.dart';

Player _player(String name, String number) => Player(
      fullName: name,
      firstName: name.split(' ').first,
      jerseyNumber: number,
      displayName: '$name #$number',
    );

void main() {
  testWidgets('paged drum uses wheel mode for players', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = CaptionV2Controller()
      ..homeTeam = 'Home Team'
      ..awayTeam = 'Away Team'
      ..homeRoster = [
        _player('Home One', '11'),
        _player('Home Two', '22'),
      ]
      ..awayRoster = [
        _player('Away One', '1'),
        _player('Away Two', '2'),
      ];
    addTearDown(controller.dispose);

    final pageController = PageController(initialPage: 0);
    addTearDown(pageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 700,
            child: DrumPicker(
              controller: controller,
              layout: DrumLayout.paged,
              mode: DrumPickerMode.infinite,
              pageController: pageController,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('paged-drum-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('scroll-list-home')), findsNothing);
    expect(find.byKey(const ValueKey('drum-home')), findsOneWidget);
  });
}
