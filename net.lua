-- Core.Net (1.21): add-on messages under an add-on's own prefix, from Council's Transport. Small on purpose: it moves
-- text, not tables (each add-on keeps its own serializer). What it adds over sending through AceComm directly:
--   * compression when the client has C_EncodingUtil (framed "Z" + base64; plain text is framed "T")
--   * a gate: nothing goes out in chat lockdown, where ChatThrottleLib would silently lose it; it waits in a queue
--   * a real test send that tells "refused by the game" from "throttled" (AreOutgoingAddonChatMessagesRestricted
--     can't: /cprobe found it true on Forever while add-on messages kept arriving)
--   * whispers reach the sender's full name: Forever's first names alone can't be whispered (Core.Names)
--
--   local ch = Core.Net:Channel("Council", { onMessage = function(text, first, sender, distribution) end })
--   ch:Send(text, "GUILD")

local Core = NorgannonCore

local Net = { channels = {} }
Core.Net = Net

local DEFAULT_DISTRIBUTIONS = { GUILD = true, OFFICER = true, RAID = true, PARTY = true, WHISPER = true, INSTANCE_CHAT = true }
local TEST_EVERY_REFUSED = 300    -- seconds between test sends while the game is turning us down

local AceComm = LibStub("AceComm-3.0")

local function encodingApi()
  local api = rawget(_G, "C_EncodingUtil")
  if api and api.CompressString and api.DecompressString and api.EncodeBase64 and api.DecodeBase64 then return api end
end

---Text framed for the wire: "Z" + compressed base64 when that is shorter (and the text is at least compressFrom long),
---else "T" + the text.
function Net.Pack(text, compressFrom)
  local api = encodingApi()
  if api and #text >= (compressFrom or 120) then
    local ok, zipped = pcall(function() return api.EncodeBase64(api.CompressString(text)) end)
    if ok and type(zipped) == "string" and #zipped < #text then return "Z" .. zipped end
  end
  return "T" .. text
end

---The text from a framed wire string, or nil for anything else (too long, unknown frame, bad compression).
function Net.Unpack(wire, maxIncoming)
  maxIncoming = maxIncoming or 120000
  if type(wire) ~= "string" or Core.IsSecret(wire) or #wire > maxIncoming then return nil end
  local kind, body = wire:sub(1, 1), wire:sub(2)
  if kind == "T" then return body end
  if kind == "Z" then
    local api = encodingApi()
    if not api then return nil end
    local ok, plain = pcall(function() return api.DecompressString(api.DecodeBase64(body)) end)
    if ok and type(plain) == "string" and #plain <= maxIncoming * 4 then return plain end
  end
  return nil
end

local function resultName(code)
  local names = rawget(_G, "Enum") and Enum.SendAddonMessageResult
  for name, value in pairs(names or {}) do
    if value == code then return name end
  end
  return tostring(code)
end

local Channel = {}
Channel.__index = Channel

---A channel under prefix. opts: onMessage(text, first, sender, distribution) for each message from someone else;
---distributions (a set; default guild, officer, raid, party, whisper, instance); maxIncoming (120000 bytes);
---maxQueue (200); compressFrom (120); onDrain() after a held queue goes out.
function Net:Channel(prefix, opts)
  if self.channels[prefix] then return self.channels[prefix] end
  local ch = setmetatable({ prefix = prefix, opts = opts or {}, queue = {}, addresses = {}, nextTest = 0 }, Channel)
  AceComm:Embed(ch)
  ch:RegisterComm(prefix, "Receive")
  self.channels[prefix] = ch
  return ch
end

---Why nothing can go out now: "lockdown" (for now; messages wait), "refused" (the game turned down the last test), or nil.
function Channel:Blocked()
  if Core.In("C_ChatInfo", "InChatMessagingLockdown") then return "lockdown" end
  if self.refused then return "refused" end
  return nil
end

local function deliver(ch, item)
  ch:SendCommMessage(ch.prefix, item.wire, item.distribution, item.target, item.priority)
end

---Sends text. In lockdown it waits in the queue, unless volatile (a stale update is worth nothing later). Returns true
---when it went out now. A whisper goes to the full name this channel or Core.Names has seen for that first name.
function Channel:Send(text, distribution, target, priority, volatile)
  local blocked = self:Blocked()
  if blocked == "refused" then return false end
  if distribution == "WHISPER" and target then
    target = self.addresses[target] or Core.Names:Address(target) or target
  end
  local item = { wire = Net.Pack(text, self.opts.compressFrom), distribution = distribution, target = target,
    priority = priority or "NORMAL" }
  if blocked then
    if volatile then return false end
    if #self.queue >= (self.opts.maxQueue or 200) then table.remove(self.queue, 1) end
    self.queue[#self.queue + 1] = item
    return false
  end
  deliver(self, item)
  return true
end

function Channel:QueueSize() return #self.queue end

---A small real message, which peers ignore ("Ttest"), finds out whether the game accepts our messages at all.
---ChatThrottleLib hides the game's answer, so only a direct send can say. Sent in the guild, when in one.
function Channel:Test()
  if not Core.Global("IsInGuild") or Core.In("C_ChatInfo", "InChatMessagingLockdown") then return end
  local code = Core.In("C_ChatInfo", "SendAddonMessage", self.prefix, "Ttest", "GUILD")
  self.lastResult = code == nil and "no answer" or resultName(code)
  local ok = code == nil or code == 0 or self.lastResult == "AddonMessageThrottle" or self.lastResult == "ChannelThrottle"
  self.refused = not ok or nil
  if self.refused then self.nextTest = GetTime() + TEST_EVERY_REFUSED end
end

---Retests a refusal now and then, and sends what waited once lockdown lifts. Core ticks every channel each second.
function Channel:Tick()
  if self.refused and GetTime() >= self.nextTest then self:Test() end
  if #self.queue > 0 and not self:Blocked() then
    local queue = self.queue
    self.queue = {}
    for _, item in ipairs(queue) do deliver(self, item) end
    if self.opts.onDrain then Core.SafeCall(self.opts.onDrain) end
  end
end

---AceComm's callback (also callable directly). Anything secret, from an unexpected distribution, from yourself, or
---that won't unpack is dropped; the rest goes to onMessage. Nothing a peer sends can raise an error here.
function Channel:Receive(prefix, wire, distribution, sender)
  if prefix ~= self.prefix or Core.IsSecret(wire) or Core.IsSecret(sender) then return end
  if not (self.opts.distributions or DEFAULT_DISTRIBUTIONS)[distribution] then return end
  local first = Core.Names.First(sender)
  if not first or Core.Names.IsMe(sender) then return end
  self.addresses[first] = sender
  Core.Names:Learn(sender)
  local text = Net.Unpack(wire, self.opts.maxIncoming)
  if not text or not self.opts.onMessage then return end
  pcall(self.opts.onMessage, text, first, sender, distribution)
end

Core:OnLogin(function()
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function() for _, ch in pairs(Net.channels) do ch:Tick() end end)
  end
end)
