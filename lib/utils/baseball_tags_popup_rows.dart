/// Baseball Tags runner-out options shared by Keyboard Fire and the player-popup verb panel.
/// Values must stay in sync with caption_fields_widget Tags parsing (`Tags Runner Out at: …`).
List<Map<String, String>> baseballTagsPopupChoiceRows() {
  String tag(String base, String option) => 'Tags Runner Out at: $base - $option';
  return <Map<String, String>>[
    {'label': 'No base detail (names only)', 'value': ''},
    {
      'label': 'On the Base Path',
      'value': 'Tags Runner Out at: On the Base Path',
    },
    {'label': '1st — Pickoff', 'value': tag('1st', 'Pickoff')},
    {'label': '1st — Stealing', 'value': tag('1st', 'Stealing')},
    {'label': '2nd — Pickoff', 'value': tag('2nd', 'Pickoff')},
    {'label': '2nd — Stealing', 'value': tag('2nd', 'Stealing')},
    {
      'label': '2nd — Stretch a Single',
      'value': tag('2nd', 'Attempting to Stretch a Single'),
    },
    {'label': '2nd — Tag Up', 'value': tag('2nd', 'Attempting to Tag Up')},
    {'label': '2nd — Advance', 'value': tag('2nd', 'Attempting to Advance')},
    {'label': '3rd — Pickoff', 'value': tag('3rd', 'Pickoff')},
    {'label': '3rd — Stealing', 'value': tag('3rd', 'Stealing')},
    {
      'label': '3rd — Stretch a Double',
      'value': tag('3rd', 'Attempting to Stretch a Double'),
    },
    {'label': '3rd — Tag Up', 'value': tag('3rd', 'Attempting to Tag Up')},
    {'label': '3rd — Advance', 'value': tag('3rd', 'Attempting to Advance')},
    {'label': 'Home — Stealing', 'value': tag('Home', 'Stealing')},
    {
      'label': 'Home — Stretch a Triple',
      'value': tag('Home', 'Attempting to Stretch a Triple'),
    },
    {'label': 'Home — Tag Up', 'value': tag('Home', 'Attempting to Tag Up')},
    {'label': 'Home — Score', 'value': tag('Home', 'Attempting to Score')},
  ];
}
