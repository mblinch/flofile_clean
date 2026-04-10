/// Release notes shown once after the app binary is newer than the last
/// acknowledged build (see [PreferencesService.setLastAcknowledgedAppBuild]).
///
/// When you ship an update:
/// 1. Bump [pubspec.yaml] `version` (+build number).
/// 2. Edit [kAppUpdateNotesBody] (and title if needed). Use empty body to skip
///    the dialog for that release while still advancing the stored build.
const String kAppUpdateNotesTitle = 'What’s new';

const String kAppUpdateNotesBody = '''
Sparkle update — Keyboard Fire polish

• Category order: long-press a category row (~½ s), then drag. A floating preview follows your pointer; blue line shows the drop target. Order is saved per sport.

• Verb order: same gesture on verb rows (not Favorites). The source row fades while you move; order is saved and persists across launches.

• This dialog appears once after each app update. You can dismiss it with OK or by tapping outside.
''';
