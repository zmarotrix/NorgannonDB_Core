-- Performance budgets, measured in game: /norg perf [seconds] times the suite's hot code while
-- you play, then reports against the budgets (docs/suite-plan.md): under 1 ms per frame on
-- average and no frame over 16 ms from our code, plus memory per addon. The last report is
-- saved (NorgannonCoreDB.perf) so it can be read outside the game.
--
-- Addons list what to time: Core:RegisterPerf("Tracker refresh", CV.Tracker, "Refresh", "clairvoyance").
-- Nothing is wrapped until a measurement starts, and everything is put back when it ends, so
-- the profiler costs nothing the rest of the time. Only functions called through their table are
-- timed (a local function or a stored reference isn't).

local Core = NorgannonCore

local Perf = { entries = {}, running = false }
Core.Perf = Perf

local BUDGET_AVG, BUDGET_FRAME = 1, 16           -- ms
local DEFAULT_SECONDS = 60
local REPORT_LINES = 8                           -- the heaviest functions a report prints
local SUITE_FOLDERS = { "NorgannonDB", "NorgannonDB_Core", "Clairvoyance", "NorgannonDBCollector", "Oracle", "Archivum", "Retrospect", "Dimension",
  "Council", "Muster", "Mercy", "Bulwark", "Guise" }

---Registers a function to time while measuring: tbl[method], shown as label (grouped by addon).
function Core:RegisterPerf(label, tbl, method, addon)
  for _, entry in ipairs(Perf.entries) do
    if entry.tbl == tbl and entry.method == method then return end
  end
  table.insert(Perf.entries, { label = label, tbl = tbl, method = method, addon = addon or "core" })
end

-------------------------------------------------------------------------------------------
-- Measuring
-------------------------------------------------------------------------------------------

local frameCount, depth = 0, 0        -- frames seen while measuring; nesting of timed calls
local frameTime, frameTimeOf = 0, -1  -- our top-level time so far in a frame, and which frame that is
local stats, totals

local function closeFrame()
  if frameTimeOf >= 0 and frameTime > totals.worst then totals.worst = frameTime end
  frameTime, frameTimeOf = 0, frameCount
end

-- Replaces a function with a timed copy. The original runs under pcall so that the timing is
-- still recorded when it errors; the error is then raised again for the caller. The results
-- pass through as varargs: a table per call here was charged to the Core's memory while
-- measuring (the compass alone is timed about 100 times a second).
local function wrap(entry)
  local original = entry.tbl[entry.method]
  if type(original) ~= "function" then return end
  entry.original = original
  local stat = { calls = 0, total = 0, max = 0 }
  stats[entry.label] = stat
  local function finish(start, ok, ...)
    local took = debugprofilestop() - start
    depth = depth - 1
    stat.calls, stat.total = stat.calls + 1, stat.total + took
    if took > stat.max then stat.max = took end
    if depth == 0 then
      -- only the outermost timed call counts toward the frame (no double counting)
      if frameTimeOf ~= frameCount then closeFrame() end
      frameTime = frameTime + took
      totals.total = totals.total + took
    end
    if not ok then error((...), 0) end
    return ...
  end
  entry.tbl[entry.method] = function(...)
    depth = depth + 1
    return finish(debugprofilestop(), pcall(original, ...))
  end
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, dt)
  frameCount = frameCount + 1
  self.elapsed = (self.elapsed or 0) + dt
  if self.stopAfter and self.elapsed >= self.stopAfter then Perf:Stop() end
end)

---Starts measuring for `seconds` (default 60); the report prints when it ends.
function Perf:Start(seconds)
  if self.running then self:Stop(true) end
  stats, totals = {}, { total = 0, worst = 0 }
  frameCount, depth, frameTime, frameTimeOf = 0, 0, 0, -1
  for _, entry in ipairs(self.entries) do wrap(entry) end
  self.running = true
  self.started = GetTime()
  driver.elapsed, driver.stopAfter = 0, seconds or DEFAULT_SECONDS
  driver:Show()
  Core:Print(string.format("measuring for %d s: play normally (move, fight, open the map); /norg perf stop ends early", driver.stopAfter))
end

-- Each suite add-on's memory in KB: { {name, kb}, ... }. The game's number includes garbage
-- not collected yet (an add-on that makes and drops many tables looks big until the collector
-- gets round to it); with `collect`, a full collection runs first and `garbage` says how much
-- of each add-on's number that was. A full collection is a short hitch, fine in a diagnostic.
local function memoryByAddon(collect)
  local out = {}
  local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  local function read()
    local kbs = {}
    if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
    for _, name in ipairs(SUITE_FOLDERS) do
      if get and (not loaded or loaded(name)) then
        local ok, kb = pcall(get, name)
        if ok and type(kb) == "number" and kb > 0 then kbs[name] = kb end
      end
    end
    return kbs
  end
  local before = read()
  local after = before
  if collect then
    collectgarbage("collect")
    after = read()
  end
  for _, name in ipairs(SUITE_FOLDERS) do
    if after[name] then
      out[#out + 1] = { name = name, kb = after[name], garbage = collect and math.max(0, (before[name] or 0) - after[name]) or nil }
    end
  end
  return out
end
Perf.MemoryByAddon = memoryByAddon

-- the measurement so far, in the shape saved to NorgannonCoreDB.perf
local function buildReport(entries, started)
  local frames = math.max(1, frameCount)
  local report = {
    when = date and date("%Y-%m-%d %H:%M") or "",
    seconds = math.floor((GetTime() - (started or GetTime())) + .5),
    frames = frames,
    avg = totals.total / frames,
    worst = totals.worst,
    labels = {},
    memory = memoryByAddon(true),
  }
  for _, entry in ipairs(entries) do
    local stat = stats[entry.label]
    if stat and stat.calls > 0 then
      table.insert(report.labels, {
        label = entry.label, addon = entry.addon, calls = stat.calls, total = stat.total,
        perFrame = stat.total / frames, avg = stat.total / stat.calls, max = stat.max,
      })
    end
  end
  table.sort(report.labels, function(a, b) return a.total > b.total end)
  report.avgOk, report.worstOk = report.avg < BUDGET_AVG, report.worst < BUDGET_FRAME
  return report
end

---Ends the measurement, puts every function back and reports (unless quiet).
function Perf:Stop(quiet)
  if not self.running then return nil end
  closeFrame()
  for _, entry in ipairs(self.entries) do
    if entry.original then entry.tbl[entry.method], entry.original = entry.original, nil end
  end
  driver:Hide()
  self.running = false
  local report = buildReport(self.entries, self.started)
  self.last = report
  if Core.db then Core.db.perf = report end
  if not quiet then self:Print(report) end
  return report
end

local function verdict(pass) return pass and "|cff40ff40OK|r" or "|cffff4040OVER|r" end

function Perf:Print(r)
  r = r or self.last
  if not r then Core:Print("no measurement yet: /norg perf [seconds]") return end
  Core:Print(string.format("%d s, %d frames: %.3f ms per frame on average (budget %d) %s; worst frame %.1f ms (budget %d) %s",
    r.seconds, r.frames, r.avg, BUDGET_AVG, verdict(r.avgOk), r.worst, BUDGET_FRAME, verdict(r.worstOk)))
  for i = 1, math.min(REPORT_LINES, #r.labels) do
    local l = r.labels[i]
    Core:Print(string.format("  %s: %.3f ms/frame, %d calls, %.2f ms avg, %.1f ms max", l.label, l.perFrame, l.calls, l.avg, l.max))
  end
  local mem = {}
  for _, m in ipairs(r.memory) do
    mem[#mem + 1] = string.format("%s %.1f MB", m.name, m.kb / 1024)
      .. (m.garbage and m.garbage >= 1024 and string.format(" (+%.1f MB garbage)", m.garbage / 1024) or "")
  end
  if #mem > 0 then Core:Print("  memory in use: " .. table.concat(mem, ", ")) end
end

-------------------------------------------------------------------------------------------
-- /norg mem: what the suite holds, and what the Core's big tables hold
-------------------------------------------------------------------------------------------

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

---Prints each suite add-on's memory (in use, and garbage waiting for the collector) and the
---sizes of the Core's run-time tables. Runs a full garbage collection (a short hitch).
function Perf:Memory()
  for _, m in ipairs(memoryByAddon(true)) do
    Core:Print(string.format("  %s: %.0f KB in use%s", m.name, m.kb,
      m.garbage and m.garbage >= 1 and string.format(", %.0f KB was garbage", m.garbage) or ""))
  end
  local index = Core.DB:IndexStats()
  local kinds = {}
  for _, kind in ipairs(Core.DB.KINDS) do
    kinds[#kinds + 1] = kind .. " " .. (index[kind] and tostring(index[kind]) or "not built")
  end
  Core:Print("  name index (built on first use): " .. table.concat(kinds, ", "))
  local m = Core.Map:MemoryStats()
  Core:Print(string.format("  map: %d pins from %d owners in %d areas, %d world positions cached, %d overlap keys; frames: %d world, %d minimap, %d glows",
    m.pins, m.owners, m.areas, m.worldPositions, m.overlapKeys, m.worldFrames, m.minimapFrames, m.glowFrames))
  Core:Print(string.format("  minimap: %s, %d of %d pins inside, %d drawn, nearest %s; view radius %s yd, your instance %s, pin instances %s",
    m.minimapState, m.minimapInside, m.minimapConsidered, m.minimapDrawn,
    m.minimapNearest and string.format("%.0f yd", m.minimapNearest) or "none",
    m.minimapRadius and string.format("%.0f", m.minimapRadius) or "?",
    tostring(m.minimapInstance), m.pinInstances ~= "" and m.pinInstances or "none"))
  local c = Core.Compass:MemoryStats()
  Core:Print(string.format("  compass: %d targets, %d marker frames", c.targets, c.markerFrames))
  Core:Print(string.format("  names: %d people by GUID, %d by first name; party progress from %d players",
    count(Core.Names.byGuid), count(Core.Names.byFirst), count(Core.Comms and Core.Comms.remote)))
end

---Measures how fast each suite add-on makes garbage: a full collection, then `seconds` of play
---(default 10) with the collector paused, then the growth per second. The collector restarts
---at the end; if the client refuses to pause it, the numbers can come out low.
---
---It also says where the Core's share comes from: the KB made inside every function on the
---Core's tables (Core, Core.UI, Core.Map, ...) and the timed add-on functions (the /norg perf
---list), each counted without what the other wrapped functions inside it made; and, per game
---event the Core dispatches for the suite, how many came and the KB made while its listeners ran. A game event's own arguments (UNIT_AURA's
---updateInfo table, for one) are made by the client as it hands the event to the Core's event
---frame, so they count against the Core but show in neither list: that's the "rest" line.
local RATE_LINES = 8

function Perf:MemoryRate(seconds)
  seconds = seconds or 10
  if self.rating then Core:Print("already measuring memory growth") return end
  self.rating = true
  local count = collectgarbage
  local events, functions = {}, {}
  local open = {}   -- event -> KB when its dispatch started (dispatches can nest)

  -- KB made inside each function, with the collector paused (exact). Each counts only its own:
  -- what wrapped functions it calls is taken off (a stack of what the callees made).
  local wrapped, seen = {}, {}
  local childKB, depth = {}, 0
  local function wrapOne(tbl, method, label)
    local original = rawget(tbl, method)
    if type(original) ~= "function" or seen[original] then return end
    seen[original] = true
    local stat = functions[label] or { kb = 0, calls = 0 }
    functions[label] = stat
    local function finish(before, ...)
      local inclusive = count("count") - before
      local own = inclusive - childKB[depth]
      depth = depth - 1
      if depth > 0 then childKB[depth] = childKB[depth] + inclusive end
      stat.kb, stat.calls = stat.kb + own, stat.calls + 1
      return ...
    end
    tbl[method] = function(...)
      depth = depth + 1
      childKB[depth] = 0
      return finish(count("count"), original(...))
    end
    wrapped[#wrapped + 1] = { tbl = tbl, method = method, original = original }
  end
  if not self.running then
    for _, entry in ipairs(self.entries) do wrapOne(entry.tbl, entry.method, entry.label) end
  end
  -- not the measuring itself, nor what must stay the same function while it runs
  local SKIP = { Perf = true, SetEventTap = true, MemoryRate = true, Memory = true, MemoryByAddon = true }
  local function wrapTable(tbl, prefix)
    for key, value in pairs(tbl) do
      if type(key) == "string" and not SKIP[key] and type(value) == "function" then
        wrapOne(tbl, key, prefix .. key)
      end
    end
  end
  wrapTable(Core, "Core:")
  for key, value in pairs(Core) do
    if type(key) == "string" and not SKIP[key] and type(value) == "table" and value ~= Core and not value.GetObjectType then
      wrapTable(value, "Core." .. key .. ":")
    end
  end

  -- the Core's own frame scripts, which no table reaches: KB made in each (with what it calls)
  local scripts = {}
  local hbd = LibStub and LibStub("HereBeDragons-NorgannonCore-2.0", true)
  local ctl = rawget(_G, "ChatThrottleLib")
  local FRAMES = {
    { "map driver", Core.Map.driver }, { "compass", Core.Compass.frame }, { "compass idle", Core.Compass.driver },
    { "arrow", Core.Arrow and Core.Arrow.frame }, { "HereBeDragons", hbd and hbd.eventFrame },
    { "ChatThrottleLib", ctl and ctl.Frame },
  }
  local swapped = {}
  for _, pair in ipairs(FRAMES) do
    local name, frame = pair[1], pair[2]
    if frame and frame.GetScript then
      for _, script in ipairs({ "OnUpdate", "OnEvent" }) do
        local original = frame:GetScript(script)
        if original then
          local stat = { kb = 0, calls = 0 }
          scripts[name .. " " .. script] = stat
          frame:SetScript(script, function(...)
            local before = count("count")
            original(...)
            stat.kb, stat.calls = stat.kb + count("count") - before, stat.calls + 1
          end)
          swapped[#swapped + 1] = { frame = frame, script = script, original = original }
        end
      end
    end
  end
  local frames = 0
  local ticker = CreateFrame("Frame")
  ticker:SetScript("OnUpdate", function() frames = frames + 1 end)

  local start = {}
  for _, m in ipairs(memoryByAddon(true)) do start[m.name] = m.kb end
  local startTotal, startTime = count("count"), GetTime()
  local paused = pcall(collectgarbage, "stop")
  Core:SetEventTap(function(event, starting)
    if starting then
      open[event] = count("count")
    elseif open[event] then
      local e = events[event]
      if not e then
        e = { n = 0, kb = 0 }
        events[event] = e
      end
      e.n, e.kb = e.n + 1, e.kb + count("count") - open[event]
      open[event] = nil
    end
  end)
  Core:Print(string.format("measuring memory growth for %d s: play normally (it starts with a full collection, a short hitch)", seconds))
  C_Timer.After(seconds, function()
    local total = count("count") - startTotal
    Core:SetEventTap(nil)
    ticker:SetScript("OnUpdate", nil)
    for _, w in ipairs(swapped) do w.frame:SetScript(w.script, w.original) end
    local took = math.max(.001, GetTime() - startTime)
    seconds = took
    for i = #wrapped, 1, -1 do
      local w = wrapped[i]
      w.tbl[w.method] = w.original
    end
    if paused then pcall(collectgarbage, "restart") end
    self.rating = nil
    local coreGrew = 0
    for _, m in ipairs(memoryByAddon(false)) do
      local grew = m.kb - (start[m.name] or m.kb)
      if m.name == "NorgannonDB_Core" then coreGrew = grew end
      Core:Print(string.format("  %s: %+.1f KB/s", m.name, grew / seconds))
    end
    if not paused then Core:Print("  (the collector couldn't be paused; it may have run meanwhile)") end
    Core:Print(string.format("  measured %.1f s, %d frames (%.0f fps); everything together grew %.1f KB/s",
      took, frames, frames / took, total / took))
    local lines = {}
    for name, stat in pairs(scripts) do
      if stat.calls > 0 then lines[#lines + 1] = { label = name, kb = stat.kb, n = stat.calls } end
    end
    table.sort(lines, function(a, b) return a.kb > b.kb end)
    Core:Print("  the Core's frame scripts (KB/s made in each, with what it called):")
    for _, l in ipairs(lines) do
      Core:Print(string.format("    %s: %.1f KB/s, %d calls", l.label, l.kb / took, l.n))
    end

    local list, inFunctions = {}, 0
    for label, stat in pairs(functions) do
      if stat.calls > 0 then list[#list + 1] = { label = label, kb = stat.kb, n = stat.calls } end
      inFunctions = inFunctions + stat.kb
    end
    table.sort(list, function(a, b) return a.kb > b.kb end)
    Core:Print("  the Core's functions and the timed ones (KB/s made in each, not counting the others it called):")
    for i = 1, math.min(RATE_LINES, #list) do
      Core:Print(string.format("    %s: %.1f KB/s, %d calls", list[i].label, list[i].kb / seconds, list[i].n))
    end
    list = {}
    local eventCount = 0
    for event, e in pairs(events) do
      list[#list + 1] = { label = event, kb = e.kb, n = e.n }
      eventCount = eventCount + e.n
    end
    table.sort(list, function(a, b) return a.n > b.n end)
    Core:Print(string.format("  game events the Core handed to the suite: %d (%.0f a second); the busiest, with KB/s their listeners made:",
      eventCount, eventCount / seconds))
    for i = 1, math.min(RATE_LINES, #list) do
      Core:Print(string.format("    %s: %d (%.0f/s), %.1f KB/s", list[i].label, list[i].n, list[i].n / seconds, list[i].kb / seconds))
    end
    Core:Print(string.format("  the Core grew %.1f KB/s; the functions above made %.1f KB/s; the rest is code the Core's tables don't reach (local functions, frame scripts) and game events' own arguments",
      coreGrew / seconds, inFunctions / seconds))
  end)
end

-------------------------------------------------------------------------------------------
-- The Core's own hot paths
-------------------------------------------------------------------------------------------

Core:OnLogin(function()
  Core:RegisterPerf("Map: world map pins", Core.Map, "RefreshWorld")
  Core:RegisterPerf("Map: minimap pins", Core.Map, "RefreshMinimap")
  Core:RegisterPerf("Map: new pin sets", Core.Map, "SetPins")
  Core:RegisterPerf("Compass", Core.Compass, "Update")
  Core:RegisterPerf("Arrow", Core.Arrow, "Update")
  Core:RegisterPerf("Quest log scan", Core.Player, "Refresh")
  Core:RegisterPerf("Database search", Core.DB, "Search")
  Core:RegisterPerf("Party messages", Core.Comms, "OnCommReceived")
end)
