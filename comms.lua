-- Party quest progress, wire-compatible with Questie's "questie" addon channel, so suite users
-- and Questie users in one group see each other's progress. Suite-wide: Clairvoyance shows it in
-- the tracker and tooltips; any suite addon can read it.
--
-- The protocol is QuestieComms message version 5: AceComm transport, Questie's binary serializer
-- (the "1short" stream) and these packets:
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

local floor, byte, char, concat = math.floor, string.byte, string.char, table.concat
local pairs, ipairs, type = pairs, ipairs, type

local PREFIX = "questie"
local MSG_VERSION = 5
-- Questie compares this numeric version with its own to suggest updates, and answers peers
-- above major 5 with the compact v2 list. A plain numeric version avoids both pitfalls.
local PROTOCOL_VERSION = "6.0.0"
local MAX_GROUP = 15
local FLUSH_DELAY = 1          -- seconds: progress changes are coalesced into one update per quest

local MSG = { UPDATE = 1, REMOVE = 2, FULL = 10, REQUEST = 11, FULL_V2 = 12, UPDATE_V2 = 14 }

local Comms = { remote = {}, pending = {} }
Core.Comms = Comms
AceComm:Embed(Comms)

-------------------------------------------------------------------------------------------
-- Questie's serializer ("1short" stream: bytes 0, 237 and 238 are escaped)
-------------------------------------------------------------------------------------------

local CONTROL, ZERO = 237, 238
local out

local function wbyte(b)
  if b == 0 then
    out[#out + 1] = char(ZERO)
  elseif b == CONTROL then
    out[#out + 1] = char(CONTROL, 1)
  elseif b == ZERO then
    out[#out + 1] = char(CONTROL, 2)
  else
    out[#out + 1] = char(b)
  end
end

local function wshort(v) wbyte(floor(v / 256) % 256) wbyte(v % 256) end
local function wint(v)
  v = v % 4294967296
  wbyte(floor(v / 16777216) % 256) wbyte(floor(v / 65536) % 256) wbyte(floor(v / 256) % 256) wbyte(v % 256)
end
local function wlong(v)
  wint(floor(v / 4294967296))
  wint(v % 4294967296)
end

local function floatbits(n)
  local sign = 0
  if n < 0 then sign, n = 0x80, -n end
  local mant, expo = math.frexp(n)
  if mant ~= mant then return 0xFF880000 end
  if mant == math.huge or expo > 0x80 then return sign == 0 and 0x7F800000 or 0xFF800000 end
  if (mant == 0 and expo == 0) or expo < -0x7E then return sign * 16777216 end
  expo = expo + 0x7E
  mant = floor((mant * 2 - 1) * math.ldexp(0.5, 24))
  return (sign + floor(expo / 2)) * 16777216 + ((expo % 2) * 0x80 + floor(mant / 0x10000)) * 65536
    + (floor(mant / 0x100) % 0x100) * 256 + mant % 0x100
end

local function isarray(t, count)
  for i = 1, count do
    if t[i] == nil then return false end
  end
  return true
end

local write
write = function(v)
  local t = type(v)
  if t == "number" then
    if v % 1 ~= 0 then
      wbyte(6)
      wint(floatbits(v))
      return
    end
    local sign = 0
    if v < 0 then v, sign = -v, 1 end
    if v > 2147483646 then
      wbyte(4 + sign) wlong(v)
    elseif v < 222 and sign == 0 then
      wbyte(32 + v)
    elseif v < 255 then
      wbyte(12 + sign) wbyte(v)
    elseif v < 65530 then
      wbyte(14 + sign) wshort(v)
    else
      wbyte(2 + sign) wint(v)
    end
  elseif t == "string" then
    local len = #v
    if len > 254 then
      wbyte(8) wshort(len)
    else
      wbyte(7) wbyte(len)
    end
    for i = 1, len do wbyte(byte(v, i)) end
  elseif t == "boolean" then
    wbyte(v and 17 or 16)
  elseif t == "table" then
    local count = 0
    for _, inner in pairs(v) do
      if inner ~= nil then count = count + 1 end
    end
    if isarray(v, count) then
      if count > 65530 then
        wbyte(22) wint(count)
      elseif count > 254 then
        wbyte(21) wshort(count)
      else
        wbyte(20) wbyte(count)
      end
      for i = 1, count do write(v[i]) end
    else
      if count > 254 then
        wbyte(11) wshort(count)
      else
        wbyte(10) wbyte(count)
      end
      for key, inner in pairs(v) do
        write(key)
        write(inner)
      end
    end
  else
    wbyte(1)
  end
end

function Comms.Serialize(tab)
  out = {}
  write(1)   -- Questie wraps every payload as { [1] = payload }
  write(tab)
  local result = concat(out)
  out = nil
  return result
end

local data, pos, hashes

local function rbyte()
  local v = byte(data, pos)
  pos = pos + 1
  if not v then error("truncated message", 0) end
  if v == ZERO then return 0 end
  if v == CONTROL then
    local c = byte(data, pos)
    pos = pos + 1
    return c == 1 and CONTROL or ZERO
  end
  return v
end
local function rshort() return rbyte() * 256 + rbyte() end
local function rint() return rbyte() * 16777216 + rbyte() * 65536 + rbyte() * 256 + rbyte() end
local function rlong() return rint() * 4294967296 + rint() end

local function rstring(len)
  local chars = {}
  for i = 1, len do chars[i] = char(rbyte()) end
  return concat(chars)
end

local function bitsfloat(int)
  local b1, b2 = floor(int / 16777216) % 256, floor(int / 65536) % 256
  local b3, b4 = floor(int / 256) % 256, int % 256
  local sign = b1 > 0x7F and -1 or 1
  local expo = (b1 % 0x80) * 2 + floor(b2 / 0x80)
  local mant = ((b2 % 0x80) * 0x100 + b3) * 0x100 + b4
  if mant == 0 and expo == 0 then return 0 end
  if expo == 0xFF then return mant == 0 and sign * math.huge or 0 / 0 end
  return sign * math.ldexp(1 + mant / 0x800000, expo - 0x7F)
end

-- Questie references repeated strings (over 4 characters) by a djb2 hash of an earlier one
local function hash(s)
  local h = 5381
  for i = 1, #s do h = (31 * h + byte(s, i)) % 4294967296 end
  return h
end

local function remember(s)
  if type(s) == "string" then
    local h = hash(s)
    if hashes[h] == nil then hashes[h] = s end
  end
end

local read
local function rtable(count)
  local t = {}
  for _ = 1, count do
    local key = read()
    remember(key)
    local value = read()
    remember(value)
    if key ~= nil then t[key] = value end
  end
  return t
end

local function rarray(count)
  local t = {}
  for i = 1, count do
    local value = read()
    remember(value)
    t[i] = value
  end
  return t
end

local readers = {
  [1] = function() return nil end,
  [2] = function() return rint() end,
  [3] = function() return -rint() end,
  [4] = function() return rlong() end,
  [5] = function() return -rlong() end,
  [6] = function() return bitsfloat(rint()) end,
  [7] = function() return rstring(rbyte()) end,
  [8] = function() return rstring(rshort()) end,
  [9] = function() return hashes[rint()] end,
  [10] = function() return rtable(rbyte()) end,
  [11] = function() return rtable(rshort()) end,
  [12] = function() return rbyte() end,
  [13] = function() return -rbyte() end,
  [14] = function() return rshort() end,
  [15] = function() return -rshort() end,
  [16] = function() return false end,
  [17] = function() return true end,
  [18] = function() return nil end,
  [19] = function() return nil end,
  [20] = function() return rarray(rbyte()) end,
  [21] = function() return rarray(rshort()) end,
  [22] = function() return rarray(rint()) end,
}

read = function()
  local typ = rbyte()
  if typ > 31 then return typ - 32 end
  local reader = readers[typ]
  if not reader then error("unknown type " .. typ, 0) end
  return reader()
end

function Comms.Deserialize(message)
  data, pos, hashes = message, 1, {}
  local ok, result = pcall(rtable, 1)
  data, hashes = nil, nil
  return ok and result[1] or nil
end

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
Comms.LocalObjectives = localObjectives

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
  if distribution ~= "WHISPER" and (GetNumGroupMembers() > MAX_GROUP or (UnitInBattleground and UnitInBattleground("player"))) then
    return
  end
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

-- The whole quest log as v2 blocks, each small enough for one addon message.
function Comms:SendQuestLog(distribution, target)
  distribution = distribution or groupChannel()
  if not distribution then return end
  local blocks, block, count = {}, { 0 }, 0
  for _, questId in ipairs(Core.Player:QuestIds()) do
    local objectives = localObjectives(questId)
    if objectives and objectives[1] then
      local entry = { questId, #objectives }
      for _, o in ipairs(objectives) do
        entry[#entry + 1] = o.id or 0
        entry[#entry + 1] = byte(o.typ)
        entry[#entry + 1] = o.ful
        entry[#entry + 1] = o.req
      end
      local candidate = {}
      for i, v in ipairs(block) do candidate[i] = v end
      for _, v in ipairs(entry) do candidate[#candidate + 1] = v end
      candidate[1] = count + 1
      if count > 0 and #Comms.Serialize(candidate) > 200 then
        blocks[#blocks + 1] = block
        block, count = { 1 }, 1
        for _, v in ipairs(entry) do block[#block + 1] = v end
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
    objectives[i] = { id = id ~= 0 and id or nil, type = char(typ), fulfilled = ful, required = req, finished = ful == req }
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
  [MSG.REMOVE] = function(p, player) if p.id then forget(p.id, player) end end,
  [MSG.FULL] = function(p, player) for _, quest in pairs(p.rawQuestList or {}) do readV1(quest, player) end end,
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
  [MSG.UPDATE_V2] = function(p, player) if type(p[1]) == "table" then readV2(p[1], 1, player) end end,
}

local function isSelf(sender)
  return sender == UnitName("player") or sender == GetUnitName("player", true)
end

local CHANNELS = { WHISPER = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

function Comms:OnCommReceived(prefix, message, distribution, sender)
  if prefix ~= PREFIX or type(message) ~= "string" or Core.IsSecret(message) or type(sender) ~= "string"
    or Core.IsSecret(sender) or isSelf(sender) or not CHANNELS[distribution] then
    return
  end
  local p = Comms.Deserialize(message)
  if type(p) ~= "table" or type(p.msgVer) ~= "number" or floor(p.msgVer) ~= MSG_VERSION then return end
  local handler = handlers[p.msgId]
  if handler then pcall(handler, p, sender) end
end

Comms:RegisterComm(PREFIX, "OnCommReceived")

---Party members' progress on a quest: { [player] = { [index] = objective } } (only players in your group).
function Comms:GetParty(questId)
  local out = {}
  for player, objectives in pairs(self.remote[questId] or {}) do
    if UnitInParty(player) or UnitInRaid(player) then out[player] = objectives end
  end
  return out
end

local TYPE_KIND = { m = "npcs", o = "objects", i = "items" }

---Every party objective about an entity: { {questId, player, index, objective}, ... }.
---kind is "npcs", "objects" or "items"; an item objective also matches its droppers and vendors.
function Comms:ProgressFor(kind, id)
  local hits = {}
  for questId, players in pairs(self.remote) do
    for player, objectives in pairs(players) do
      if UnitInParty(player) or UnitInRaid(player) then
        for index, o in pairs(objectives) do
          local okind = TYPE_KIND[o.type]
          local match = o.id and okind == kind and o.id == id
          if not match and o.id and okind == "items" and (kind == "npcs" or kind == "objects") then
            local info = Core.DB:ItemInfo(o.id)
            match = info and ((kind == "npcs" and (info.drops.npcs and info.drops.npcs[id] or info.vendors[id]))
              or (kind == "objects" and info.drops.objects and info.drops.objects[id])) and true or false
          end
          if match then hits[#hits + 1] = { questId = questId, player = player, index = index, objective = o } end
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
    if kind == "remove" then Comms:SendQuestRemove(questId) else Comms:SendQuestUpdate(questId) end
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
Comms.QuestChanged = function(_, questId, removed) changed(questId, removed) end

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
    C_Timer.After(3, function() Comms:RequestQuestLogs() Comms:SendQuestLog() end)
  elseif now > members then
    C_Timer.After(3, function() Comms:SendQuestLog() end)   -- someone joined: they need ours
  end
  members = now
  for questId, players in pairs(Comms.remote) do
    for player in pairs(players) do
      if not (UnitInParty(player) or UnitInRaid(player)) then forget(questId, player) end
    end
  end
end
for _, event in ipairs({ "GROUP_JOINED", "GROUP_LEFT", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
  Core:On(event, "comms", rosterChanged)
end
