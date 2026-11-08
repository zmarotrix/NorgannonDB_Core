# Changelog

Earlier versions are in the git history.

## 1.22.2 (2026-11-07)

Memory, measured in game with `/norg mem rate`: the Core was still making about 173 KB of garbage a second.

- The compass made about 650 bytes per frame while you moved or turned, because the game's `C_Texture.GetAtlasInfo`
  makes a new table on every call, and every marker asked it on every frame. Whether the client has an atlas is
  now asked once per atlas. The compass's markers and the map's pin frames only set an icon when it changes
  (`Core.MapIcons.SetOwned`; `Core.MapIcons.Reset()` forgets both).
- `/norg mem rate` now measures every function on the Core's tables (`Core`, `Core.UI`, `Core.Map`, ...) as well as
  the timed ones. Each is counted without what the other measured functions inside it made, so the rest is
  narrowed to local code and the game events' own arguments.
- `/norg mem` says how the last minimap pass went: drawn, minimap hidden, or no player position; the pins it
  looked at and found inside; the view radius; and your instance beside the pins' instances. In game it had drawn
  no pins since the reload.
- `/norg mem rate` lists the busiest game events the Core passed to the suite, with KB/s made by their listeners
  (`Core:SetEventTap`).

## 1.22.1 (2026-11-07)

- The Core has its own mark: a light blue four-point star (`#a6e4ff`, mark key `core`). It replaces the database
  cylinder on the Norgannon minimap button, the minimap list, NorgannonDB's Settings page, the About card, the
  game's add-on list (TOC icon), and as the mark for add-ons outside the suite. "Powered by NorgannonDB" in every
  window's footer shows a small star instead of the database icon.
- The NorgannonDB data add-on keeps the gold database cylinder: that one is the data, the star is the suite's core.
- `Core.FAMILY` gains `core` (NorgannonDB Core), so `UI.Accent("core")` and the UI gallery know it.

## 1.22.0 (2026-11-07)

Memory. In game the Core showed 23.5 MB after two minutes of questing; it was two things, both fixed.

- The minimap pins no longer make garbage. Each redraw (20 a second) made a table for every pin inside the minimap,
  one per pin for its icon's file list and one per overlap check: about 22 KB per redraw with 486 pins, 445 KB a
  second, which the game counts against the Core until the collector gets to it. Now a redraw makes none. Areas on
  another continent are skipped whole.
- The name index is built per kind, the first time something asks (a search, `Core.DB:IdsByName`), not at login, and
  packed: a name with one id keeps the id itself, and the display name is read from the database when shown. All four
  kinds took 10.3 MB; they now take 6.2 MB, and a session that only hovers objects holds 0.6 MB. A kind builds in
  under 20 ms. `Core.DB:EnsureIndex(kind)` builds one kind (or every kind without one); `DB.indexReady` and
  `NORGANNON_INDEX_READY` now mean every kind is built. Results and `IdsByName` still return lists.
- The compass doesn't redraw while you stand still facing the same way; it redraws when you move or turn, when its
  targets are recomputed (4 a second), and on a highlight or a colour change. Finding the nearest pin per group
  makes no tables.
- `/norg mem` prints each suite add-on's memory in use and how much of it was garbage (after a full collection, a
  short hitch), the name index per kind, the map's pins, areas, cached world positions and frames, the compass, and
  the people Names knows. `/norg mem rate [seconds]` pauses the collector for that long (default 10) and prints how
  fast each add-on makes garbage.
- `/norg perf` reports memory in use after a full collection, with the garbage beside it, and covers every suite
  add-on. The timing wrapper no longer makes a table per call, which it charged to the Core.
- New: `Core.DB:IndexStats()`, `Core.Map:MemoryStats()`, `Core.Compass:MemoryStats()`, `Core.Perf:Memory()`,
  `Core.Perf:MemoryRate(seconds)`, `Compass.stats.draws`.

## 1.21.2 (2026-11-07)

- NorgannonDB's Settings page is now the suite's hub, made for many add-ons:
  - The header says it's the core of the suite, with the Core's version and, on one line, NorgannonDB's data (or
    that the data isn't loaded, so add-ons that need it are off).
  - Your add-ons are tiles, two to a row: mark, name, what it does, version. "Running" is no longer said nine times;
    a tile only says something when an add-on isn't running ("Installed, not loaded", or "Turned off" and why).
  - Clicking a tile opens that add-on, as its row in the minimap list does; hovering shows its tooltip.
  - The tiles scroll when there are more than fit. The credits are a short footer.
- `Core:AddonState` can say `"off"`: the add-on loaded but turned itself off (`Core:NewAddon` found the Core or the
  data too old), with the reason from `Core:AddonProblem(key)`.

## 1.21.1 (2026-11-07)

- An add-on's name in its chat lines, its tooltip and the minimap flyout uses `UI.AccentText`, so a dark accent
  (Bulwark's blue) is lightened enough to read.
- `/norg` and NorgannonDB's Settings page opened in combat now open when the fight ends, instead of being refused.
- The NorgannonDB card says "add-on". The README lists every suite add-on, and says which need NorgannonDB.

## 1.21.0 (2026-11-07)

- `Core.Net`, add-on messages under an add-on's own prefix, taken from Council's: `Net:Channel(prefix, { onMessage })`,
  `:Send(text, distribution, target, priority, volatile)`, `:Blocked()`, `:Test()`, `:QueueSize()`. It moves text, and
  each add-on keeps its own serializer. It compresses when the client can, holds messages through chat lockdown instead
  of losing them, finds out with a real test send whether the game refuses them, and whispers the sender's full name.
  `Net.Pack` and `Net.Unpack` give the wire framing ("T" text, "Z" compressed).

## 1.20.0 (2026-11-07)

- API 1.20, the pieces several add-ons had each built their own copy of:
  - `Core.Names`: who someone is when characters have a first and a last name. `Names.First`,
    `Names.Full`, `Names.Key`, `Names.HasSurname`, `Names.Me`, `Names.IsMe`, and
    `Names:Address(nameOrUnit)`, the full name a whisper reaches, learned from chat and add-on
    messages. `Core.Guild.Short` is now `Names.First`.
  - `Core:Restricted("combat" | "fight" | "send")`: one answer to "may we act now?". Combat is
    read from `InCombatLockdown`, because the client's restriction check reads false in
    open-world combat. Message `NORGANNON_RESTRICTIONS_CHANGED`.
  - `Core:NewAddon` gains `onUnknown` (a slash command's catch-all, e.g. a search) and `ownLoad` (for an add-on that
    loads its own saved variables and decides when it's ready).
  - `UI.ActionList`: rows with a title, a line under it, right-hand text, an item's icon and
    tooltip, and buttons. `UI.Input`: a text field in the suite's look. `UI.Tip`.
  - Colours for states: `UI.C.good`, `bad`, `warn`, `info` and `hint`, plus `UI.State(name)`.
    `UI.AccentText(key)` lightens an accent that is too dark to read as text (Bulwark's blue),
    and `UI.Contrast(a, b)`.

## 1.19.0 (2026-11-07)

- Core no longer needs NorgannonDB. Add-ons that don't read the game data (Muster, Mercy, Bulwark) now
  run with Core alone, without the quest database (about 33 MB of game memory). With NorgannonDB missing, Core's data calls
  answer nothing, and `/norg demo` and `/norg version` say so.
- API 1.19, for building add-ons (see docs/dev/getting-started.md in the suite workspace):
  - `Core:NewAddon(key, opts)`: the version check, saved variables with defaults and migrations,
    registration, the minimap flyout row, the game's add-on menu, the slash command and the settings
    page, in one call. Settings asked for in combat open when the fight ends.
  - `Core:SavedVars(name, opts)`: saved variables with a version (`_v`), migrations that run once,
    and deep defaults.
  - `Core.Fn`, `Core.Has`, `Core.Call`, `Core.Plain`, `Core.Global`, `Core.In`, `Core.SetSecret`,
    `Core.Now`: one safe way to call the client.
  - `Core:HasData()`, `Core:DefineAddon(info)` for add-ons outside the suite, `UI.MarkPath(key)`.
  - `Core:Require` now keeps its promise across major versions: a previous major listed in
    `Core.COMPAT` is still served. `Core:IsDeprecated` and `Core:RequireMessage` go with it.

## 1.18.0 (2026-11-07)

- One Norgannon button on the minimap in place of one button per suite add-on. Click it for a
  list of your NorgannonDB add-ons: each row has the add-on's mark, name and a short status
  (from its tooltip). Click or right-click a row as you would the add-on's own button; hover it
  for the add-on's tooltip. Escape or a click elsewhere closes the list.
- Pin an add-on (the pin at the end of its row, or NorgannonDB > Minimap in the game's
  Settings) to keep its own button on the minimap as well. An add-on's "Show the minimap button"
  setting now means pinned.
- Everything starts unpinned. Add-on buttons keep the places they were dragged to, for when
  they are pinned again.
- The Norgannon button drags around the minimap's edge like the others, and can be hidden on
  the Minimap page.
- API 1.18: `MinimapButton:SetPinned`, `:IsPinned`, `:SetMainShown`, `:IsMainShown`, `:Status`.
