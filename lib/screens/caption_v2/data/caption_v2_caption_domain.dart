import '../../../caption_style/verb_caption_wording.dart';
import '../../../caption_style/verb_sub_options.dart';

/// Caption-domain grammar shared by the V2 controller and its tests.
///
/// Player/team formatting stays in the controller because it depends on the
/// active caption template. This helper owns verb agreement and the semantic
/// role an explicitly selected opponent has in the action.
class CaptionV2CaptionDomain {
  CaptionV2CaptionDomain._();

  static String actionCore({
    required String verb,
    required String sport,
    required bool plural,
    required int rbi,
    String? singularPhrase,
    String? pluralPhrase,
    VerbSubOptions? subOptions,
  }) {
    final options =
        subOptions ?? VerbSubOptions.defaultsFor(verb, sport: sport);
    final hitNoun = _hitNoun(verb);
    final savedSingular = singularPhrase?.trim();
    final hasCustomHitWording = hitNoun != null &&
        savedSingular != null &&
        savedSingular.isNotEmpty &&
        savedSingular != VerbCaptionWording.defaultWording(verb);
    if (hasCustomHitWording && rbi == 0) {
      if (plural && pluralPhrase?.trim().isNotEmpty == true) {
        return pluralPhrase!.trim();
      }
      return savedSingular;
    }
    if (hitNoun != null) {
      final leadIn = plural ? 'hit a' : 'hits a';
      if (verb == 'Home Run' && rbi > 0) {
        return options.hitClauseWithHomeRun(
          leadIn: leadIn,
          hitNoun: hitNoun,
          count: rbi,
        );
      }
      if (rbi > 0 &&
          const {'Single', 'Double', 'Triple', 'Sacrifice Fly'}
              .contains(verb)) {
        return options.hitClauseWithRbi(
          leadIn: leadIn,
          hitNoun: hitNoun,
          count: rbi,
        );
      }
      if (verb == 'Grand Slam') {
        return options.hitClauseWithGrandSlam(
          leadIn: leadIn,
          hitNoun: 'home run',
        );
      }
      return '$leadIn $hitNoun';
    }

    final singular = singularPhrase?.trim().isNotEmpty == true
        ? singularPhrase!.trim()
        : _v1DefaultWording(verb, sport);
    if (plural && pluralPhrase?.trim().isNotEmpty == true) {
      return pluralPhrase!.trim();
    }
    if (plural &&
        const {
          'Mound Visit',
          'Drives',
          'Three-Pointer',
          'Kicks',
          'Battles',
          'Hit by Pitch',
          'Tags',
          'Contests',
        }.contains(verb)) {
      switch (verb) {
        case 'Hit by Pitch':
          return 'are hit by a pitch';
        case 'Tags':
          return 'tag';
        case 'Drives':
          return 'drive to the basket';
        case 'Three-Pointer':
          return 'make a three-pointer';
        case 'Battles':
          return sport.toLowerCase() == 'soccer'
              ? 'battle for the ball'
              : 'battle';
        default:
          return VerbCaptionWording.inferPluralFromSingular(singular);
      }
    }
    return plural
        ? VerbCaptionWording.defaultPluralWording(verb, singular)
        : singular;
  }

  /// Joins an action to a selected opponent or the opposing team.
  ///
  /// V1 gives a few verbs a more precise participant role than "against".
  static String withOpponent({
    required String verb,
    required String action,
    required String opponentTeam,
    String? opposingPlayers,
  }) {
    final named = opposingPlayers?.trim();
    final target = named != null && named.isNotEmpty
        ? named
        : 'the ${opponentTeam.trim()}';

    switch (verb) {
      case 'Hit by Pitch':
        return '$action by $target';
      case 'Tags':
        return '$action $target out';
      case 'Steals the Ball':
        return '$action from $target';
      case 'Contests':
        return '$action by $target';
      case 'Post Game Win':
      case 'Post Game Loss':
        return action;
      default:
        return '$action against $target';
    }
  }

  static String _v1DefaultWording(String verb, String sport) {
    switch (verb) {
      case 'Mound Visit':
        return 'participates in a mound visit';
      case 'Bunts':
        return 'bunts';
      case 'Tags':
        return 'tags';
      case 'Drives':
        return 'drives to the basket';
      case 'Three-Pointer':
        return 'makes a three-pointer';
      case 'Steals the Ball':
        return 'steals the ball';
      case 'Contests':
        return 'contests a shot';
      case 'Kicks':
        return 'kicks the ball';
      case 'Battles':
        return sport.toLowerCase() == 'soccer'
            ? 'battles for the ball'
            : 'battles';
      default:
        return VerbCaptionWording.defaultWording(verb);
    }
  }

  static String? _hitNoun(String verb) {
    switch (verb) {
      case 'Single':
        return 'single';
      case 'Double':
        return 'double';
      case 'Triple':
        return 'triple';
      case 'Home Run':
        return 'home run';
      case 'Sacrifice Fly':
        return 'sacrifice fly';
      case 'Grand Slam':
        return 'grand slam';
      default:
        return null;
    }
  }
}
