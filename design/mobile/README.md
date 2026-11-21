# FloFile Captions — phone layout design

Reference design for the phone layout shown by the Admin-only "Mobile layout" toggle.
These files are design mockups (HTML), not Flutter code. Use them for layout, sizes, colours and behaviour.
Do NOT change the Getty caption structure; the sample captions only show where text goes.

## Screens (`screens/`)
| File | Screen |
|---|---|
| `Main.dc.html` | Caption screen, Home players pane. Contains ALL caption-screen logic (swipe, tabs, selection, caption build, incomplete-save warning). |
| `CaptionActions.dc.html` | Same screen opened on the Actions pane (Matthews + Faceoff selected) |
| `CaptionAway.dc.html` | Same screen opened on the Away pane (Matthews v Giroux) |
| `Setup.dc.html` | New session: Game, Photos source, Wire, IPTC mode + template link, Go time |
| `Template.dc.html` | IPTC template, grouped fields (Story / Credit / Location / Filing) |
| `Photos.dc.html` | Photo grid, 3 columns, status dots |
| `EditPhoto.dc.html` | Photo editor: photo on top, sliders below |
| `Settings.dc.html` | Settings as grouped list |

The markup between `<x-dc>` and `</x-dc>` is the layout (inline styles = exact sizes/colours). The `<script>` block at the bottom holds the data and behaviour. `{{name}}` placeholders are filled from `renderVals()` in that script.

`photos/` holds the sample photos the screens use (their `/_blob/...` addresses map to ph1–ph4).

## Frame
- 390 × 844 logical px (iPhone). Also test 412 × 915 (Android).
- Font: Inter (400–800).

## Caption screen, top to bottom (Main.dc.html)
1. Header 48px: back, "OTT @ TOR" + "Nov 17, 2026 · Getty", photo counter, settings.
2. Photo 196px tall, cover crop; file name bottom-left; Edit button bottom-right.
3. Banner slot 30px — ALWAYS reserved (empty when idle). Shows incomplete-save warning (red) or "Saved …" (green). Must never move the layout.
4. Caption block: CAPTION label + Personality on one line; caption text box fixed at 72px (≈4 lines at 13px/1.38) and scrolls inside; period buttons Pre 1 2 3 OT Post.
5. Tabs TOR | Actions | OTT (44px tall, active = white text + 2px blue underline).
6. Swipe area (PageView, 3 pages, 390px each): swipe left/right or tap a tab. Swipe threshold ~45px. Page dots below.
   - Home / Away: 5-column grid, gap 6px, buttons 54px tall, radius 10, name (9px caps) above number (19px, 800). Selected = white bg, dark text. "Other" row: Players / Team / Teammates (44px).
   - Actions: search / custom action field (40px) then rows 44px with letter index; selected row white with ✓.
7. Bottom bar: Save & Prev (52px wide), Paste last (52px), Save & Next (fills width, white, primary), FTP (64px). Buttons 48px tall, radius 12.

Behaviour:
- Tap a player toggles it. Caption + Personality update live ("Player;Player" in Personality).
- Save & Next with player(s) but no action → do NOT save; banner warning; jump to the Actions page.
- Save & Next valid → save, next photo, clear selection, return to the Home players page, banner "Saved <file>".

## Colours
| Use | Hex |
|---|---|
| App background | #0f1114 |
| Card / surface | #181b1f (border #23272d) |
| Buttons / inputs | #1d2126 – #22262c |
| Dividers | #1f2328 |
| Text | #e9edf2 |
| Secondary text | #8a929c / #a3abb5 |
| Selected (button bg) | #f2f4f7 with text #0f1114 |
| Link / active tab line | #8fb6e0 |
| Warning (amber) | text #f0cf7a on #2d2614 |
| Error banner | text #f3a49d on #3a1d1f |
| Success banner | text #7fd9a8 on #15291f |
| Status dots | captioned #4cc38a, not yet #e2b84a, new #8fb6e0 |

## Rules
- Touch targets ≥ 44px.
- Same controllers/services as desktop; only widgets differ. Choose layout by width (LayoutBuilder, phone < ~600px).
- Mobile layout toggle visible only in Admin Mode.
