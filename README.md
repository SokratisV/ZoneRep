# ZoneRep

**See, zone by zone, how much reputation each faction's quests give, how much you have earned, and how much is left. Click a quest to mark its quest giver on the map.**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Release](https://img.shields.io/github/v/release/SokratisV/ZoneRep)](https://github.com/SokratisV/ZoneRep/releases/latest)
![WoW](https://img.shields.io/badge/WoW-Forever-f8b700)
![Interface](https://img.shields.io/badge/interface-16001-555)

> **Requires [Questie](https://www.curseforge.com/wow/addons/questie).** Every quest, its reputation
> reward, its zone, who can take it and where its quest giver stands is read live from Questie's
> database. ZoneRep ships no quest data of its own, and does nothing without Questie.

> **Client support.** Built for **WoW Forever** (interface `16001`). Forever serves Classic content from
> the Midnight 12.x client, so it reports a Classic project id but only exposes the modern namespaced
> API; every call that moved is feature-detected rather than switched on project id.

Open the window with `/zonerep` (or `/zrep`). Every zone with reputation quests is a row; open it to see
each faction the zone's quests give rep with, as a progress bar:

```
Elwynn Forest                              3,592 / 3,592  -  0 left
  Stormwind                                1,984 / 3,592  -  1,608 left
```

## What it shows

- **Per zone and faction.** For each zone: the total reputation its one-time quests give, how much of it
  you have **earned** (the quests you have completed, so it is correct from your first login with the addon,
  not just from then on) and how much is **left to earn**. The header of each zone adds it all up.
- **By zone or by faction.** Switch the list between zones (with their factions under them) and
  factions (with their zones under them). The chosen view is lit, and remembered.
- **The quests themselves.** Click a faction row to list the quests that still give rep with it, biggest
  first, each with its rep value. Quests already in your log are marked.
- **Search.** Type a zone, a faction or the name of a quest. Matching zones open on their own and only the
  matching rows stay; a quest name takes you straight to its faction row.
- **Current zone, Expand all, Collapse all, Hide finished.** One click to jump to the zone you stand in, to
  open or close everything, or to drop what you have finished.
- **Kills and other sources.** No database lists the rep you gain from killing mobs, turning in items or
  other quest-less sources, so ZoneRep measures it while you play and files it under the zone you were in.
  It shows as `+N` next to the quest figures. It counts from the day you install ZoneRep, per character,
  and has no "left" figure. A quest hand-in is not counted twice.
- **Names for every faction.** The game only names factions that are in your character's reputation list.
  For the rest, ZoneRep uses the names in Questie's own faction list.

## Marking quests on the map

Click a quest in the list and the world map opens on its quest giver's zone with a pin on the spot:

- a gold **X** where to **pick the quest up**, a gold **?** where to **hand it in** once it is in your log;
- as many pins as you like at once; **right-click** a pin to remove it, or use **Clear marks** (or
  `/zonerep clearmarks`);
- a pin removes itself when you pick the quest up (or hand it in), and the quest turns gold in the list
  while it is marked.

The pins are ZoneRep's own, drawn on the Blizzard map, because Forever's user-waypoint API is not reliable.
Positions come from Questie, so a quest that starts from an item or a world event has no spot to mark and
says so in chat.

## How the numbers are worked out

- Only **one-time** quests count. Repeatable, daily and weekly quests, and quests Questie hides, are left
  out.
- Only quests **your race and class can take** count. Questie's own check decides, so a Horde character
  never sees the Alliance quests.
- Quests that exclude each other count once: the one you did, or else the most generous.
- Values are Questie's, including its adjustments such as the Human bonus. Standing caps (rep that stops
  counting past Honored or Revered) are **not** applied, so a zone can promise more than a faction will
  still take from you.
- A quest is **earned** once the game flags it completed (or Questie records it so).

## Commands

```
/zonerep               open or close the window         (alias: /zrep)
/zonerep clearmarks    remove every map pin
/zonerep reset         forget the rep tracked from kills and other sources (this character)
/zonerep rescan        read Questie's quest data again
/zonerep factions      list the factions nobody has a name for, with the quests that give them
/zonerep debug         what ZoneRep can read: quest index, tracker, your race id
```

## Look

ZoneRep is drawn in the style of [FlareUI](https://www.curseforge.com/wow/addons/flareui): the rock tile
in warm dark bronze under a bronze frame, gold titles, dark rounded rows and grey plate buttons. FlareUI is
optional; with it loaded its own border and plate art is used, without it the same layout is drawn from
Blizzard's textures.

## Data

ZoneRep keeps a small saved table, `ZoneRepDB`: the window's position, the chosen view, and the rep it has
tracked from kills and other sources, per character. Nothing leaves your client.

The text is English; zone, faction and quest names are the game's and Questie's, in your client's language.

## Install

Install **Questie** and ZoneRep, then restart the game (a reload is not enough the first time).

## License & credits

[MIT](LICENSE). The quest data is [Questie](https://github.com/Questie/Questie)'s (GPL-3.0), read at runtime;
none of it, and none of Questie's code, is copied into ZoneRep. The look follows FlareUI's, and nothing of
FlareUI's is copied either: its art is only referenced when FlareUI is installed.
