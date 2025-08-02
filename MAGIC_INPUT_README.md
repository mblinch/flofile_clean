# Magic Input Feature

The caption writer now includes a magic input feature that allows you to quickly generate baseball captions using shorthand notation.

## How to Use

Type in the Magic Bar (the text field in the center of the caption builder) using the following format:

**Format:** `[player_number] [action] [inning]`

### Examples:

- `27 hr 1` - Player #27 hits a home run in the 1st inning
- `15 single 3` - Player #15 hits a single in the 3rd inning  
- `42 double 2` - Player #42 hits a double in the 2nd inning
- `8 triple 4` - Player #8 hits a triple in the 4th inning
- `99 walks 5` - Player #99 walks in the 5th inning
- `12 steals 6` - Player #12 steals a base in the 6th inning
- `33 catches 7` - Player #33 makes a catch in the 7th inning
- `45 pitches 1` - Player #45 pitches in the 1st inning

### Supported Actions:

**Hitting:**
- `hr`, `homerun`, `homer` - Home Run
- `single`, `1b` - Single
- `double`, `2b` - Double  
- `triple`, `3b` - Triple
- `walks`, `walk`, `bb` - Walks
- `strikeout`, `k` - Strikeout
- `hbp`, `hitbypitch` - Hit by Pitch

**Fielding:**
- `catches`, `catch` - Catches
- `throws`, `throw` - Throws
- `tags`, `tag` - Tags
- `groundball`, `ground` - Groundball
- `doubleplay`, `dp` - Double Play
- `tripleplay`, `tp` - Triple Play

**Running:**
- `steals`, `steal`, `sb` - Steals
- `runs`, `run` - Runs
- `slides`, `slide` - Slides
- `rounds`, `round` - Rounds

**Pitching:**
- `pitches`, `pitch`, `pitching` - Pitching
- `pitchingchange`, `pitchchange` - Pitching Change

**Other Actions:**
- `swings`, `swing` - Swings
- `bunts`, `bunt` - Bunts
- `celebrates`, `celebrate` - Celebrates
- `dejection`, `dejected` - Dejection
- `looks`, `look` - Looks On
- `atbat`, `at-bat`, `bat` - At Bat
- `fielding`, `field` - Fielding Position
- `warmup`, `warm` - Warm Ups
- `stretching`, `stretch` - Stretching
- `battingpractice`, `bp` - Batting Practice
- `fieldingpractice`, `fp` - Fielding Practice
- `takesthefield`, `takesfield` - Takes the Field
- `comesofffield`, `offfield` - Comes Off the Field
- `nationalanthem`, `anthem` - National Anthem
- `postgamewin`, `win` - Post Game Win
- `postgameloss`, `loss` - Post Game Loss
- `walksofffield`, `walksoff` - Walks Off Field
- `runsofffield`, `runsoff` - Runs Off Field

## How It Works

1. **Player Selection**: The system searches for the player by jersey number in both home and away rosters
2. **Action Parsing**: Recognizes various baseball action keywords and maps them to the appropriate verb
3. **Inning Setting**: Automatically sets the inning number if provided
4. **RBI Setting**: For hitting actions (single, double, triple, home run), automatically sets RBI count to 1
5. **Caption Generation**: Updates the caption with the selected player, action, and inning

## Notes

- The inning number is optional
- If no inning is specified, the caption will be generated without inning information
- The system will show a brief success message when magic input is detected
- Make sure both teams are selected before using magic input for best results
- The feature works alongside the existing player selection and verb selection interfaces 