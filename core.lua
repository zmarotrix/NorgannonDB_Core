-- NorgannonDB_Core: the runtime library under the NorgannonDB suite (Clairvoyance, Oracle,
-- Retrospect and the rest, see registry.lua). It owns what the addons would otherwise duplicate or fight over: the
-- client layer, events and messages, the UI kit, the suite registry and settings.
-- The public API is versioned and documented in docs/core-api.md; check it at load:
--
--   local Core = NorgannonCore
--   if not Core or not Core:Require(1, 0) then return end

local ADDON = ...

local Core = {
  VERSION_MAJOR = 1,
  VERSION_MINOR = 22,
  addonName = ADDON or "NorgannonDB_Core",
  db = nil,                 -- NorgannonCoreDB, set at ADDON_LOADED
  -- Older majors this Core still serves, with the last minor of each. Empty: the promise is the same major version
  -- only (an add-on written for 1.x runs on any later 1.x). Kept so a future major could serve 1.x if it ever must.
  COMPAT = {},
}
NorgannonCore = Core

---true if this Core serves a consumer written for API major.minor: the same major at that minor or later, or a
---previous major still kept working through Core.COMPAT.
function Core:Require(major, minor)
  minor = minor or 0
  if major == self.VERSION_MAJOR then return minor <= self.VERSION_MINOR end
  local lastMinor = self.COMPAT[major]
  return lastMinor ~= nil and minor <= lastMinor
end

---true when an add-on written for major.minor runs only through a compatibility shim: it works, but should move on.
function Core:IsDeprecated(major)
  return major ~= self.VERSION_MAJOR and self.COMPAT[major] ~= nil
end

---Why an add-on written for major.minor can't run here, in a player's words; nil if it can.
function Core:RequireMessage(name, major, minor)
  if self:Require(major, minor) then return nil end
  local wanted = major .. "." .. (minor or 0)
  if major > self.VERSION_MAJOR or (major == self.VERSION_MAJOR and (minor or 0) > self.VERSION_MINOR) then
    return string.format("%s needs NorgannonDB Core %s or newer (this is %s): update NorgannonDB Core. %s is turned off.",
      name, wanted, self:Version(), name)
  end
  return string.format("%s was made for NorgannonDB Core %s, which this Core (%s) no longer serves: update %s. It is turned off.",
    name, wanted, self:Version(), name)
end

---Whether NorgannonDB, the game data, is loaded. Core runs without it (1.19): Core.DB answers nil and empty lists,
---and the map, quest and search features have nothing to show. Add-ons that need the data list it in their TOC.
function Core:HasData()
  local DB = rawget(_G, "NorgannonDB")
  return type(DB) == "table" and DB.Get ~= nil
end

function Core:Version()
  return self.VERSION_MAJOR .. "." .. self.VERSION_MINOR
end

-------------------------------------------------------------------------------------------
-- Calling other addons' code: an error in one listener must not stop the others
-------------------------------------------------------------------------------------------

-- securecallfunction hands an error to the error handler and carries on, so a broken listener
-- can't take the rest down with it (nor taint the caller). The plain call is for a client without it.
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

-- Adds or replaces an owner's function in registry[key], which must exist. A new owner goes into
-- a copy of the list: a dispatch may be looping over it right now (a listener can register
-- another), and adding a key to a table during pairs is undefined in Lua. The new owner hears
-- from the next dispatch on.
local function setOwner(registry, key, owner, fn)
  local list = registry[key]
  if list[owner] ~= nil then
    list[owner] = fn
    return
  end
  local copy = {}
  for existing, existingFn in pairs(list) do copy[existing] = existingFn end
  copy[owner] = fn
  registry[key] = copy
end

---Calls fn(event, ...) for a game event. owner keys the handler (one per owner and event).
---Returns false for events this client does not have.
function Core:On(event, owner, fn)
  if not validEvent(event) then return false end
  if not handlers[event] then
    -- RegisterEvent throws on an event the client doesn't have
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
    handlers[event] = {}
  end
  setOwner(handlers, event, owner, fn)
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

-- eventTap(event, starting) brackets each dispatch while /norg mem rate measures; nil otherwise
local eventTap = nil

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  local tap = eventTap
  if tap then tap(event, true) end
  for _, fn in pairs(list) do call(fn, event, ...) end
  if tap then tap(event, false) end
end)

---For measuring (/norg mem rate): fn(event, starting) around every game event the Core dispatches; nil stops.
function Core:SetEventTap(fn) eventTap = fn end

-------------------------------------------------------------------------------------------
-- Messages between suite addons (and inside the Core)
-------------------------------------------------------------------------------------------

local listeners = {}  -- message -> { owner -> fn }

function Core:Listen(message, owner, fn)
  listeners[message] = listeners[message] or {}
  setOwner(listeners, message, owner, fn)
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
    if db[key] == nil then db[key] = type(value) == "table" and {} or value end   -- never share DEFAULTS' tables
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
  local ok, text = pcall(string.format, fmt, ...)   -- a bad format must not break the caller: log it raw
  local log = db.debugLog
  local clock = date and date("%H:%M:%S") or ""
  table.insert(log, string.format("%s %s: %s", clock, tostring(source), ok and text or fmt))
  while #log > LOG_SIZE do table.remove(log, 1) end
end
