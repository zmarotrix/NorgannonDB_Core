-- Core:NewAddon (1.19): one call that makes an add-on part of the suite. It replaces the ~100 lines every suite add-on
-- used to write by hand: the version check, the chat prefix, saved variables with defaults and migrations, the registry,
-- the minimap flyout row, the game's add-on menu (compartment), the slash command and opening its settings page.
--
--   local Core = NorgannonCore
--   if not (Core and Core.NewAddon) then print("Template needs NorgannonDB Core 1.19 or newer; it is turned off.") return end
--   local A = Core:NewAddon("template", {
--     folder = ..., api = { 1, 19 },
--     db = "TemplateDB", defaults = { shown = true }, version = 1,
--     slash = { "/template" }, commands = { reset = { function() ... end, "put the window back" } },
--   })
--   if A.disabled then return end
--
-- docs/dev/getting-started.md walks through it; templates/NorgannonTemplate is a working example.

local Core = NorgannonCore
local UI = Core.UI

-------------------------------------------------------------------------------------------
-- Saved variables: defaults, a version and migrations
-------------------------------------------------------------------------------------------

local function fill(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then
      if type(v) == "table" then
        target[k] = {}
        fill(target[k], v)
      else
        target[k] = v
      end
    elseif type(v) == "table" and type(target[k]) == "table" then
      fill(target[k], v)
    end
  end
  return target
end
Core.FillDefaults = fill

---Loads the saved variable `name` (call it at or after its add-on's ADDON_LOADED): runs each migration it hasn't had,
---fills in missing defaults (deep; a player's own values always stay) and stores the version in `_v`.
---opts = { defaults = {}, version = 1, migrate = { [2] = function(sv) ... end } }. Saves from before versioning count as
---version 1; a brand-new save starts at `version` and runs no migration. Returns the table, which is also _G[name].
function Core:SavedVars(name, opts)
  opts = opts or {}
  local saved = rawget(_G, name)
  local fresh = type(saved) ~= "table" or next(saved) == nil
  local sv = type(saved) == "table" and saved or {}
  local version = opts.version or 1
  local from = tonumber(sv._v) or (fresh and version or 1)
  if from > version then
    Core:Debug(name, "saved at version %d, newer than this add-on's %d: left as it is", from, version)
  end
  for v = from + 1, version do
    local step = opts.migrate and opts.migrate[v]
    if step then
      local ok, err = pcall(step, sv)
      if not ok then Core:Debug(name, "migration to %d failed: %s", v, tostring(err)) end
    end
  end
  if (tonumber(sv._v) or 0) < version then sv._v = version end
  fill(sv, opts.defaults or {})
  _G[name] = sv
  return sv
end

-------------------------------------------------------------------------------------------
-- The add-on object
-------------------------------------------------------------------------------------------

local function metadata(folder, field)
  local fn = Core.Fn("C_AddOns", "GetAddOnMetadata") or Core.Fn(nil, "GetAddOnMetadata")
  if not fn then return nil end
  local ok, value = pcall(fn, folder, field)
  return ok and value or nil
end

local function clickHint(A, mm)
  local left = mm.clickHint or (A.Toggle and "open or close" or "settings")
  local parts = { "Click: " .. left }
  if mm.shiftHint then parts[#parts + 1] = "Shift-click: " .. mm.shiftHint end
  if not (mm.rightHint == false) then parts[#parts + 1] = "Right-click: " .. (mm.rightHint or "settings") end
  parts[#parts + 1] = "Drag: move"
  return table.concat(parts, "  ·  ")
end

---Makes an add-on part of the suite. key is its registry key ("muster"); an add-on outside the suite passes name,
---accent ("rrggbb"), role and mark (a texture path) to be listed beside it. Returns the add-on table A (also the global
---opts.global or the folder name). If this Core or NorgannonDB can't serve it, A.disabled is true and the player is told
---why once, in chat: stop loading the add-on's files then.
---
---opts:
---  folder            the add-on's folder (pass `...`'s first value); defaults to the registry's
---  api = {1, 19}     the Core API it was written for
---  data = {1, 4}     NorgannonDB's schema it needs, if it reads the game data (list NorgannonDB in the TOC too)
---  db, defaults, version, migrate                 account-wide saved variable (Core:SavedVars)
---  char, charDefaults, charVersion, charMigrate   per-character saved variable
---  slash = {"/x", ...}, commands = { name = fn(rest) | { fn(rest), "what it does" } }
---  minimap = false | { onClick(button)?, onShiftClick()?, status()? -> a live line, clickHint?, shiftHint?, rightHint? }
---
---A gets: key, name, addonName, info, PREFIX, ACCENT, ready, db, char; :Print, :Debug, :Send, :Listen (messages prefixed
---KEY_), :OnReady(fn) (saved variables loaded), :OnLogin(fn), :AddSettingsPage(frame), :OpenSettings(), :RunCommand(msg),
---:PrintHelp(). Define A:Toggle() for the main action (left-click, /x with nothing after it); without one, left-click opens
---settings. Define your own A:OpenSettings() after NewAddon for a settings window of your own.
function Core:NewAddon(key, opts)
  opts = opts or {}
  local known = Core:GetAddonInfo(key)
  local folder = opts.folder or (known and known.folder) or key
  local info = known or Core:DefineAddon({
    key = key, name = opts.name or folder, folder = folder, accent = opts.accent or "e7c66c", role = opts.role or "",
    slash = opts.slash and opts.slash[1], mark = opts.mark, external = true,
  })
  local name = info.name
  local global = opts.global or folder

  local A = type(rawget(_G, global)) == "table" and rawget(_G, global) or {}
  _G[global] = A
  A.key, A.name, A.addonName, A.info = key, name, folder, info
  A.PREFIX = "|cff" .. info.accent .. name .. "|r"
  A.ACCENT = UI.Hex(info.accent)

  function A:Print(msg) Core:Print(msg, self.PREFIX) end
  function A:Debug(fmt, ...) Core:Debug(key, fmt, ...) end

  -- Can this Core, and the data, serve it?
  local api = opts.api or { Core.VERSION_MAJOR, 0 }
  local why = Core:RequireMessage(name, api[1], api[2])
  if not why and opts.data then
    local DB = rawget(_G, "NorgannonDB")
    if not (type(DB) == "table" and DB.RequireSchema and DB:RequireSchema(opts.data[1], opts.data[2] or 0)) then
      why = string.format("%s needs NorgannonDB %d.%d or newer, the game data; it is turned off.", name, opts.data[1], opts.data[2] or 0)
    end
  end
  if why then
    A.disabled = true
    Core:OnLogin(function()
      if C_Timer and C_Timer.After then C_Timer.After(3, function() A:Print(why) end) else A:Print(why) end
    end)
    return A
  end
  if Core:IsDeprecated(api[1]) then Core:Debug(key, "written for Core API %d.x, served through a compatibility shim", api[1]) end

  -- Messages inside the add-on ride on the Core's bus, prefixed with its key
  local MSG = string.upper(key) .. "_"
  function A:Send(msg, ...) Core:Send(MSG .. msg, ...) end
  function A:Listen(msg, owner, fn) Core:Listen(MSG .. msg, owner, fn) end
  function A:Unlisten(msg, owner) Core:Unlisten(MSG .. msg, owner) end

  -- Load order
  local readyQueue = {}
  function A:OnReady(fn)
    if self.ready then Core.SafeCall(fn) else readyQueue[#readyQueue + 1] = fn end
  end
  function A:OnLogin(fn) Core:OnLogin(fn) end

  local owner = "addon:" .. key
  Core:On("ADDON_LOADED", owner, function(_, loaded)
    if loaded ~= folder then return end
    Core:Off("ADDON_LOADED", owner)
    if opts.db then
      A.db = Core:SavedVars(opts.db, { defaults = opts.defaults, version = opts.version, migrate = opts.migrate })
    end
    if opts.char then
      A.char = Core:SavedVars(opts.char, { defaults = opts.charDefaults, version = opts.charVersion or opts.version,
        migrate = opts.charMigrate })
    end
    A.ready = true
    local queue = readyQueue
    readyQueue = nil
    for _, fn in ipairs(queue) do Core.SafeCall(fn) end
  end)

  Core:RegisterAddon(key, { version = metadata(folder, "Version") or "0.0.0" })

  -- Settings
  function A:AddSettingsPage(frame)
    self.settingsCategory = Core:AddSettingsPage(frame, name)
    return self.settingsCategory
  end
  function A:OpenSettings()
    if InCombatLockdown and InCombatLockdown() then
      -- the game's Settings window can't open in combat: it opens when the fight ends
      self:Print("Settings open when this fight ends.")
      Core:AfterCombat(function() self:OpenSettings() end, owner .. ":settings")
      return
    end
    local category = self.settingsCategory or Core.settingsCategory
    if category and Settings and Settings.OpenToCategory then pcall(Settings.OpenToCategory, category:GetID()) end
  end

  -- Slash command: "/x" alone is the main action, "/x settings" and "/x help" always work
  A.commands = opts.commands or {}
  function A:PrintHelp()
    local slash = opts.slash and opts.slash[1] or ("/" .. key)
    local names = {}
    for cmd in pairs(self.commands) do if cmd ~= "" then names[#names + 1] = cmd end end
    table.sort(names)
    self:Print(slash .. (self.Toggle and " - open or close" or " - settings"))
    for _, cmd in ipairs(names) do
      local entry = self.commands[cmd]
      local text = type(entry) == "table" and entry[2]
      self:Print(slash .. " " .. cmd .. (text and (" - " .. text) or ""))
    end
    if not self.commands.settings then self:Print(slash .. " settings - the settings page") end
  end
  function A:RunCommand(msg)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = string.lower(cmd or "")
    local entry = self.commands[cmd]
    if entry then
      local fn = type(entry) == "table" and entry[1] or entry
      return fn(rest)
    end
    if cmd == "" then
      if self.Toggle then return self:Toggle() end
      return self:OpenSettings()
    end
    if cmd == "settings" or cmd == "options" or cmd == "config" then return self:OpenSettings() end
    self:PrintHelp()
  end
  if opts.slash then
    local id = string.upper(folder):gsub("[^%w]", "")
    for i, text in ipairs(opts.slash) do _G["SLASH_" .. id .. i] = text end
    SlashCmdList[id] = function(msg) A:RunCommand(msg) end
  end

  -- The minimap flyout row (and own button when pinned), and the game's add-on menu
  if opts.minimap ~= false then
    local mm = type(opts.minimap) == "table" and opts.minimap or {}
    local function onClick(button)
      if not A.ready then return end
      if mm.onClick then return mm.onClick(button) end
      if button == "RightButton" then return A:OpenSettings() end
      if mm.onShiftClick and IsShiftKeyDown and IsShiftKeyDown() then return mm.onShiftClick() end
      if A.Toggle then return A:Toggle() end
      A:OpenSettings()
    end
    local function tooltip(tt)
      local c = A.ACCENT
      tt:AddLine(name, c[1], c[2], c[3])
      if info.role and info.role ~= "" then tt:AddLine(info.role, 1, 1, 1) end
      if mm.status then
        local ok, line = pcall(mm.status)
        if ok and line and line ~= "" then tt:AddLine(line, c[1], c[2], c[3]) end
      end
      local h = UI.C.muted
      tt:AddLine(clickHint(A, mm), h[1], h[2], h[3])
    end
    A.MinimapClick, A.MinimapTooltip = onClick, tooltip
    Core:OnLogin(function() Core.MinimapButton:Add(key, { onClick = onClick, tooltip = tooltip }) end)
    _G[global .. "_OnAddonCompartmentClick"] = function(_, button) onClick(button) end
    _G[global .. "_OnAddonCompartmentEnter"] = function(_, frame)
      GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
      tooltip(GameTooltip)
      GameTooltip:Show()
    end
    _G[global .. "_OnAddonCompartmentLeave"] = function() GameTooltip:Hide() end
  end

  return A
end
