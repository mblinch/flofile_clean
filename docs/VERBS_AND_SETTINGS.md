# Verbs and Settings: How They’re Saved and Passed On

## Where verb data lives

### 1. Built-in verb lists (code)
- **File:** `lib/widgets/caption_fields_widget.dart`
- **What:** Hardcoded category → verb lists per sport:
  - `basketballVerbCategories` (Offense, Defense, Reactions, Non Game-Action)
  - `hockeyVerbCategories` (Offense, Defense, Goalie, …)
  - Baseball uses the same structure via `verbCategories` getter
- **Category order default:** `categoryOrder` getter (e.g. Offense, Defense, …, Favorites)
- **Not stored in prefs** — change here to change the “factory” defaults for a new install.

### 2. Preferences (per device, per sport)
- **File:** `lib/services/preferences_service.dart`
- **Storage:** `SharedPreferences` (local key/value store).

| What | Key pattern | Sport-specific |
|------|-------------|----------------|
| Category order | `category_order`, `category_order_baseball`, `category_order_{sport}` | Yes |
| Favorite verbs | `favorite_verbs_baseball`, `favorite_verbs_{sport}` | Yes |
| Favorite teams | `favorite_teams_baseball`, `favorite_teams_{sport}` (values like `HOME:Yankees`, `AWAY:Red Sox`) | Yes |
| Custom verb wordings | `custom_verb_wordings_baseball`, `custom_verb_wordings_{sport}` (verb → custom display text) | Yes |
| Verb overrides | `verb_overrides_{sport}` (built-in verb → `{ label, … }` for edited labels/phrases) | Yes |
| Custom verbs | `custom_verbs_{sport}` (user-created verbs) | Yes |
| Deleted verbs | `deleted_verbs_{sport}` (built-in verbs hidden from list) | Yes |

### 3. How the UI uses it
- **Caption builder:** `CaptionFieldsWidget` loads the above from `PreferencesService` in `_loadPreferences()` (category order, favorites, custom wordings, verb overrides) for the **current sport**.
- **Favorites:** User adds/removes favorites (e.g. right‑click → “Add to Favorites”); `saveFavoriteVerbs()` is called for the current sport.
- **Category order:** User can reorder categories (e.g. drag); `saveCategoryOrder()` is called for the current sport.
- **Edited verbs:** Edits to built-in verbs (label/phrase) are stored as **verb overrides**; custom wording is stored in **custom verb wordings**. Both are loaded in `_loadPreferences()` and applied when rendering or building captions.

So: **editing verbs in-app = changing verb overrides and/or custom verb wordings**. Those are already saved per sport and persist on the device.

---

## Making your edited verbs “the default”

Two meanings:

1. **Default for this device after a reset**  
   Use **“Save as default”** in Preferences. That stores your current verb-related (and other) settings as the “default bundle.” When you tap **“Reset to defaults,”** the app restores from that bundle instead of the hardcoded defaults. So your edited verbs and settings become the default after a reset.

2. **Default for new installs / other people**  
   **Export** your preferences (after editing), then **Import** on another machine or share the file. The export now includes all verb-related and per-sport data (see below), so “passing on” is done via export/import.

The built-in verb *lists* (which verbs exist in each category) only change if you edit the Dart code (e.g. `basketballVerbCategories`). The **labels and custom wordings** you edit in-app are stored in preferences and are what get exported/imported and used as “default” after reset when you’ve used “Save as default.”

---

## Saving and passing on settings (export / import)

- **Where:** Preferences dialog → **Export** / **Import** (and optional **Save as default**).
- **Export:** Copies a JSON map to the clipboard (and optionally can save to a file). It now includes:
  - All of the above verb-related keys **per sport** (baseball, hockey, basketball): category order, favorite verbs, favorite teams, custom verb wordings, verb overrides, custom verbs, deleted verbs.
  - Other prefs: FTP profiles, layout, caption entry mode, firebar position, etc.
- **Import:** Reads that JSON (from clipboard or file), then restores every key that’s present, including per-sport verb data. So you can **pass one file (or clipboard paste) to another install or person** and they get the same verbs and settings.
- **Save as default:** Writes the same export blob to a special key. **Reset to defaults** restores from that blob when present; otherwise it uses the built-in defaults.

So: **edited verbs and settings can be saved and passed on** by exporting, sharing the JSON, and importing on the other device or for the next person.

---

## Set as default for a sport (Option 1)

In **Preferences** → **Sport default** you can choose a sport (Baseball, Hockey, Basketball) and tap **Set as default**. That saves the current verbs, category order, favorites, overrides, and custom wordings for that sport as the **sport default**. From then on, when someone has no saved preferences for that sport yet (e.g. first time they use it), the app uses this sport default instead of the hardcoded one. You can do this per sport when you’re ready.

---

## Export to file / Import from file

Use **Export to file** to save the full preferences JSON to a `.json` file (e.g. to move to another computer or back up). Use **Import from file** to load that file and replace current preferences. Same data as clipboard Export/Import, just file-based.

---

## Cloud sync (your server)

If you host a small backend, set **Sync server URL** and **Account ID** in **Preferences** → **Cloud sync**. **Upload** sends your current preferences to your server; **Download** fetches them and applies them. So the same settings (including verb edits) work across computers without moving files. See `docs/SYNC_SERVER_API.md` for the API your server must implement.
