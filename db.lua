-- NorgannonDB for the suite: name search over every quest, NPC, object and item, and the
-- relation indexes (SPEC 1.2 `index`). Addons ask here instead of scanning the database.
--
--   local results = Core.DB:Search("peacebloom", { kinds = { objects = true, items = true } })
--   for _, r in ipairs(results) do print(r.kind, r.name, #r.ids) end

local Core = NorgannonCore
local DBX = {}   -- Core.DB. "DB" in this file is NorgannonDB, the data itself
Core.DB = DBX

local KINDS = { "quests", "npcs", "objects", "items" }
DBX.KINDS = KINDS

local function db() return NorgannonDB end

-------------------------------------------------------------------------------------------
-- Names
-------------------------------------------------------------------------------------------

---Localized name of an entity (falls back to enUS), without decoding the record.
function DBX:Name(kind, id)
  local DB = db()
  local record = DB and DB[kind] and DB[kind][id]
  if not record then return nil end
  local loc = DB:GetLocale()
  local entry = loc and loc[kind] and loc[kind][id]
  if type(entry) == "string" then return entry end
  if type(entry) == "table" then
    local name = rawget(entry, "name")
    if name then return name end
  end
  return rawget(record, "name")
end

---true if the quest can't be obtained in the game (SPEC: quest.hidden == true).
function DBX:IsQuestHidden(id)
  local DB = db()
  local hidden = DB and DB.index and DB.index.hiddenQuests and DB.index.hiddenQuests[id]
  return hidden == true
end

-------------------------------------------------------------------------------------------
-- Name index: one slot per distinct lower-cased name and kind, with every id of that name,
-- so a search for "Peacebloom" tracks every Peacebloom node at once.
--
-- Built per kind, the first time something asks about that kind, not at login: all four kinds
-- held 10 MB, and most sessions only ever ask about one or two (a tooltip asks about objects,
-- Council about items). Packed: a slot is its lower-cased name and its ids, where ids is the id
-- itself when the name has only one (most do) and a sorted list otherwise. The display name is
-- read from the database when a result is shown.
-------------------------------------------------------------------------------------------

local index = {}          -- [kind] = { lower = { name, ... }, ids = { id or {id, ...}, ... }, byLower = { [name] = slot } }
DBX.indexReady = false    -- every kind built

local function buildKind(kind)
  local DB = db()
  local lower, ids, byLower = {}, {}, {}
  local n = 0
  for id in pairs(DB and DB[kind] or {}) do
    if not (kind == "quests" and DBX:IsQuestHidden(id)) then
      local name = DBX:Name(kind, id)
      if type(name) == "string" and name ~= "" then
        local key = string.lower(name)
        local slot = byLower[key]
        if not slot then
          n = n + 1
          byLower[key], lower[n], ids[n] = n, key, id
        elseif type(ids[slot]) == "table" then
          table.insert(ids[slot], id)
        else
          ids[slot] = { ids[slot], id }
        end
      end
    end
  end
  for _, list in ipairs(ids) do
    if type(list) == "table" then table.sort(list) end
  end
  return { lower = lower, ids = ids, byLower = byLower }
end

-- a slot's ids as a list (a fresh one for a single id, so callers may keep it)
local function idList(slots, slot)
  local ids = slots.ids[slot]
  if type(ids) == "table" then return ids end
  return { ids }
end

-- a slot's display name: the database's (localized) name of its first id
local function displayName(kind, slots, slot)
  local ids = slots.ids[slot]
  return DBX:Name(kind, type(ids) == "table" and ids[1] or ids) or slots.lower[slot]
end

local function kindIndex(kind)
  local slots = index[kind]
  if not slots then
    slots = buildKind(kind)
    index[kind] = slots
    for _, k in ipairs(KINDS) do
      if not index[k] then return slots end
    end
    DBX.indexReady = true
    Core:Send("NORGANNON_INDEX_READY")
  end
  return slots
end

---Builds the name index for one kind, or for every kind (each is built the first time it's asked for anyway).
function DBX:EnsureIndex(kind)
  if kind then
    kindIndex(kind)
    return
  end
  for _, k in ipairs(KINDS) do kindIndex(k) end
end

---How the name index stands, for /norg mem: { [kind] = slots or false (not built) }.
function DBX:IndexStats()
  local out = {}
  for _, kind in ipairs(KINDS) do out[kind] = index[kind] and #index[kind].lower or false end
  return out
end

-------------------------------------------------------------------------------------------
-- Search
-------------------------------------------------------------------------------------------

local SINGULAR = { quests = "quest", npcs = "npc", objects = "object", items = "item" }
DBX.SINGULAR = SINGULAR

-- match class: 0 exact, 1 prefix, 2 word prefix, 3 anywhere
local MATCH_CLASSES = 4
local function classify(lower, needle)
  local at = string.find(lower, needle, 1, true)
  if not at then return nil end
  if at == 1 then return #lower == #needle and 0 or 1 end
  local before = string.sub(lower, at - 1, at - 1)
  if before == " " or before == "-" or before == "'" or before == "(" then return 2 end
  return 3
end

-- A match while ranking is one number, kind * SLOT_RANGE + slot, so a query that matches most of
-- the database doesn't build a table per match.
local SLOT_RANGE = 100000

local function matchName(ref)
  return index[KINDS[math.floor(ref / SLOT_RANGE)]].lower[ref % SLOT_RANGE]
end

local function byMatchName(a, b) return matchName(a) < matchName(b) end

local lastSearch = nil   -- { needle, kindsKey, slots = { [kind] = {slot, ...} } }

-- Finds every match, bucketed by match class and then by name length (short names first).
-- candidatesOf[kind], when given, narrows the search to those slots.
local function collectMatches(needle, kinds, candidatesOf)
  local buckets = {}      -- [class + 1][length] = { ref, ... }
  for c = 1, MATCH_CLASSES do buckets[c] = {} end
  local slotsByKind, total = {}, 0
  for k, kind in ipairs(KINDS) do
    if not kinds or kinds[kind] then
      local lower = index[kind].lower
      local found = {}
      local candidates = candidatesOf and candidatesOf[kind]
      local count = candidates and #candidates or #lower
      for i = 1, count do
        local slot = candidates and candidates[i] or i
        local name = lower[slot]
        local class = classify(name, needle)
        if class then
          found[#found + 1] = slot
          local byLength = buckets[class + 1]
          local list = byLength[#name]
          if not list then
            list = {}
            byLength[#name] = list
          end
          list[#list + 1] = k * SLOT_RANGE + slot
          total = total + 1
        end
      end
      slotsByKind[kind] = found
    end
  end
  return buckets, slotsByKind, total
end

-- The first `limit` results in rank order. Only the buckets the limit reaches get sorted: a
-- one-letter query matches most of the database, so this keeps it linear.
local function takeRanked(buckets, limit)
  local results = {}
  for c = 1, MATCH_CLASSES do
    local byLength = buckets[c]
    local lengths = {}
    for length in pairs(byLength) do lengths[#lengths + 1] = length end
    table.sort(lengths)
    for _, length in ipairs(lengths) do
      if #results >= limit then break end
      local list = byLength[length]
      table.sort(list, byMatchName)
      for _, ref in ipairs(list) do
        if #results >= limit then break end
        local kind, slot = KINDS[math.floor(ref / SLOT_RANGE)], ref % SLOT_RANGE
        local slots = index[kind]
        results[#results + 1] = { kind = SINGULAR[kind], key = kind, name = displayName(kind, slots, slot),
          ids = idList(slots, slot), class = c - 1 }
      end
    end
  end
  return results
end

---Searches entity names. opts: kinds = { npcs = true, ... } (default all), limit (default 50).
---Returns a ranked list of { kind = "npc", key = "npcs", name, ids = {...}, class }, and the
---number of matches before the limit.
---Typing more of the same query only re-checks the previous matches.
function DBX:Search(text, opts)
  opts = opts or {}
  local needle = string.lower(strtrim(text or ""))
  if needle == "" then return {}, 0 end
  for _, kind in ipairs(KINDS) do
    if not opts.kinds or opts.kinds[kind] then kindIndex(kind) end
  end

  local kindsKey = ""
  for _, kind in ipairs(KINDS) do
    if not opts.kinds or opts.kinds[kind] then kindsKey = kindsKey .. kind end
  end
  local refine = lastSearch and lastSearch.kindsKey == kindsKey and #needle > #lastSearch.needle
    and string.sub(needle, 1, #lastSearch.needle) == lastSearch.needle

  local buckets, slotsByKind, total = collectMatches(needle, opts.kinds, refine and lastSearch.slots)
  lastSearch = { needle = needle, kindsKey = kindsKey, slots = slotsByKind }
  return takeRanked(buckets, opts.limit or 50), total
end

---Every id of an exact (case-insensitive, localized) name: DB:IdsByName("objects", "Peacebloom").
---For tooltips that only have a name. Returns an empty list when nothing matches.
function DBX:IdsByName(kind, name)
  if type(name) ~= "string" or Core.IsSecret(name) then return {} end
  if not SINGULAR[kind] then return {} end
  local slots = kindIndex(kind)
  local slot = slots.byLower[string.lower(name)]
  return slot and idList(slots, slot) or {}
end

-------------------------------------------------------------------------------------------
-- Relations (hidden quests are filtered out everywhere)
-------------------------------------------------------------------------------------------

local function visible(list)
  local out = {}
  for _, id in ipairs(list or {}) do
    if not DBX:IsQuestHidden(id) then out[#out + 1] = id end
  end
  return out
end

---Quests an NPC or object starts, ends and is an objective of: { starts, ends, objective }.
function DBX:QuestsFor(kind, id)
  local DB = db()
  local record = DB and DB:Get(kind, id)
  local objectiveOf = DB and DB.index and DB.index.objectiveOf and DB.index.objectiveOf[kind]
  return {
    starts = visible(record and record.questStarts),
    ends = visible(record and record.questEnds),
    objective = (objectiveOf and objectiveOf[id]) or {},
  }
end

---Where an item comes from and what it is for: { drops, vendors, rewardOf, startQuest, objective }.
function DBX:ItemInfo(id)
  local DB = db()
  local item = DB and DB:Get("items", id)
  if not item then return nil end
  local objectiveOf = DB.index and DB.index.objectiveOf and DB.index.objectiveOf.items
  return {
    drops = item.drops or {}, vendors = item.vendors or {}, rewardOf = visible(item.rewardOf),
    startQuest = item.startQuest and not DBX:IsQuestHidden(item.startQuest) and item.startQuest or nil,
    objective = (objectiveOf and objectiveOf[id]) or {},
  }
end

---What a zone holds: { npcs, objects, quests } (areaId, not UiMapID).
function DBX:Zone(areaId)
  local DB = db()
  local zones = DB and DB.index and DB.index.zones
  local z = zones and zones[areaId]
  return { npcs = z and z.npcs or {}, objects = z and z.objects or {}, quests = z and z.quests or {} }
end

---Quests that become available after this one (it is their prerequisite), and the next in its chain.
function DBX:Unlocks(questId)
  local DB = db()
  local unlocks = DB and DB.index and DB.index.unlocks
  local quest = DB and DB:Get("quests", questId)
  return (unlocks and unlocks[questId]) or {}, quest and quest.nextQuestInChain
end

-------------------------------------------------------------------------------------------
-- Instances (NorgannonDB 1.3): dungeons and raids, one record per wing
-------------------------------------------------------------------------------------------

local function instances()
  local DB = db()
  return DB and DB.instances or {}
end

---One instance by key ("deadmines", "sm-cathedral"), or nil.
function DBX:Instance(key) return instances()[key] end

-- the client's own (localized) name of an area, if it has one
local function clientAreaName(area)
  if not (C_Map and C_Map.GetAreaInfo) then return nil end
  local ok, name = pcall(C_Map.GetAreaInfo, area)
  if ok and type(name) == "string" and name ~= "" then return name end
end

---The instance's name in the client's language: "The Deadmines", "Scarlet Monastery: Cathedral".
function DBX:InstanceName(key)
  local inst = instances()[key]
  if not inst then return nil end
  local base = inst.name
  if inst.area then
    base = clientAreaName(inst.area) or base
    if not base then
      local DB = db()
      base = DB and DB.dungeons and DB.dungeons[inst.area] and DB.dungeons[inst.area].name
    end
  end
  base = inst.groupName or base or key
  if inst.wing then return base .. ": " .. inst.wing end
  return base
end

---Every instance key, ordered by recommended level, then name. filter(key, inst) may skip some.
function DBX:InstanceKeys(filter)
  local keys = {}
  for key, inst in pairs(instances()) do
    if not filter or filter(key, inst) then keys[#keys + 1] = key end
  end
  local all = instances()
  table.sort(keys, function(a, b)
    local la = all[a].levels and all[a].levels.min or 99
    local lb = all[b].levels and all[b].levels.min or 99
    if la ~= lb then return la < lb end
    return (self:InstanceName(a) or a) < (self:InstanceName(b) or b)
  end)
  return keys
end

---The instance keys for an area id (several for an instance with wings).
function DBX:InstancesAt(area)
  local out = {}
  for key, inst in pairs(instances()) do
    if inst.area == area then out[#out + 1] = key end
  end
  table.sort(out)
  return out
end

-------------------------------------------------------------------------------------------
-- Recipes (NorgannonDB 1.4): every crafting recipe, by its spell id
-------------------------------------------------------------------------------------------

local function recipes()
  local DB = db()
  return DB and DB.recipes or {}
end

-- one of NorgannonDB's recipe indexes ("craftedBy", "reagentOf", ...), at id
local function recipeIndexed(name, id)
  local DB = db()
  local indexes = DB and DB.index and DB.index.recipes
  return indexes and indexes[name] and indexes[name][id]
end

---One recipe by spell id, or nil.
function DBX:Recipe(id) return recipes()[id] end

---The recipe's name in the client's language (the spell's name), else NorgannonDB's.
function DBX:RecipeName(id)
  local spell = rawget(_G, "C_Spell")
  local getName = spell and spell.GetSpellName or rawget(_G, "GetSpellInfo")
  if getName then
    local ok, name = pcall(getName, id)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  local rec = recipes()[id]
  return rec and rec.name
end

---A profession's recipe ids (skill line id), by the skill they're learned at, then name.
function DBX:Recipes(skill)
  local all, out = recipes(), {}
  for id, rec in pairs(all) do
    if rec.skill == skill then out[#out + 1] = id end
  end
  table.sort(out, function(a, b)
    local la, lb = all[a].learn or 0, all[b].learn or 0
    if la ~= lb then return la < lb end
    return (all[a].name or "") < (all[b].name or "")
  end)
  return out
end

---The recipes that make an item, that use it, and the one a recipe item teaches.
function DBX:CraftedBy(itemId) return recipeIndexed("craftedBy", itemId) or {} end
function DBX:ReagentOf(itemId) return recipeIndexed("reagentOf", itemId) or {} end
function DBX:RecipeTaughtBy(itemId) return recipeIndexed("taughtBy", itemId) end

---What disenchants into a material: { min, max = item levels, quality = {2, 3, 4} }, or nil.
function DBX:DisenchantedFrom(itemId) return recipeIndexed("disenchant", itemId) end

---A recipe's colour at a skill: "red" (can't learn it yet), "orange", "yellow", "green" or
---"grey" (no more skill-ups); nil without a skill.
function DBX.RecipeColor(rec, skill)
  if not (rec and skill) then return nil end
  local levels = rec.levels   -- the skill each colour starts at: orange, yellow, green, grey
  if skill < (rec.learn or levels[1]) then return "red" end
  if skill < levels[2] then return "orange" end
  if skill < levels[3] then return "yellow" end
  if skill < levels[4] then return "green" end
  return "grey"
end
