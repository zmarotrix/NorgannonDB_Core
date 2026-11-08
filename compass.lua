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

local Compass = { stats = { markers = 0, draws = 0 } }
Core.Compass = Compass

local WIDTH, HEIGHT = 560, 30
local FOV = math.pi                -- the strip spans 180 degrees
local HALF_FOV = FOV / 2
local END_MARGIN = 40              -- the scale stops this far short of the strip's ends
local DEFAULT_Y = -62              -- under the top of the screen
local MAX_MARKERS = 24
local NEAREST_EVERY = 0.25         -- seconds between "nearest pin per group" passes
local NEAR, FAR = 60, 1200         -- yards: full size at NEAR, smallest and faintest at FAR
local MARKER_MIN, MARKER_MAX = 11, 18
local FOCUS_MARKER = 18            -- the arrow's target, at any distance

local f = CreateFrame("Frame", "NorgannonCoreCompass", UIParent)
f:SetSize(WIDTH, HEIGHT)
f:SetPoint("TOP", UIParent, "TOP", 0, DEFAULT_Y)
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
  if side == "LEFT" then
    t:SetGradient("HORIZONTAL", clear, dark)
  else
    t:SetGradient("HORIZONTAL", dark, clear)
  end
end
band("LEFT")
band("RIGHT")
local line = f:CreateTexture(nil, "BORDER")
line:SetHeight(1)
line:SetPoint("BOTTOMLEFT", END_MARGIN, 3)
line:SetPoint("BOTTOMRIGHT", -END_MARGIN, 3)
line:SetColorTexture(C.frameGold[1], C.frameGold[2], C.frameGold[3], .7)
local notch = f:CreateTexture(nil, "OVERLAY")
notch:SetTexture(UI.TEX.arrow)
notch:SetSize(12, 12)
notch:SetPoint("TOP", f, "BOTTOM", 0, 5)
notch:SetVertexColor(C.gold[1], C.gold[2], C.gold[3])

-- Cardinal letters and ticks every 15 degrees. The game's angles count counter-clockwise from
-- north, so west is 90.
local CARDINALS = { [0] = "N", [90] = "W", [180] = "S", [270] = "E" }
local ORDINALS = { [45] = "NW", [135] = "SW", [225] = "SE", [315] = "NE" }

local scaleMarks = {}
for deg = 0, 345, 15 do
  local m = {}
  m.angle = math.rad(deg)
  if CARDINALS[deg] then
    m.text = UI.Text(f, "title", 15, C.gold)
    m.text:SetText(CARDINALS[deg])
  elseif ORDINALS[deg] then
    m.text = UI.Text(f, "title", 11, C.muted)
    m.text:SetText(ORDINALS[deg])
  else
    m.tick = f:CreateTexture(nil, "BORDER")
    m.tick:SetSize(1, 5)
    m.tick:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], .6)
  end
  scaleMarks[#scaleMarks + 1] = m
end

-- the screen offset of a world angle, given the player's facing (nil when out of view),
-- and the angle from straight ahead
local function screenOffset(angle, facing)
  local delta = (angle - facing + math.pi) % (2 * math.pi) - math.pi   -- -pi..pi, positive = left
  if math.abs(delta) > HALF_FOV then return nil end
  return -delta / HALF_FOV * (WIDTH / 2 - END_MARGIN), delta
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

local function markerFrame(i)
  local m = markers[i]
  if not m then
    m = CreateFrame("Button", nil, f)
    m.GetCenter = function() return nil end   -- as the map's pins do: see NoCenter in map.lua
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetAllPoints()
    m:SetScript("OnEnter", markerEnter)
    m:SetScript("OnLeave", function()
      Core.Map:SetHighlight(nil)
      GameTooltip:Hide()
    end)
    markers[i] = m
  end
  return m
end

-- nearest pin per compass group, recomputed every NEAREST_EVERY seconds. The tables are kept
-- from pass to pass (a pass made one per candidate before, four times a second).
local targets = {}                    -- { pin, x, y, d2 }, nearest first
local pool = {}                       -- target records, reused
local bestPin, bestD2 = {}, {}        -- group -> its nearest pin so far, and how far
local focusPin, focusOf = nil, nil    -- the arrow target's marker pin, made once per target
local drawDirty = true                -- something besides your position and facing changed: redraw

local function byDistance(a, b) return a.d2 < b.d2 end

local function addTarget(n, pin, x, y, d2)
  local t = pool[n]
  if not t then
    t = {}
    pool[n] = t
  end
  t.pin, t.x, t.y, t.d2 = pin, x, y, d2
  targets[n] = t
end

local function collectTargets(px, py, instance)
  for group in pairs(bestPin) do bestPin[group], bestD2[group] = nil, nil end
  for _, pins in pairs(Core.Map.owners) do
    for _, pin in ipairs(pins) do
      local group = pin.compass
      if group then
        local wx, wy, inst = Core.Map.WorldOf(pin)
        if wx and inst == instance then
          local dx, dy = wx - px, wy - py
          local d2 = dx * dx + dy * dy
          local nearest = bestD2[group]
          if not nearest or d2 < nearest then bestPin[group], bestD2[group] = pin, d2 end
        end
      end
    end
  end
  local n = 0
  for group, pin in pairs(bestPin) do
    local wx, wy = Core.Map.WorldOf(pin)
    n = n + 1
    addTarget(n, pin, wx, wy, bestD2[group])
  end
  local focus = Core.Arrow and Core.Arrow.world and Core.Arrow.target
  if focus and Core.Arrow.world.instance == instance then
    local w = Core.Arrow.world
    local dx, dy = w.x - px, w.y - py
    if focusOf ~= focus then
      focusPin, focusOf = { title = focus.title or "Waypoint", icon = "diamond", color = C.gold, focus = true }, focus
    end
    n = n + 1
    addTarget(n, focusPin, w.x, w.y, dx * dx + dy * dy)
  end
  for i = n + 1, #targets do targets[i] = nil end
  table.sort(targets, byDistance)
  -- only the nearest fit
  for i = MAX_MARKERS + 1, #targets do targets[i] = nil end
  -- let go of pins that are no longer targets. The sort mixes up the records, so a kept target can
  -- be any record in the pool, not just the first #targets
  for _, t in ipairs(targets) do t.kept = true end
  for _, t in ipairs(pool) do
    if t.kept then t.kept = nil else t.pin = nil end
  end
  drawDirty = true
end

-------------------------------------------------------------------------------------------
-- Update: every frame (the view turns with the camera), nearest pins every NEAREST_EVERY
-------------------------------------------------------------------------------------------

local sinceNearest = NEAREST_EVERY
local drawn = {}                    -- where and which way the strip was last drawn
local FADE_OUT, FADE_IN = .6, .25   -- seconds
local fade = 0                      -- the strip's opacity while fading in and out

local function drawScale(facing)
  for _, m in ipairs(scaleMarks) do
    local x, delta = screenOffset(m.angle, facing)
    local region = m.text or m.tick
    if x then
      region:ClearAllPoints()
      if m.text then
        region:SetPoint("CENTER", f, "CENTER", x, 2)
      else
        region:SetPoint("BOTTOM", f, "BOTTOM", x, 4)
      end
      region:SetAlpha(1 - (math.abs(delta) / HALF_FOV) ^ 3)   -- fading toward the strip's ends
      region:Show()
    else
      region:Hide()
    end
  end
end

local function drawMarkers(px, py, instance, facing)
  local n = 0
  for _, t in ipairs(targets) do
    local angle, distance = HBD:GetWorldVector(instance, px, py, t.x, t.y)
    local x, delta
    if angle then x, delta = screenOffset(angle, facing) end
    if x then
      n = n + 1
      local m = markerFrame(n)
      local closeness = 1 - math.max(0, math.min(1, (distance - NEAR) / (FAR - NEAR)))
      local size = t.pin.focus and FOCUS_MARKER or (MARKER_MIN + (MARKER_MAX - MARKER_MIN) * closeness)
      m:SetSize(size, size)
      local tintable = Core.MapIcons.SetOwned(m.icon, t.pin.icon)
      local c = Core.Map.PinColor(t.pin)
      if c and tintable then
        m.icon:SetVertexColor(c[1], c[2], c[3])
      else
        m.icon:SetVertexColor(1, 1, 1)
      end
      local key = Core.Map.highlight
      local dim = (key and Core.Map.HighlightKey(t.pin) ~= key) and Core.Map.DIM or 1
      -- fainter with distance and toward the strip's ends
      m:SetAlpha((.45 + .55 * closeness) * (1 - (math.abs(delta) / HALF_FOV) ^ 4) * dim)
      m:ClearAllPoints()
      m:SetPoint("CENTER", f, "CENTER", x, 1)
      m:SetFrameLevel(f:GetFrameLevel() + 2 + math.floor(closeness * 10))   -- nearer ones on top
      m.pin, m.distance = t.pin, distance
      m:Show()
    end
  end
  for i = n + 1, #markers do
    markers[i]:Hide()
    markers[i].pin = nil
  end
  Compass.stats.markers = n
end

-- When the game stops giving addons your position or facing (secret values in combat on this
-- client, or none at all in some places), the compass can't follow you: it holds its last
-- picture and fades out instead of jumping or vanishing, and fades back in when it can update.
function Compass:Update(dt)
  if not Compass:IsEnabled() then
    f:Hide()
    fade = 0
    return
  end
  local px, py, instance = HBD:GetPlayerWorldPosition()
  local facing = GetPlayerFacing()
  if not px or not facing or Core.IsSecret(px) or Core.IsSecret(facing) then
    Compass.unavailable = true
    if f:IsShown() then
      fade = math.max(0, fade - (dt or 0) / FADE_OUT)
      f:SetAlpha(fade)
      if fade <= 0 then f:Hide() end
    end
    return
  end
  Compass.unavailable = false
  sinceNearest = sinceNearest + (dt or NEAREST_EVERY)
  if sinceNearest >= NEAREST_EVERY then
    sinceNearest = 0
    collectTargets(px, py, instance)
  end
  if #targets == 0 and not Compass.alwaysShow then
    f:Hide()
    fade = 0
    return
  end
  if not f:IsShown() then
    fade = 0
    drawDirty = true
  end
  f:Show()
  fade = Compass.moving and 1 or math.min(1, fade + (dt or 0) / FADE_IN)
  f:SetAlpha(fade)
  -- standing still and not turning: the strip already shows this (most frames while reading,
  -- looting or fighting in place)
  if drawDirty or px ~= drawn.x or py ~= drawn.y or facing ~= drawn.facing or instance ~= drawn.instance then
    drawn.x, drawn.y, drawn.facing, drawn.instance = px, py, facing, instance
    drawDirty = false
    Compass.stats.draws = Compass.stats.draws + 1
    drawScale(facing)
    drawMarkers(px, py, instance, facing)
  end
end

---What the compass holds, for /norg mem.
function Compass:MemoryStats()
  return { targets = #targets, records = #pool, markerFrames = #markers }
end

-- a highlight or a quest's new colour changes how markers look
Core:Listen("NORGANNON_MAP_HIGHLIGHT", "compass", function() drawDirty = true end)
Core:Listen("NORGANNON_QUEST_COLOR_CHANGED", "compass", function() drawDirty = true end)

f:SetScript("OnUpdate", function(_, dt) Compass:Update(dt) end)

-- A hidden frame gets no OnUpdate, and the strip hides when there is nothing to show, so this
-- always-running frame is what notices when there is something again.
local driver = CreateFrame("Frame")
Compass.driver = driver
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

local function settings()
  Core.db.compass = Core.db.compass or {}
  return Core.db.compass
end

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

-- Moving it (/norg compass move, or the settings page): the strip lights up with a hint; drag
-- it, then Lock (or right-click it).
local moveHint = f:CreateFontString(nil, "OVERLAY")
moveHint:SetFontObject(UI.Font("body", 12))
moveHint:SetPoint("TOP", f, "BOTTOM", 0, -8)
moveHint:SetText("Drag the compass  ·  right-click to lock")
moveHint:Hide()
local moveGlow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
moveGlow:SetAllPoints()
moveGlow:SetColorTexture(1, .82, .3, .18)
moveGlow:Hide()

function Compass:SetMovable(on)
  -- the client rejects RegisterForDrag(nil): register once, and lock by clearing the handlers
  -- and the mouse instead
  f:EnableMouse(on)
  if on then
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      UI.SavePosition(self, "NorgannonCoreCompass")
    end)
    f:SetScript("OnMouseUp", function(_, button)
      if button == "RightButton" then Compass:SetMovable(false) end
    end)
  else
    f:SetScript("OnDragStart", nil)
    f:SetScript("OnDragStop", nil)
    f:SetScript("OnMouseUp", nil)
  end
  moveHint:SetShown(on)
  moveGlow:SetShown(on)
  self.alwaysShow = on or nil   -- visible while placing it; not saved, so a /reload can't strand it
  self.moving = on
  sinceNearest = NEAREST_EVERY
  self:Update(0)
  Core:Send("NORGANNON_COMPASS_MOVING", on)
end

---Compass size (scale, .6 to 1.6), saved.
function Compass:SetSize(scale)
  settings().scale = scale
  f:SetScale(scale)
end
function Compass:GetSize() return settings().scale or 1 end

---Back to the default place under the top of the screen.
function Compass:ResetPosition()
  if Core.db then Core.db.windows.NorgannonCoreCompass = nil end
  f:ClearAllPoints()
  f:SetPoint("TOP", UIParent, "TOP", 0, DEFAULT_Y)
end

Core:OnLogin(function()
  settings().alwaysShow = nil   -- an older version saved this while moving
  f:SetScale(Compass:GetSize())
  UI.RestorePosition(f, "NorgannonCoreCompass")
end)
