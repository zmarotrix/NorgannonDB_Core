-- The suite's page in the game's Settings window (Options > AddOns > NorgannonDB): the Core's version, whether the
-- game data is loaded, your NorgannonDB add-ons as tiles, and credits. Suite add-ons add their own pages under it with
-- Core:AddSettingsPage.

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

local TILE_H, GAP, SIDE = 50, 8, 16
local FOOTER_H = 84            -- credits and the two controls under the tiles
local FALLBACK_W = 600         -- the page's width before the game has laid it out

-- Only what isn't simply running gets a word: running is the normal case, and the version says it's there.
local function problem(key, state)
  if state == "off" then return "Turned off: " .. tostring(Core:AddonProblem(key) or "see chat"), C.bad end
  if state == "installed" then return "Installed, not loaded", C.warn end
end

local function openAddon(key)
  local MB = Core.MinimapButton
  if not (MB and MB.entries and MB.entries[key]) then return end
  -- the game's Settings window sits over everything: step out of it first (never in combat, where it's protected)
  if SettingsPanel and SettingsPanel:IsShown() and not InCombatLockdown() and HideUIPanel then
    pcall(HideUIPanel, SettingsPanel)
  end
  MB:Click(key, "LeftButton")
end

-- One tile: mark, name in the add-on's accent, its role (or what's wrong) and its version. A click opens the add-on,
-- as its row in the minimap flyout does, and hovering shows the same tooltip.
local function newTile(parent, info)
  local tile = CreateFrame("Button", nil, parent)
  tile:SetHeight(TILE_H)
  tile.key = info.key
  tile.bg = UI.Round(tile, "BACKGROUND", 0, 6)
  tile.bg:SetColor(C.stone2, .9)
  tile.mark = UI.Mark(tile, info.key, 32)
  tile.mark:SetPoint("LEFT", 9, 0)
  tile.version = UI.Text(tile, "body", 12, C.faint)
  tile.version:SetPoint("TOPRIGHT", -10, -8)
  tile.version:SetJustifyH("RIGHT")
  tile.name = UI.Text(tile, "title", 15, UI.AccentText(info.key))
  tile.name:SetPoint("TOPLEFT", tile.mark, "TOPRIGHT", 10, 1)
  tile.name:SetText(info.kicker and (info.kicker .. " " .. info.name) or info.name)
  tile.role = UI.Text(tile, "body", 12, C.muted)
  tile.role:SetPoint("TOPLEFT", tile.name, "BOTTOMLEFT", 0, -3)
  tile.role:SetText(info.role or "")
  tile.state = UI.Text(tile, "body", 12)       -- what's wrong, in place of the role; empty while running
  tile.state:SetPoint("TOPLEFT", tile.role, "TOPLEFT")
  tile:SetScript("OnEnter", function(self)
    self.bg:SetColor(UI.Mix(C.stone2, UI.Accent(self.key), .14), 1)
    local entry = Core.MinimapButton and Core.MinimapButton.entries[self.key]
    if entry and entry.tooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      pcall(entry.tooltip, GameTooltip)
      GameTooltip:Show()
    end
  end)
  tile:SetScript("OnLeave", function(self)
    self.bg:SetColor(C.stone2, .9)
    GameTooltip:Hide()
  end)
  tile:SetScript("OnClick", function(self) openAddon(self.key) end)
  return tile
end

-- Places the tiles of what's on this computer in two columns; missing add-ons get none, and the rest close up.
local function layout(page)
  local width = page.area:GetWidth()
  if not width or width < 100 then width = FALLBACK_W - 2 * SIDE end
  local colW = math.floor((width - GAP) / 2)
  page.area.content:SetWidth(width)
  local shown = 0
  for _, tile in ipairs(page.rows) do
    local state = Core:AddonState(tile.key)
    tile:SetShown(state ~= "missing")
    if state ~= "missing" then
      local version = Core:AddonVersion(tile.key)
      tile.version:SetText(version and ("v" .. version) or "")
      local text, color = problem(tile.key, state)
      tile.state:SetText(text or "")
      if color then tile.state:SetTextColor(color[1], color[2], color[3]) end
      tile.role:SetShown(text == nil)
      local col, row = shown % 2, math.floor(shown / 2)
      tile:SetWidth(colW)
      local textW = colW - 61                -- the tile less its mark and margins
      tile.name:SetWidth(textW - 56)         -- room for the version
      tile.role:SetWidth(textW)
      tile.state:SetWidth(textW)
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", page.area.content, "TOPLEFT", col * (colW + GAP), -row * (TILE_H + GAP))
      shown = shown + 1
    end
  end
  page.area.content:SetHeight(math.max(1, math.ceil(shown / 2) * (TILE_H + GAP)))
  page.suiteHead:SetShown(shown > 0)
  page.shown = shown
end

local function buildPage()
  local page = CreateFrame("Frame")
  page:Hide()

  local mark = UI.Mark(page, "core", 48)
  mark:SetPoint("TOPLEFT", SIDE, -14)
  local title = UI.Text(page, "title", 26, C.goldSoft)
  title:SetPoint("TOPLEFT", mark, "TOPRIGHT", 12, -2)
  title:SetText("NorgannonDB")
  local role = UI.Text(page, "body", 14, C.muted)
  role:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  role:SetText("The core of the suite: your add-ons, their versions and credits")
  page.dbLine = UI.Text(page, "body", 13, C.faint)
  page.dbLine:SetPoint("TOPLEFT", mark, "BOTTOMLEFT", 0, -10)

  local suiteHead = UI.Text(page, "title", 16, C.goldSoft)
  suiteHead:SetPoint("TOPLEFT", page.dbLine, "BOTTOMLEFT", 0, -16)
  suiteHead:SetText("Your add-ons")
  page.suiteHead = suiteHead

  -- the tiles scroll when there are more than fit (a small UI scale, a short window)
  local area = UI.ScrollArea(page)
  area:SetPoint("TOPLEFT", suiteHead, "BOTTOMLEFT", 0, -8)
  area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -SIDE, FOOTER_H)
  area:HookScript("OnSizeChanged", function() if page:IsShown() then layout(page) end end)
  page.area = area

  page.rows = {}
  local list = {}
  for _, info in ipairs(Core.SUITE) do list[#list + 1] = info end
  list[#list + 1] = Core:GetAddonInfo("collector")   -- NorgannonDB itself is the page's header
  for _, info in ipairs(list) do page.rows[#page.rows + 1] = newTile(area.content, info) end

  -- footer: the credits the licences ask for, then the gallery and the debug log
  local credits = UI.Text(page, "body", 12, C.muted)
  credits:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", SIDE, 44)
  credits:SetWordWrap(true)
  credits:SetText("Made by " .. UI.Code(C.goldSoft) .. "Maro|r. Quest, NPC, object and item data from Questie and "
    .. "QuestieDB (GPL-3.0) and pfQuest by Shagu (MIT). Fonts: Marcellus and Alegreya Sans (SIL Open Font License).")
  page.credits = credits

  local gallery = UI.Button(page, "Open the UI gallery", "quiet", function() Core:ShowGallery() end)
  gallery:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", SIDE, 12)
  local debugLabel = UI.Text(page, "body", 13, C.muted)
  debugLabel:SetPoint("LEFT", gallery, "RIGHT", 20, 0)
  debugLabel:SetText("Debug log")
  page.debug = UI.Toggle(page, function(on)
    if Core.db then Core.db.debug = on end
  end)
  page.debug:SetPoint("LEFT", debugLabel, "RIGHT", 8, 0)

  function page:OnRefresh()
    local info = NorgannonDB and NorgannonDB.info
    if Core:HasData() and info then
      local stats = info.stats or {}
      self.dbLine:SetText(string.format("Core %s  ·  NorgannonDB data %s (%s): %s quests, %s NPCs, %s objects, %s items",
        Core:Version(), info.generated or "?", info.build or "?", stats.quests or "?", stats.npcs or "?",
        stats.objects or "?", stats.items or "?"))
    else
      self.dbLine:SetText(string.format("Core %s  ·  NorgannonDB, the game data, isn't loaded: add-ons that need it "
        .. "are off, the rest run", Core:Version()))
    end
    local pageW = self:GetWidth()
    if not pageW or pageW < 100 then pageW = FALLBACK_W end
    self.dbLine:SetWidth(pageW - 2 * SIDE)
    self.credits:SetWidth(pageW - 2 * SIDE)
    layout(self)
    self.debug:SetOn(Core.db and Core.db.debug, true)
  end
  page:SetScript("OnShow", page.OnRefresh)
  return page
end

Core:OnReady(function()
  if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
  local page = buildPage()
  local category = Settings.RegisterCanvasLayoutCategory(page, "NorgannonDB")
  Settings.RegisterAddOnCategory(category)
  Core.settingsPage, Core.settingsCategory = page, category
end)

-- the compass and the arrow belong to the Core: their page sits under NorgannonDB
Core:OnReady(function()
  if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return end
  local page = CreateFrame("Frame")
  page:Hide()
  local list = UI.SettingsList(page)
  list:Header("Compass")
  list:Toggle("Show the compass", "One marker per tracked objective, across the top of the screen.",
    function() return Core.Compass:IsEnabled() end, function(on) Core.Compass:SetShown(on) end)
  list:Slider("Compass size", nil, .6, 1.6, .05,
    function() return Core.Compass:GetSize() end, function(v) Core.Compass:SetSize(v) end, "%.0f%%", 100)
  list:Buttons("Position", "Drag it anywhere; right-click it (or Lock) when done.", {
    { "Move", function() Core.Compass:SetMovable(true) end },
    { "Lock", function() Core.Compass:SetMovable(false) end },
    { "Reset", function() Core.Compass:ResetPosition() end },
  })
  list:Header("Waypoint arrow")
  list:Slider("Arrow size", "The arrow appears only when you point it somewhere.", .6, 1.6, .05,
    function() return Core.Arrow:GetSize() end, function(v) Core.Arrow:SetSize(v) end, "%.0f%%", 100)
  page:SetScript("OnShow", function() list:Refresh() end)
  Core.compassPage, Core.compassList = page, list
  Core:OnLogin(function()
    if Core.settingsCategory then Core.compassCategory = Core:AddSettingsPage(page, "Compass & arrow") end
  end)
end)

---Opens the suite's Settings page. The game's Settings window can't open in combat: then it opens when the fight ends.
function Core:OpenSettings()
  if InCombatLockdown and InCombatLockdown() then
    Core:Print("Settings open when this fight ends.")
    Core:AfterCombat(function() Core:OpenSettings() end, "core.settings")
    return
  end
  if self.settingsCategory and Settings and Settings.OpenToCategory then
    pcall(Settings.OpenToCategory, self.settingsCategory:GetID())
  end
end

---Adds an addon's own page under the suite's Settings page; returns the category.
function Core:AddSettingsPage(frame, name)
  if not (self.settingsCategory and Settings and Settings.RegisterCanvasLayoutSubcategory) then return end
  return Settings.RegisterCanvasLayoutSubcategory(self.settingsCategory, frame, name)
end
