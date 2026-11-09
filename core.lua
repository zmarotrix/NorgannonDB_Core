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
  VERSION_MINOR = 28,
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
    return string.format("%s needs Norgannon Core %s or newer (this is %s): update Norgannon Core. %s is turned off.",
      name, wanted, self:Version(), name)
  end
  return string.format("%s was made for Norgannon Core %s, which this Core (%s) no longer serves: update %s. It is turned off.",
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
-- Events, messages and the rest of the base (1.27): LibForever-1.0, the public Forever toolkit, owns them. It lives in
-- ForeverAPI (lib/LibForever-1.0); tools/deploy.py copies it into libs/. Core's names point at it, so nothing that
-- calls Core changes. Its functions ignore self, which is why Core.On = LF.On works as Core:On.
-------------------------------------------------------------------------------------------

local LF = LibStub("LibForever-1.0")
Core.LibForever = LF

Core.SafeCall = LF.SafeCall
Core.On, Core.Off, Core.SetEventTap = LF.On, LF.Off, LF.SetEventTap
Core.Listen, Core.Unlisten, Core.Send = LF.Listen, LF.Unlisten, LF.Send
local call = LF.SafeCall

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
  LF:Print(msg, prefix or self.PREFIX)
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

-- LibForever's own lines (a failed saved-variable migration, say) go to the same log. Core's lines don't pass
-- through the library's sink, so another add-on setting its own sink can't take them away.
LF:SetDebugSink(function(source, text) Core:Debug(source, "%s", text) end,
  function() return Core.db ~= nil and not not Core.db.debug end)
