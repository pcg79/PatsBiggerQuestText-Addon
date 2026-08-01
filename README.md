# Pat's Bigger Quest Text

A tiny World of Warcraft (Retail) addon that makes quest-related text bigger and
easier to read:

- The **quest dialog window** — description, objectives, rewards, and progress
  text you see when accepting and turning in quests.
- The **NPC gossip window** — the greeting paragraph and the clickable dialog
  options.

Both are controlled by the same size setting.

## Install

1. Copy the whole `PatsBiggerQuestText` folder into your WoW AddOns directory:

   ```
   World of Warcraft/_retail_/Interface/AddOns/PatsBiggerQuestText/
   ```

   The folder must contain `PatsBiggerQuestText.toc` and `PatsBiggerQuestText.lua`
   directly (the folder name must match the `.toc` name).

2. Restart WoW, or type `/reload` if you're already logged in.
3. On the character select / AddOns screen, make sure **Pat's Bigger Quest Text**
   is enabled. (If it shows as "out of date," tick **Load out of date AddOns**.)

## Usage

- `/pbqt 18` — set the quest/gossip text size to 18 (valid range 10–30).
- `/pbqt scale 1.3` — scale the whole quest/gossip window to 1.3x (range 1.0–2.0).
- `/pbqt` — show the current size and scale.
- `/pbqt config` — open the options panel with both sliders.

You can also reach the sliders via **Game Menu → Options → AddOns → Pat's Bigger
Quest Text**.

**Text size** enlarges just the text inside the window — great for readability,
but very large text can crowd the fixed-size frame. **Window scale** zooms the
entire window (background, text and buttons together) so it never feels cramped.
Use them together: bump the text size for readability, then raise the window
scale until it has room to breathe.

Both settings are saved account-wide, so they apply to all your characters.

## Notes / tweaking

- Default size is **16**. Change `DEFAULT_SIZE`, `MIN_SIZE`, or `MAX_SIZE` at the
  top of `PatsBiggerQuestText.lua` if you want a different default or range.
- The quest **title** is intentionally left at its default size so the visual
  hierarchy is preserved. To resize other elements, add their FontString names
  to the `FONT_STRINGS` list in the Lua file.
- If a new patch bumps the interface version and the addon shows as out of date,
  update `## Interface:` in `PatsBiggerQuestText.toc` (or just enable "Load out
  of date AddOns").
