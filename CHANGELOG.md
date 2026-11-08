# Changelog

Earlier versions are in the git history.

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
