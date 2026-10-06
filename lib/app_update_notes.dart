// Text for the “What’s new” window after someone installs a newer build.
//
// When you put out a new version of the app:
//   • Raise the version in pubspec.yaml (the number after + must get bigger each time,
//     or the app will think nothing changed).
//   • Edit the title and body below so they describe what you actually shipped.
//   • If you do not want a popup this time, set kAppUpdateNotesBody to '' (empty).
//     The app will still save the new build number so people are not stuck in a loop.

const String kAppUpdateNotesTitle = 'What’s new';

const String kAppUpdateNotesBody = '''
Here is what changed in this version.

On-device jersey OCR (macOS): photos auto-scan for jersey numbers and player names, matched against your loaded home/away rosters. Hold the loupe on a number or name for a focused scan. Tap a match chip to select that player.

Caption V2 polish continues across photo preview, roster, and Firebar workflows.

This message shows one time after you update. Tap OK or outside the box to close it.
''';
