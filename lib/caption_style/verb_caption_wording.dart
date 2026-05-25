/// Default action phrase for a verb label (no "against the team" suffix).
class VerbCaptionWording {
  VerbCaptionWording._();

  static String defaultWording(String verb) {
    switch (verb) {
      case 'Home Run':
        return 'home run';
      case 'Single':
        return 'single';
      case 'Double':
        return 'double';
      case 'Triple':
        return 'triple';
      case 'Sacrifice Fly':
        return 'sacrifice fly';
      case 'Grand Slam':
        return 'grand slam';
      case 'At Bat':
        return 'takes an at bat in his batting stance';
      case 'Pitching':
        return 'delivers a pitch';
      case 'Mound Visit':
        return 'mound visit';
      case 'Swings':
        return 'swings';
      case 'Bunts':
        return 'bunts';
      case 'Hit by Pitch':
        return 'is hit by a pitch';
      case 'Walks':
        return 'takes a walk';
      case 'Fielding Position':
        return 'takes fielding position';
      case 'Looks On':
        return 'looks on';
      case 'Walks Off Field':
        return 'walks off the field';
      case 'Runs Off Field':
        return 'runs off the field';
      case 'Takes the Field':
        return 'takes the field';
      case 'Comes Off the Field':
        return 'comes off the field';
      case 'National Anthem':
        return 'looks on during the national anthem prior to play';
      case 'Stretching':
        return 'stretches prior to play';
      case 'Warm Ups':
        return 'takes part in warm ups prior to play';
      case 'Pitching Change':
        return 'pitcher taken out of the game';
      case 'Catches':
        return 'catches a ball';
      case 'Throws':
        return 'throws a ball';
      case 'Tags':
        return 'tags a runner out';
      case 'Groundball':
        return 'fields a groundball';
      case 'Double Play':
        return 'turns a double play';
      case 'Triple Play':
        return 'turns a triple play';
      case 'Steals':
        return 'steals a base';
      case 'Slides':
        return 'slides into a base';
      case 'Runs':
        return 'runs to a base';
      case 'Rounds':
        return 'rounds a base';
      case 'Celebrates':
      case 'Celebration':
        return 'celebrates';
      case 'Celebrates a Goal':
        return 'celebrates a goal';
      case 'Goes to the Net':
        return 'goes to the net';
      case 'Guards the Net':
        return 'guards the net';
      case 'Walks to the Ice':
        return 'walks to the ice';
      case 'Skates':
        return 'skates';
      case 'Shoots':
        return 'shoots';
      case 'Battles':
        return 'battles';
      case 'Scores':
        return 'scores';
      case 'Faceoff':
        return 'takes a faceoff';
      case 'Blocks':
        return 'blocks';
      case 'Clears':
        return 'clears the puck';
      case 'Checks':
        return 'checks';
      case 'Defends':
        return 'defends';
      case 'Saves':
        return 'makes a save';
      case 'Handles the Puck':
        return 'handles the puck';
      case 'Stands in Net':
        return 'stands in net';
      case 'Takes the Ice':
        return 'takes the ice';
      case 'Comes Off the Ice':
        return 'comes off the ice';
      case 'Drives':
        return 'drives';
      case 'Dribbles':
        return 'dribbles';
      case 'Dunks':
        return 'dunks';
      case 'Lays Up':
        return 'lays up';
      case 'Three-Pointer':
        return 'shoots a three-pointer';
      case 'Free Throw':
        return 'shoots a free throw';
      case 'Steals the Ball':
        return 'steals the ball';
      case 'Contests':
        return 'contests a shot';
      case 'Rebounds':
        return 'rebounds';
      case 'Takes the Court':
        return 'takes the court';
      case 'Comes Off the Court':
        return 'comes off the court';
      case 'Kicks':
        return 'kicks';
      case 'Controls':
        return 'controls the ball';
      case 'Scores a Goal':
        return 'scores a goal';
      case 'Tackles':
        return 'tackles';
      case 'Blocks Shot':
        return 'blocks a shot';
      case 'Intercepts':
        return 'intercepts';
      case 'Marks':
        return 'marks an opponent';
      case 'Headers Away':
        return 'heads the ball away';
      case 'Punches':
        return 'punches the ball';
      case 'Catches Cross':
        return 'catches a cross';
      case 'Distribution':
        return 'distributes the ball';
      case 'Comes Off Line':
        return 'comes off his line';
      case 'Smothers':
        return 'smothers the ball';
      case 'Corner Kick':
        return 'takes a corner kick';
      case 'Free Kick':
        return 'takes a free kick';
      case 'Penalty Kick':
        return 'takes a penalty kick';
      case 'Throw-In':
        return 'takes a throw-in';
      case 'Wall Defense':
        return 'defends on a wall';
      case 'Walkout':
        return 'walks out';
      case 'Dejection':
        return 'reacts with dejection';
      default:
        return verb.toLowerCase();
    }
  }
}
