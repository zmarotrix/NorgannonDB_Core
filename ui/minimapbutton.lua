-- Minimap buttons for the suite's addons: the standard round button (the game's own border and
-- background) with the addon's mark, dragged anywhere around the minimap's edge (square and
-- rounded minimap shapes respected), its place saved per addon (NorgannonCoreDB.minimap).
--
--   Core.MinimapButton:Add("oracle", {
--     tooltip = function(tt) tt:AddLine("Oracle") end,
--     onClick = function(button) ... end,       -- "LeftButton" / "RightButton"; shift is the caller's to read
--   })
--   Core.MinimapButton:SetShown("oracle", false)   -- the addon's "Show the minimap button" setting

local Core = NorgannonCore
local UI = Core.UI

local MB = { buttons = {} }
Core.MinimapButton = MB

local SIZE = 32   -- the game tracking button's size
local DEFAULT_ANGLES = { clairvoyance = 200, oracle = 225, foresight = 250, archivum = 275 }

-- { upper-left, lower-left, upper-right, lower-right }: which quadrants of the minimap are round
local SHAPES = {
  ["ROUND"] = { true, true, true, true }, ["SQUARE"] = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { false, false, false, true }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
  ["SIDE-LEFT"] = { false, true, false, true }, ["SIDE-RIGHT"] = { true, false, true, false },
  ["SIDE-TOP"] = { false, false, true, true }, ["SIDE-BOTTOM"] = { true, true, false, false },
  ["TRICORNER-TOPLEFT"] = { false, true, true, true }, ["TRICORNER-TOPRIGHT"] = { true, true, false, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, false, true, true }, ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local function settings(key)
  local db = Core.db
  if not db then return {} end
  db.minimap = db.minimap or {}
  db.minimap[key] = db.minimap[key] or {}
  return db.minimap[key]
end

---Where a button at this angle (degrees, 0 = right, counter-clockwise) sits from the minimap's
---centre: on the circle in round quadrants, on the square's edge in square ones.
function MB.Offset(angle)
  local a = math.rad(angle)
  local x, y = math.cos(a), math.sin(a)
  local q = 1
  if x < 0 then q = q + 1 end
  if y > 0 then q = q + 2 end
  local shape = SHAPES[GetMinimapShape and GetMinimapShape() or "ROUND"] or SHAPES.ROUND
  local w = (Minimap:GetWidth() or 140) / 2 + 10
  local h = (Minimap:GetHeight() or 140) / 2 + 10
  if shape[q] then
    return x * w, y * h
  end
  local diag = math.sqrt(2 * w * w)
  return math.max(-w, math.min(x * diag, w)), math.max(-h, math.min(y * diag, h))
end

local function place(b)
  local x, y = MB.Offset(settings(b.key).angle or DEFAULT_ANGLES[b.key] or 225)
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function dragUpdate(b)
  local mx, my = Minimap:GetCenter()
  if not mx then return end
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  settings(b.key).angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
  place(b)
end
MB.DragUpdate = dragUpdate

---Adds an addon's minimap button. opts: tooltip(tt), onClick(button).
function MB:Add(key, opts)
  if self.buttons[key] then return self.buttons[key] end
  local b = CreateFrame("Button", "NorgannonMinimapButton_" .. key, Minimap)
  b.key = key
  b:SetSize(SIZE, SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b.background = b:CreateTexture(nil, "BACKGROUND")
  b.background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  -- the game's own tracking button's geometry: the ring's circle isn't centred in its texture,
  -- so the dark disc and the mark are placed from the top-left, as the game places them
  -- (measured in game: the ring's centre is at 17, -16)
  b.background:SetSize(24, 24)
  b.background:SetPoint("TOPLEFT", 5, -4)
  b.icon = UI.Mark(b, key, 22, "ARTWORK")
  b.icon:ClearAllPoints()
  b.icon:SetPoint("TOPLEFT", 6, -5)
  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  b.border:SetSize(54, 54)
  b.border:SetPoint("TOPLEFT")
  b:SetScript("OnClick", function(_, button) if opts.onClick then Core.SafeCall(opts.onClick, button) end end)
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
    if opts.tooltip then opts.tooltip(GameTooltip) end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.buttons[key] = b
  place(b)
  b:SetShown(not settings(key).hidden)
  return b
end

---Shows or hides an addon's minimap button (saved).
function MB:SetShown(key, on)
  settings(key).hidden = not on or nil
  local b = self.buttons[key]
  if b then b:SetShown(on and true or false) end
end

function MB:IsShown(key) return not settings(key).hidden end

-- the minimap's shape can change (another addon making it square): put the buttons back
Core:On("PLAYER_ENTERING_WORLD", "core.minimapbuttons", function()
  for _, b in pairs(MB.buttons) do place(b) end
end)
