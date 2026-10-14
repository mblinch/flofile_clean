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

Numbers mode: set the squares to 4, 5, or 6 across with − and + beside the roster search. Plus makes the squares larger. The default is 4. Home and away share the same count.

Caption text size − and + stay in the top caption bar.

Player search text starts at the left once you type. The magnifying glass hides until the field is empty.

This message shows one time after you update. Tap OK or outside the box to close it.
''';
