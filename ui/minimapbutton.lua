-- The suite on the minimap: one Norgannon button whose flyout lists every suite addon (mark,
-- name, a status line from its tooltip; clicks go to the addon as if its own button was clicked),
-- and, for addons the player pins, the addon's own round button as before. Every button is the
-- standard round minimap button (the game's border and background), dragged anywhere around the
-- minimap's edge (square and rounded shapes respected), its place saved in NorgannonCoreDB.minimap.
--
--   Core.MinimapButton:Add("oracle", {
--     tooltip = function(tt) tt:AddLine("Oracle") end,
--     onClick = function(button) ... end,       -- "LeftButton" / "RightButton"; shift is the caller's to read
--   })
--   Core.MinimapButton:SetShown("oracle", false)   -- the addon's "Show the minimap button" setting:
--                                                  -- pins (or unpins) its own button; it stays in the flyout
--
-- MinimapButton.buttons[key] is the frame the addon's button is on screen: its own button when
-- pinned, else the Norgannon button (so a popup anchored to it opens somewhere visible).

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

local MB = { pins = {}, entries = {} }
Core.MinimapButton = MB

local SIZE = 32          -- the game tracking button's size
local RING_GAP = 10      -- pixels between the minimap's edge and a button's centre
local MAIN_ANGLE = 225
local DEFAULT_ANGLE = 225
local DEFAULT_ANGLES = { clairvoyance = 200, oracle = 225, retrospect = 250, archivum = 275 }
local ROW_H, FLYOUT_W, PAD = 36, 250, 6
local TEXT_W = FLYOUT_W - 1 - 6 - 24 - 8 - 4 - 20 - 6 - 1   -- between the mark and the pin

-------------------------------------------------------------------------------------------
-- Saved settings: NorgannonCoreDB.minimap = { v = 2, angle, hidden, addons = { [key] = { angle, pinned } } }
-------------------------------------------------------------------------------------------

---Up to Core 1.17 the table held one entry per addon ({ angle, hidden }). Their places are kept
---for when the addon is pinned; everything starts unpinned (the old "hidden" meant the same).
function MB.Migrate(m)
  if m.v == 2 then return m end
  local addons = {}
  for key, old in pairs(m) do
    if type(old) == "table" then addons[key] = { angle = old.angle } end
  end
  for key in pairs(m) do m[key] = nil end
  m.v, m.addons = 2, addons
  return m
end

local function store()
  local db = Core.db
  if not db then MB.scratch = MB.scratch or { v = 2, addons = {} } return MB.scratch end
  db.minimap = MB.Migrate(db.minimap or { v = 2, addons = {} })
  return db.minimap
end

local function addonSettings(key)
  local addons = store().addons
  addons[key] = addons[key] or {}
  return addons[key]
end

-------------------------------------------------------------------------------------------
-- Placing and dragging a round button around the minimap
-------------------------------------------------------------------------------------------

---Where a button at this angle (degrees, 0 = right, counter-clockwise) sits from the minimap's
---centre: on the circle in round quadrants, on the square's edge in square ones.
function MB.Offset(angle)
  local a = math.rad(angle)
  local x, y = math.cos(a), math.sin(a)
  local shape = Core.MinimapShape()
  local w = (Minimap:GetWidth() or 140) / 2 + RING_GAP
  local h = (Minimap:GetHeight() or 140) / 2 + RING_GAP
  if not shape or Core.IsMinimapRoundAt(shape, x, y) then
    return x * w, y * h
  end
  -- a square corner: push out along the angle as far as a corner reaches, then clamp to the sides
  local diag = math.sqrt(2 * w * w)
  return math.max(-w, math.min(x * diag, w)), math.max(-h, math.min(y * diag, h))
end

local function place(b)
  local x, y = MB.Offset(b.settings().angle or b.defaultAngle)
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function dragUpdate(b)
  local mx, my = Minimap:GetCenter()
  if not mx then return end
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  b.settings().angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
  place(b)
  if b.onMoved then b.onMoved() end
end

-- the game's own tracking button's geometry: the ring's circle isn't centred in its texture,
-- so the dark disc and the mark are placed from the top-left, as the game places them
-- (measured in game: the ring's centre is at 17, -16)
local function roundButton(name, mark, settings, defaultAngle, onClick, onEnter)
  local b = CreateFrame("Button", name, Minimap)
  b.settings, b.defaultAngle = settings, defaultAngle
  b:SetSize(SIZE, SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b.background = b:CreateTexture(nil, "BACKGROUND")
  b.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  b.background:SetSize(24, 24)
  b.background:SetPoint("TOPLEFT", 5, -4)
  b.icon = UI.Mark(b, mark, 22, "ARTWORK")
  b.icon:ClearAllPoints()
  b.icon:SetPoint("TOPLEFT", 6, -5)
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b.border:SetSize(54, 54)
  b.border:SetPoint("TOPLEFT")
  b:SetScript("OnClick", function(self, button) onClick(self, button) end)
  b:SetScript("OnDragStart", function(self)
    self.dragging = true
    GameTooltip:Hide()
    self:SetScript("OnUpdate", dragUpdate)
  end)
  b:SetScript("OnDragStop", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
  end)
  b:SetScript("OnEnter", function(self)
    if self.dragging then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    onEnter(self)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place(b)
  return b
end

-------------------------------------------------------------------------------------------
-- Reading an addon's tooltip: the flyout's status line, and its hover tooltip
-------------------------------------------------------------------------------------------

local function isHint(text)
  return text:find("[Cc]lick:") or text:find("Drag:")
end

---The lines an addon's tooltip function adds, as { text, r, g, b, right, rr, rg, rb }.
function MB.TooltipLines(key)
  local entry = MB.entries[key]
  local lines = {}
  if not (entry and entry.tooltip) then return lines end
  local tt = setmetatable({}, { __index = function() return function() end end })
  function tt:AddLine(text, r, g, b) lines[#lines + 1] = { tostring(text or ""), r, g, b } end
  function tt:AddDoubleLine(left, right, r, g, b, rr, rg, rb)
    lines[#lines + 1] = { tostring(left or ""), r, g, b, right and tostring(right), rr, rg, rb }
  end
  function tt:SetText(text, r, g, b) lines = { { tostring(text or ""), r, g, b } } end
  function tt:NumLines() return #lines end
  pcall(entry.tooltip, tt)
  return lines
end

---The flyout's status line for an addon: the last line of its tooltip that is neither its name
---nor a click hint (a live status like "3 replies wait for you" comes after the role line), else
---the role from the suite registry. Returns text, colour.
function MB:Status(key)
  local lines = MB.TooltipLines(key)
  for i = #lines, 2, -1 do
    local line = lines[i]
    if line[1] ~= "" and not isHint(line[1]) then
      local plain = line[2] == nil or (line[2] == 1 and line[3] == 1 and line[4] == 1)
      return line[1], plain and C.muted or { line[2], line[3], line[4] }
    end
  end
  local info = Core:GetAddonInfo(key)
  return info and info.role or "", C.muted
end

-- the addon's tooltip, less "Drag: move" (a row in the flyout doesn't drag)
local function showTooltip(key)
  for _, line in ipairs(MB.TooltipLines(key)) do
    local text = line[1]:gsub("%s*·%s*Drag: move", ""):gsub("^Drag: move%s*·%s*", "")
    if text ~= "Drag: move" then
      if line[5] then
        GameTooltip:AddDoubleLine(text, line[5], line[2], line[3], line[4], line[6], line[7], line[8])
      else
        GameTooltip:AddLine(text, line[2], line[3], line[4])
      end
    end
  end
end

-------------------------------------------------------------------------------------------
-- Addons
-------------------------------------------------------------------------------------------

local ORDER = {}
for i, info in ipairs(Core.SUITE) do ORDER[info.key] = i end

---Registered addon keys in the suite's order (anything else after, by name).
function MB:Keys()
  local keys = {}
  for key in pairs(self.entries) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    local oa, ob = ORDER[a] or 1000, ORDER[b] or 1000
    if oa ~= ob then return oa < ob end
    return a < b
  end)
  return keys
end

---A click on an addon, from its own button or its row in the flyout.
function MB:Click(key, button)
  local entry = self.entries[key]
  if entry and entry.onClick then Core.SafeCall(entry.onClick, button) end
end

---Registers an addon (opts: tooltip(tt), onClick(button)); returns its own round button, which
---is shown only while the addon is pinned.
function MB:Add(key, opts)
  if self.entries[key] then return self.pins[key] end
  self.entries[key] = opts or {}
  local b = roundButton("NorgannonMinimapButton_" .. key, key, function() return addonSettings(key) end,
    DEFAULT_ANGLES[key] or DEFAULT_ANGLE,
    function(_, button) MB:Click(key, button) end,
    function() local e = MB.entries[key] if e.tooltip then e.tooltip(GameTooltip) end end)
  b.key = key
  self.pins[key] = b
  b:SetShown(self:IsPinned(key))
  self:Update()
  Core:Send("NORGANNON_MINIMAP_CHANGED", key)
  return b
end

function MB:IsPinned(key) return addonSettings(key).pinned == true end

---Pins an addon's own button to the minimap (saved); it stays in the flyout either way.
function MB:SetPinned(key, on)
  addonSettings(key).pinned = on and true or nil
  local b = self.pins[key]
  if b then b:SetShown(on and true or false) end
  self:Update()
  Core:Send("NORGANNON_MINIMAP_CHANGED", key)
end

-- every addon's "Show the minimap button" setting: its own button on the minimap means pinned
function MB:SetShown(key, on) self:SetPinned(key, on) end
function MB:IsShown(key) return self:IsPinned(key) end

MB.buttons = setmetatable({}, { __index = function(_, key)
  local own = MB.pins[key]
  if not own then return nil end
  if own:IsShown() then return own end
  return MB.main and MB.main:IsShown() and MB.main or own
end })

-------------------------------------------------------------------------------------------
-- The Norgannon button and its flyout
-------------------------------------------------------------------------------------------

function MB:IsMainShown() return not store().hidden end

---Shows or hides the Norgannon button (saved). Pinned buttons stay either way.
function MB:SetMainShown(on)
  store().hidden = not on or nil
  self:Update()
end

local function mainTooltip()
  local n = #MB:Keys()
  GameTooltip:AddLine("NorgannonDB", C.goldSoft[1], C.goldSoft[2], C.goldSoft[3])
  GameTooltip:AddLine(n == 1 and "1 add-on of the suite" or (n .. " add-ons of the suite"), 1, 1, 1)
  GameTooltip:AddLine("Click: the list  ·  Right-click: settings  ·  Drag: move", .43, .4, .32)
end

local function pinTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  local name = self.row.name:GetText()
  if MB:IsPinned(self.row.key) then
    GameTooltip:AddLine("Pinned to the minimap", 1, 1, 1)
    GameTooltip:AddLine("Click to unpin: " .. name .. " stays in this list.", C.muted[1], C.muted[2], C.muted[3])
  else
    GameTooltip:AddLine("Pin to the minimap", 1, 1, 1)
    GameTooltip:AddLine(name .. " gets its own button as well.", C.muted[1], C.muted[2], C.muted[3])
  end
  GameTooltip:Show()
end

local function newRow(flyout)
  local row = CreateFrame("Button", nil, flyout)
  row:SetHeight(ROW_H)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.hover = row:CreateTexture(nil, "BACKGROUND")
  row.hover:SetAllPoints()
  row.hover:SetColorTexture(1, 1, 1, .06)
  row.hover:Hide()
  row.mark = UI.Mark(row, "core", 24)
  row.mark:SetPoint("LEFT", 6, 0)
  row.pin = CreateFrame("Button", nil, row)
  row.pin:SetSize(20, 20)
  row.pin:SetPoint("RIGHT", -6, 0)
  row.pin.row = row
  row.pin.icon = UI.Icon(row.pin, "pin", 14)
  row.pin.icon:SetPoint("CENTER")
  row.name = UI.Text(row, "title", 14)
  row.name:SetPoint("TOPLEFT", row.mark, "TOPRIGHT", 8, 2)
  row.name:SetWidth(TEXT_W)
  row.name:SetJustifyH("LEFT")
  row.status = UI.Text(row, "body", 12, C.muted)
  row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
  row.status:SetWidth(TEXT_W)
  row.status:SetJustifyH("LEFT")
  row.status:SetWordWrap(false)
  row:SetScript("OnClick", function(self, button)
    flyout:Hide()
    MB:Click(self.key, button)
  end)
  row:SetScript("OnEnter", function(self)
    self.hover:Show()
    GameTooltip:SetOwner(flyout, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if flyout.side == "left" then
      GameTooltip:SetPoint("TOPRIGHT", self, "TOPLEFT", -PAD - 2, 0)
    else
      GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", PAD + 2, 0)
    end
    showTooltip(self.key)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function(self) self.hover:Hide() GameTooltip:Hide() end)
  row.pin:SetScript("OnClick", function(self)
    MB:SetPinned(self.row.key, not MB:IsPinned(self.row.key))
    pinTooltip(self)
  end)
  row.pin:SetScript("OnEnter", function(self) self.row.hover:Show() pinTooltip(self) end)
  row.pin:SetScript("OnLeave", function(self) self.row.hover:Hide() GameTooltip:Hide() end)
  return row
end

local function paintPin(row)
  local c = MB:IsPinned(row.key) and UI.Accent(row.key) or C.faint
  row.pin.icon:SetVertexColor(c[1], c[2], c[3], 1)
end

local function buildFlyout()
  local f = CreateFrame("Frame", "NorgannonMinimapFlyout", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:Hide()
  f.box = UI.Box(f, "BACKGROUND", 0)
  f.box:Set(C.lineStrong, C.stone2, C.stone)
  f.rows = {}
  table.insert(UISpecialFrames, "NorgannonMinimapFlyout")   -- Escape closes it
  -- a click anywhere else closes it (the Norgannon button's own click toggles it)
  pcall(f.RegisterEvent, f, "GLOBAL_MOUSE_DOWN")
  f:SetScript("OnEvent", function(self)
    if self:IsShown() and not self:IsMouseOver() and not (MB.main and MB.main:IsMouseOver()) then self:Hide() end
  end)
  f:SetScript("OnHide", function() GameTooltip:Hide() end)
  return f
end

---Fills the flyout from the registered addons and puts it beside the Norgannon button, opening
---towards the middle of the screen.
function MB:LayoutFlyout()
  local f = self.flyout
  if not f then return end
  local keys = self:Keys()
  for i, key in ipairs(keys) do
    local row = f.rows[i] or newRow(f)
    f.rows[i] = row
    row.key = key
    local info = Core:GetAddonInfo(key)
    row.mark:SetTexture(UI.MarkPath(key))
    local accent = UI.AccentText(key)
    row.name:SetText(info and info.name or key)
    row.name:SetTextColor(accent[1], accent[2], accent[3], 1)
    local status, color = self:Status(key)
    row.status:SetText(status)
    row.status:SetTextColor(color[1], color[2], color[3], 1)
    paintPin(row)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -PAD - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -PAD - (i - 1) * ROW_H)
    row:Show()
  end
  for i = #keys + 1, #f.rows do f.rows[i]:Hide() end
  f:SetSize(FLYOUT_W, PAD * 2 + #keys * ROW_H)

  local main = self.main
  local x, y = main:GetCenter()
  local w, h = UIParent:GetWidth() or GetScreenWidth(), UIParent:GetHeight() or 768
  local mainScale, uiScale = main:GetEffectiveScale(), UIParent:GetEffectiveScale()
  x, y = (x or 0) * mainScale / uiScale, (y or 0) * mainScale / uiScale
  f.side = x > w / 2 and "left" or "right"
  local vertical = y > h / 2 and "TOP" or "BOTTOM"
  f:ClearAllPoints()
  if f.side == "left" then
    f:SetPoint(vertical .. "RIGHT", main, vertical .. "LEFT", -2, 0)
  else
    f:SetPoint(vertical .. "LEFT", main, vertical .. "RIGHT", 2, 0)
  end
end

function MB:ToggleFlyout(show)
  self.flyout = self.flyout or buildFlyout()
  if show == nil then show = not self.flyout:IsShown() end
  if show and next(self.entries) then
    self:LayoutFlyout()
    self.flyout:Show()
  else
    self.flyout:Hide()
  end
end

local function buildMain()
  local b = roundButton("NorgannonMinimapButton", "core", store, MAIN_ANGLE,
    function(_, button)
      GameTooltip:Hide()
      if button == "RightButton" then
        MB:ToggleFlyout(false)
        MB:OpenSettings()
      else
        MB:ToggleFlyout()
      end
    end, mainTooltip)
  b:SetFrameLevel(9)
  b.onMoved = function() if MB.flyout and MB.flyout:IsShown() then MB:LayoutFlyout() end end
  b:HookScript("OnDragStart", function() MB:ToggleFlyout(false) end)
  return b
end

---Shows what the settings say: the Norgannon button once any addon is registered, each addon's
---own button while it's pinned, and a fresh flyout if it is open.
function MB:Update()
  local any = next(self.entries) ~= nil
  if any and not self.main then self.main = buildMain() end
  if self.main then self.main:SetShown(any and self:IsMainShown()) end
  if self.flyout and self.flyout:IsShown() then
    if self.main and self.main:IsShown() then self:LayoutFlyout() else self.flyout:Hide() end
  end
  if self.settingsList then self.settingsList:Refresh() end
end

-- the minimap's shape can change (another addon making it square): put the buttons back
Core:On("PLAYER_ENTERING_WORLD", "core.minimapbuttons", function()
  if MB.main then place(MB.main) end
  for _, b in pairs(MB.pins) do place(b) end
end)

-------------------------------------------------------------------------------------------
-- Settings: NorgannonDB > Minimap
-------------------------------------------------------------------------------------------

function MB:OpenSettings()
  if self.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(self.settingsCategory:GetID())
  else
    Core:OpenSettings()
  end
end

---Adds a pin row for every addon that registered since the page was last shown.
function MB:FillSettings()
  local list = self.settingsList
  if not list then return end
  list.pinRows = list.pinRows or {}
  for _, key in ipairs(self:Keys()) do
    if not list.pinRows[key] then
      local info = Core:GetAddonInfo(key)
      local name = info and info.name or key
      list.pinRows[key] = list:Toggle("Pin " .. name,
        "Keeps " .. name .. "'s own button on the minimap. This is also its \"Show the minimap button\" setting.",
        function() return MB:IsPinned(key) end, function(on) MB:SetPinned(key, on) end)
    end
  end
  list:Refresh()
end

Core:OnReady(function()
  if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return end
  local page = CreateFrame("Frame")
  page:Hide()
  local list = UI.SettingsList(page)
  list:Header("The Norgannon button")
  list:Toggle("Show the Norgannon button",
    "One minimap button for the whole suite. Click it for a list of your NorgannonDB add-ons: click one as you would its own button, right-click for its settings.",
    function() return MB:IsMainShown() end, function(on) MB:SetMainShown(on) end)
  list:Header("Pinned to the minimap")
  page:SetScript("OnShow", function() MB:FillSettings() end)
  MB.settingsPage, MB.settingsList = page, list
  Core:OnLogin(function()
    if Core.settingsCategory then MB.settingsCategory = Core:AddSettingsPage(page, "Minimap") end
  end)
end)
