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
local SUITE = { "NorgannonDB", "NorgannonDB_Core", "Clairvoyance", "NorgannonDBCollector", "Oracle", "Archivum", "Foresight" }
Perf.BUDGET_AVG, Perf.BUDGET_FRAME = BUDGET_AVG, BUDGET_FRAME

---Registers a function to time while measuring: tbl[method], shown as label (grouped by addon).
function Core:RegisterPerf(label, tbl, method, addon)
  for _, e in ipairs(Perf.entries) do
    if e.tbl == tbl and e.method == method then return end
  end
  table.insert(Perf.entries, { label = label, tbl = tbl, method = method, addon = addon or "core" })
end

-------------------------------------------------------------------------------------------
-- Measuring
-------------------------------------------------------------------------------------------

local frame, depth = 0, 0          -- frames seen while measuring; nesting of timed calls
local frameSum, sumFrame = 0, -1   -- our top-level time in the current frame
local stats, totals

local function closeFrame()
  if sumFrame >= 0 and frameSum > totals.worst then totals.worst = frameSum end
  frameSum, sumFrame = 0, frame
end

local function wrap(e)
  local original = e.tbl[e.method]
  if type(original) ~= "function" then return end
  e.original = original
  local s = { calls = 0, total = 0, max = 0 }
  stats[e.label] = s
  e.tbl[e.method] = function(...)
    depth = depth + 1
    local start = debugprofilestop()
    local r = { pcall(original, ...) }
    local took = debugprofilestop() - start
    depth = depth - 1
    s.calls, s.total = s.calls + 1, s.total + took
    if took > s.max then s.max = took end
    if depth == 0 then
      -- only the outermost timed call counts toward the frame (no double counting)
      if sumFrame ~= frame then closeFrame() end
      frameSum = frameSum + took
      totals.total = totals.total + took
    end
    if not r[1] then error(r[2], 0) end
    return unpack(r, 2, table.maxn(r))
  end
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, dt)
  frame = frame + 1
  self.elapsed = (self.elapsed or 0) + dt
  if self.until_ and self.elapsed >= self.until_ then Perf:Stop() end
end)

---Starts measuring for `seconds` (default 60); the report prints when it ends.
function Perf:Start(seconds)
  if self.running then self:Stop(true) end
  stats, totals = {}, { total = 0, worst = 0 }
  frame, depth, frameSum, sumFrame = 0, 0, 0, -1
  for _, e in ipairs(self.entries) do wrap(e) end
  self.running = true
  self.started = GetTime()
  driver.elapsed, driver.until_ = 0, seconds or DEFAULT_SECONDS
  driver:Show()
  Core:Print(string.format("measuring for %d s: play normally (move, fight, open the map); /norg perf stop ends early", driver.until_))
end

local function memory()
  local out = {}
  if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
  local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
  local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
  for _, name in ipairs(SUITE) do
    if get and (not loaded or loaded(name)) then
      local ok, kb = pcall(get, name)
      if ok and type(kb) == "number" and kb > 0 then out[#out + 1] = { name = name, kb = kb } end
    end
  end
  return out
end

---Ends the measurement, puts every function back and reports (unless quiet).
function Perf:Stop(quiet)
  if not self.running then return nil end
  closeFrame()
  for _, e in ipairs(self.entries) do
    if e.original then e.tbl[e.method], e.original = e.original, nil end
  end
  driver:Hide()
  self.running = false
  local frames = math.max(1, frame)
  local report = {
    when = date and date("%Y-%m-%d %H:%M") or "", seconds = math.floor((GetTime() - (self.started or GetTime())) + .5),
    frames = frames, avg = totals.total / frames, worst = totals.worst, labels = {}, memory = memory(),
  }
  for _, e in ipairs(self.entries) do
    local s = stats[e.label]
    if s and s.calls > 0 then
      table.insert(report.labels, { label = e.label, addon = e.addon, calls = s.calls, total = s.total,
        perFrame = s.total / frames, avg = s.total / s.calls, max = s.max })
    end
  end
  table.sort(report.labels, function(a, b) return a.total > b.total end)
  report.avgOk, report.worstOk = report.avg < BUDGET_AVG, report.worst < BUDGET_FRAME
  self.last = report
  if Core.db then Core.db.perf = report end
  if not quiet then self:Print(report) end
  return report
end

local function ok(pass) return pass and "|cff40ff40OK|r" or "|cffff4040OVER|r" end

function Perf:Print(r)
  r = r or self.last
  if not r then Core:Print("no measurement yet: /norg perf [seconds]") return end
  Core:Print(string.format("%d s, %d frames: %.3f ms per frame on average (budget %d) %s; worst frame %.1f ms (budget %d) %s",
    r.seconds, r.frames, r.avg, BUDGET_AVG, ok(r.avgOk), r.worst, BUDGET_FRAME, ok(r.worstOk)))
  for i = 1, math.min(8, #r.labels) do
    local l = r.labels[i]
    Core:Print(string.format("  %s: %.3f ms/frame, %d calls, %.2f ms avg, %.1f ms max", l.label, l.perFrame, l.calls, l.avg, l.max))
  end
  local mem = {}
  for _, m in ipairs(r.memory) do mem[#mem + 1] = string.format("%s %.1f MB", m.name, m.kb / 1024) end
  if #mem > 0 then Core:Print("  memory: " .. table.concat(mem, ", ")) end
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
