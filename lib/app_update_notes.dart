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

In Keyboard Fire you can change the order of categories and verbs. Press and hold for about half a second, then drag. You will see a small floating copy of the row following your mouse or finger, and a blue line where it will land. Your new order is saved and comes back the next time you open the app.

Favorites are not reordered this way; only the regular category and verb lists.

This message shows one time after you update. Tap OK or outside the box to close it.

We also rewrote the instructions for this screen in simpler language.
''';
