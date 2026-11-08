-- /norg: the suite-wide command.

local Core = NorgannonCore

local HELP = {
  "/norg - open the NorgannonDB settings page (suite, versions, credits)",
  "/norg ui - the UI kit gallery",
  "/norg debug [show [n] | clear] - toggle or read the debug log",
  "/norg demo [off] - preview pins, compass and arrow with your quest log",
  "/norg compass [on | off | move | lock] - the objective compass",
  "/norg arrow off - dismiss the waypoint arrow",
  "/norg icons - the town service and gathering icons, and which source the client has",
  "/norg perf [seconds | stop | report] - measure the suite against its performance budgets (default 60 s)",
  "/norg mem [rate [seconds]] - memory per suite add-on and the Core's tables; rate: how fast each makes garbage",
  "/norg mappins - list what is drawn on the open world map (who draws which markers)",
  "/norg version",
}

local function printHelp()
  for _, line in ipairs(HELP) do Core:Print(line) end
end

local function openSettings() Core:OpenSettings() end
local function showGallery() Core:ShowGallery() end

local function demo(rest)
  if not Core:HasData() then
    Core:Print("the demo draws your quests from NorgannonDB, which isn't loaded")
    return
  end
  if rest == "off" then
    Core:Demo(false)
    Core:Print("demo pins cleared")
  else
    local n = Core:Demo(true)
    Core:Print(string.format("demo: %d pins from your quest log. Open the map, watch the minimap and compass; /norg demo off to clear.", n))
  end
end

local function compass(rest)
  if rest == "off" then
    Core.Compass:SetShown(false)
  elseif rest == "move" then
    Core.Compass:SetMovable(true)
    Core:Print("drag the compass, then /norg compass lock")
  elseif rest == "lock" then
    Core.Compass:SetMovable(false)
  else
    Core.Compass:SetShown(true)
  end
end

local function arrow() Core.Arrow:Clear("dismissed") end

-- read-only: the world map's pin pools (Blizzard's and add-ons') and how many are shown
local function mapPins()
  if not WorldMapFrame:IsShown() then
    Core:Print("open the world map first")
    return
  end
  local lines = {}
  for template, pool in pairs(WorldMapFrame.pinPools or {}) do
    local ok, n = pcall(pool.GetNumActive, pool)
    if ok and n and n > 0 then lines[#lines + 1] = string.format("%s: %d", tostring(template), n) end
  end
  table.sort(lines)
  Core:Print(string.format("world map %s: %d pin types", tostring(WorldMapFrame:GetMapID()), #lines))
  for _, line in ipairs(lines) do Core:Print("  " .. line) end
  Core:Print(string.format("  NorgannonDB layer: %d pins, %d glows", Core.Map.stats.world or 0, Core.Map.stats.clusters or 0))
end

local function perf(rest)
  if rest == "stop" then
    if not Core.Perf:Stop() then Core:Print("not measuring") end
  elseif rest == "report" then
    Core.Perf:Print()
  else
    Core.Perf:Start(tonumber(rest))
  end
end

local function mem(rest)
  local sub, n = rest:match("^(%S*)%s*(%d*)")
  if sub == "rate" then
    Core.Perf:MemoryRate(tonumber(n))
  else
    Core.Perf:Memory()
  end
end

local function icons()
  local keys = {}
  for key in pairs(Core.Map.SERVICE_ICONS) do keys[#keys + 1] = key end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local source, name = Core.Map.IconSource("service." .. key)
    local inline = source == "atlas" and ("|A:" .. name .. ":16:16|a") or ("|T" .. tostring(name) .. ":16:16|t")
    Core:Print(string.format("%s %s: %s (%s)", inline, key, source, tostring(name)))
  end
end

local function version()
  local info = NorgannonDB and NorgannonDB.info
  if not Core:HasData() then
    Core:Print(string.format("Core %s, without NorgannonDB's data", Core:Version()))
    return
  end
  Core:Print(string.format("Core %s, data %s (%s)", Core:Version(), info and info.generated or "?", info and info.build or "?"))
end

local function debugLog(rest)
  local db = Core.db
  if not db then return end
  local sub, n = rest:match("^(%S*)%s*(%d*)")
  if sub == "show" then
    local log, count = db.debugLog, tonumber(n) or 20
    for i = math.max(1, #log - count + 1), #log do Core:Print(log[i]) end
  elseif sub == "clear" then
    db.debugLog = {}
    Core:Print("debug log cleared")
  else
    db.debug = not db.debug
    Core:Print("debug log " .. (db.debug and "on" or "off"))
  end
end

local COMMANDS = {
  [""] = openSettings, about = openSettings, settings = openSettings,
  ui = showGallery, gallery = showGallery,
  demo = demo,
  compass = compass,
  arrow = arrow,
  mappins = mapPins,
  perf = perf,
  mem = mem,
  icons = icons,
  version = version,
  debug = debugLog,
}

SLASH_NORGANNONCORE1 = "/norg"
SlashCmdList["NORGANNONCORE"] = function(msg)
  local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
  local run = COMMANDS[string.lower(cmd or "")] or printHelp
  run(rest)
end
