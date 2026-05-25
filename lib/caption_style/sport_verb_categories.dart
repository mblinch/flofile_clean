/// Built-in verb lists per sport (shared by caption UI and layout previews).
class SportVerbCategories {
  SportVerbCategories._();

  static const Map<String, List<String>> baseball = {
    'Offense': [
      'Single',
      'Double',
      'Triple',
      'Home Run',
      'Sacrifice Fly',
      'At Bat',
      'Swings',
      'Bunts',
      'Hit by Pitch',
    ],
    'Defense': [
      'Catches',
      'Throws',
      'Tags',
      'Groundball',
      'Fielding Position',
      'Double Play',
      'Triple Play',
      '',
      '',
    ],
    'Pitching': [
      'Pitching',
      'Pitching Change',
      'Mound Visit',
      '',
      '',
      '',
      '',
      '',
      '',
    ],
    'Running': ['Steals', 'Slides', 'Runs', 'Rounds', '', '', '', '', ''],
    'Reactions': [
      'Celebrates',
      'Dejection',
      'Post Game Win',
      'Post Game Loss',
      '',
      '',
      '',
      '',
      '',
    ],
    'Non Game-Action': [
      'Looks On',
      'Batting Practice',
      'Fielding Practice',
      'Takes the Field',
      'Comes Off the Field',
      'National Anthem',
      'Stretching',
      'Warm Ups',
      '',
    ],
  };

  static const Map<String, List<String>> basketball = {
    'Offense': [
      'Drives',
      'Dribbles',
      'Shoots',
      'Scores',
      'Dunks',
      'Lays Up',
      'Three-Pointer',
      'Free Throw',
    ],
    'Defense': [
      'Blocks',
      'Steals the Ball',
      'Defends',
      'Contests',
      'Rebounds',
      '',
      '',
      '',
      '',
    ],
    'Reactions': [
      'Celebrates',
      'Dejection',
      'Post Game Win',
      'Post Game Loss',
      '',
      '',
      '',
      '',
      '',
    ],
    'Non Game-Action': [
      'Looks On',
      'Warm Ups',
      'Takes the Court',
      'Comes Off the Court',
      'National Anthem',
      'Stretching',
      'Bench',
      '',
      '',
    ],
  };

  static const Map<String, List<String>> soccer = {
    'Offense': [
      'Dribbles',
      'Shoots',
      'Kicks',
      'Controls',
      'Battles',
      'Scores a Goal',
      'Celebrates a Goal',
    ],
    'Defense': [
      'Tackles',
      'Blocks Shot',
      'Clears',
      'Intercepts',
      'Marks',
      'Headers Away',
      '',
      '',
    ],
    'Goalkeeper': [
      'Saves',
      'Punches',
      'Catches Cross',
      'Distribution',
      'Comes Off Line',
      'Smothers',
      '',
      '',
    ],
    'Set Pieces': [
      'Corner Kick',
      'Free Kick',
      'Penalty Kick',
      'Throw-In',
      'Wall Defense',
      '',
      '',
      '',
    ],
    'Non Game-Action': [
      'Looks On',
      'Warm Ups',
      'Walkout',
      'National Anthem',
      'Stretching',
      'Bench',
      'Post Game Win',
      'Post Game Loss',
      'Dejection',
    ],
    'Reactions': [
      'Celebrates',
      'Celebrates a Goal',
      'Dejection',
      'Frustration',
      'Post Game Win',
      'Post Game Loss',
      '',
      '',
    ],
  };

  static const Map<String, List<String>> hockey = {
    'Offense': [
      'Skates',
      'Shoots',
      'Battles',
      'Scores',
      'Goes to the Net',
      'Faceoff',
      'Celebrates a Goal',
      'Celebrates',
    ],
    'Defense': [
      'Blocks',
      'Clears',
      'Checks',
      'Defends',
    ],
    'Goalie': [
      'Saves',
      'Handles the Puck',
      'Stands in Net',
      'Guards the Net',
    ],
    'Non Game-Action': [
      'Looks On',
      'Warm Ups',
      'Takes the Ice',
      'Walks to the Ice',
      'Comes Off the Ice',
      'National Anthem',
      'Stretching',
      'Bench',
      'Post Game Win',
      'Post Game Loss',
      'Dejection',
    ],
    'Reactions': [
      'Celebrates',
      'Celebrates a Goal',
      'Dejection',
      'Post Game Win',
      'Post Game Loss',
    ],
  };

  /// Default preview verb per sport (stable sample captions).
  static const Map<String, String> defaultPreviewVerb = {
    'baseball': 'Single',
    'hockey': 'Skates',
    'basketball': 'Shoots',
    'soccer': 'Dribbles',
  };

  static Map<String, List<String>> forSport(String sport) {
    switch (sport.toLowerCase().trim()) {
      case 'hockey':
        return hockey;
      case 'basketball':
        return basketball;
      case 'soccer':
        return soccer;
      case 'baseball':
      default:
        return baseball;
    }
  }

  static Map<String, List<String>> copyForSport(String sport) {
    return forSport(sport).map((k, v) => MapEntry(k, List<String>.from(v)));
  }
}
