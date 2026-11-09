-- Core:Say (1.25): a chat line from an add-on that reaches chat, or a chat box the player can send with Enter. It
-- remembers which chats reach, in instances and outside them separately, in NorgannonCoreDB.say.
--
-- Since 1.28 Say and OpenChat are LibForever-1.0's (Say.lua in ForeverAPI's lib/); Core gives it the saved table.

local Core = NorgannonCore
local LF = Core.LibForever

Core.Say, Core.OpenChat = LF.Say, LF.OpenChat

LF:SetSayMemory(function()
  local db = Core.db
  if not db then return nil end
  db.say = db.say or {}
  return db.say
end, function(msg) Core:Print(msg) end)

---Forgets what Core:Say learned about which chats reach (for example after a game update).
function Core:ResetSay()
  if Core.db then Core.db.say = {} end
end
