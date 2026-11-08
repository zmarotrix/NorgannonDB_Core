# Changelog

Earlier versions are in the git history.

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
