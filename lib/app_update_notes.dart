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

UI polish with a tighter theme and JetBrains Mono for mono fields. Caption layout supports Custom text snippets with a trailing suffix. Startup team pickers reopen the full list on a second click instead of leaving a caret.

Baseball: MLB inning-from-timestamp starts matching when Timestamp is On (no toggle click needed). RBI captions no longer double “hits a” when the verb phrase already includes it (e.g. “hits a RBI single”).

This message shows one time after you update. Tap OK or outside the box to close it.
''';
