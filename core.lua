-- NorgannonDB_Core: the runtime library under the NorgannonDB suite (Clairvoyance, Oracle,
-- Foresight, Archivum). It owns what the addons would otherwise duplicate or fight over: the
-- client layer, events and messages, the UI kit, the suite registry and settings.
-- The public API is versioned and documented in docs/core-api.md; check it at load:
--
--   local Core = NorgannonCore
--   if not Core or not Core:Require(1, 0) then return end

local ADDON = ...

local Core = {
  VERSION_MAJOR = 1,
  VERSION_MINOR = 9,
  addonName = ADDON or "NorgannonDB_Core",
  db = nil,                 -- NorgannonCoreDB, set at ADDON_LOADED
}
NorgannonCore = Core

---true if this Core serves a consumer written for API major.minor.
function Core:Require(major, minor)
  return major == self.VERSION_MAJOR and (minor or 0) <= self.VERSION_MINOR
end

function Core:Version()
  return self.VERSION_MAJOR .. "." .. self.VERSION_MINOR
end

-------------------------------------------------------------------------------------------
-- Calling other addons' code: an error in one listener must not stop the others
-------------------------------------------------------------------------------------------

local function call(fn, ...)
  if securecallfunction then return securecallfunction(fn, ...) end
  return fn(...)
end
Core.SafeCall = call

-------------------------------------------------------------------------------------------
-- Game events: one frame for the whole suite
-------------------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}   -- event -> { owner -> fn }

local function validEvent(event)
  if C_EventUtils and C_EventUtils.IsEventValid then return C_EventUtils.IsEventValid(event) end
  return true
end

---Calls fn(event, ...) for a game event. owner keys the handler (one per owner and event).
---Returns false for events this client does not have.
function Core:On(event, owner, fn)
  if not validEvent(event) then return false end
  if not handlers[event] then
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
    handlers[event] = {}
  end
  handlers[event][owner] = fn
  return true
end

function Core:Off(event, owner)
  local list = handlers[event]
  if not list then return end
  list[owner] = nil
  if next(list) == nil then
    handlers[event] = nil
    eventFrame:UnregisterEvent(event)
  end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for _, fn in pairs(list) do call(fn, event, ...) end
end)

-------------------------------------------------------------------------------------------
-- Messages between suite addons (and inside the Core)
-------------------------------------------------------------------------------------------

local listeners = {}  -- message -> { owner -> fn }

function Core:Listen(message, owner, fn)
  listeners[message] = listeners[message] or {}
  listeners[message][owner] = fn
end

function Core:Unlisten(message, owner)
  if listeners[message] then listeners[message][owner] = nil end
end

function Core:Send(message, ...)
  local list = listeners[message]
  if not list then return end
  for _, fn in pairs(list) do call(fn, message, ...) end
end

-------------------------------------------------------------------------------------------
-- Load order: run code once saved variables are in (ADDON_LOADED) or the world is up
-------------------------------------------------------------------------------------------

local readyQueue, loginQueue = {}, {}
local isReady, isLoggedIn = false, false

---fn() after the Core's saved variables are loaded (immediately if they already are).
function Core:OnReady(fn)
  if isReady then call(fn) else table.insert(readyQueue, fn) end
end

---fn() after PLAYER_LOGIN (immediately if it already happened).
function Core:OnLogin(fn)
  if isLoggedIn then call(fn) else table.insert(loginQueue, fn) end
end

local DEFAULTS = { windows = {}, debug = false, debugLog = {}, seenWelcome = {} }

Core:On("ADDON_LOADED", Core, function(_, name)
  if name ~= Core.addonName then return end
  Core:Off("ADDON_LOADED", Core)
  local saved = rawget(_G, "NorgannonCoreDB")   -- nil on the first run
  local db = type(saved) == "table" and saved or {}
  for key, value in pairs(DEFAULTS) do
    if db[key] == nil then db[key] = type(value) == "table" and {} or value end
  end
  NorgannonCoreDB, Core.db = db, db
  isReady = true
  for _, fn in ipairs(readyQueue) do call(fn) end
  readyQueue = nil
end)

Core:On("PLAYER_LOGIN", Core, function()
  Core:Off("PLAYER_LOGIN", Core)
  isLoggedIn = true
  for _, fn in ipairs(loginQueue) do call(fn) end
  loginQueue = nil
end)

-------------------------------------------------------------------------------------------
-- Chat and debug log
-------------------------------------------------------------------------------------------

Core.PREFIX = "|cffe7c66cNorgannonDB|r"

function Core:Print(msg, prefix)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage((prefix or self.PREFIX) .. ": " .. tostring(msg))
  end
end

local LOG_SIZE = 300

---Adds a line to the debug log (kept in saved variables) when /norg debug is on.
function Core:Debug(source, fmt, ...)
  local db = self.db
  if not db or not db.debug then return end
  local ok, text = pcall(string.format, fmt, ...)
  local log = db.debugLog
  table.insert(log, string.format("%s %s: %s", date and date("%H:%M:%S") or "", tostring(source), ok and text or fmt))
  while #log > LOG_SIZE do table.remove(log, 1) end
end
