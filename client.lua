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
