-- Player state: one event-driven model of the quest log, completed quests, professions, level
-- and position, so suite addons never each scan the quest log. Bursts of quest events are
-- coalesced into one scan on the next frame, and the scan's differences go out as messages:
--
--   NORGANNON_QUEST_ACCEPTED (questId)          NORGANNON_QUEST_REMOVED (questId, turnedIn)
--   NORGANNON_QUEST_PROGRESS (questId, index)   NORGANNON_QUEST_COMPLETE (questId)
--   NORGANNON_QUEST_TURNED_IN (questId)         NORGANNON_QUESTLOG_UPDATED (changes)
--   NORGANNON_SKILLS_CHANGED                    NORGANNON_LEVEL_CHANGED (level)
--
-- Uses the APIs the WoW Forever client has (C_QuestLog with quest IDs, counter-first objective
-- text, QUEST_ACCEPTED with only the quest ID). Secret values are skipped, never compared.

local Core = NorgannonCore
local Player = { quests = {}, completed = {}, skills = {}, level = 1 }
Core.Player = Player

local IsSecret = Core.IsSecret

local function public(t)
  return type(t) == "table" and not IsSecret(t)
end

-------------------------------------------------------------------------------------------
-- Objective text: "3/10 Mottled Boar slain" (Forever) or "Mottled Boar slain: 3/10" (Classic)
-------------------------------------------------------------------------------------------

-- a client format string ("%s slain: %d/%d", "%1$s: %2$d/%3$d") as a Lua pattern
local patterns = {}
local function formatPattern(format)
  if type(format) ~= "string" then return nil end
  local p = patterns[format]
  if p then return p end
  -- placeholders first (positional "%1$s" before plain "%s"), then escape, then captures
  p = format:gsub("%%%d+%$s", "\001"):gsub("%%%d+%$d", "\002"):gsub("%%s", "\001"):gsub("%%d", "\002")
  p = p:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
  patterns[format] = p
  return p
end

local TYPE_FORMATS = { monster = "QUEST_MONSTERS_KILLED", item = "QUEST_ITEMS_NEEDED", object = "QUEST_OBJECTS_FOUND" }

---The subject of an objective ("Mottled Boar") from its text, in either layout.
function Player.ObjectiveName(text, objectiveType)
  if type(text) ~= "string" or IsSecret(text) then return nil end
  local global = TYPE_FORMATS[objectiveType] and _G[TYPE_FORMATS[objectiveType]]
  local pattern = formatPattern(global)
  if pattern then
    local a, b, c = string.match(text, "^" .. pattern .. "$")
    for _, capture in ipairs({ a, b, c }) do
      if capture and not tonumber(capture) then return strtrim(capture) end
    end
  end
  local name = string.match(text, "^(.-)%s*[:：]%s*%d+%s*/%s*%d+$") or string.match(text, "^%d+%s*/%s*%d+%s+(.+)$")
  return strtrim(name or text)
end

-------------------------------------------------------------------------------------------
-- Quest log scan
-------------------------------------------------------------------------------------------

local function readObjectives(questId)
  local list = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(questId)
  local out = {}
  if not public(list) then return out end
  for i, o in ipairs(list) do
    if public(o) then
      local text = not IsSecret(o.text) and o.text or nil
      local current, required = o.numFulfilled, o.numRequired
      if IsSecret(current) or IsSecret(required) then current, required = nil, nil end
      out[i] = {
        text = text, type = not IsSecret(o.type) and o.type or nil,
        finished = not IsSecret(o.finished) and o.finished or false,
        current = current, required = required,
        name = text and Player.ObjectiveName(text, o.type),
      }
    else
      out[i] = { finished = false }
    end
  end
  return out
end

local function scan()
  local quests = {}
  if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return quests end
  for index = 1, C_QuestLog.GetNumQuestLogEntries() do
    local info = C_QuestLog.GetInfo(index)
    if public(info) and not info.isHeader and info.questID and not IsSecret(info.questID) then
      local id = info.questID
      local complete = false
      if C_QuestLog.IsFailed and C_QuestLog.IsFailed(id) then
        complete = "failed"
      elseif C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) then
        complete = true
      end
      quests[id] = {
        id = id, title = info.title, level = info.level, logIndex = index,
        complete = complete, objectives = readObjectives(id),
      }
    end
  end
  return quests
end

local function sameObjective(a, b)
  return a and b and a.current == b.current and a.finished == b.finished and a.text == b.text
end

---Rescans the quest log now and announces the differences.
function Player:Refresh()
  local old, new = self.quests, scan()
  self.quests = new
  local changes = { accepted = {}, removed = {}, progressed = {}, completed = {} }

  for id, q in pairs(new) do
    local before = old[id]
    if not before then
      table.insert(changes.accepted, id)
      Core:Send("NORGANNON_QUEST_ACCEPTED", id)
    else
      for i, o in ipairs(q.objectives) do
        if not sameObjective(o, before.objectives[i]) then
          table.insert(changes.progressed, id)
          Core:Send("NORGANNON_QUEST_PROGRESS", id, i)
        end
      end
      if q.complete == true and before.complete ~= true then
        table.insert(changes.completed, id)
        Core:Send("NORGANNON_QUEST_COMPLETE", id)
      end
    end
  end
  for id in pairs(old) do
    if not new[id] then
      local turnedIn = self.completed[id] == true
      table.insert(changes.removed, id)
      Core:Send("NORGANNON_QUEST_REMOVED", id, turnedIn)
    end
  end
  if #changes.accepted + #changes.removed + #changes.progressed + #changes.completed > 0 then
    Core:Send("NORGANNON_QUESTLOG_UPDATED", changes)
  end
  return changes
end

local function queueRefresh()
  Core:NextFrame(function() Player:Refresh() end, "questlog")
end

---The quest log entry for a quest, or nil if it isn't in the log.
function Player:GetQuest(id) return self.quests[id] end
function Player:HasQuest(id) return self.quests[id] ~= nil end

---Quest IDs in the log, in quest log order.
function Player:QuestIds()
  local ids = {}
  for id in pairs(self.quests) do ids[#ids + 1] = id end
  table.sort(ids, function(a, b) return self.quests[a].logIndex < self.quests[b].logIndex end)
  return ids
end

function Player:IsCompleted(id) return self.completed[id] == true end

-------------------------------------------------------------------------------------------
-- Completed quests
-------------------------------------------------------------------------------------------

local function loadCompleted()
  local completed = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local list = C_QuestLog.GetAllCompletedQuestIDs()
    if public(list) then
      for _, id in ipairs(list) do completed[id] = true end
    end
  end
  Player.completed = completed
end

-------------------------------------------------------------------------------------------
-- Professions: { [skillLineId] = rank }
-------------------------------------------------------------------------------------------

local function readSkills()
  local skills = {}
  if GetProfessions and GetProfessionInfo then
    for _, index in pairs({ GetProfessions() }) do
      local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
      if skillLine and rank and not IsSecret(rank) then skills[skillLine] = rank end
    end
  end
  if GetNumSkillLines and GetSkillLineInfo then
    -- older API: match localized names against NorgannonDB's profession table
    local byName = {}
    local DB = NorgannonDB
    for id in pairs(DB and DB.professions or {}) do
      local name = DB:L("professions", id, "name")
      if name then byName[name] = id end
    end
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank = GetSkillLineInfo(i)
      if not isHeader and name and byName[name] and rank then skills[byName[name]] = rank end
    end
  end
  return skills
end

local function refreshSkills()
  local new, changed = readSkills(), false
  for id, rank in pairs(new) do if Player.skills[id] ~= rank then changed = true end end
  for id in pairs(Player.skills) do if not new[id] then changed = true end end
  Player.skills = new
  if changed then Core:Send("NORGANNON_SKILLS_CHANGED") end
end

---Rank in a profession (skill line id), or nil if the player doesn't have it.
function Player:GetSkill(id) return self.skills[id] end

-------------------------------------------------------------------------------------------
-- Character and position
-------------------------------------------------------------------------------------------

local function readCharacter()
  Player.level = UnitLevel("player") or Player.level
  local _, classToken = UnitClass("player")
  local _, raceToken = UnitRace("player")
  Player.class, Player.race = classToken, raceToken
  Player.faction = UnitFactionGroup("player")
end

---uiMapID, x, y (0-1) and areaId of the player; nil when unknown (instances, secret values).
function Player:GetPosition()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local uiMapID = C_Map.GetBestMapForUnit("player")
  if not uiMapID or IsSecret(uiMapID) then return nil end
  local position = C_Map.GetPlayerMapPosition(uiMapID, "player")
  if not position or IsSecret(position) then return uiMapID end
  local x, y = position:GetXY()
  if not x or IsSecret(x) or IsSecret(y) or x <= 0 or y <= 0 or x > 1 or y > 1 then return uiMapID end
  local maps = NorgannonDB and NorgannonDB.maps
  return uiMapID, x, y, maps and maps.uiMapToArea and maps.uiMapToArea[uiMapID]
end

-------------------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------------------

Core:OnLogin(function()
  readCharacter()
  loadCompleted()
  Player.skills = readSkills()
  Player.quests = scan()
  Player.ready = true
  Core:Send("NORGANNON_PLAYER_READY")
end)

for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED" }) do
  Core:On(event, "player", queueRefresh)
end
Core:On("UNIT_QUEST_LOG_CHANGED", "player", function(_, unit)
  if unit == "player" then queueRefresh() end
end)
Core:On("QUEST_TURNED_IN", "player", function(_, questId)
  if questId and not IsSecret(questId) then
    Player.completed[questId] = true
    Core:Send("NORGANNON_QUEST_TURNED_IN", questId)
  end
  queueRefresh()
end)
Core:On("PLAYER_LEVEL_UP", "player", function(_, level)
  if level and not IsSecret(level) then Player.level = level end
  Core:Send("NORGANNON_LEVEL_CHANGED", Player.level)
end)
for _, event in ipairs({ "SKILL_LINES_CHANGED", "TRADE_SKILL_UPDATE", "CHAT_MSG_SKILL" }) do
  Core:On(event, "player", function() Core:NextFrame(refreshSkills, "skills") end)
end
