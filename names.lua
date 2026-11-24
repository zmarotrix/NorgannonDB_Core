-- Names (1.20): who someone is, on a client where characters have a first and a last name.
--
-- On Forever, chat and add-on messages give a sender as "First Last" ("Tyrant Kuma"), while the guild roster and
-- UnitName give only "First". A whisper to a first name alone fails ("No player named ..."). So there are two
-- questions, and two answers:
--   who is it?            Names.First(name): the key the roster uses, the same for every form of the name
--   how do I reach them?  Names:Address(nameOrUnit): the full name, from the unit or from what chat has shown us
--
-- Since 1.27 it is LibForever-1.0's Names (Names.lua in ForeverAPI's lib/), the same table; it learns names from chat
-- itself.

NorgannonCore.Names = NorgannonCore.LibForever.Names

-------------------------------------------------------------------------------------------
-- Character (1.34): keys for saved data that can't change under an add-on.
--
-- GetRealmName() named a server until the 2026-11-20 client and has been "" since, so data kept under "Realm-Name" came
-- apart: the same character under "Realm-Name" and "-Name". The player's GUID ("Player-6933-00ABCDEF") kept its value
-- across that change (23 combat logs, 5 to 23 November), so a character is its GUID, and its server is the GUID's number.
-- Names stay in the record, for showing.
--
-- Pairs and Mine find what was saved under the old keys. They change nothing: the add-on merges its own records.
-------------------------------------------------------------------------------------------

local Core = NorgannonCore
local Character = {}
Core.Character = Character

local guid

---The GUID of the character logged in: the key to save its things under. nil until the game says.
---@return string|nil
function Character.Key()
  if not guid then
    local g = Core.Global("UnitGUID", "player")
    if type(g) == "string" and g:find("^Player%-") then guid = g end
  end
  return guid
end

---The server number in a character's GUID ("6933"), yours by default: what keeps two servers' guilds or markets apart.
---@param key string|nil
---@return string|nil
function Character.Server(key)
  key = key or Character.Key()
  return type(key) == "string" and key:match("^Player%-(%d+)") or nil
end

---The realm and the name in an old "Realm-Name" key; nil for a GUID.
---@param key any
---@return string|nil realm, string|nil name
function Character.Split(key)
  if type(key) ~= "string" or key:find("^Player%-%d") then return nil end
  return key:match("^(.*)%-([^%-]+)$")
end

-- what add-ons wrote when there was no realm name: nothing at all, or their own stand-in
local NO_REALM = { [""] = true, ["?"] = true, ["Realm"] = true }
Character.NO_REALM = NO_REALM

-- { [name] = { named = { keys }, unnamed = { keys } } } over the old keys of a table
local function byName(t, split)
  local out = {}
  for key in pairs(t) do
    local realm, name = split(key)
    if realm and name and name ~= "" then
      local e = out[name]
      if not e then
        e = { named = {}, unnamed = {} }
        out[name] = e
      end
      local list = NO_REALM[realm] and e.unnamed or e.named
      list[#list + 1] = key
    end
  end
  for _, e in pairs(out) do
    table.sort(e.named)
    table.sort(e.unnamed)
  end
  return out
end

---The old keys of t that are one thing saved twice, with a realm name and without: a list of { from, to }, to keep what
---`from` holds under `to`. Where two named realms have the same name, nobody can say whose the unnamed one is, so it's
---left alone. opts: split(key) → realm, name (Character.Split); same(a, b) false keeps two records apart.
---@param t table
---@param opts table|nil
---@return table pairs
function Character.Pairs(t, opts)
  local split, same = opts and opts.split or Character.Split, opts and opts.same
  local out = {}
  for _, e in pairs(byName(t, split)) do
    if #e.named <= 1 then
      local to = e.named[1] or e.unnamed[1]
      for _, from in ipairs(e.unnamed) do
        if from ~= to and (not same or same(t[to], t[from])) then out[#out + 1] = { from = from, to = to } end
      end
    end
  end
  table.sort(out, function(a, b) return a.from < b.from end)
  return out
end

---The old key under which t has what is `name`'s, or nil when there's none, or more than one and nobody can say which.
---opts: split, as above; mine(record) false rules a record out (another class, say).
---@param t table
---@param name any
---@param opts table|nil
---@return string|nil key
function Character.Mine(t, name, opts)
  local e = type(name) == "string" and byName(t, opts and opts.split or Character.Split)[name]
  if not e then return nil end
  local found
  for _, list in ipairs({ e.named, e.unnamed }) do
    for _, key in ipairs(list) do
      if not (opts and opts.mine) or opts.mine(t[key]) then
        if found then return nil end
        found = key
      end
    end
  end
  return found
end

---The realm and the guild in an old "realm/guild" key; nil for one that starts with a server number.
function Character.SplitGuild(key)
  if type(key) ~= "string" then return nil end
  local realm, name = key:match("^(.-)/(.+)$")
  if not realm or realm:find("^%d+$") then return nil end
  return realm, name
end

---The key for the player's guild: "6933/Guild Name". nil when not in a guild, or before the game has said.
---@return string|nil key, string|nil guild
function Character.GuildKey()
  local name, server = Core.Global("GetGuildInfo", "player"), Character.Server()
  if type(name) ~= "string" or name == "" or not server then return nil end
  return server .. "/" .. name, name
end
