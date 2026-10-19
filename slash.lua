-- /norg: the suite-wide command.

local Core = NorgannonCore

local HELP = {
  "/norg - open the NorgannonDB settings page (suite, versions, credits)",
  "/norg ui - the UI kit gallery",
  "/norg debug [show [n] | clear] - toggle or read the debug log",
  "/norg demo [off] - preview pins, compass and arrow with your quest log",
  "/norg compass [on | off | move | lock] - the objective compass",
  "/norg arrow off - dismiss the waypoint arrow",
  "/norg version",
}

SLASH_NORGANNONCORE1 = "/norg"
SlashCmdList["NORGANNONCORE"] = function(msg)
  local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
  cmd = string.lower(cmd or "")
  if cmd == "" or cmd == "about" or cmd == "settings" then
    Core:OpenSettings()
  elseif cmd == "ui" or cmd == "gallery" then
    Core:ShowGallery()
  elseif cmd == "demo" then
    if rest == "off" then
      Core:Demo(false)
      Core:Print("demo pins cleared")
    else
      local n = Core:Demo(true)
      Core:Print(string.format("demo: %d pins from your quest log. Open the map, watch the minimap and compass; /norg demo off to clear.", n))
    end
  elseif cmd == "compass" then
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
  elseif cmd == "arrow" then
    Core.Arrow:Clear("dismissed")
  elseif cmd == "version" then
    local info = NorgannonDB and NorgannonDB.info
    Core:Print(string.format("Core %s, data %s (%s)", Core:Version(), info and info.generated or "?", info and info.build or "?"))
  elseif cmd == "debug" then
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
  else
    for _, line in ipairs(HELP) do Core:Print(line) end
  end
end
