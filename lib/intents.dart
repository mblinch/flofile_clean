import 'package:flutter/widgets.dart';

/// App-wide intent for the Keyboard Fire shortcut (Cmd+Shift+K).
/// Registered globally in main.dart and handled in CaptionBuilderScreen.
class KeyboardFireIntent extends Intent {
  const KeyboardFireIntent();
}

/// App-wide intent for Preferences (Cmd+,). Opens the preferences/settings dialog.
class OpenPreferencesIntent extends Intent {
  const OpenPreferencesIntent();
}
