# Magic Input Verbs Reference

This document lists all the verbs and actions supported in the magic input feature. Use these in the format: `[player_number] [verb] [inning_optional]`

## Hitting Actions

| Magic Input | Full Action Name | Description |
|-------------|------------------|-------------|
| `hr`, `homerun`, `homer` | Home Run | Player hits a home run |
| `single`, `1b` | Single | Player hits a single |
| `double`, `2b` | Double | Player hits a double |
| `triple`, `3b` | Triple | Player hits a triple |
| `groundball`, `ground` | Groundball | Player hits a groundball |
| `bunts`, `bunt` | Bunts | Player bunts the ball |
| `hbp`, `hitbypitch` | Hit by Pitch | Player gets hit by a pitch |

## Base Running

| Magic Input | Full Action Name | Description |
|-------------|------------------|-------------|
| `steals`, `steal`, `sb` | Steals | Player steals a base |
| `runs`, `run` | Runs | Player runs |
| `slides`, `slide` | Slides | Player slides |
| `rounds`, `round` | Rounds | Player rounds a base |

## Pitching & Defense

| Magic Input | Full Action Name | Description |
|-------------|------------------|-------------|
| `pitches`, `pitch`, `pitching` | Pitching | Player is pitching |
| `strikeout`, `k` | Strikeout | Player strikes out |
| `walks`, `walk`, `bb` | Walks | Player walks |
| `catches`, `catch` | Catches | Player catches the ball |
| `throws`, `throw` | Throws | Player throws the ball |
| `tags`, `tag` | Tags | Player tags a runner |
| `fielding`, `field` | Fielding Position | Player in fielding position |

## Game Situations

| Magic Input | Full Action Name | Description |
|-------------|------------------|-------------|
| `doubleplay`, `dp` | Double Play | Double play situation |
| `tripleplay`, `tp` | Triple Play | Triple play situation |
| `atbat`, `at-bat`, `bat` | At Bat | Player at bat |
| `swings`, `swing` | Swings | Player swings at pitch |

## Emotional/Reaction Actions

| Magic Input | Full Action Name | Description |
|-------------|------------------|-------------|
| `celebrates`, `celebrate` | Celebrates | Player celebrates |
| `dejection`, `dejected` | Dejection | Player shows dejection |
| `looks`, `look` | Looks On | Player looks on |

## Pre/Post Game Actions

| Magic Input | Full Action Name | Description |
|-------------|------------------|-------------|
| `warmup`, `warm` | Warm Ups | Player warming up |
| `stretching`, `stretch` | Stretching | Player stretching |
| `battingpractice`, `bp` | Batting Practice | Player in batting practice |
| `fieldingpractice`, `fp` | Fielding Practice | Player in fielding practice |
| `takesthefield`, `takesfield` | Takes the Field | Player takes the field |
| `comesofffield`, `offfield` | Comes Off the Field | Player comes off the field |
| `nationalanthem`, `anthem` | National Anthem | National anthem moment |
| `pitchingchange`, `pitchchange` | Pitching Change | Pitching change situation |
| `postgamewin`, `win` | Post Game Win | Post game win celebration |
| `postgameloss`, `loss` | Post Game Loss | Post game loss reaction |
| `walksofffield`, `walksoff` | Walks Off Field | Player walks off field |
| `runsofffield`, `runsoff` | Runs Off Field | Player runs off field |

## Usage Examples

### Basic Format
```
[player_number] [verb] [inning_optional]
```

### Examples
- `27 hr` → Player #27 hits a home run
- `27 hr 1` → Player #27 hits a home run with 1 RBI in 1st inning
- `16 single 3` → Player #16 hits a single with 1 RBI in 3rd inning
- `31 k` → Player #31 strikes out
- `45 steal` → Player #45 steals a base
- `12 celebrate` → Player #12 celebrates
- `8 pitch` → Player #8 is pitching

### Notes
- **Inning numbers** are optional and can be 1-9 or higher
- **RBI counts** are automatically set to the inning number when provided
- **Player numbers** must exist in the loaded rosters
- **Case insensitive** - all inputs work regardless of capitalization

## Adding New Verbs

To add a new verb to the magic input system:

1. **Add the case** in the `_parseMagicInput` method in `caption_fields_widget.dart`
2. **Add the full action name** to the verb selection UI
3. **Update this reference document** with the new verb

### Example Addition
```dart
case 'newverb':
case 'new_verb':
  action = 'New Verb';
  break;
```

## Current Total: 40+ Supported Actions

The magic input system currently supports over 40 different baseball actions, covering hitting, pitching, base running, fielding, and game situations. 