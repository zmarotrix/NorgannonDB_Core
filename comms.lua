-- Party quest progress, wire-compatible with Questie's "questie" addon channel, so suite users
-- and Questie users in one group see each other's progress. Suite-wide: Clairvoyance shows it in
-- the tracker and tooltips; any suite addon can read it.
--
-- The protocol is QuestieComms message version 5: AceComm transport, Questie's binary serializer
-- (questie_serializer.lua) and these packets:
--   1  quest update     { quest = { id, objectives = { [i] = { id, typ, fin, ful, req } } } }
--   2  quest removed    { id }
--  10  full quest list  { rawQuestList = { [questId] = <quest update quest> } }
--  11  request lists    (answered with 12, whispered)
--  12  full list v2     { [1] = { count, questId, n, (id, typeByte, ful, req) x n, ... } }
--  14  quest update v2  { [1] = { questId, n, (id, typeByte, ful, req) x n } }
--
-- API: Comms:GetParty(questId) -> { [player] = { [i] = { id, type, fulfilled, required, finished } } }
--      Comms:ProgressFor(kind, id) -> { {questId, player, index, objective}, ... }  (kind: "npcs", "objects", "items")
-- Messages: NORGANNON_PARTY_UPDATED (questId, player), NORGANNON_PARTY_CLEARED

local Core = NorgannonCore
local AceComm = LibStub("AceComm-3.0")

local floor, byte, char = math.floor, string.byte, string.char
local pairs, ipairs, type = pairs, ipairs, type

local PREFIX = "questie"
local MSG_VERSION = 5
-- Questie compares this numeric version with its own to suggest updates, and answers peers
-- above major 5 with the compact v2 list. A plain numeric version avoids both pitfalls.
local PROTOCOL_VERSION = "6.0.0"
local MAX_GROUP = 15           -- larger groups (raids, battlegrounds) would flood the channel
local FLUSH_DELAY = 1          -- seconds: progress changes are coalesced into one update per quest
local SHARE_DELAY = 3          -- seconds after joining before quest logs go out
local MAX_BLOCK_BYTES = 200    -- a full-list block must fit one addon message

local MSG = { UPDATE = 1, REMOVE = 2, FULL = 10, REQUEST = 11, FULL_V2 = 12, UPDATE_V2 = 14 }

local Comms = { remote = {}, pending = {} }
Core.Comms = Comms
AceComm:Embed(Comms)

Comms.Serialize = Core.QuestieSerializer.Serialize
Comms.Deserialize = Core.QuestieSerializer.Deserialize

-------------------------------------------------------------------------------------------
-- Our progress, from Core.Player and NorgannonDB
-------------------------------------------------------------------------------------------

-- Questie names an objective by the entity behind it (NPC, object, item, faction), in the
-- client's objective order; NorgannonDB's objectives.order reproduces that order.
local function objectiveEntity(quest, index)
  local o = quest and quest.objectives
  if not o then return nil end
  local slot = o.order and o.order[index]
  local kind, n
  if slot then
    kind, n = slot[1], slot[2]
  else
    for _, k in ipairs({ "npcs", "objects", "items", "killCredit", "spells" }) do
      if o[k] and o[k][1] then kind, n = k, 1 break end
    end
    if not kind and o.reputation then kind, n = "reputation", 1 end
  end
  if kind == "reputation" then return o.reputation[1] end
  local entry = kind and o[kind] and o[kind][n]
  return entry and (entry.id or entry.credit) or nil
end

local function localObjectives(questId)
  local entry = Core.Player:GetQuest(questId)
  if not entry then return nil end
  local quest = NorgannonDB and NorgannonDB:Get("quests", questId)
  local objectives = {}
  for i, o in ipairs(entry.objectives) do
    if o.type then
      objectives[i] = {
        id = objectiveEntity(quest, i),
        typ = string.sub(o.type, 1, 1),
        fin = o.finished and true or false,
        ful = o.current or (o.finished and 1 or 0),
        req = o.required or 1,
      }
    end
  end
  return objectives
end

local function groupChannel()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

local function packet(id)
  return { ver = PROTOCOL_VERSION, msgVer = MSG_VERSION, msgId = id }
end

function Comms:Send(p, distribution, target, priority)
  if not distribution then return end
  local crowd = GetNumGroupMembers() > MAX_GROUP or (UnitInBattleground and UnitInBattleground("player"))
  if distribution ~= "WHISPER" and crowd then return end
  local ok, message = pcall(Comms.Serialize, p)
  if ok and message then self:SendCommMessage(PREFIX, message, distribution, target, priority or "NORMAL") end
end

function Comms:SendQuestUpdate(questId)
  local channel = groupChannel()
  local objectives = channel and localObjectives(questId)
  if objectives then
    local p = packet(MSG.UPDATE)
    p.quest = { id = questId, objectives = objectives }
    self:Send(p, channel)
  end
end

function Comms:SendQuestRemove(questId)
  local channel = groupChannel()
  if channel then
    local p = packet(MSG.REMOVE)
    p.id = questId
    self:Send(p, channel, nil, "ALERT")
  end
end

-- Stands in for an objective we can't read (secret type): the v2 layout is positional, so a gap
-- would misplace every objective after it, and the peer would misread the rest of the block.
local UNREADABLE_OBJECTIVE = { typ = "o", ful = 0, req = 1 }

-- one quest in the v2 flat layout: questId, n, (id, typeByte, fulfilled, required) x n
local function flatQuest(questId)
  local objectives = localObjectives(questId)
  if not (objectives and next(objectives)) then return nil end
  local count = #Core.Player:GetQuest(questId).objectives
  local entry = { questId, count }
  for i = 1, count do
    local o = objectives[i] or UNREADABLE_OBJECTIVE
    entry[#entry + 1] = o.id or 0
    entry[#entry + 1] = byte(o.typ)
    entry[#entry + 1] = o.ful
    entry[#entry + 1] = o.req
  end
  return entry
end

local function append(list, values)
  for _, v in ipairs(values) do list[#list + 1] = v end
end

-- The whole quest log as v2 blocks, each small enough for one addon message. A block is
-- { questCount, flatQuest..., flatQuest... }; a quest that would overflow starts the next one.
function Comms:SendQuestLog(distribution, target)
  distribution = distribution or groupChannel()
  if not distribution then return end
  local blocks, block, count = {}, { 0 }, 0
  for _, questId in ipairs(Core.Player:QuestIds()) do
    local entry = flatQuest(questId)
    if entry then
      local candidate = {}
      append(candidate, block)
      append(candidate, entry)
      candidate[1] = count + 1
      if count > 0 and #Comms.Serialize(candidate) > MAX_BLOCK_BYTES then
        blocks[#blocks + 1] = block
        block, count = { 1 }, 1
        append(block, entry)
      else
        block, count = candidate, count + 1
      end
    end
  end
  if count > 0 then blocks[#blocks + 1] = block end
  for _, b in ipairs(blocks) do
    local p = packet(MSG.FULL_V2)
    p[1] = b
    self:Send(p, distribution, target, distribution == "WHISPER" and "NORMAL" or "BULK")
  end
end

function Comms:RequestQuestLogs()
  local channel = groupChannel()
  if channel then self:Send(packet(MSG.REQUEST), channel) end
end

-------------------------------------------------------------------------------------------
-- Their progress
-------------------------------------------------------------------------------------------

local function isGroupMember(player)
  return UnitInParty(player) or UnitInRaid(player)
end

local function store(questId, player, objectives)
  Comms.remote[questId] = Comms.remote[questId] or {}
  Comms.remote[questId][player] = objectives
  Core:Send("NORGANNON_PARTY_UPDATED", questId, player)
end

local function forget(questId, player)
  if Comms.remote[questId] then
    Comms.remote[questId][player] = nil
    if not next(Comms.remote[questId]) then Comms.remote[questId] = nil end
    Core:Send("NORGANNON_PARTY_UPDATED", questId, player)
  end
end

-- v2 flat layout: questId, count, (id, typeByte, fulfilled, required) x count
local function readV2(list, offset, player)
  local questId, count = list[offset], list[offset + 1]
  if not questId or not count then return nil end
  offset = offset + 2
  local objectives = {}
  for i = 1, count do
    local id, typ, ful, req = list[offset], list[offset + 1], list[offset + 2], list[offset + 3]
    if not typ then break end
    objectives[i] = {
      id = id ~= 0 and id or nil, type = char(typ), fulfilled = ful, required = req, finished = ful == req,
    }
    offset = offset + 4
  end
  store(questId, player, objectives)
  return offset
end

local function readV1(quest, player)
  if type(quest) ~= "table" or not quest.id or type(quest.objectives) ~= "table" then return end
  local objectives = {}
  for index, o in pairs(quest.objectives) do
    objectives[index] = { id = o.id, type = o.typ, fulfilled = o.ful, required = o.req, finished = o.fin }
  end
  store(quest.id, player, objectives)
end

local handlers = {
  [MSG.UPDATE] = function(p, player) readV1(p.quest, player) end,
  [MSG.REMOVE] = function(p, player)
    if p.id then forget(p.id, player) end
  end,
  [MSG.FULL] = function(p, player)
    for _, quest in pairs(p.rawQuestList or {}) do readV1(quest, player) end
  end,
  [MSG.REQUEST] = function(_, player) Comms:SendQuestLog("WHISPER", player) end,
  [MSG.FULL_V2] = function(p, player)
    local list = p[1]
    if type(list) ~= "table" then return end
    local offset = 2
    for _ = 1, list[1] or 0 do
      offset = readV2(list, offset, player)
      if not offset then break end
    end
  end,
  [MSG.UPDATE_V2] = function(p, player)
    if type(p[1]) == "table" then readV2(p[1], 1, player) end
  end,
}

local function isSelf(sender)
  return sender == UnitName("player") or sender == GetUnitName("player", true)
end

local CHANNELS = { WHISPER = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

function Comms:OnCommReceived(prefix, message, distribution, sender)
  if prefix ~= PREFIX then return end
  if type(message) ~= "string" or Core.IsSecret(message) then return end
  if type(sender) ~= "string" or Core.IsSecret(sender) then return end
  if isSelf(sender) or not CHANNELS[distribution] then return end
  local p = Comms.Deserialize(message)
  if type(p) ~= "table" or type(p.msgVer) ~= "number" or floor(p.msgVer) ~= MSG_VERSION then return end
  local handler = handlers[p.msgId]
  if handler then pcall(handler, p, sender) end   -- whatever a peer sends must not raise an error here
end

Comms:RegisterComm(PREFIX, "OnCommReceived")

---Party members' progress on a quest: { [player] = { [index] = objective } } (only players in your group).
function Comms:GetParty(questId)
  local out = {}
  for player, objectives in pairs(self.remote[questId] or {}) do
    if isGroupMember(player) then out[player] = objectives end
  end
  return out
end

local TYPE_KIND = { m = "npcs", o = "objects", i = "items" }

-- true if an NPC or object drops the item (or, for an NPC, sells it)
local function itemComesFrom(itemId, kind, id)
  local info = Core.DB:ItemInfo(itemId)
  if not info then return false end
  local drops = info.drops
  if kind == "npcs" then return (drops.npcs and drops.npcs[id] or info.vendors[id]) and true or false end
  return (drops.objects and drops.objects[id]) and true or false
end

-- true if a party objective is about this entity
local function objectiveConcerns(o, kind, id)
  if not o.id then return false end
  local objectiveKind = TYPE_KIND[o.type]
  if objectiveKind == kind and o.id == id then return true end
  return objectiveKind == "items" and (kind == "npcs" or kind == "objects") and itemComesFrom(o.id, kind, id)
end

---Every party objective about an entity: { {questId, player, index, objective}, ... }.
---kind is "npcs", "objects" or "items"; an item objective also matches its droppers and vendors.
function Comms:ProgressFor(kind, id)
  local hits = {}
  for questId, players in pairs(self.remote) do
    for player, objectives in pairs(players) do
      if isGroupMember(player) then
        for index, o in pairs(objectives) do
          if objectiveConcerns(o, kind, id) then
            hits[#hits + 1] = { questId = questId, player = player, index = index, objective = o }
          end
        end
      end
    end
  end
  return hits
end

-------------------------------------------------------------------------------------------
-- Sharing: our changes go out coalesced; joining a group asks for and shares quest logs
-------------------------------------------------------------------------------------------

local function flush()
  Comms.flushing = nil
  for questId, kind in pairs(Comms.pending) do
    if kind == "remove" then
      Comms:SendQuestRemove(questId)
    else
      Comms:SendQuestUpdate(questId)
    end
  end
  Comms.pending = {}
end

local function changed(questId, removed)
  if type(questId) ~= "number" or not groupChannel() then return end
  Comms.pending[questId] = removed and "remove" or "update"
  if not Comms.flushing then
    Comms.flushing = true
    C_Timer.After(FLUSH_DELAY, flush)
  end
end

Core:Listen("NORGANNON_QUEST_ACCEPTED", "comms", function(_, id) changed(id) end)
Core:Listen("NORGANNON_QUEST_PROGRESS", "comms", function(_, id) changed(id) end)
Core:Listen("NORGANNON_QUEST_REMOVED", "comms", function(_, id) changed(id, true) end)

local members = 0
local function rosterChanged(event)
  if event == "GROUP_LEFT" then
    Comms.remote, members = {}, 0
    Core:Send("NORGANNON_PARTY_CLEARED")
    return
  end
  if not groupChannel() then return end
  local now = GetNumGroupMembers()
  if event == "GROUP_JOINED" or event == "PLAYER_ENTERING_WORLD" then
    C_Timer.After(SHARE_DELAY, function()
      Comms:RequestQuestLogs()
      Comms:SendQuestLog()
    end)
  elseif now > members then
    C_Timer.After(SHARE_DELAY, function() Comms:SendQuestLog() end)   -- someone joined: they need ours
  end
  members = now
  for questId, players in pairs(Comms.remote) do
    for player in pairs(players) do
      if not isGroupMember(player) then forget(questId, player) end
    end
  end
end
for _, event in ipairs({ "GROUP_JOINED", "GROUP_LEFT", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
  Core:On(event, "comms", rosterChanged)
end
