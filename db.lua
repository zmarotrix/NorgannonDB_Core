-- NorgannonDB for the suite: name search over every quest, NPC, object and item, and the
-- relation indexes (SPEC 1.2 `index`). Addons ask here instead of scanning the database.
--
--   local results = Core.DB:Search("peacebloom", { kinds = { objects = true, items = true } })
--   for _, r in ipairs(results) do print(r.kind, r.name, #r.ids) end

local Core = NorgannonCore
local DBX = {}
Core.DB = DBX

local KINDS = { "quests", "npcs", "objects", "items" }
DBX.KINDS = KINDS

local BUILD_BUDGET_MS = 4      -- per frame while the name index builds in the background
local CHUNK = 400              -- records between budget checks

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
-- so a search for "Peacebloom" tracks every Peacebloom node at once
-------------------------------------------------------------------------------------------

local index = nil         -- [kind] = { lower = {}, display = {}, ids = {} }
local building = nil      -- coroutine while the index builds
DBX.indexReady = false

local function buildIndex(yield)
  local DB = db()
  local result = {}
  for _, kind in ipairs(KINDS) do
    local slots = { lower = {}, display = {}, ids = {} }
    local byLower = {}
    local n = 0
    for id in pairs(DB and DB[kind] or {}) do
      if not (kind == "quests" and DBX:IsQuestHidden(id)) then
        local name = DBX:Name(kind, id)
        if type(name) == "string" and name ~= "" then
          local lower = string.lower(name)
          local slot = byLower[lower]
          if slot then
            table.insert(slots.ids[slot], id)
          else
            slot = #slots.lower + 1
            byLower[lower] = slot
            slots.lower[slot], slots.display[slot], slots.ids[slot] = lower, name, { id }
          end
        end
      end
      n = n + 1
      if yield and n % CHUNK == 0 then yield() end
    end
    for _, ids in ipairs(slots.ids) do table.sort(ids) end
    slots.byLower = byLower
    result[kind] = slots
  end
  return result
end

local function finish(result)
  index = result
  building = nil
  DBX.indexReady = true
  Core:Send("NORGANNON_INDEX_READY")
end

---Builds the name index now (if a search needs it before the background build is done).
function DBX:EnsureIndex()
  if index then return end
  finish(buildIndex(nil))
end

-- Background build after login: a few milliseconds per frame, never a hitch.
local function step()
  if not building then return end
  local start = debugprofilestop()
  while building and debugprofilestop() - start < BUILD_BUDGET_MS do
    local ok, result = coroutine.resume(building)
    if not ok then
      building = nil
      Core:Debug("db", "name index failed: %s", tostring(result))
      return
    end
    if coroutine.status(building) == "dead" then
      finish(result)
      return
    end
  end
  C_Timer.After(0, step)
end

Core:OnLogin(function()
  if index or building then return end
  building = coroutine.create(function() return buildIndex(coroutine.yield) end)
  C_Timer.After(1, step)
end)

-------------------------------------------------------------------------------------------
-- Search
-------------------------------------------------------------------------------------------

local SINGULAR = { quests = "quest", npcs = "npc", objects = "object", items = "item" }
DBX.SINGULAR = SINGULAR

-- match class: 0 exact, 1 prefix, 2 word prefix, 3 anywhere
local function classify(lower, needle)
  local at = string.find(lower, needle, 1, true)
  if not at then return nil end
  if at == 1 then return #lower == #needle and 0 or 1 end
  local before = string.sub(lower, at - 1, at - 1)
  if before == " " or before == "-" or before == "'" or before == "(" then return 2 end
  return 3
end

local last = nil   -- { needle, kindsKey, slots = { [kind] = {slot, ...} } }

---Searches entity names. opts: kinds = { npcs = true, ... } (default all), limit (default 50).
---Returns a ranked list of { kind = "npc", key = "npcs", name, ids = {...}, class }.
---Typing more of the same query only re-checks the previous matches.
function DBX:Search(text, opts)
  opts = opts or {}
  local needle = string.lower(strtrim(text or ""))
  if needle == "" then return {} end
  self:EnsureIndex()
  local limit = opts.limit or 50

  local kindsKey = ""
  for _, kind in ipairs(KINDS) do
    if not opts.kinds or opts.kinds[kind] then kindsKey = kindsKey .. kind end
  end
  local refine = last and last.kindsKey == kindsKey and #needle > #last.needle
    and string.sub(needle, 1, #last.needle) == last.needle

  -- Rank without sorting every match: bucket by match class, then by name length (short
  -- names first), and sort only the buckets the limit reaches. A one-letter query matches
  -- most of the database, so this keeps it linear.
  local buckets = { {}, {}, {}, {} }      -- [class + 1][length] = { ref, ... }
  local slotsByKind, total = {}, 0
  for k, kind in ipairs(KINDS) do
    if not opts.kinds or opts.kinds[kind] then
      local lower = index[kind].lower
      local found = {}
      local candidates = refine and last.slots[kind]
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
          list[#list + 1] = k * 100000 + slot   -- kind and slot in one number
          total = total + 1
        end
      end
      slotsByKind[kind] = found
    end
  end
  last = { needle = needle, kindsKey = kindsKey, slots = slotsByKind }

  local results = {}
  local function nameOf(ref) return index[KINDS[math.floor(ref / 100000)]].lower[ref % 100000] end
  local function byName(a, b) return nameOf(a) < nameOf(b) end
  for c = 1, 4 do
    local byLength = buckets[c]
    local lengths = {}
    for length in pairs(byLength) do lengths[#lengths + 1] = length end
    table.sort(lengths)
    for _, length in ipairs(lengths) do
      if #results >= limit then break end
      local list = byLength[length]
      table.sort(list, byName)
      for _, ref in ipairs(list) do
        if #results >= limit then break end
        local kind, slot = KINDS[math.floor(ref / 100000)], ref % 100000
        local slots = index[kind]
        results[#results + 1] = { kind = SINGULAR[kind], key = kind, name = slots.display[slot], ids = slots.ids[slot], class = c - 1 }
      end
    end
  end
  return results, total
end

---Every id of an exact (case-insensitive, localized) name: DB:IdsByName("objects", "Peacebloom").
---For tooltips that only have a name. Returns an empty list when nothing matches.
function DBX:IdsByName(kind, name)
  if type(name) ~= "string" or Core.IsSecret(name) then return {} end
  self:EnsureIndex()
  local slots = index[kind]
  local slot = slots and slots.byLower[string.lower(name)]
  return slot and slots.ids[slot] or {}
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

---The instance's name in the client's language: "The Deadmines", "Scarlet Monastery: Cathedral".
function DBX:InstanceName(key)
  local inst = instances()[key]
  if not inst then return nil end
  local base = inst.name
  if inst.area then
    local area = inst.area
    if C_Map and C_Map.GetAreaInfo then
      local ok, name = pcall(C_Map.GetAreaInfo, area)
      if ok and type(name) == "string" and name ~= "" then base = name end
    end
    if not base then
      local DB = db()
      base = DB and DB.dungeons and DB.dungeons[area] and DB.dungeons[area].name
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
