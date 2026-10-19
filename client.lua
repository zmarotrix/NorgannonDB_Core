-- Client layer: which client this is, secret-value safety and the combat lockdown queue.
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

local queue, queued = {}, {}

---Runs fn now, or once combat ends. A key replaces an earlier queued call with the same key,
---so repeated requests (e.g. "re-anchor the tracker") run only once.
function Core:AfterCombat(fn, key)
  if not InCombatLockdown() then
    Core.SafeCall(fn)
    return true
  end
  if key and queued[key] then
    queue[queued[key]] = fn
  else
    table.insert(queue, fn)
    if key then queued[key] = #queue end
  end
  return false
end

Core:On("PLAYER_REGEN_ENABLED", "combatQueue", function()
  local pending = queue
  queue, queued = {}, {}
  for _, fn in ipairs(pending) do Core.SafeCall(fn) end
end)

---fn on the next frame (coalesces bursts of events into one update when given a key).
local nextFrame = {}
function Core:NextFrame(fn, key)
  if key then
    if nextFrame[key] then return end
    nextFrame[key] = true
  end
  C_Timer.After(0, function()
    if key then nextFrame[key] = nil end
    Core.SafeCall(fn)
  end)
end
