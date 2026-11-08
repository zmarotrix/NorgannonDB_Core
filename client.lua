-- Client layer: which client this is, secret-value safety, the combat lockdown queue and
-- next-frame scheduling.
-- WoW Forever runs Classic content on the modern client (interface 16000-16999). Some values
-- are "secret" in combat and instances: they may be passed along but never compared or used
-- in a branch, so everything that reads unit or quest data goes through these helpers.

local Core = NorgannonCore

local interface = select(4, GetBuildInfo())
Core.client = {
  interface = interface,
  isForever = interface >= 16000 and interface < 17000,
  locale = GetLocale(),
}

---true if v is a secret value (or a table holding them) that must not be inspected.
function Core.IsSecret(v)
  if issecretvalue and issecretvalue(v) then return true end
  if type(v) == "table" and issecrettable and issecrettable(v) then return true end
  return false
end

---v, or fallback when v is secret.
function Core.Safe(v, fallback)
  if Core.IsSecret(v) then return fallback end
  return v
end

-------------------------------------------------------------------------------------------
-- Calling the client (1.19). The API docs list calls for every game flavour, so any of them may
-- be missing on Forever, refuse (error), or answer in secret values. These are the suite's one
-- way to call it; add-ons used to carry their own copies.
-------------------------------------------------------------------------------------------

---The client function ns.name, or the global name when ns is nil; nil if the client lacks it.
function Core.Fn(ns, name)
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
function Core.Has(ns, name) return Core.Fn(ns, name) ~= nil end

---fn(...) through pcall: ok, ... with the answer exactly as it came, secrets included. For handing values to
---widgets that accept secrets. ok is false when fn is missing or errored.
function Core.Call(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function plain(ok, ...)
  if not ok then return nil end
  local n = select("#", ...)
  if n == 0 then return nil end
  local out = { ... }
  for i = 1, n do
    if Core.IsSecret(out[i]) then out[i] = nil end
  end
  return unpack(out, 1, n)
end

---fn(...) with every secret value turned into nil, and nil when fn is missing or errored: for logic that branches.
function Core.Plain(fn, ...)
  if type(fn) ~= "function" then return nil end
  return plain(pcall(fn, ...))
end

---The global client function name(...), through Core.Plain.
function Core.Global(name, ...) return Core.Plain(Core.Fn(nil, name), ...) end

---The namespaced client function ns.name(...), through Core.Plain: Core.In("C_Bank", "CanViewBank").
function Core.In(ns, name, ...) return Core.Plain(Core.Fn(ns, name), ...) end

---obj:method(...) where the arguments may be secret (a widget that accepts them): false if the client refused.
function Core.SetSecret(obj, method, ...)
  local fn = obj and obj[method]
  if type(fn) ~= "function" then return false end
  return (pcall(fn, obj, ...))
end

---The server's time (seconds), else the computer's.
function Core.Now() return Core.Global("GetServerTime") or time() end

-------------------------------------------------------------------------------------------
-- Combat lockdown: protected work waits for the end of combat
-------------------------------------------------------------------------------------------

local queue, slotOfKey = {}, {}   -- fn, ... in order; key -> that key's place in the queue

---Runs fn now, or once combat ends. A key replaces an earlier queued call with the same key,
---so repeated requests (e.g. "re-anchor the tracker") run only once.
function Core:AfterCombat(fn, key)
  if not InCombatLockdown() then
    Core.SafeCall(fn)
    return true
  end
  if key and slotOfKey[key] then
    queue[slotOfKey[key]] = fn
  else
    table.insert(queue, fn)
    if key then slotOfKey[key] = #queue end
  end
  return false
end

Core:On("PLAYER_REGEN_ENABLED", "combatQueue", function()
  local pending = queue
  queue, slotOfKey = {}, {}
  for _, fn in ipairs(pending) do Core.SafeCall(fn) end
end)

-------------------------------------------------------------------------------------------
-- Minimap shapes: which quadrants of the minimap are round, for the map layer and the buttons
-------------------------------------------------------------------------------------------

local MINIMAP_SHAPES = {
  -- { upper-left, lower-left, upper-right, lower-right }
  ["SQUARE"] = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { true, false, false, false }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { false, false, false, true },
  ["SIDE-LEFT"] = { true, true, false, false }, ["SIDE-RIGHT"] = { false, false, true, true },
  ["SIDE-TOP"] = { true, false, true, false }, ["SIDE-BOTTOM"] = { false, true, false, true },
  ["TRICORNER-TOPLEFT"] = { true, true, true, false }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { false, true, true, true },
}

---The minimap's shape for Core.IsMinimapRoundAt, or nil for a plain round minimap.
function Core.MinimapShape()
  return GetMinimapShape and MINIMAP_SHAPES[GetMinimapShape() or "ROUND"]
end

---Whether a shape is round at a point (x right, y up, from the minimap's centre).
function Core.IsMinimapRoundAt(shape, x, y)
  local column = x < 0 and 1 or 3
  if y > 0 then return shape[column] end
  return shape[column + 1]
end

-------------------------------------------------------------------------------------------
-- Next frame
-------------------------------------------------------------------------------------------

local scheduled = {}   -- keys waiting for their next-frame call

---fn on the next frame (coalesces bursts of events into one update when given a key).
function Core:NextFrame(fn, key)
  if key then
    if scheduled[key] then return end
    scheduled[key] = true
  end
  C_Timer.After(0, function()
    if key then scheduled[key] = nil end
    Core.SafeCall(fn)
  end)
end
