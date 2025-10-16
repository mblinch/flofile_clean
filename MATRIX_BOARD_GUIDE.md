# Matrix Caption Board - Quick Reference

## Overview

The Matrix Caption Board is a fast caption builder designed to minimize mouse travel and keyboard interaction for rapid caption generation during live sports events.

## How to Enable

1. Open the app preferences (gear icon or keyboard shortcut)
2. Select "Matrix Board (Fast Caption Builder)" from the layout options
3. Click Save

## Layout

```
┌─────────────────────────────────────────────┬──────────────┐
│  [HOME: EDM]  [AWAY: TOR]  [Tab to toggle]  │              │
├─────────────────────────────────────────────┤   Picture    │
│              MATRIX GRID                     │   Preview    │
│    Scores | Skates | Celebrates | ...       │              │
│ #97 McDavid   □   |   □   |      □     |... │              │
│ #29 Draisaitl □   |   □   |      □     |... ├──────────────┤
│ ...                                          │              │
│                                              │  Thumbnails  │
├─────────────────────────────────────────────┤              │
│  CAPTION PREVIEW                             │              │
│  [Full Getty-style caption shows here]      │              │
│  [Copy] [Save]                               │              │
└─────────────────────────────────────────────┴──────────────┘
```

## Quick Start

### One-Click Caption Generation
1. Click any cell in the matrix (Player × Verb)
2. Caption generates instantly in the preview area
3. Click **Copy** to clipboard or **Save** to metadata

### Adding an Opponent (Optional)
1. For verbs like "Scores" or "Saves"
2. Hold **Shift** and click a cell (future implementation)
3. The opponent appears in the caption automatically
4. Press **Esc** to clear the opponent

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| **Tab** | Toggle between HOME and AWAY teams |
| **Arrow Keys** | Navigate the matrix grid |
| **Enter** | Commit the selected cell |
| **1-5** | Quick-select verb (column number) |
| **Esc** | Clear opponent selection |

## Verb Definitions

1. **Scores** - With opponent support
2. **Skates** - General skating action
3. **Celebrates** - Celebration moments
4. **Looks On** - Observing the play
5. **Saves** - Goalie saves (with opponent support)

## Caption Templates

### With Opponent
```
{Player} #{Num} of the {Team} scores against {Opponent} #{OppNum} 
of the {OppTeam} during {Period} at {Venue} on {Date}.
```

### Without Opponent
```
{Player} #{Num} of the {Team} {Verb} during {Period} at {Venue} on {Date}.
```

## Overtime Phrasing

The board automatically formats overtime periods:
- **OT1** → "overtime"
- **OT2** → "double overtime"
- **OT3** → "triple overtime"

## Tips for Speed

1. **Mouse Workflow**: Click player-verb cell → Click Copy → Next image
2. **Keyboard Workflow**: Arrow keys → Enter → Cmd+C → Right arrow (next image)
3. **Team Switching**: Press Tab to instantly switch between home/away rosters
4. **Hover Preview**: Hover over any cell to highlight the row and column

## Features

- ✅ Instant caption generation
- ✅ Live caption preview
- ✅ Keyboard navigation
- ✅ Responsive grid layout
- ✅ Mock data for testing (10 players per team)
- ✅ Real roster integration (when teams are selected)
- ✅ Hover highlights for better visibility
- ✅ One-click copy to clipboard
- ✅ Direct save to metadata

## Testing

The Matrix Board includes mock NHL data by default:
- **Home**: Edmonton Oilers (10 players)
- **Away**: Toronto Maple Leafs (10 players)

When you select real teams in the startup dialog, the board will use actual rosters from the API.

## Troubleshoads

**Q: The matrix is empty**
- Ensure teams are selected in the startup dialog
- Check that rosters loaded successfully

**Q: Caption doesn't update**
- Click a cell to select it
- Check that venue and date metadata are present

**Q: Keyboard shortcuts don't work**
- Click inside the matrix area to focus
- Ensure no other dialogs are open

## Future Enhancements

Planned features:
- Shift+Click opponent selection from inactive team
- Custom verb definitions
- Period selection dropdown
- Caption history/favorites
- Batch processing mode

---

**Happy Captioning! 🚀**


