-- The guild roster, once for the whole suite (1.17): who's in it, their rank, class and level, who's online, and whose
-- rank can invite. It only reads. Add-ons that need it call Guild:Watch(owner), and the roster is asked for once a minute
-- only while someone watches, so two add-ons don't each poll it.
--
-- Names: Forever characters have a first and a last name. The roster and UnitName give the first ("Tyrant"), chat and
-- loot lines give both ("Tyrant Kuma"), and a whisper to the first name alone fails. Guild.Short is who someone is;
-- the roster's own text is kept as .full, and is not promised to be an address.

local Core = NorgannonCore

local Guild = { revision = 0, count = 0, byName = {}, known = false }
Core.Guild = Guild

local REFRESH_EVERY = 60
-- Where "invite" sits in GuildControlGetRankFlags. Read from /cprobe's data: the three ranks that can invite are the three
-- with this flag. CanGuildInvite answers for yourself; this is only for other people's ranks.
local INVITE_FLAG = 7

local watchers = {}
local lastStamp
local nextAsk = 0

-- Calls a client function, with errors and secret values turned into nil.
local function clean(ok, ...)
  if not ok then return nil end
  local n = select("#", ...)
  local out = { ... }
  for i = 1, n do
    if Core.IsSecret(out[i]) then out[i] = nil end
  end
  return unpack(out, 1, n)
end
local function call(name, ...)
  local fn = rawget(_G, name)
  if type(fn) ~= "function" then return nil end
  return clean(pcall(fn, ...))
end
local function callIn(ns, name, ...)
  local t = rawget(_G, ns)
  local fn = type(t) == "table" and t[name]
  if type(fn) ~= "function" then return nil end
  return clean(pcall(fn, ...))
end

---Who someone is, from any form of their name: "Tyrant Kuma", "Tyrant-Realm" and "Tyrant" are all "Tyrant".
---nil for a secret or empty name.
function Guild.Short(name)
  return Core.Names.First(name)   -- names.lua (1.20)
end

-------------------------------------------------------------------------------------------
-- Reading
-------------------------------------------------------------------------------------------

local inviteRanks

local function readRanks()
  local out, any = {}, false
  for i = 1, call("GuildControlGetNumRanks") or 0 do
    local flags = callIn("C_GuildInfo", "GuildControlGetRankFlags", i)
    if type(flags) == "table" and flags[INVITE_FLAG] == true then
      out[i - 1] = true      -- the roster counts ranks from 0, this call from 1
      any = true
    end
  end
  inviteRanks = any and out or nil
end

local function read()
  local total = call("GetNumGuildMembers")
  if type(total) ~= "number" or total == 0 then return false end
  local byName, stamp = {}, {}
  for i = 1, total do
    local name, rankName, rankIndex, level, _, zone, _, _, online, _, classFile, _, _, _, _, _, guid = call("GetGuildRosterInfo", i)
    local short = Guild.Short(name)
    if short then
      byName[short] = { name = short, full = name, rank = rankIndex, rankName = rankName, level = level, zone = zone,
        online = online and true or false, class = classFile, guid = guid }
      stamp[#stamp + 1] = short .. ":" .. tostring(rankIndex) .. ":" .. (online and "1" or "0")
    end
  end
  if next(byName) == nil then return false end   -- every name secret: wait for the next read
  readRanks()
  table.sort(stamp)
  local text = table.concat(stamp, ";")
  local before, wasKnown = Guild.byName, Guild.known
  Guild.byName, Guild.count, Guild.known = byName, total, true
  if text ~= lastStamp then
    lastStamp = text
    Guild.revision = Guild.revision + 1
    -- who came and went since the last read; nothing on the first, when everyone would look new
    local joined, left = {}, {}
    if wasKnown then
      for short in pairs(byName) do if not before[short] then joined[#joined + 1] = short end end
      for short in pairs(before) do if not byName[short] then left[#left + 1] = short end end
      table.sort(joined)
      table.sort(left)
    end
    Core:Send("NORGANNON_GUILD_ROSTER", Guild.revision, joined, left)
  end
  return true
end

-------------------------------------------------------------------------------------------
-- Asking
-------------------------------------------------------------------------------------------

---Asks the game for the roster now. Not during chat lockdown, when nothing it sends back can be read anyway.
function Guild:Ask()
  if callIn("C_ChatInfo", "InChatMessagingLockdown") then return end
  if not call("IsInGuild") then return end
  local info = rawget(_G, "C_GuildInfo")
  if type(info) == "table" and info.GuildRoster then callIn("C_GuildInfo", "GuildRoster") else call("GuildRoster") end
end

---Keeps the roster fresh while owner wants it. Returns at once; NORGANNON_GUILD_ROSTER says when it's read.
function Guild:Watch(owner)
  watchers[owner] = true
  self:Ask()
end

function Guild:Unwatch(owner)
  watchers[owner] = nil
end

---Asks again if someone watches and a minute has passed. now is GetTime().
function Guild:Tick(now)
  if not next(watchers) or now < nextAsk then return end
  nextAsk = now + REFRESH_EVERY
  self:Ask()
end

-------------------------------------------------------------------------------------------
-- Answers
-------------------------------------------------------------------------------------------

function Guild:InGuild() return call("IsInGuild") and true or false end
function Guild:Name() return (call("GetGuildInfo", "player")) end
function Guild:Known() return self.known end

---A member's row: { name, full, rank, rankName, level, zone, online, class, guid }, or nil.
function Guild:Get(name)
  local short = Guild.Short(name)
  return short and self.byName[short]
end

function Guild:IsMember(name) return self:Get(name) ~= nil end

---Every member's row, by name.
function Guild:Members()
  local out = {}
  for _, row in pairs(self.byName) do out[#out + 1] = row end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function Guild:OnlineCount()
  local n = 0
  for _, row in pairs(self.byName) do if row.online then n = n + 1 end end
  return n
end

---Can I invite people to the guild? The game's own answer.
function Guild:CanInvite()
  return call("CanGuildInvite") and true or false
end

---Can someone of this rank invite? nil when the ranks haven't been read or the client doesn't say.
function Guild:RankCanInvite(rankIndex)
  if rankIndex == 0 then return true end
  if not inviteRanks then return nil end
  return inviteRanks[rankIndex] == true
end

---Members online right now whose rank can invite, guild master first, never yourself.
function Guild:Inviters()
  local me = Guild.Short((call("UnitName", "player")))
  local out = {}
  for short, row in pairs(self.byName) do
    if row.online and short ~= me and self:RankCanInvite(row.rank) then out[#out + 1] = row end
  end
  table.sort(out, function(a, b)
    if a.rank ~= b.rank then return (a.rank or 99) < (b.rank or 99) end
    return a.name < b.name
  end)
  return out
end

Core:On("GUILD_ROSTER_UPDATE", "core.guild", function() read() end)
Core:On("GUILD_RANKS_UPDATE", "core.guild", function() read() end)
Core:On("PLAYER_GUILD_UPDATE", "core.guild", function(_, unit)
  if unit and unit ~= "player" then return end
  if not call("IsInGuild") then
    Guild.byName, Guild.count, Guild.known, lastStamp = {}, 0, false, nil
    Guild.revision = Guild.revision + 1
    Core:Send("NORGANNON_GUILD_ROSTER", Guild.revision, {}, {})
  else
    Guild:Ask()
  end
end)
Core:OnLogin(function()
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(5, function() Guild:Tick(GetTime()) end)
  end
end)
