-- The shared map layer: suite addons submit pins, the Core draws them once on the world map
-- and the minimap. Four addons never stack four pin layers, and every pin follows the same
-- rules: constant on-screen size while the map zooms, draw order by layer, a soft glow over a
-- quest's dense spawns while you hover it, and no centre reported to the gamepad map cursor
-- (which would taint it).
--
--   Core.Map:SetPins("clairvoyance", {
--     { area = 14, x = 52.1, y = 43.0, icon = "pin", color = {1, .82, 0}, layer = 3,
--       cluster = "q788", title = "Mottled Boar", tooltip = function(pin, tt) end, onClick = function(pin, button) end },
--   })
--
-- Coordinates are NorgannonDB's: an areaId and x, y in percent (0-100) of that zone's map.
--
-- Pins of a quest set `quest = questId`: they take the quest's colour from Core.Colors (unless
-- they give `color`), hovering one dims every other quest's pins, and without an onClick a
-- left-click rolls a new colour and a right-click opens the colour picker.

local Core = NorgannonCore
local UI = Core.UI
local HBD = LibStub("HereBeDragons-NorgannonCore-2.0")

local Map = { owners = {}, stats = { world = 0, minimap = 0, clusters = 0 } }
Core.Map = Map

local WORLD_LEVEL = 2015          -- Blizzard's map pins start around 2000; stay above them
local CLUSTER_GLOW_ALPHA = .4     -- shown only on hover, so it can be fairly strong
local MINIMAP_MAX = 150           -- most pins drawn on the minimap, nearest first
local MINIMAP_EDGE_MARGIN = 6     -- pixels: a pin closer to the edge than this isn't drawn
local THROTTLE = 0.05             -- seconds between redraw checks
local DEFAULT_PIN_SIZE = 7
local HOVER_GROW = 1.25           -- a hovered pin's size
local OVERLAP_REACH = .9          -- of a pin's size: closer than this, two pins with one overlapKey "stack"
local CONTINENT_DOT, CONTINENT_ICON = 9, 14   -- marker sizes on continent maps: a plain pin, anything else

local Icons = Core.MapIcons
local setIcon = Icons.Set
Map.ICONS, Map.SERVICE_ICONS = Icons.ICONS, Icons.SERVICE_ICONS
Map.IconSource, Map.SetIcon = Icons.Source, setIcon

local clusterPins = Core.ClusterPins
Map.Cluster = clusterPins

local function maps() return NorgannonDB and NorgannonDB.maps end
function Map.AreaToUiMap(area)
  local m = maps()
  return area and m and m.areaToUiMap[area]
end
function Map.UiMapToArea(uiMap)
  local m = maps()
  return uiMap and m and m.uiMapToArea[uiMap]
end

-- Blizzard's gamepad map cursor reads pin centres outside secure code; a frame that reports no
-- centre is skipped, which keeps our pins from tainting the gamepad map UI.
local function NoCenter() return nil end

-------------------------------------------------------------------------------------------
-- Pin sets
-------------------------------------------------------------------------------------------

local byArea = {}            -- area -> { pin, ... } across owners, sorted by layer
local indexDirty = true
local worldDirty = true
local worldPos = setmetatable({}, { __mode = "k" })   -- pin -> { x, y, instance } (or false)

---Replaces an owner's pins (nil or {} removes them).
function Map:SetPins(owner, pins)
  self.owners[owner] = pins and #pins > 0 and pins or nil
  indexDirty, worldDirty = true, true
end

function Map:ClearPins(owner) self:SetPins(owner, nil) end

local areaInstance = {}     -- area -> the instance its pins are in (false: none), filled by the minimap
local function byLayer(a, b) return (a.layer or 1) < (b.layer or 1) end
local resetDrawn   -- defined with the overlap rule

local function rebuildIndex()
  byArea = {}
  for _, pins in pairs(Map.owners) do
    for _, pin in ipairs(pins) do
      if pin.area and pin.x and pin.y then
        local list = byArea[pin.area]
        if not list then
          list = {}
          byArea[pin.area] = list
        end
        list[#list + 1] = pin
      end
    end
  end
  for _, list in pairs(byArea) do
    table.sort(list, byLayer)
  end
  indexDirty = false
  resetDrawn(true)
  areaInstance = {}
end

---Pins in an area (after index rebuild), lowest layer first.
function Map:PinsIn(area)
  if indexDirty then rebuildIndex() end
  return byArea[area] or {}
end

local function worldOf(pin)
  local cached = worldPos[pin]
  if cached == nil then
    local uiMap = Map.AreaToUiMap(pin.area)
    local x, y, instance
    if uiMap then x, y, instance = HBD:GetWorldCoordinatesFromZone(pin.x / 100, pin.y / 100, uiMap) end
    cached = x and { x, y, instance } or false
    worldPos[pin] = cached
  end
  if cached then return cached[1], cached[2], cached[3] end
end
Map.WorldOf = worldOf

-------------------------------------------------------------------------------------------
-- Pin frames
-------------------------------------------------------------------------------------------

-- the group a pin highlights with: its quest, else its cluster
local function highlightKey(pin)
  return pin and (pin.quest and ("q" .. pin.quest) or pin.highlight or pin.cluster)
end
Map.HighlightKey = highlightKey

local DIM = .3    -- opacity of everything outside the highlighted group
Map.DIM = DIM
local applyHighlight   -- defined after the frame pools

-- a pin frame's opacity: its own, dimmed when another group is highlighted
local function highlightedAlpha(baseAlpha, pin)
  local key = Map.highlight
  return baseAlpha * ((key and highlightKey(pin) ~= key) and DIM or 1)
end

---Highlights one group (dims the others on the world map, minimap and compass); nil clears.
function Map:SetHighlight(key)
  if self.highlight == key then return end
  self.highlight = key
  applyHighlight()
end

local function pinColor(pin)
  if pin.color then return pin.color end
  local key = pin.colorKey or pin.quest
  if key and Core.Colors then return Core.Colors:ForQuest(key) end
end
Map.PinColor = pinColor

local function pinEnter(self)
  local pin = self.pin
  if not pin then return end
  self.icon:SetSize(self.size * HOVER_GROW, self.size * HOVER_GROW)
  Map:SetHighlight(highlightKey(pin))
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if pin.tooltip then
    Core.SafeCall(pin.tooltip, pin, GameTooltip)
  elseif pin.title then
    GameTooltip:AddLine(pin.title, 1, 1, 1)
  end
  local faint = UI.C.faint
  if (pin.quest or pin.colorKey) and not pin.onClick then
    GameTooltip:AddLine("Click: new colour  ·  Right-click: choose colour", faint[1], faint[2], faint[3])
  end
  if pin.shiftHint then
    GameTooltip:AddLine(pin.shiftHint, faint[1], faint[2], faint[3])
  end
  GameTooltip:Show()
end

local function pinLeave(self)
  self.icon:SetSize(self.size, self.size)
  Map:SetHighlight(nil)
  GameTooltip:Hide()
end

local function pinClick(self, button)
  local pin = self.pin
  if not pin then return end
  if pin.onShiftClick and IsShiftKeyDown() then
    Core.SafeCall(pin.onShiftClick, pin, button)
  elseif pin.onClick then
    Core.SafeCall(pin.onClick, pin, button)
  elseif (pin.colorKey or pin.quest) and Core.Colors then
    local key = pin.colorKey or pin.quest
    if button == "RightButton" then Core.Colors:Pick(key) else Core.Colors:Randomize(key) end
  end
end

local function newPin(parent)
  local f = CreateFrame("Button", nil, parent)
  f.GetCenter = NoCenter
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("CENTER")
  f:SetScript("OnEnter", pinEnter)
  f:SetScript("OnLeave", pinLeave)
  f:SetScript("OnClick", pinClick)
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  return f
end

-- gives a pooled pin frame this pin's look and behaviour
local function dress(f, pin, size, alpha)
  local tintable = setIcon(f.icon, pin.icon)
  local c = pinColor(pin)
  if c and tintable then
    f.icon:SetVertexColor(c[1], c[2], c[3])
  else
    f.icon:SetVertexColor(1, 1, 1)
  end
  f.size = size
  f:SetSize(size, size)
  f.icon:SetSize(size, size)
  f.baseAlpha = alpha or 1
  f:SetAlpha(highlightedAlpha(f.baseAlpha, pin))
  f.pin = pin
  f:EnableMouse(pin.title ~= nil or pin.tooltip ~= nil or pin.onClick ~= nil or pin.quest ~= nil or pin.onShiftClick ~= nil)
end

-------------------------------------------------------------------------------------------
-- World map
-------------------------------------------------------------------------------------------

local canvas = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child or WorldMapFrame
local world = CreateFrame("Frame", "NorgannonCoreWorldLayer", canvas)
world:SetAllPoints(canvas)
world:SetFrameLevel(WORLD_LEVEL)
Map.worldLayer = world

local worldPins, areaFrames = {}, {}
local pinScale, shownMap = 1, nil

local function canvasScale()
  local s = WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
  return s > 0 and 1 / s or 1
end

local function place(f, x, y)
  local px, py = x / 100 * world:GetWidth(), y / 100 * world:GetHeight()
  f:SetScale(pinScale)
  f:ClearAllPoints()
  f:SetPoint("CENTER", world, "TOPLEFT", px / pinScale, -py / pinScale)
end

local function areaFrame(i)
  local f = areaFrames[i]
  if not f then
    f = CreateFrame("Frame", nil, world)
    f.GetCenter = NoCenter
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetAllPoints()
    f.glow:SetTexture(UI.TEX.glow)
    areaFrames[i] = f
  end
  return f
end

-- Continent and world maps: one marker per objective (the centre of its spawns in a zone)
-- and per turn-in, translated from the zone's map. Every spawn at this scale would be
-- confetti, and available quests are left out (hundreds per continent). Pins opt out with
-- continent = false; only quest pins (quest or compass key) are shown.
local function continentMarkers(uiMap)
  if indexDirty then rebuildIndex() end
  local groups, order = {}, {}
  for area, list in pairs(byArea) do
    local zoneMap = Map.AreaToUiMap(area)
    if zoneMap and zoneMap ~= uiMap then
      for _, pin in ipairs(list) do
        if pin.world ~= false and pin.continent ~= false and (pin.quest or pin.compass) then
          local key = tostring(pin.compass or pin.cluster or ("q" .. pin.quest)) .. "@" .. area
          local g = groups[key]
          if not g then
            g = { sx = 0, sy = 0, n = 0, pin = pin, zoneMap = zoneMap }
            groups[key] = g
            order[#order + 1] = g
          end
          g.sx, g.sy, g.n = g.sx + pin.x, g.sy + pin.y, g.n + 1
        end
      end
    end
  end
  local markers = {}
  for _, g in ipairs(order) do
    local x, y = HBD:TranslateZoneCoordinates(g.sx / g.n / 100, g.sy / g.n / 100, g.zoneMap, uiMap)
    if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
      local pin, n, zoneMap = g.pin, g.n, g.zoneMap
      markers[#markers + 1] = {
        x = x * 100, y = y * 100, icon = pin.icon, quest = pin.quest, color = pin.color, colorKey = pin.colorKey,
        layer = pin.layer, size = (pin.icon == "pin" or pin.icon == nil) and CONTINENT_DOT or CONTINENT_ICON, title = pin.title,
        tooltip = function(_, tt)
          if pin.tooltip then Core.SafeCall(pin.tooltip, pin, tt) else tt:AddLine(pin.title or "?", 1, 1, 1) end
          local info = C_Map.GetMapInfo(zoneMap)
          local m = UI.C.muted
          tt:AddLine(string.format("%d %s in %s", n, n == 1 and "spot" or "spots", info and info.name or "?"), m[1], m[2], m[3])
        end,
      }
    end
  end
  table.sort(markers, function(a, b) return (a.layer or 1) < (b.layer or 1) end)
  return markers
end
Map.ContinentMarkers = continentMarkers

-- Pins sharing an overlapKey (the same quest's "!" or "?") don't stack: one is skipped when
-- another of its key is already drawn within reach. Measured in screen pixels, so zooming in
-- separates spawns that are really apart. Per pass, drawn[key] = { x1, y1, x2, y2, ... } with
-- drawnCount[key] numbers in use; a pin that isn't skipped is added. The lists are kept from
-- pass to pass (the minimap does one every THROTTLE seconds), so a pass makes no tables.
local drawn, drawnCount = {}, {}

-- a new pass; forget the lists too when the pins change (their keys may be gone)
resetDrawn = function(forget)
  if forget then drawn = {} end
  for key in pairs(drawnCount) do drawnCount[key] = 0 end
end

local function overlapsDrawn(key, x, y, reach)
  local list, n = drawn[key], drawnCount[key] or 0
  if list then
    local r2 = reach * reach
    for i = 1, n, 2 do
      local dx, dy = list[i] - x, list[i + 1] - y
      if dx * dx + dy * dy < r2 then return true end
    end
  else
    list = {}
    drawn[key] = list
  end
  list[n + 1], list[n + 2] = x, y
  drawnCount[key] = n + 2
  return false
end

local function isZoneMap(uiMap)
  local info = C_Map.GetMapInfo(uiMap)
  return not (info and info.mapType and Enum and Enum.UIMapType and info.mapType < Enum.UIMapType.Zone)
end

-- draws the glows (each hidden until its group is highlighted); returns how many there are
local function drawClusterGlows(clusters)
  local count = 0
  for _, cluster in ipairs(clusters) do
    count = count + 1
    local f = areaFrame(count)
    local c = cluster.color or pinColor(cluster.members[1]) or UI.C.goldSoft
    f.glow:SetVertexColor(c[1], c[2], c[3], CLUSTER_GLOW_ALPHA)
    f.key = highlightKey(cluster.members[1])
    f.active = true
    f:SetFrameLevel(WORLD_LEVEL + 1)
    f:ClearAllPoints()
    f:SetSize(cluster.rx * 2 / 100 * world:GetWidth(), cluster.ry * 2 / 100 * world:GetHeight())
    f:SetPoint("CENTER", world, "TOPLEFT", cluster.x / 100 * world:GetWidth(), -cluster.y / 100 * world:GetHeight())
    -- the glow only shows a quest's spread while one of its pins is hovered
    f:SetShown(Map.highlight ~= nil and f.key == Map.highlight)
  end
  for i = count + 1, #areaFrames do
    areaFrames[i]:Hide()
    areaFrames[i].active = nil
  end
  return count
end

-- draws the world pins; returns how many were drawn and how many were skipped as overlapping
local function drawWorldPins(pins)
  resetDrawn()
  local w, h = world:GetWidth(), world:GetHeight()
  local count, overlapped = 0, 0
  for _, pin in ipairs(pins) do
    if pin.world ~= false then
      local key = pin.overlapKey
      if key and overlapsDrawn(key, pin.x / 100 * w / pinScale, pin.y / 100 * h / pinScale,
          (pin.size or DEFAULT_PIN_SIZE) * OVERLAP_REACH) then
        overlapped = overlapped + 1
      else
        count = count + 1
        local f = worldPins[count] or newPin(world)
        worldPins[count] = f
        dress(f, pin, pin.size or DEFAULT_PIN_SIZE, pin.alpha)
        f:SetFrameLevel(WORLD_LEVEL + 2 + (pin.layer or 1))
        place(f, pin.x, pin.y)
        f:Show()
      end
    end
  end
  for i = count + 1, #worldPins do
    worldPins[i]:Hide()
    worldPins[i].pin = nil
  end
  return count, overlapped
end

function Map:RefreshWorld()
  worldDirty = false
  local uiMap = WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
  if uiMap ~= shownMap then
    -- one announcement per change, so add-ons needn't poll the map (uiMap is false when closed)
    local mapArea = uiMap and Map.UiMapToArea(uiMap)
    C_Timer.After(0, function() Core:Send("NORGANNON_WORLDMAP_CHANGED", uiMap or nil, mapArea) end)
  end
  shownMap = uiMap
  local area = uiMap and Map.UiMapToArea(uiMap)
  local pins = area and Map:PinsIn(area) or {}
  pinScale = canvasScale()
  local continent = uiMap and not isZoneMap(uiMap)
  if continent then pins = continentMarkers(uiMap) end

  local glows = drawClusterGlows(continent and {} or clusterPins(pins))
  local drawn, overlapped = drawWorldPins(pins)
  Map.stats.world, Map.stats.clusters, Map.stats.overlapped = drawn, glows, overlapped
end

local function rescaleWorld()
  local s = canvasScale()
  if s == pinScale then return end
  pinScale = s
  worldDirty = true   -- zoom changes which overlapping pins are hidden: redraw on the next tick
  for _, f in ipairs(worldPins) do
    if f:IsShown() and f.pin then place(f, f.pin.x, f.pin.y) end
  end
end

-------------------------------------------------------------------------------------------
-- Minimap (world coordinates: handles zoom, rotation, indoor maps and minimap shapes)
-------------------------------------------------------------------------------------------

local miniPins = {}
local view = {}   -- the player and the minimap for this refresh; filled by prepareMinimap

local function prepareMinimap()
  local px, py, instance = HBD:GetPlayerWorldPosition()
  if not px or Core.IsSecret(px) then return false end
  local rotate = GetCVar("rotateMinimap") == "1"
  local facing = rotate and GetPlayerFacing() or 0
  if rotate and (not facing or Core.IsSecret(facing)) then return false end
  view.x, view.y, view.instance = px, py, instance
  view.rotate, view.sin, view.cos = rotate, math.sin(facing), math.cos(facing)
  view.radius = (C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius())
    or (Minimap.GetViewRadius and Minimap:GetViewRadius()) or 150
  view.halfw, view.halfh = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
  view.shape = Core.MinimapShape()
  return true
end

---Pixel offset of a pin from the minimap centre (x right, y up), and whether it is inside.
---HereBeDragons' world coordinates fall going east (x) and rise going north (y), so east is
---player x minus pin x and north is pin y minus player y. A rotating minimap turns the picture
---so your facing points up (facing counts counter-clockwise from north).
local function minimapOffset(pin, margin)
  local wx, wy, instance = worldOf(pin)
  if not wx or instance ~= view.instance then return end
  local east, north = view.x - wx, wy - view.y
  if view.rotate then east, north = east * view.cos + north * view.sin, north * view.cos - east * view.sin end
  local x, y = east / view.radius * view.halfw, north / view.radius * view.halfh
  local distance = math.sqrt(x * x + y * y)
  local round = true
  if view.shape and x ~= 0 and y ~= 0 then round = Core.IsMinimapRoundAt(view.shape, x, y) end
  local inside
  if round then
    inside = distance + margin < view.halfw
  else
    inside = math.abs(x) + margin < view.halfw and math.abs(y) + margin < view.halfh
  end
  return x, y, distance, inside
end

-- The pins inside the minimap this pass, as parallel arrays kept from pass to pass: a pass runs
-- every THROTTLE seconds, and a table per visible pin was most of the Core's memory churn.
local visPin, visX, visY, visD, visOrder = {}, {}, {}, {}, {}
local visLast = 0
local function nearer(a, b) return visD[a] < visD[b] end

function Map:RefreshMinimap()
  local n = 0
  local stats = Map.stats
  stats.minimapState = not Minimap:IsVisible() and "minimap hidden" or nil
  stats.minimapConsidered, stats.minimapInside = 0, 0
  if not stats.minimapState and not prepareMinimap() then stats.minimapState = "no player position" end
  if not stats.minimapState then
    if indexDirty then rebuildIndex() end
    stats.minimapState = "drawn"
    stats.minimapRadius, stats.minimapInstance = view.radius, view.instance
    local count = 0
    for area, pins in pairs(byArea) do
      local instance = areaInstance[area]
      if instance == nil then
        local _, _, inst = worldOf(pins[1])
        instance = inst or false
        areaInstance[area] = instance
      end
      -- all of an area's pins share its instance: whole areas on another continent are skipped
      if instance == view.instance then
        for _, pin in ipairs(pins) do
          if pin.minimap ~= false then
            stats.minimapConsidered = stats.minimapConsidered + 1
            local x, y, distance, inside = minimapOffset(pin, MINIMAP_EDGE_MARGIN)
            if inside then
              count = count + 1
              visPin[count], visX[count], visY[count], visD[count], visOrder[count] = pin, x, y, distance, count
            end
          end
        end
      end
    end
    for i = count + 1, visLast do visOrder[i], visPin[i] = nil, nil end   -- let go of last pass's pins
    visLast = count
    stats.minimapInside = count
    if count > MINIMAP_MAX then
      table.sort(visOrder, nearer)
      for i = MINIMAP_MAX + 1, count do visOrder[i] = nil end
      count = MINIMAP_MAX
    end
    resetDrawn()   -- the same overlapKey rule as the world map, in minimap pixels
    for i = 1, count do
      local v = visOrder[i]
      local pin, x, y = visPin[v], visX[v], visY[v]
      local key = pin.overlapKey
      local size = pin.minimapSize or DEFAULT_PIN_SIZE
      if not (key and overlapsDrawn(key, x, y, size * OVERLAP_REACH)) then
        n = n + 1
        local f = miniPins[n] or newPin(Minimap)
        miniPins[n] = f
        dress(f, pin, size, pin.alpha)
        f:SetFrameLevel(Minimap:GetFrameLevel() + 5 + (pin.layer or 1))
        f:ClearAllPoints()
        f:SetPoint("CENTER", Minimap, "CENTER", x, y)
        f:Show()
      end
    end
  end
  for i = n + 1, #miniPins do
    miniPins[i]:Hide()
    miniPins[i].pin = nil
  end
  Map.stats.minimap = n
end

-------------------------------------------------------------------------------------------
-- Highlight: fade every pin outside the hovered group
-------------------------------------------------------------------------------------------

applyHighlight = function()
  local key = Map.highlight
  local function fade(f)
    if f:IsShown() and f.pin then f:SetAlpha(highlightedAlpha(f.baseAlpha or 1, f.pin)) end
  end
  for _, f in ipairs(worldPins) do fade(f) end
  for _, f in ipairs(miniPins) do fade(f) end
  for _, f in ipairs(areaFrames) do
    if f.active then f:SetShown(key ~= nil and f.key == key) end
  end
  Core:Send("NORGANNON_MAP_HIGHLIGHT", key)
end

-- a quest's new colour: redraw (the minimap redraws every tick anyway)
Core:Listen("NORGANNON_QUEST_COLOR_CHANGED", "map", function() worldDirty = true end)

-------------------------------------------------------------------------------------------
-- Pulse: "show me" - a group's pins grow and shrink for a moment so the eye finds them
-------------------------------------------------------------------------------------------

local PULSE_PERIOD, PULSE_GROW = .55, .9

---Pulses every pin of a highlight group (e.g. "q788") for duration seconds (default 1.6); the
---other groups dim meanwhile, as when hovering. Works on pins drawn later too (map just opened).
function Map:Pulse(key, duration)
  self.pulse = { key = key, start = GetTime(), duration = duration or 1.6 }
  self:SetHighlight(key)
end

local function applyPulse()
  local p = Map.pulse
  if not p then return end
  local t = GetTime() - p.start
  local ended = t >= p.duration
  local scale = ended and 1 or 1 + PULSE_GROW * (1 - math.cos(2 * math.pi * t / PULSE_PERIOD)) / 2
  for _, pool in ipairs({ worldPins, miniPins }) do
    for _, f in ipairs(pool) do
      if f:IsShown() and f.pin and highlightKey(f.pin) == p.key and f.size then
        f.icon:SetSize(f.size * scale, f.size * scale)
      end
    end
  end
  if ended then
    Map.pulse = nil
    if Map.highlight == p.key then Map:SetHighlight(nil) end
  end
end

-------------------------------------------------------------------------------------------
-- Driver: redraw the world map when it opens, changes map or gets new pins; rescale on
-- zoom; the minimap follows the player every THROTTLE seconds
-------------------------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
  if Map.pulse then applyPulse() end
  elapsed = elapsed + dt
  if elapsed < THROTTLE then return end
  elapsed = 0
  if WorldMapFrame:IsShown() then
    if worldDirty or WorldMapFrame:GetMapID() ~= shownMap then
      Map:RefreshWorld()
    else
      rescaleWorld()
    end
  elseif shownMap then
    Map:RefreshWorld()   -- hides everything once the map is closed
  end
  Map:RefreshMinimap()
end)

---What the map layer holds, for /norg mem: owners, pins, indexed areas, cached world positions, frames.
function Map:MemoryStats()
  local out = { owners = 0, pins = 0, areas = 0, worldPositions = 0, overlapKeys = 0,
    worldFrames = #worldPins, minimapFrames = #miniPins, glowFrames = #areaFrames }
  for _, pins in pairs(self.owners) do out.owners, out.pins = out.owners + 1, out.pins + #pins end
  for _ in pairs(byArea) do out.areas = out.areas + 1 end
  for _ in pairs(worldPos) do out.worldPositions = out.worldPositions + 1 end
  for _ in pairs(drawn) do out.overlapKeys = out.overlapKeys + 1 end
  local s = self.stats
  out.minimapState, out.minimapDrawn, out.minimapConsidered, out.minimapInside = s.minimapState or "not run", s.minimap or 0,
    s.minimapConsidered or 0, s.minimapInside or 0
  out.minimapRadius, out.minimapInstance = s.minimapRadius, s.minimapInstance
  -- which instances the pins are in, against the player's
  local instances = {}
  for _, list in pairs(byArea) do
    local _, _, inst = worldOf(list[1])
    instances[#instances + 1] = tostring(inst)
  end
  out.pinInstances = table.concat(instances, " ")
  return out
end

---Draws everything now (normally the driver does it within THROTTLE seconds).
function Map:Refresh()
  self:RefreshWorld()
  self:RefreshMinimap()
end
