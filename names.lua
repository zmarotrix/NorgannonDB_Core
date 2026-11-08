-- Names (1.20): who someone is, on a client where characters have a first and a last name.
--
-- On Forever, chat and add-on messages give a sender as "First Last" ("Tyrant Kuma"), while the guild roster and
-- UnitName give only "First". A whisper to a first name alone fails ("No player named ..."). So there are two
-- questions, and two answers:
--   who is it?            Names.First(name): the key the roster uses, the same for every form of the name
--   how do I reach them?  Names:Address(nameOrUnit): the full name, from the unit or from what chat has shown us
-- Four add-ons answered these their own way before; Guise's resolver was the most thorough and is the one here.

local Core = NorgannonCore

local Names = { byGuid = {}, byFirst = {} }
Core.Names = Names

local function usable(name)
  return type(name) == "string" and not Core.IsSecret(name) and name ~= ""
end

---The name with the realm taken off and spaces trimmed: "Elowen Brightwater-Realm" is "Elowen Brightwater". nil when
---secret or empty.
function Names.Full(name)
  if not usable(name) then return nil end
  name = strtrim(name)
  if name == "" then return nil end
  return Core.Global("Ambiguate", name, "none") or name:match("^([^%-]+)") or name
end

---The first name: who the roster and UnitName say. "Tyrant Kuma", "Tyrant-Realm" and "Tyrant" are all "Tyrant".
function Names.First(name)
  name = Names.Full(name)
  return name and (name:match("^%S+") or name)
end

---A key to save a person under, the same whichever way their name arrives: the first name in lower case.
function Names.Key(name)
  local first = Names.First(name)
  return first and string.lower(first)
end

---Whether a name carries a last name (so a whisper can reach it).
function Names.HasSurname(name)
  name = Names.Full(name)
  return name ~= nil and name:find(" ", 1, true) ~= nil
end

---Remembers a full name, with its GUID when known. Chat and add-on messages call this; add-ons may too.
function Names:Learn(full, guid)
  full = Names.Full(full)
  if not full or not Names.HasSurname(full) then return end
  if usable(guid) then self.byGuid[guid] = full end
  local first = Names.First(full)
  local known = self.byFirst[first]
  if known == nil then
    self.byFirst[first] = full
  elseif known ~= full then
    self.byFirst[first] = false   -- two people share this first name: a first name alone can't tell them apart
  end
end

---The name a whisper reaches ("First Last"), for a full name, a first name or a unit token; nil when nobody can say
---(the first name is shared, never seen, or secret).
function Names:Address(who)
  if not usable(who) then return nil end
  if Core.Global("UnitExists", who) then
    local guid = Core.Global("UnitGUID", who)
    local full = Core.Global("GetUnitName", who, true)
    if Names.HasSurname(full) then
      full = Names.Full(full)
      if guid then self.byGuid[guid] = full end
      return full
    end
    if guid and self.byGuid[guid] then return self.byGuid[guid] end
    who = full or Core.Global("UnitName", who)
    if not usable(who) then return nil end
  end
  if Names.HasSurname(who) then return Names.Full(who) end
  local known = self.byFirst[Names.First(who)]
  return known or nil
end

---Your own name, in full when the client gives it ("Tyrant Kuma"), else your first name.
function Names.Me()
  local full = Core.Global("GetUnitName", "player", true)
  if Names.HasSurname(full) then return Names.Full(full) end
  return Names.Full(Core.Global("UnitName", "player"))
end

---Whether a name, in any form, is you.
function Names.IsMe(name)
  local first = Names.First(name)
  return first ~= nil and first == Names.First(Names.Me())
end

-- Every chat line names its sender in full, with a GUID: the cheapest way to learn who's who. In chat lockdown the
-- sender is secret, and Learn skips it.
local CHAT = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_WHISPER",
  "CHAT_MSG_CHANNEL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER" }
for _, event in ipairs(CHAT) do
  Core:On(event, "core.names", function(_, _, sender, _, _, _, _, _, _, _, _, _, guid)
    Names:Learn(sender, guid)
  end)
end
Core:On("CHAT_MSG_ADDON", "core.names", function(_, _, _, _, sender) Names:Learn(sender) end)
