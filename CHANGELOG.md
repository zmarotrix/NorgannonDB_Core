# Changelog

Earlier versions are in the git history.

## 1.28.4 (2026-11-11)

- `Core.Map.ZonesInView()` lists the zones whose pins the world map shows: the zone map's own, or, on OpenMap's stitched map, every zone in view. `NORGANNON_WORLDMAP_ZONES (zones)` announces a change. Add-ons that make pins zone by zone use it to cover every zone you're looking at.

## 1.28.3 (2026-11-10)

- Each quest in `Core.Player` carries `header`: the quest log's header above it (its zone or category, as the game names it). Add-ons use it for quests no database knows.

## 1.28.2 (2026-11-09)

- **Works with OpenMap**, the seamless world map. On its stitched map, the suite's pins (quests, tracking, gathering,
  rares, Oracle's entrances) now show for every zone in view, not just the one under the centre, and draw above
  OpenMap's map art instead of under it. They are placed through OpenMap's own API (`OpenMapAPI.WorldFromMap` and
  `MapFromWorld`) and redraw when its view moves. On Blizzard's own map, or without OpenMap, nothing changes.
  `Core.Map.OpenMapStitched()` says whether the stitched map is up.

## 1.28.1 (2026-11-09)

- **Fixed "NorgannonDB_Core tried to call the protected function Button:SetPassThroughButtons()"** when opening the
  map or quest log. Add-ons in the suite opened or switched Blizzard's world map from their own code ("Show on map").
  The map then built its own quest pins inside add-on code, and the pin pool stayed tainted for the session.
  `Core.Map:Reveal(area, key)` replaces that: it pulses the pins now if the map is open on their zone, or when the
  player next opens it there, and never opens or switches the map itself. Clairvoyance and Oracle use it.
  `platform_test.py` fails any suite add-on that opens or switches Blizzard's map.

## 1.28.0 (2026-11-09)

- `Core.Net` and `Core:Say` / `Core:OpenChat` are LibForever-1.0's too (phase 2 of the toolkit), the same table and
  functions. `Core:Say` still remembers which chats reach in `NorgannonCoreDB.say`; `Core:ResetSay` stays in Core.
- Map pins can take `ring = {r, g, b}`, a border colour around the dot (`Map.RINGS`).

## 1.27.0 (2026-11-09)

- The Forever toolkit is now its own library, LibForever-1.0, which other add-on developers can use too. It lives in
  ForeverAPI and ships in `libs/LibForever-1.0`. Events and messages, `AfterCombat`, `NextFrame`, `Restricted`, the
  client and secret-value helpers (`Fn`, `Call`, `Plain`, `Global`, `In`, `SetSecret`, `IsSecret`, `Safe`, `Now`,
  `Client`), `Core.Compat`, `Core.Secret`, `Core.Names` and `Core:SavedVars` are the library's, under the same names.
  Nothing an add-on calls changed. `UI.UnitBar`, `Core:Debug`'s log and `Core:Print`'s prefix stay in Core.
- `NORGANNON_RESTRICTIONS_CHANGED` still fires; it now follows the library's `LIBFOREVER_RESTRICTIONS_CHANGED`.
- `compat_list.lua` is gone: the generated Compat list is the library's `CompatList.lua`, made by ForeverAPI's
  `tools/compat_gen.py`.

## 1.26.2 (2026-11-08)

- The minimap flyout's second line is always grey; only the add-on's name carries its colour.
- Roles: Mercy is "Healing frames" and Bulwark "Aggro management".

## 1.26.1 (2026-11-07)

- `Core.Compat.CastingInfo()` and `ChannelInfo()`, classic's player-only cast calls, through `UnitCastingInfo` and
  `UnitChannelInfo` (Forever loads Blizzard's mainline deprecation shims, which don't include them). 60 functions.
- `Core.Compat.UnitAura` and friends use Blizzard's `AuraUtil.UnpackAuraData` where the client has it.

## 1.26.0 (2026-11-07)

- `Core.Compat` covers 17 more classic functions, generated from ForeverAPI's table of what Forever dropped:
  quest log (`IsQuestFlaggedCompleted`, `GetQuestLogIndexByID`, `GetNumQuestLogEntries`, `AbandonQuest`, ...),
  reputation headers, gossip counts, `GetContainerItemID`, `IsEquippedItem`, `LoadAddOn`, `GetZonePVPInfo` and more:
  58 in all. Only calls that take the same arguments and give the same answers are generated; ones whose answer
  changed (`SendAddonMessage` now returns a result code) are left out. `tools/compat_gen.py` regenerates the list.

## 1.25.0 (2026-11-07)

- `Core:Say(text, kind)`: a chat line from an add-on that reaches chat, or, where the game doesn't let it through
  (reported in instances, and seen by Council in raids), the chat box opens with the line ready to send with Enter.
  It remembers which chats reach, in instances and outside them separately. `Core:OpenChat(text)`, `Core:ResetSay()`.
  From Council's loot announcements.
- The developer guide opens with the Forever toolkit: each WoW Forever problem and the Core call that solves it.

## 1.24.0 (2026-11-07)

- For add-ons that show health, threat or anything else the client keeps secret (health always, about 90 getters in
  combat), the way Mercy and Bulwark do it, now for everyone:
  - `UI.UnitBar(parent, opts)`: a health or power bar that never reads the secret numbers. Colour fixed or a
    red-to-green gradient, text current, percent or missing, short numbers.
  - `Core.Secret`: `Curve` and `ColorCurve` (the client does the maths on a secret), `Text` and `Number` (formatted
    secrets), `Alpha` (show or fade by a secret boolean, since `SetShown` won't take one), `Color` and
    `ColorFromBoolean`.
  - `UI.UnitAuras(parent, unit, opts)`: a unit's buffs and debuffs, drawn by the game in a container of yours, in
    combat too. Add-ons can't read auras in combat on Forever, but the game can draw them.
- Not built, on purpose: a cooldown swipe for secret in-combat cooldowns. Every Cooldown setter takes secrets only from
  Blizzard's own code (ForeverAPI's widget data), so an add-on can't feed one.
- Forever's `WOW_PROJECT_ID` is 18, `WOW_PROJECT_CAMELOT` (ForeverAPI), not Retail as reported: `Core.Client.Flavor()`
  never trusted it, and the comment now says so.

## 1.23.1 (2026-11-07)

- Fixed: with more than 24 objectives near you, the compass stopped and the game reported
  "compass.lua:237: attempt to index field 'pin'" many times over. Since 1.22.2 the compass could let go of the pin
  of a marker it was still showing. The harness now tries 40 nearby objectives.

## 1.23.0 (2026-11-07)

- `Core.Compat`: the classic functions WoW Forever's client no longer has, with their classic answers:
  `GetSpellInfo`, `GetSpellCooldown`, `GetItemInfo`, `GetContainerItemInfo`, `GetSpellBookItemInfo`, `UnitAura`
  and 35 more (`Compat.MAP` lists them). Each uses the client's own global where there is one, else its
  replacement in C_Spell, C_Item, C_Container, C_SpellBook or C_AddOns, reshaped to the classic return values. No
  globals are written, so other add-ons are left alone. The harness checks the list against ForeverAPI's dump.
- `Core.Client.IsForever()`, `Flavor()` ("forever", "classic", "retail", ...), `IsClassicWorld()` and `Interface()`:
  which client this is, from the interface number, because `WOW_PROJECT_ID` is reported to say Retail on Forever.

## 1.22.6 (2026-11-07)

- The suite's name in game is **Norgannon**, its brand name (brand/BRAND.md). NorgannonDB stays the name of the game
  database. The Settings category, the hub page, the minimap button's tooltip, the About card and "Powered by" say
  Norgannon, and this add-on's title is Norgannon Core. Folders, globals and saved variables are unchanged.
- The add-ons' roles follow the brand's words: Quest map & tracker, Dungeon & world atlas, Alt tracker, Bag manager,
  Healer frames, Threat & aggro, Guild loot & records, Guild recruiting.
- The About card says what Norgannon is, and asks for help keeping the database true.

## 1.22.5 (2026-11-07)

- `/norg minimap` puts three test pins around you (red on you, green 50 yards north, blue 100 yards east) for a
  minute and says what the minimap pass made of them: how many were inside and drawn, the nearest, the view radius,
  and the zone's size. In game the minimap had drawn no pins; this tells "no objective near you" (Clairvoyance
  keeps "!" and "?" off the minimap, so only objective pins go there) apart from a minimap that can't draw.

## 1.22.4 (2026-11-07)

- Council and Muster are the suite's add-ons for guilds: `Core.SUITE` lists them last with `group = "guild"`.
  NorgannonDB's Settings page shows them after the others under a "For guilds" heading, and the minimap list sorts
  them last.
- Archivum, the database browser, is shelved: it's gone from the registry, so nothing lists it as missing. Its mark
  stays in the Core's media in case it comes back.
- The README's suite table follows: For guilds last, no Archivum.

## 1.22.3 (2026-11-07)

- The minimap's view radius on a client without `C_Minimap.GetViewRadius` (Forever) is now the classic client's
  size for the zoom level, indoors or outdoors: 233 yards out to 67 outdoors, 150 to 25 indoors. It was a fixed 150.
- `/norg mem` names the nearest pin to you on the minimap pass.
- `/norg mem rate` measures how long it really ran and how many frames, how much everything together grew, and the
  KB made in each of the Core's own frame scripts (map driver, compass, arrow, HereBeDragons, ChatThrottleLib),
  which no table reaches. `Core.Map.driver` and `Core.Compass.driver` are exposed for it.

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
