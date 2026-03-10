# Fast keyboard-only caption workflow

Goal: write captions with minimal mouse use—keystrokes for players and verbs.

---

## What already works

### 1. Player selection (caption field)

**Where:** The main **Caption** text field (top of the caption builder).

**How:** Type a shortcode, then **Space**. The code is applied and can select players, inning, etc.

| You type | Effect |
|----------|--------|
| `h27` + Space | Select **home** player #27 (and add to personality) |
| `v15` + Space | Select **away** player #15 |
| `hh27` + Space | Home #27, no team name in output |
| `vv15` + Space | Away #15, no team name in output |
| `i3` + Space | Set inning to 3 |
| `di5` + Space | “During inning” 5 |

So for players: **h + jersey + Space** for home, **v + jersey + Space** for away. Multiple players: e.g. `h7 ` then `h23 ` then `v12 `.

### 2. Verb selection (number shortcuts)

**No focus needed (global shortcut):** Hold **Option (Alt)**, then press two digits: first = category (1–6), second = verb (1–9, 0=10th). Works from anywhere. Example: **Option+2** then **Option+3** → category 2, verb 3.

**Focus:** Click the verb area once so it has keyboard focus (or Tab to it if focus order allows).

**How:**

- **Two digits** = category, then verb  
  - e.g. `2` then `3` → category 2, verb 3.
- **Cmd + digit** = choose category, then next key = verb  
  - e.g. **Cmd+2** then **3** → category 2, verb 3.

So: **first digit = category (1–6), second = verb (1–9, 0=10th)**.  
**Cmd+1..6** = “jump to category”, then one digit = verb.

### 3. Player popup board (hockey)

- **Player selection:** Use the **search** fields; you can type **jersey numbers** (e.g. `7` or `27`) and submit (Enter) to add that player for that team. Tab between home/away search.
- **Categories:** **Cmd+1** … **Cmd+6** to expand category 1…6 (first in list = 1, including Favorites).
- **Verbs:** Still by clicking; number shortcuts for verbs could be added here later.

---

## Recommended fast flow (main layout)

1. **Start in the Caption field** (focus there).
2. **Players:**  
   `h27 ` → home 27  
   `v12 ` → away 12  
   (Add more with more `hNN ` / `vNN ` if needed.)
3. **Verbs:**  
   - Click once in the **verb area** (or Tab to it).  
   - Then e.g. **Cmd+2** then **3** (category 2, verb 3) or type **23**.
4. **Inning** (if needed):  
   Back in caption field: `i5 ` (or `di5 `).
5. **Save / next:** e.g. **Cmd+Enter** (if you have that shortcut) or one click.

So: **caption field for players (and inning)** → **verb area for verb by numbers** → done.

---

## Making it even faster (possible improvements)

1. **Unified “command” field**  
   One field that accepts both:
   - `h27 `, `v12 ` for players
   - `23` or `2 3` (after a delimiter) for “category 2, verb 3”  
   So you never leave the field: players then verb then inning, all by typing.

2. **Verb shortcuts from caption field**  
   When focus is in the caption field, interpret a short pattern (e.g. `;23` or `v 23`) as “select category 2 verb 3” so you don’t have to click into the verb area.

3. **Numbered player list**  
   Show roster as “1. Name, 2. Name…” and allow typing a number (and maybe team prefix) to pick by position in list instead of jersey (useful when you don’t know jerseys).

4. **Tab order**  
   Ensure Tab moves: Caption → Verb area → other controls, so you can go “players in caption → Tab → verb numbers” without the mouse.

5. **Player popup: verb by number**  
   After Cmd+category to expand, accept a single digit to choose verb 1–9 in that category so the whole flow is keyboard-only there too.

---

## Summary

- **Players:** Caption field, **hNN** and **vNN** + **Space**.
- **Verbs:** Verb area focused, then **two digits** or **Cmd+category** then **digit**.
- **Fast flow:** Type players (and inning) in caption → focus verb area once → type verb numbers → save/next.

If you want to prioritize one code change next, the highest impact is usually: **unified command field** or **verb-by-number from caption field** so you never leave the keyboard.
