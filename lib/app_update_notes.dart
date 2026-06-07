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

When you sign in, your caption styles, verb layouts, and FTP settings sync to your account and follow you to other computers. Skip sign in still works — everything stays local on that machine.

Caption preview spacing is more reliable (no doubled punctuation or missing spaces at segment joins). Home Run type options show again in Keyboard Fire. Burst captions are not re-prompted when you revisit an image you already decided on.

Admin caption editing keeps your game identifier when switching sports. The geographical editor wraps instead of clipping. FTP controls sit above the Save buttons in the sidebar.

This message shows one time after you update. Tap OK or outside the box to close it.
''';
