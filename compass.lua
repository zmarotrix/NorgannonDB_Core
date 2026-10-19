-- The compass: a strip across the top of the screen with N/E/S/W and one marker per tracked
-- objective, like Skyrim's. It shows every tracked objective at once and never says which to
-- do next, so it fits the suite's no-leveling-guide rule better than an arrow.
--
-- Pins opt in with a group key: { ..., compass = "q788:1" }. The compass shows one marker per
-- group, pointing at the group's nearest pin, in the pin's colour and icon. Hover a marker for
-- its tooltip and distance. The arrow's focus target (Core.Arrow) shows as a gold diamond.
--
-- The bar is click-through (only markers take the mouse), hides where the client gives no
-- facing (instances), and can hide when there is nothing to show.

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C
local HBD = LibStub("HereBeDragons-NorgannonCore-2.0")

local Compass = { stats = { markers = 0 } }
Core.Compass = Compass

local WIDTH, HEIGHT = 560, 30
local FOV = math.pi                -- the strip spans 180 degrees
local MAX_MARKERS = 24
local NEAREST_EVERY = 0.25         -- seconds between "nearest pin per group" passes
local NEAR, FAR = 60, 1200         -- yards: full size at NEAR, smallest and faintest at FAR

local f = CreateFrame("Frame", "NorgannonCoreCompass", UIParent)
f:SetSize(WIDTH, HEIGHT)
f:SetPoint("TOP", UIParent, "TOP", 0, -62)
f:SetFrameStrata("LOW")
f:EnableMouse(false)              -- click-through; markers take the mouse themselves
f:SetMovable(true)
f:SetClampedToScreen(true)
f:Hide()
Compass.frame = f

-- the strip: dark band fading out at both ends, a thin gold line, a centre notch
local function band(side)
  local t = f:CreateTexture(nil, "BACKGROUND")
  t:SetPoint("TOP" .. side)
  t:SetPoint("BOTTOM" .. side)
  t:SetWidth(WIDTH / 2)
  t:SetColorTexture(1, 1, 1, 1)
  local dark = CreateColor(.03, .025, .02, .72)
  local clear = CreateColor(.03, .025, .02, 0)
  if side == "LEFT" then t:SetGradient("HORIZONTAL", clear, dark) else t:SetGradient("HORIZONTAL", dark, clear) end
end
band("LEFT")
band("RIGHT")
local line = f:CreateTexture(nil, "BORDER")
line:SetHeight(1)
line:SetPoint("BOTTOMLEFT", 40, 3)
line:SetPoint("BOTTOMRIGHT", -40, 3)
line:SetColorTexture(C.frameGold[1], C.frameGold[2], C.frameGold[3], .7)
local notch = f:CreateTexture(nil, "OVERLAY")
notch:SetTexture(UI.TEX.arrow)
notch:SetSize(12, 12)
notch:SetPoint("TOP", f, "BOTTOM", 0, 5)
notch:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])

-- cardinal letters and ticks every 15 degrees
local marks = {}
for deg = 0, 345, 15 do
  local m = {}
  m.angle = math.rad(deg)
  if deg % 90 == 0 then
    m.text = UI.Text(f, "title", 15, C.gold)
    m.text:SetText(({ [0] = "N", [90] = "W", [180] = "S", [270] = "E" })[deg])
  elseif deg % 45 == 0 then
    m.text = UI.Text(f, "title", 11, C.muted)
    m.text:SetText(({ [45] = "NW", [135] = "SW", [225] = "SE", [315] = "NE" })[deg])
  else
    m.tick = f:CreateTexture(nil, "BORDER")
    m.tick:SetSize(1, 5)
    m.tick:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], .6)
  end
  marks[#marks + 1] = m
end

-- the screen offset of a world angle, given the player's facing (nil when out of view)
local function offset(angle, facing)
  local delta = (angle - facing + math.pi) % (2 * math.pi) - math.pi   -- -pi..pi, positive = left
  if math.abs(delta) > FOV / 2 then return nil end
  return -delta / (FOV / 2) * (WIDTH / 2 - 40), delta
end

-------------------------------------------------------------------------------------------
-- Markers
-------------------------------------------------------------------------------------------

local markers = {}

local function markerEnter(self)
  local pin = self.pin
  if not pin then return end
  Core.Map:SetHighlight(Core.Map.HighlightKey(pin))
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  if pin.tooltip then
    Core.SafeCall(pin.tooltip, pin, GameTooltip)
  else
    GameTooltip:AddLine(pin.title or "?", 1, 1, 1)
  end
  if self.distance then
    GameTooltip:AddLine(string.format("%d yards", self.distance), C.muted[1], C.muted[2], C.muted[3])
  end
  GameTooltip:Show()
end

local function marker(i)
  local m = markers[i]
  if not m then
    m = CreateFrame("Button", nil, f)
    m.GetCenter = function() return nil end
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetAllPoints()
    m:SetScript("OnEnter", markerEnter)
    m:SetScript("OnLeave", function() Core.Map:SetHighlight(nil) GameTooltip:Hide() end)
    markers[i] = m
  end
  return m
end

-- nearest pin per compass group, recomputed every NEAREST_EVERY seconds
local targets = {}

local function collect(px, py, instance)
  local best = {}
  for _, pins in pairs(Core.Map.owners) do
    for _, pin in ipairs(pins) do
      local group = pin.compass
      if group then
        local wx, wy, inst = Core.Map.WorldOf(pin)
        if wx and inst == instance then
          local dx, dy = wx - px, wy - py
          local d2 = dx * dx + dy * dy
          local b = best[group]
          if not b or d2 < b.d2 then best[group] = { pin = pin, x = wx, y = wy, d2 = d2 } end
        end
      end
    end
  end
  local list = {}
  for _, b in pairs(best) do list[#list + 1] = b end
  local focus = Core.Arrow and Core.Arrow.world and Core.Arrow.target
  if focus and Core.Arrow.world.instance == instance then
    local w = Core.Arrow.world
    local dx, dy = w.x - px, w.y - py
    list[#list + 1] = { pin = { title = focus.title or "Waypoint", icon = "diamond", color = C.gold, focus = true },
      x = w.x, y = w.y, d2 = dx * dx + dy * dy }
  end
  table.sort(list, function(a, b) return a.d2 < b.d2 end)
  for i = MAX_MARKERS + 1, #list do list[i] = nil end
  targets = list
end

-------------------------------------------------------------------------------------------
-- Update: every frame (the view turns with the camera), nearest pins every NEAREST_EVERY
-------------------------------------------------------------------------------------------

local sinceNearest = NEAREST_EVERY

function Compass:Update(dt)
  local db = Core.db
  local enabled = not (db and db.compass and db.compass.hidden)
  local px, py, instance = HBD:GetPlayerWorldPosition()
  local facing = GetPlayerFacing()
  if not enabled or not px or not facing or Core.IsSecret(px) or Core.IsSecret(facing) then
    f:Hide()
    return
  end
  sinceNearest = sinceNearest + (dt or NEAREST_EVERY)
  if sinceNearest >= NEAREST_EVERY then
    sinceNearest = 0
    collect(px, py, instance)
  end
  if #targets == 0 and not (db and db.compass and db.compass.alwaysShow) then
    f:Hide()
    return
  end
  f:Show()

  for _, m in ipairs(marks) do
    local x, delta = offset(m.angle, facing)
    local region = m.text or m.tick
    if x then
      region:ClearAllPoints()
      if m.text then region:SetPoint("CENTER", f, "CENTER", x, 2) else region:SetPoint("BOTTOM", f, "BOTTOM", x, 4) end
      region:SetAlpha(1 - (math.abs(delta) / (FOV / 2)) ^ 3)
      region:Show()
    else
      region:Hide()
    end
  end

  local n = 0
  for _, t in ipairs(targets) do
    local angle, distance = HBD:GetWorldVector(instance, px, py, t.x, t.y)
    local x, delta
    if angle then x, delta = offset(angle, facing) end
    if x then
      n = n + 1
      local m = marker(n)
      local closeness = 1 - math.max(0, math.min(1, (distance - NEAR) / (FAR - NEAR)))
      local size = t.pin.focus and 18 or (11 + 7 * closeness)
      m:SetSize(size, size)
      local tintable = Core.Map.SetIcon(m.icon, t.pin.icon)
      local c = Core.Map.PinColor(t.pin)
      if c and tintable then m.icon:SetVertexColor(c[1], c[2], c[3]) else m.icon:SetVertexColor(1, 1, 1) end
      local key = Core.Map.highlight
      local dim = (key and Core.Map.HighlightKey(t.pin) ~= key) and .3 or 1
      m:SetAlpha((.45 + .55 * closeness) * (1 - (math.abs(delta) / (FOV / 2)) ^ 4) * dim)
      m:ClearAllPoints()
      m:SetPoint("CENTER", f, "CENTER", x, 1)
      m:SetFrameLevel(f:GetFrameLevel() + 2 + math.floor(closeness * 10))
      m.pin, m.distance = t.pin, distance
      m:Show()
    end
  end
  for i = n + 1, #markers do markers[i]:Hide() markers[i].pin = nil end
  Compass.stats.markers = n
end

f:SetScript("OnUpdate", function(_, dt) Compass:Update(dt) end)

-- an always-running driver: the strip itself hides when there is nothing to show
local driver = CreateFrame("Frame")
local idle = 0
driver:SetScript("OnUpdate", function(_, dt)
  if f:IsShown() then return end
  idle = idle + dt
  if idle < NEAREST_EVERY then return end
  idle = 0
  sinceNearest = NEAREST_EVERY
  Compass:Update(0)
end)

-------------------------------------------------------------------------------------------
-- Settings
-------------------------------------------------------------------------------------------

function Compass:SetShown(on)
  if Core.db then
    Core.db.compass = Core.db.compass or {}
    Core.db.compass.hidden = not on
  end
  sinceNearest = NEAREST_EVERY
  self:Update(0)
end

function Compass:IsEnabled()
  return not (Core.db and Core.db.compass and Core.db.compass.hidden)
end

-- unlock to move: /norg compass move
function Compass:SetMovable(on)
  f:EnableMouse(on)
  f:RegisterForDrag(on and "LeftButton" or nil)
  if on then
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local point, _, relativePoint, x, y = self:GetPoint()
      if Core.db then Core.db.windows.NorgannonCoreCompass = { point = point, relativePoint = relativePoint, x = x, y = y } end
    end)
  end
  Core.db.compass = Core.db.compass or {}
  Core.db.compass.alwaysShow = on or nil   -- visible while placing it
  self.moving = on
end

Core:OnLogin(function()
  local saved = Core.db and Core.db.windows.NorgannonCoreCompass
  if saved and saved.point then
    f:ClearAllPoints()
    f:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
  end
end)
