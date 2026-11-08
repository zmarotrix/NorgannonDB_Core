-- Core:Say (1.25): a chat line from an add-on that reaches chat, or a chat box the player can send with Enter.
--
-- On WoW Forever an add-on's chat line doesn't always arrive: C_ChatInfo.SendChatMessage is "restricted in some
-- situations" (Blizzard's docs), players report add-ons can't say, yell or emote in instances, and Council found its
-- raid announcements silently not reaching chat. What every client allows is the player pressing Enter. So Core:Say
-- sends the line and watches for it to come back; if it doesn't, it opens the chat box with the line ready and
-- remembers that for this kind of chat (in instances and outside them separately), so next time the box opens at once.
-- From Council's loot announcements (Council 0.2).

local Core = NorgannonCore

local ECHO_WAIT = 3       -- seconds for our own line to come back
local SLASH = { SAY = "/s ", YELL = "/y ", EMOTE = "/e ", PARTY = "/p ", RAID = "/raid ", RAID_WARNING = "/rw ",
  GUILD = "/g ", OFFICER = "/o ", INSTANCE_CHAT = "/i " }
local ECHO = { SAY = { "CHAT_MSG_SAY" }, YELL = { "CHAT_MSG_YELL" }, EMOTE = { "CHAT_MSG_EMOTE" },
  PARTY = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER" }, RAID = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER" },
  RAID_WARNING = { "CHAT_MSG_RAID_WARNING" }, GUILD = { "CHAT_MSG_GUILD" }, OFFICER = { "CHAT_MSG_OFFICER" },
  INSTANCE_CHAT = { "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" } }
local MAX_LENGTH = 255

local waiting = {}        -- text -> place key, while its echo is awaited

local function place(kind)
  local _, instance = Core.Global("IsInInstance")
  return kind .. ":" .. ((instance and instance ~= "none") and "instance" or "world")
end

local function remembered()
  local db = Core.db
  if not db then return {} end
  db.say = db.say or {}
  return db.say
end

---Opens the chat box with text ready to send ("/raid Thunderfury to Brin").
function Core:OpenChat(text)
  local util = rawget(_G, "ChatFrameUtil")
  local open = (util and util.OpenChat) or rawget(_G, "ChatFrame_OpenChat")
  if open then return (pcall(open, text)) end
  return false
end

local function heard(_, text)
  if Core.IsSecret(text) or type(text) ~= "string" then return end
  local key = waiting[text]
  if key then
    waiting[text] = nil
    remembered()[key] = true
  end
end
for _, events in pairs(ECHO) do
  for _, event in ipairs(events) do Core:On(event, "core.say", heard) end
end

---Says text in kind ("SAY", "YELL", "EMOTE", "PARTY", "RAID", "RAID_WARNING", "GUILD", "OFFICER", "INSTANCE_CHAT";
---"WHISPER" with target). Returns "sent" (it went out, or is being checked), "box" (the chat box opened with it ready:
---the player presses Enter) or false. Call it from a click or a command: a line nobody asked for is spam, box or not.
function Core:Say(text, kind, target)
  kind = kind or "SAY"
  text = tostring(text):sub(1, MAX_LENGTH)
  local slash = kind == "WHISPER" and ("/w " .. tostring(Core.Names:Address(target) or target) .. " ") or SLASH[kind]
  local key = place(kind)
  local known = remembered()[key]
  if known == false then
    return slash and Core:OpenChat(slash .. text) and "box" or false
  end
  local send = Core.Fn("C_ChatInfo", "SendChatMessage") or Core.Fn(nil, "SendChatMessage")
  if not send then return false end
  if kind == "WHISPER" then target = Core.Names:Address(target) or target end
  local watch = known == nil and ECHO[kind] ~= nil and not Core.In("C_ChatInfo", "InChatMessagingLockdown")
  if watch then waiting[text] = key end
  if not pcall(send, text, kind, nil, target) then
    waiting[text] = nil
    remembered()[key] = false
    return slash and Core:OpenChat(slash .. text) and "box" or false
  end
  if watch and C_Timer and C_Timer.After then
    C_Timer.After(ECHO_WAIT, function()
      if waiting[text] == key then
        waiting[text] = nil
        remembered()[key] = false
        Core:Print("A line didn't reach chat, so the chat box opens with it ready: press Enter to send.")
        if slash then Core:OpenChat(slash .. text) end
      end
    end)
  end
  return "sent"
end

---Forgets what Core:Say learned about which chats reach (for example after a game update).
function Core:ResetSay()
  if Core.db then Core.db.say = {} end
end
