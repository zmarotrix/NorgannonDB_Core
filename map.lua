-- The shared map layer: suite addons submit pins, the Core draws them once on the world map
-- and the minimap. Four addons never stack four pin layers, and every pin follows the same
-- rules: constant on-screen size while the map zooms, draw order by layer, a soft glow over a
-- quest's dense spawns while you hover it, and no centre reported to the gamepad map cursor (which would taint it).
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
local CLUSTER_DISTANCE = 7        -- percent of the map: pins this close join one cluster
local CLUSTER_AREA_MIN = 6        -- a cluster this big gets a soft glow, shown while its quest is hovered
local MINIMAP_MAX = 150           -- most pins drawn on the minimap, nearest first
local THROTTLE = 0.05

-- Pin icons. Quest givers use the game's own marks so they read like the default UI: the
-- client's atlas first, the classic gossip icon second, our own glyph only as a last resort.
-- grey = desaturated (low-level available quests, turn-ins that are not complete yet).
local ICONS = {
  pin = { file = UI.TEX.pin, tint = true },
  diamond = { file = UI.TEX.pinDiamond, tint = true },
  exclaim = { atlas = "QuestNormal", file = "Interface\\GossipFrame\\AvailableQuestIcon", fallback = UI.TEX.exclaim },
  exclaimDaily = { atlas = "QuestDaily", file = "Interface\\GossipFrame\\DailyQuestIcon", fallback = UI.TEX.exclaim },
  exclaimGrey = { atlas = "QuestNormal", file = "Interface\\GossipFrame\\AvailableQuestIcon", fallback = UI.TEX.exclaim, grey = true },
  question = { atlas = "QuestTurnin", file = "Interface\\GossipFrame\\ActiveQuestIcon", fallback = UI.TEX.question },
  questionRepeat = { atlas = "QuestRepeatableTurnin", file = "Interface\\GossipFrame\\DailyActiveQuestIcon", fallback = UI.TEX.question },
  questionGrey = { atlas = "QuestTurnin", file = "Interface\\GossipFrame\\IncompleteQuestIcon", fallback = UI.TEX.question, grey = true },
}
Map.ICONS = ICONS

-- Town services and gathering (Core 1.8): the client's own icons, the ones pfQuest copied.
-- The modern minimap-tracking atlas first, the classic Minimap\Tracking file second, then a
-- spell or item icon cropped round. Never tinted. `/norg icons` shows which one loaded.
local TRACKING, ICON = "Interface\\Minimap\\Tracking\\", "Interface\\Icons\\"
local SERVICE_ICONS = {
  auctioneer = { atlas = "Auctioneer", files = { TRACKING .. "Auctioneer" }, round = ICON .. "INV_Misc_Coin_02" },
  banker = { atlas = "Banker", files = { TRACKING .. "Banker" }, round = ICON .. "INV_Misc_Bag_10" },
  battlemaster = { atlas = "BattleMaster", files = { TRACKING .. "BattleMaster" }, round = ICON .. "INV_BannerPVP_01" },
  flight = { atlas = "FlightMaster", files = { TRACKING .. "FlightMaster", "Interface\\TaxiFrame\\UI-Taxi-Icon-Green" },
    round = ICON .. "Ability_Mount_Wyvern_01" },
  innkeeper = { atlas = "Innkeeper", files = { TRACKING .. "Innkeeper" }, round = ICON .. "INV_Misc_Rune_01" },
  mailbox = { atlas = "Mailbox", files = { TRACKING .. "Mailbox" }, round = ICON .. "INV_Letter_15" },
  repair = { atlas = "Repair", files = { TRACKING .. "Repair" }, round = ICON .. "Trade_BlackSmithing" },
  stablemaster = { atlas = "StableMaster", files = { TRACKING .. "StableMaster" }, round = ICON .. "Ability_Hunter_BeastTaming" },
  vendor = { atlas = "Food", files = { TRACKING .. "Food" }, round = ICON .. "INV_Misc_Food_14" },
  trainer = { atlas = "Class", files = { TRACKING .. "Class" }, round = ICON .. "INV_Misc_Book_09" },
  spirithealer = { round = ICON .. "Spell_Holy_Resurrection" },
  meetingstone = { round = ICON .. "Spell_Shadow_Twilight" },      -- Ritual of Summoning
  chests = { round = ICON .. "Racial_Dwarf_FindTreasure" },
  herbs = { round = ICON .. "INV_Misc_Flower_02" },                 -- Find Herbs
  mines = { round = ICON .. "Spell_Nature_Earthquake" },            -- Find Minerals
  fish = { round = ICON .. "Trade_Fishing" },
}
for key, spec in pairs(SERVICE_ICONS) do
  spec.fallback = UI.TEX.pinDiamond
  ICONS["service." .. key] = spec
end
Map.SERVICE_ICONS = SERVICE_ICONS

local function hasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- a square icon cropped to a circle: trimmed border and a round mask (made once per frame)
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function setRound(tex, round)
  local parent = tex:GetParent()
  local mask = parent and parent.ndbRoundMask
  if round and not mask and parent and parent.CreateMaskTexture then
    mask = parent:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
    mask:SetAllPoints(tex)
    parent.ndbRoundMask = mask
  end
  if round then
    tex:SetTexCoord(.08, .92, .08, .92)
    if mask and not tex.ndbMasked then tex:AddMaskTexture(mask) tex.ndbMasked = true end
  else
    tex:SetTexCoord(0, 1, 0, 1)
    if mask and tex.ndbMasked then tex:RemoveMaskTexture(mask) tex.ndbMasked = nil end
  end
end

-- SetTexture reports false for a missing file on modern clients
local function tryFile(tex, file) return file and tex:SetTexture(file) ~= false end

---Which source of an icon the client has: "atlas", "file", "round" or "fallback" (and the name).
function Map.IconSource(name)
  local spec = ICONS[name]
  if not spec then return nil end
  if spec.atlas and hasAtlas(spec.atlas) then return "atlas", spec.atlas end
  local probe = Map.probe
  if not probe then
    probe = UIParent:CreateTexture()
    probe:Hide()
    Map.probe = probe
  end
  for _, file in ipairs(spec.files or { spec.file }) do
    if tryFile(probe, file) then return "file", file end
  end
  if tryFile(probe, spec.round) then return "round", spec.round end
  return "fallback", spec.fallback
end

-- Sets a pin texture from ICONS (or a plain texture path); returns whether it may be tinted.
local function setIcon(tex, name)
  local spec = ICONS[name or "pin"]
  tex:SetDesaturated(false)
  local round = false
  if not spec then
    tex:SetTexture(name)
  elseif spec.atlas and hasAtlas(spec.atlas) then
    tex:SetAtlas(spec.atlas)
  else
    local done = false
    for _, file in ipairs(spec.files or { spec.file }) do
      if tryFile(tex, file) then done = true break end
    end
    if not done and tryFile(tex, spec.round) then done, round = true, true end
    if not done then tex:SetTexture(spec.fallback or UI.TEX.pin) end
  end
  setRound(tex, round)
  if spec and spec.grey then tex:SetDesaturated(true) end
  if not spec then return true end
  return spec.tint or false
end
Map.SetIcon = setIcon

local function maps() return NorgannonDB and NorgannonDB.maps end
function Map.AreaToUiMap(area) local m = maps() return area and m and m.areaToUiMap[area] end
function Map.UiMapToArea(uiMap) local m = maps() return uiMap and m and m.uiMapToArea[uiMap] end

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
    table.sort(list, function(a, b) return (a.layer or 1) < (b.layer or 1) end)
  end
  indexDirty = false
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
-- Clustering: single-link within CLUSTER_DISTANCE, per cluster key, through a grid so it
-- stays linear in the number of pins
-------------------------------------------------------------------------------------------

local function clusterPins(pins)
  local groups = {}
  for _, pin in ipairs(pins) do
    if pin.cluster then
      groups[pin.cluster] = groups[pin.cluster] or {}
      table.insert(groups[pin.cluster], pin)
    end
  end
  local clusters = {}
  local d2 = CLUSTER_DISTANCE * CLUSTER_DISTANCE
  for _, group in pairs(groups) do
    if #group >= CLUSTER_AREA_MIN then
      local parent, grid = {}, {}
      local function find(i)
        while parent[i] ~= i do parent[i] = parent[parent[i]] i = parent[i] end
        return i
      end
      for i, pin in ipairs(group) do
        parent[i] = i
        local ri = i   -- the root of i's set, kept current so each pair needs one find
        local px, py = pin.x, pin.y
        local cx, cy = math.floor(px / CLUSTER_DISTANCE), math.floor(py / CLUSTER_DISTANCE)
        for gx = cx - 1, cx + 1 do
          for gy = cy - 1, cy + 1 do
            local cell = grid[gx * 1024 + gy]
            if cell then
              for n = 1, #cell do
                local j = cell[n]
                local o = group[j]
                local dx, dy = px - o.x, py - o.y
                if dx * dx + dy * dy <= d2 then
                  local rj = find(j)
                  if ri ~= rj then
                    parent[ri] = rj
                    ri = rj
                  end
                end
              end
            end
          end
        end
        local key = cx * 1024 + cy
        local cell = grid[key]
        if not cell then
          cell = {}
          grid[key] = cell
        end
        cell[#cell + 1] = i
      end
      local sets = {}
      for i in ipairs(group) do
        local root = find(i)
        sets[root] = sets[root] or {}
        table.insert(sets[root], group[i])
      end
      for _, members in pairs(sets) do
        if #members >= CLUSTER_AREA_MIN then
          local sx, sy = 0, 0
          for _, p in ipairs(members) do sx, sy = sx + p.x, sy + p.y end
          local mx, my = sx / #members, sy / #members
          local rx, ry = 0, 0
          for _, p in ipairs(members) do
            rx, ry = math.max(rx, math.abs(p.x - mx)), math.max(ry, math.abs(p.y - my))
          end
          table.insert(clusters, { x = mx, y = my, rx = rx + 3, ry = ry + 3, members = members,
            color = members[1].color })
        end
      end
    end
  end
  return clusters
end
Map.Cluster = clusterPins

-------------------------------------------------------------------------------------------
-- Pin frames
-------------------------------------------------------------------------------------------

-- the group a pin highlights with: its quest, else its cluster
local function highlightKey(pin)
  return pin and (pin.quest and ("q" .. pin.quest) or pin.highlight or pin.cluster)
end
Map.HighlightKey = highlightKey

local DIM = .3
local applyHighlight   -- defined after the frame pools

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
  self.icon:SetSize(self.size * 1.25, self.size * 1.25)
  Map:SetHighlight(highlightKey(pin))
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if pin.tooltip then
    Core.SafeCall(pin.tooltip, pin, GameTooltip)
  elseif pin.title then
    GameTooltip:AddLine(pin.title, 1, 1, 1)
  end
  if (pin.quest or pin.colorKey) and not pin.onClick then
    local f = UI.C.faint
    GameTooltip:AddLine("Click: new colour  ·  Right-click: choose colour", f[1], f[2], f[3])
  end
  if pin.shiftHint then
    local f = UI.C.faint
    GameTooltip:AddLine(pin.shiftHint, f[1], f[2], f[3])
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

local function dress(f, pin, size, alpha)
  local tintable = setIcon(f.icon, pin.icon)
  local c = pinColor(pin)
  if c and tintable then f.icon:SetVertexColor(c[1], c[2], c[3]) else f.icon:SetVertexColor(1, 1, 1) end
  f.size = size
  f:SetSize(size, size)
  f.icon:SetSize(size, size)
  f.baseAlpha = alpha or 1
  local key = Map.highlight
  f:SetAlpha(f.baseAlpha * ((key and highlightKey(pin) ~= key) and DIM or 1))
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
        x = x * 100, y = y * 100, icon = pin.icon, quest = pin.quest, color = pin.color,
        layer = pin.layer, size = (pin.icon == "pin" or pin.icon == nil) and 9 or 14, title = pin.title,
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

local function isZoneMap(uiMap)
  local info = C_Map.GetMapInfo(uiMap)
  return not (info and info.mapType and Enum and Enum.UIMapType and info.mapType < Enum.UIMapType.Zone)
end

function Map:RefreshWorld()
  worldDirty = false
  local n, a = 0, 0
  local uiMap = WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
  if uiMap ~= shownMap then
    -- one announcement per change, so add-ons needn't poll the map
    local mapArea = uiMap and Map.UiMapToArea(uiMap)
    C_Timer.After(0, function() Core:Send("NORGANNON_WORLDMAP_CHANGED", uiMap or nil, mapArea) end)
  end
  shownMap = uiMap
  local area = uiMap and Map.UiMapToArea(uiMap)
  local pins = area and Map:PinsIn(area) or {}
  pinScale = canvasScale()
  local continent = uiMap and not isZoneMap(uiMap)
  if continent then pins = continentMarkers(uiMap) end

  local clusters = continent and {} or clusterPins(pins)
  for _, cluster in ipairs(clusters) do
    a = a + 1
    local f = areaFrame(a)
    local c = cluster.color or pinColor(cluster.members[1]) or UI.C.goldSoft
    f.glow:SetVertexColor(c[1], c[2], c[3], .4)   -- shown only on hover, so it can be fairly strong
    f.key = highlightKey(cluster.members[1])
    f.active = true
    f:SetFrameLevel(WORLD_LEVEL + 1)
    f:ClearAllPoints()
    f:SetSize(cluster.rx * 2 / 100 * world:GetWidth(), cluster.ry * 2 / 100 * world:GetHeight())
    f:SetPoint("CENTER", world, "TOPLEFT", cluster.x / 100 * world:GetWidth(), -cluster.y / 100 * world:GetHeight())
    -- the glow only shows a quest's spread while one of its pins is hovered
    f:SetShown(Map.highlight ~= nil and f.key == Map.highlight)
  end
  for i = a + 1, #areaFrames do areaFrames[i]:Hide() areaFrames[i].active = nil end

  -- pins sharing an overlapKey (the same quest's "!" or "?") don't stack: one is skipped when
  -- another of its key is already drawn within its own size on screen. Measured in screen
  -- pixels, so zooming in separates spawns that are really apart.
  local drawn = {}
  local w, h = world:GetWidth(), world:GetHeight()
  local function overlaps(pin)
    local key = pin.overlapKey
    if not key then return false end
    local sx, sy = pin.x / 100 * w / pinScale, pin.y / 100 * h / pinScale
    local reach = (pin.size or 7) * .9
    local list = drawn[key]
    if list then
      for _, p in ipairs(list) do
        local dx, dy = p[1] - sx, p[2] - sy
        if dx * dx + dy * dy < reach * reach then return true end
      end
    else
      list = {}
      drawn[key] = list
    end
    list[#list + 1] = { sx, sy }
    return false
  end
  Map.stats.overlapped = 0

  for _, pin in ipairs(pins) do
    if pin.world ~= false and overlaps(pin) then
      Map.stats.overlapped = Map.stats.overlapped + 1
    elseif pin.world ~= false then
      n = n + 1
      local f = worldPins[n] or newPin(world)
      worldPins[n] = f
      dress(f, pin, pin.size or 7, pin.alpha)
      f:SetFrameLevel(WORLD_LEVEL + 2 + (pin.layer or 1))
      place(f, pin.x, pin.y)
      f:Show()
    end
  end
  for i = n + 1, #worldPins do worldPins[i]:Hide() worldPins[i].pin = nil end
  Map.stats.world, Map.stats.clusters = n, a
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

local SHAPES = {
  -- { upper-left, lower-left, upper-right, lower-right } quadrants that are round
  ["SQUARE"] = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { true, false, false, false }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { false, false, false, true },
  ["SIDE-LEFT"] = { true, true, false, false }, ["SIDE-RIGHT"] = { false, false, true, true },
  ["SIDE-TOP"] = { true, false, true, false }, ["SIDE-BOTTOM"] = { false, true, false, true },
  ["TRICORNER-TOPLEFT"] = { true, true, true, false }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { false, true, true, true },
}

local miniPins = {}
local mm = {}

local function prepareMinimap()
  local px, py, instance = HBD:GetPlayerWorldPosition()
  if not px or Core.IsSecret(px) then return false end
  local rotate = GetCVar("rotateMinimap") == "1"
  local facing = rotate and GetPlayerFacing() or 0
  if rotate and (not facing or Core.IsSecret(facing)) then return false end
  mm.x, mm.y, mm.instance = px, py, instance
  mm.rotate, mm.sin, mm.cos = rotate, math.sin(facing), math.cos(facing)
  mm.radius = (C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius())
    or (Minimap.GetViewRadius and Minimap:GetViewRadius()) or 150
  mm.halfw, mm.halfh = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
  mm.shape = GetMinimapShape and SHAPES[GetMinimapShape() or "ROUND"]
  return true
end

---Pixel offset of a pin from the minimap centre, and whether it is inside the minimap.
local function minimapOffset(pin, margin)
  local wx, wy, instance = worldOf(pin)
  if not wx or instance ~= mm.instance then return end
  local dx, dy = mm.x - wx, mm.y - wy
  if mm.rotate then dx, dy = dx * mm.cos - dy * mm.sin, dx * mm.sin + dy * mm.cos end
  local x, y = dx / mm.radius * mm.halfw, dy / mm.radius * mm.halfh
  local distance = math.sqrt(x * x + y * y)
  local round = true
  if mm.shape and dx ~= 0 and dy ~= 0 then
    local q = dx < 0 and 1 or 3
    round = dy < 0 and mm.shape[q] or mm.shape[q + 1]
  end
  local inside
  if round then
    inside = distance + margin < mm.halfw
  else
    inside = math.abs(x) + margin < mm.halfw and math.abs(y) + margin < mm.halfh
  end
  return x, y, distance, inside
end

function Map:RefreshMinimap()
  local n = 0
  if Minimap:IsVisible() and prepareMinimap() then
    if indexDirty then rebuildIndex() end
    local visible = {}
    for _, pins in pairs(byArea) do
      for _, pin in ipairs(pins) do
        if pin.minimap ~= false then
          local x, y, distance, inside = minimapOffset(pin, 6)
          if inside then visible[#visible + 1] = { pin = pin, x = x, y = y, d = distance } end
        end
      end
    end
    if #visible > MINIMAP_MAX then
      table.sort(visible, function(p, q) return p.d < q.d end)
      for i = MINIMAP_MAX + 1, #visible do visible[i] = nil end
    end
    local drawn = {}   -- the same overlapKey rule as the world map, in minimap pixels
    for _, v in ipairs(visible) do
      local key, skip = v.pin.overlapKey, false
      if key then
        local reach = (v.pin.minimapSize or 7) * .9
        drawn[key] = drawn[key] or {}
        for _, p in ipairs(drawn[key]) do
          local dx, dy = p[1] - v.x, p[2] - v.y
          if dx * dx + dy * dy < reach * reach then skip = true break end
        end
        if not skip then table.insert(drawn[key], { v.x, v.y }) end
      end
      if not skip then
      n = n + 1
      local f = miniPins[n] or newPin(Minimap)
      miniPins[n] = f
      dress(f, v.pin, v.pin.minimapSize or 7, v.pin.alpha)
      f:SetFrameLevel(Minimap:GetFrameLevel() + 5 + (v.pin.layer or 1))
      f:ClearAllPoints()
      f:SetPoint("CENTER", Minimap, "CENTER", -v.x, v.y)
      f:Show()
      end
    end
  end
  for i = n + 1, #miniPins do miniPins[i]:Hide() miniPins[i].pin = nil end
  Map.stats.minimap = n
end

-------------------------------------------------------------------------------------------
-- Highlight: fade every pin outside the hovered group
-------------------------------------------------------------------------------------------

applyHighlight = function()
  local key = Map.highlight
  local function fade(f)
    if f:IsShown() and f.pin then
      f:SetAlpha((f.baseAlpha or 1) * ((key and highlightKey(f.pin) ~= key) and DIM or 1))
    end
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
-- Driver: redraw the world map when it opens, changes map or gets new pins; rescale on
-- zoom; the minimap follows the player every THROTTLE seconds
-------------------------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
  if Map.pulse then Map.ApplyPulse() end   -- defined below the driver
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
Map.ApplyPulse = applyPulse

---Draws everything now (normally the driver does it within THROTTLE seconds).
function Map:Refresh()
  self:RefreshWorld()
  self:RefreshMinimap()
end
