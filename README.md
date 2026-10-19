# NorgannonDB Core

The shared runtime under the NorgannonDB suite: Clairvoyance, Oracle, Foresight and Archivum.
It ships in the NorgannonDB download and depends on NorgannonDB.

It provides:
- the client layer, events and messages
- player state (quest log, completed quests, professions, position)
- name search and relation lookups over NorgannonDB
- the suite's UI kit
- the shared map layer for the world map and minimap, the objective compass and the waypoint arrow
- shared quest colors
- the suite's Settings page

The API is versioned and documented in the suite workspace (`docs/core-api.md`).

Commands: `/norg` (settings, suite status, credits), `/norg ui` (UI kit gallery), `/norg demo`
(map, compass and arrow preview from your quest log), `/norg compass`, `/norg debug`.

Made by **Maro**. All rights reserved for now; see `LICENSE` and `THIRD-PARTY-NOTICES.md`.
