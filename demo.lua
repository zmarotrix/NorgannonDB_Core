-- /norg demo: a preview of the map layer, minimap, compass and arrow with your real quest log,
-- built from NorgannonDB. It is a test bench for the Core, not a quest helper: Clairvoyance owns
-- quest pins, availability rules and settings.

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

local MAX_SOURCES = 4   -- an item objective shows its most likely droppers only

-- one pin per spawn of an NPC or object; spec holds what they share
local function addSpawns(pins, kind, id, spec)
  local record = NorgannonDB:Get(kind, id)
  if not record then return end
  local name = NorgannonDB.L and NorgannonDB:L(kind, id, "name") or record.name
  for area, points in pairs(record.spawns or {}) do
    for _, p in ipairs(points) do
      pins[#pins + 1] = {
        area = area, x = p[1], y = p[2], icon = spec.icon or "pin", color = spec.color, layer = spec.layer or 3,
        cluster = spec.group, compass = spec.compass and spec.group or nil, size = spec.size, quest = spec.quest,
        title = name, tooltip = spec.tooltip,
      }
    end
  end
end

-- the database objective behind the game's objective i (objectives.order maps them)
local function objectiveEntry(q, i)
  local objectives = q.objectives or {}
  local order = objectives.order
  if order and order[i] then
    local kind, n = order[i][1], order[i][2]
    return kind, objectives[kind] and objectives[kind][n]
  end
  local flat = {}
  for _, kind in ipairs({ "npcs", "objects", "items" }) do
    for _, entry in ipairs(objectives[kind] or {}) do flat[#flat + 1] = { kind, entry } end
  end
  if flat[i] then return flat[i][1], flat[i][2] end
end

-- color: a colour, or a quest id (its current colour, read when the tooltip opens)
local function tooltipFor(questTitle, color, line)
  return function(pin, tt)
    local c = type(color) == "number" and Core.Colors:ForQuest(color) or color
    tt:AddLine(questTitle, c[1], c[2], c[3])
    if line then tt:AddLine(line, 1, 1, 1) end
    if pin.title then tt:AddLine(pin.title, C.muted[1], C.muted[2], C.muted[3]) end
  end
end

-- an item objective: pins on the most likely sources of the item
local function addItemSources(pins, itemId, spec)
  local info = Core.DB:ItemInfo(itemId)
  local sources = {}
  for npc, chance in pairs(info and info.drops.npcs or {}) do sources[#sources + 1] = { "npcs", npc, chance } end
  for obj, chance in pairs(info and info.drops.objects or {}) do sources[#sources + 1] = { "objects", obj, chance } end
  table.sort(sources, function(a, b) return (a[3] or 0) > (b[3] or 0) end)
  for s = 1, math.min(MAX_SOURCES, #sources) do addSpawns(pins, sources[s][1], sources[s][2], spec) end
end

local function addObjectivePins(pins, id, q, entry)
  for index, o in ipairs(entry.objectives) do
    if not o.finished then
      local kind, objective = objectiveEntry(q, index)
      local spec = { quest = id, group = "q" .. id .. ":" .. index, compass = true,
        tooltip = tooltipFor(entry.title or q.name, id, o.text) }
      if objective and (kind == "npcs" or kind == "objects") then
        addSpawns(pins, kind, objective.id, spec)
      elseif objective and kind == "items" then
        addItemSources(pins, objective.id, spec)
      end
    end
  end
end

-- turn-in: gold "?" when complete (on the compass), grey while objectives remain
local function addTurnInPins(pins, id, q, entry)
  local complete = entry.complete == true
  for _, npc in ipairs(q.finishers and q.finishers.npcs or {}) do
    addSpawns(pins, "npcs", npc, { icon = complete and "question" or "questionGrey", layer = 5, size = 16,
      group = "end" .. id, compass = complete, quest = id,
      tooltip = tooltipFor(entry.title or q.name, id, complete and "Ready to turn in" or "Turn in here when done") })
  end
end

local function questPins(pins)
  local Player = Core.Player
  for _, id in ipairs(Player:QuestIds()) do
    local entry = Player:GetQuest(id)
    local q = NorgannonDB:Get("quests", id)
    if q and entry then
      addObjectivePins(pins, id, q, entry)
      addTurnInPins(pins, id, q, entry)
    end
  end
end

local function prerequisitesDone(pre)
  local Player = Core.Player
  for _, id in ipairs(pre.all or {}) do
    if not Player:IsCompleted(id) then return false end
  end
  if pre.any and #pre.any > 0 then
    for _, id in ipairs(pre.any) do
      if Player:IsCompleted(id) then return true end
    end
    return false
  end
  return true
end

-- a quick availability check for quests that start in the player's zone (Clairvoyance does this
-- properly: exclusivity, breadcrumbs, reputation, skills, events)
local function availablePins(pins, area)
  local Player, DB = Core.Player, NorgannonDB
  local level = Player.level or 1
  local _, _, raceId = UnitRace("player")
  local raceMask = DB.enums and DB.enums.raceMaskById and DB.enums.raceMaskById[raceId]
  local classMask = DB.enums and DB.enums.classKeys and DB.enums.classKeys[Player.class or ""]
  for _, id in ipairs(Core.DB:Zone(area).quests) do
    if not Player:IsCompleted(id) and not Player:HasQuest(id) then
      local q = DB:Get("quests", id)
      local available = q and q.hidden == nil and (q.minLevel or 1) <= level
        and (not raceMask or DB.HasFlag(q.races, raceMask)) and (not classMask or DB.HasFlag(q.classes, classMask))
        and (not q.prerequisites or prerequisitesDone(q.prerequisites))
      if available then
        local qlevel = q.level or 0
        local trivial = UI.Difficulty(qlevel > 0 and qlevel or level, level) == C.trivial
        for _, npc in ipairs(q.starters and q.starters.npcs or {}) do
          addSpawns(pins, "npcs", npc, { icon = trivial and "exclaimGrey" or "exclaim", layer = 4, size = 16,
            tooltip = tooltipFor(q.name, C.gold, string.format("Level %s quest", qlevel > 0 and qlevel or "?")) })
        end
      end
    end
  end
end

local function build()
  local pins = {}
  questPins(pins)
  local _, _, _, area = Core.Player:GetPosition()
  if area then availablePins(pins, area) end
  Core.Map:SetPins("demo", pins)
  return #pins
end

function Core:Demo(on)
  if on == false then
    Core.Map:ClearPins("demo")
    Core:Unlisten("NORGANNON_QUESTLOG_UPDATED", "demo")
    self.demoOn = nil
    return 0
  end
  self.demoOn = true
  Core:Listen("NORGANNON_QUESTLOG_UPDATED", "demo", function() if Core.demoOn then build() end end)
  return build()
end
