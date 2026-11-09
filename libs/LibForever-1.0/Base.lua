-- LibForever-1.0: what every WoW Forever add-on needs and the client doesn't give it. This file is the base: game
-- events and messages on one shared frame, the next frame, work held until combat ends, "may we act now?", which
-- client this is, calling client functions that may be missing or answer in secret values, and printing.
--
--   local LF = LibStub("LibForever-1.0")
--   LF:On("PLAYER_LOGIN", "MyAddon", function() LF:Print("hello", "MyAddon") end)
--
-- Every function ignores `self`, so LF:On(...) and LF.On(nil, ...) are the same call, and another table can point
-- its own names at these (NorgannonDB Core does: Core.On = LF.On).
--
-- One copy per game: LibStub keeps the highest minor version whichever add-on loads first. State lives in LF.state,
-- so a newer copy takes over the older one's event frame, handlers and queues instead of starting over.

local MAJOR, MINOR = "LibForever-1.0", 1
local LF = LibStub:NewLibrary(MAJOR, MINOR)
if not LF then return end   -- the same or a newer copy is already loaded
LF._loading = true          -- the other files of this copy load only while this is set (SavedVars.lua clears it)
LF.MAJOR, LF.MINOR = MAJOR, MINOR

---@class LibForever
---@field Client LibForever.Client
---@field Compat table
---@field Secret LibForever.Secret
---@field Names LibForever.Names

local state = LF.state or {}
LF.state = state
state.handlers = state.handlers or {}      -- event -> { owner -> fn }
state.listeners = state.listeners or {}    -- message -> { owner -> fn }
state.combat = state.combat or { queue = {}, slots = {} }   -- work waiting for combat to end; key -> its place
state.scheduled = state.scheduled or {}    -- keys waiting for their next-frame call

-------------------------------------------------------------------------------------------
-- Calling other add-ons' code: an error in one listener must not stop the others
-------------------------------------------------------------------------------------------

-- securecallfunction hands an error to the error handler and carries on, so a broken listener can't take the rest
-- down with it (nor taint the caller). The plain call is for a client without it.
local function call(fn, ...)
  if securecallfunction then return securecallfunction(fn, ...) end
  return fn(...)
end

---Calls fn(...) so that an error in it goes to the error handler and the caller carries on.
---@param fn function
---@param ... any
---@return any ...
function LF.SafeCall(fn, ...) return call(fn, ...) end

-------------------------------------------------------------------------------------------
-- Game events: one frame for every add-on that uses the library
-------------------------------------------------------------------------------------------

local function validEvent(event)
  if C_EventUtils and C_EventUtils.IsEventValid then return C_EventUtils.IsEventValid(event) end
  return true
end

-- Adds or replaces an owner's function in registry[key], which must exist. A new owner goes into a copy of the list:
-- a dispatch may be looping over it right now (a listener can register another), and adding a key to a table during
-- pairs is undefined in Lua. The new owner hears from the next dispatch on.
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

local handlers = state.handlers
local eventFrame = state.frame or CreateFrame("Frame")
state.frame = eventFrame

---Calls fn(event, ...) for a game event. owner keys the handler: one per owner and event, and only that owner's Off
---removes it, so add-ons can't remove each other's handlers. Returns false for an event this client doesn't have.
---@param event string
---@param owner any
---@param fn fun(event: string, ...: any)
---@return boolean registered
function LF.On(_, event, owner, fn)
  if not validEvent(event) then return false end
  if not handlers[event] then
    -- RegisterEvent throws on an event the client doesn't have
    if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
    handlers[event] = {}
  end
  setOwner(handlers, event, owner, fn)
  return true
end

---Removes owner's handler for a game event.
---@param event string
---@param owner any
function LF.Off(_, event, owner)
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
  local tap = state.tap
  if tap then tap(event, true) end
  for _, fn in pairs(list) do call(fn, event, ...) end
  if tap then tap(event, false) end
end)

---For measuring: fn(event, starting) around every game event the library dispatches (starting true before, false
---after); nil stops.
---@param fn fun(event: string, starting: boolean)|nil
function LF.SetEventTap(_, fn) state.tap = fn end

-------------------------------------------------------------------------------------------
-- Messages between add-ons, on the same bus
-------------------------------------------------------------------------------------------

local listeners = state.listeners

---Calls fn(message, ...) whenever someone Sends message. owner keys it, as with LF:On.
---@param message string
---@param owner any
---@param fn fun(message: string, ...: any)
function LF.Listen(_, message, owner, fn)
  listeners[message] = listeners[message] or {}
  setOwner(listeners, message, owner, fn)
end

---Removes owner's listener for message.
---@param message string
---@param owner any
function LF.Unlisten(_, message, owner)
  if listeners[message] then listeners[message][owner] = nil end
end

---Calls every listener of message with (message, ...). A listener's error doesn't stop the others.
---@param message string
---@param ... any
function LF.Send(_, message, ...)
  local list = listeners[message]
  if not list then return end
  for _, fn in pairs(list) do call(fn, message, ...) end
end

-------------------------------------------------------------------------------------------
-- Which client. Don't trust WOW_PROJECT_ID on Forever: it is 18, WOW_PROJECT_CAMELOT, neither Classic (2) nor
-- Mainline (1), so code that branches on it takes neither branch. The interface number is what tells: Forever is
-- 16000-16999 (16001 on client 1.60.1).
-------------------------------------------------------------------------------------------

local interface = select(4, GetBuildInfo())

---@class LibForever.Client
local Client = LF.Client or {}
LF.Client = Client

---true on WoW Forever.
---@return boolean
function Client.IsForever() return interface >= 16000 and interface < 17000 end

---The interface number, as a TOC writes it: 16001 on Forever 1.60.1.
---@return number
function Client.Interface() return interface end

-- the game's own project ids, by the constant's name, for clients that aren't Forever
local PROJECTS = {
  { "WOW_PROJECT_CLASSIC", "classic" }, { "WOW_PROJECT_BURNING_CRUSADE_CLASSIC", "tbc" },
  { "WOW_PROJECT_WRATH_CLASSIC", "wrath" }, { "WOW_PROJECT_CATACLYSM_CLASSIC", "cata" },
  { "WOW_PROJECT_MISTS_CLASSIC", "mists" }, { "WOW_PROJECT_MAINLINE", "retail" },
}

---"forever", else what WOW_PROJECT_ID says ("classic", "tbc", "wrath", "cata", "mists", "retail"), else "unknown".
---@return string
function Client.Flavor()
  if Client.IsForever() then return "forever" end
  local id = rawget(_G, "WOW_PROJECT_ID")
  for _, p in ipairs(PROJECTS) do
    local value = rawget(_G, p[1])
    if id ~= nil and value ~= nil and id == value then return p[2] end
  end
  return "unknown"
end

---true where the world is Classic's (Forever and the Classic Era client): its maps, zones and quests. Use this, not
---WOW_PROJECT_ID, to pick Classic map data.
---@return boolean
function Client.IsClassicWorld()
  local flavor = Client.Flavor()
  return flavor == "forever" or flavor == "classic"
end

-------------------------------------------------------------------------------------------
-- Secret values and calling the client. The API docs list calls for every game flavour, so any of them may be
-- missing on Forever, refuse (error), or answer in secret values: values that may be passed along (to a widget that
-- accepts them) but never compared, added or used in an `if`.
-------------------------------------------------------------------------------------------

---true if v is a secret value (or a table holding them) that must not be inspected.
---@param v any
---@return boolean
function LF.IsSecret(v)
  if issecretvalue and issecretvalue(v) then return true end
  if type(v) == "table" and issecrettable and issecrettable(v) then return true end
  return false
end

---v, or fallback when v is secret.
---@generic T
---@param v T
---@param fallback any
---@return T|any
function LF.Safe(v, fallback)
  if LF.IsSecret(v) then return fallback end
  return v
end

---The client function ns.name, or the global name when ns is nil; nil if the client lacks it.
---@param ns string|nil a namespace such as "C_Spell"
---@param name string
---@return function|nil
function LF.Fn(ns, name)
  local fn
  if ns == nil then
    fn = rawget(_G, name)
  else
    local t = rawget(_G, ns)
    fn = type(t) == "table" and t[name] or nil
  end
  return type(fn) == "function" and fn or nil
end

---true if the client has ns.name (or the global name when ns is nil).
---@param ns string|nil
---@param name string
---@return boolean
function LF.Has(ns, name) return LF.Fn(ns, name) ~= nil end

---fn(...) through pcall: ok, ... with the answer exactly as it came, secrets included. For handing values to widgets
---that accept secrets. ok is false when fn is missing or errored.
---@param fn function|nil
---@param ... any
---@return boolean ok
---@return any ...
function LF.Call(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function plain(ok, ...)
  if not ok then return nil end
  local n = select("#", ...)
  if n == 0 then return nil end
  local out = { ... }
  for i = 1, n do
    if LF.IsSecret(out[i]) then out[i] = nil end
  end
  return unpack(out, 1, n)
end

---fn(...) with every secret value turned into nil, and nil when fn is missing or errored: for logic that branches.
---@param fn function|nil
---@param ... any
---@return any ...
function LF.Plain(fn, ...)
  if type(fn) ~= "function" then return nil end
  return plain(pcall(fn, ...))
end

---The global client function name(...), through LF.Plain: LF.Global("GetServerTime").
---@param name string
---@param ... any
---@return any ...
function LF.Global(name, ...) return LF.Plain(LF.Fn(nil, name), ...) end

---The namespaced client function ns.name(...), through LF.Plain: LF.In("C_Bank", "CanViewBank").
---@param ns string
---@param name string
---@param ... any
---@return any ...
function LF.In(ns, name, ...) return LF.Plain(LF.Fn(ns, name), ...) end

---obj:method(...) where the arguments may be secret (a widget that accepts them): false if the client refused.
---@param obj table|nil
---@param method string
---@param ... any
---@return boolean
function LF.SetSecret(obj, method, ...)
  local fn = obj and obj[method]
  if type(fn) ~= "function" then return false end
  return (pcall(fn, obj, ...))
end

---The server's time (seconds), else the computer's.
---@return number
function LF.Now() return LF.Global("GetServerTime") or time() end

-------------------------------------------------------------------------------------------
-- Combat lockdown: protected work waits for the end of combat
-------------------------------------------------------------------------------------------

local combat = state.combat

---Runs fn now, or once combat ends. A key replaces an earlier queued call with the same key, so repeated requests
---("re-anchor the tracker") run only once. Returns true if it ran now.
---@param fn function
---@param key any|nil
---@return boolean ranNow
function LF.AfterCombat(_, fn, key)
  if not InCombatLockdown() then
    call(fn)
    return true
  end
  if key and combat.slots[key] then
    combat.queue[combat.slots[key]] = fn
  else
    table.insert(combat.queue, fn)
    if key then combat.slots[key] = #combat.queue end
  end
  return false
end

LF:On("PLAYER_REGEN_ENABLED", "LibForever.combat", function()
  local pending = combat.queue
  combat.queue, combat.slots = {}, {}
  for _, fn in ipairs(pending) do call(fn) end
end)

-------------------------------------------------------------------------------------------
-- Next frame
-------------------------------------------------------------------------------------------

local scheduled = state.scheduled

---fn on the next frame. Given a key, a burst of calls with that key runs fn once.
---@param fn function
---@param key any|nil
function LF.NextFrame(_, fn, key)
  if key then
    if scheduled[key] then return end
    scheduled[key] = true
  end
  C_Timer.After(0, function()
    if key then scheduled[key] = nil end
    call(fn)
  end)
end

-------------------------------------------------------------------------------------------
-- Restrictions: one answer to "may we act now?". The client's own restriction check reads false in open-world
-- combat (ForeverAPI, 2026-11-07), so combat is InCombatLockdown's call.
-------------------------------------------------------------------------------------------

-- what each question checks: the client's restriction kinds (Enum.AddOnRestrictionType) and chat lockdown
local KINDS = {
  combat = { combat = true },
  fight = { combat = true, kinds = { "Combat", "Encounter", "ChallengeMode", "PvPMatch" } },  -- a fight or a match of any kind
  send = { lockdown = true, kinds = { "Chat", "Encounter", "ChallengeMode", "PvPMatch" } },   -- add-on messages
}

local function restrictionActive(name)
  local enum = rawget(_G, "Enum") and Enum.AddOnRestrictionType
  local value = enum and enum[name]
  if value == nil then return false end
  return LF.In("C_RestrictedActions", "IsAddOnRestrictionActive", value) == true
end

---Why `what` can't happen now, or nil when it can. what: "combat" (protected frames), "fight" (the default: anything a
---player wouldn't want mid-fight, such as moving items or popups; combat, an encounter, M+ or a PvP match) or "send"
---(add-on messages: chat lockdown, or a restriction that covers them). Reasons: "combat", "lockdown" or a
---restriction's name ("Encounter", ...).
---@param what "combat"|"fight"|"send"|nil
---@return string|nil reason
function LF.Restricted(_, what)
  local spec = KINDS[what or "fight"] or KINDS.fight
  if spec.combat and InCombatLockdown and InCombatLockdown() then return "combat" end
  if spec.lockdown and LF.In("C_ChatInfo", "InChatMessagingLockdown") then return "lockdown" end
  for _, name in ipairs(spec.kinds or {}) do
    if restrictionActive(name) then return name end
  end
  return nil
end

-- the message LIBFOREVER_RESTRICTIONS_CHANGED, on the next frame, when combat or any restriction starts or ends, so
-- add-ons can hold work and resume it
LF.RESTRICTIONS_CHANGED = "LIBFOREVER_RESTRICTIONS_CHANGED"
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED" }) do
  LF:On(event, "LibForever.restrictions", function()
    LF:NextFrame(function() LF:Send(LF.RESTRICTIONS_CHANGED) end, "LibForever.restrictions")
  end)
end

-------------------------------------------------------------------------------------------
-- Chat and debug
-------------------------------------------------------------------------------------------

LF.PREFIX = "|cff9ec8ffLibForever|r"

---Prints "prefix: msg" to the default chat frame (prefix defaults to LF.PREFIX).
---@param msg any
---@param prefix string|nil
function LF.Print(_, msg, prefix)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage((prefix or LF.PREFIX) .. ": " .. tostring(msg))
  end
end

---Formats a debug line and hands it to the sink set with LF:SetDebugSink; does nothing (not even the formatting)
---without a sink, or while its isOn says no. A bad format is logged raw instead of raising.
---@param source any who's talking
---@param fmt string string.format's format
---@param ... any
function LF.Debug(_, source, fmt, ...)
  local sink = state.debugSink
  if not sink or (state.debugOn and not state.debugOn()) then return end
  local ok, text = pcall(string.format, fmt, ...)
  sink(tostring(source), ok and text or fmt)
end

---Where debug lines go: write(source, text) for each line, asked only while isOn() is true (when given). nil stops.
---@param write fun(source: string, text: string)|nil
---@param isOn (fun(): boolean)|nil
function LF.SetDebugSink(_, write, isOn)
  state.debugSink, state.debugOn = write, isOn
end
