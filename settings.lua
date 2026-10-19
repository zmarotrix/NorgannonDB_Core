-- The suite's page in the game's Settings window (Options > AddOns > NorgannonDB): what is
-- installed, the database version and credits. Suite addons add their own pages under it with
-- Core:AddSettingsPage.

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

local STATE_TEXT = {
  loaded = { "Running", C.easy },
  installed = { "Installed, not loaded", C.fair },
  missing = { "Not installed", C.faint },
}

local function buildPage()
  local page = CreateFrame("Frame")
  page:Hide()

  local mark = UI.Mark(page, "norgannondb", 56)
  mark:SetPoint("TOPLEFT", 16, -14)
  local title = UI.Text(page, "title", 28, C.goldSoft)
  title:SetPoint("TOPLEFT", mark, "TOPRIGHT", 14, -4)
  title:SetText("NorgannonDB")
  local role = UI.Text(page, "body", 14, C.muted)
  role:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  role:SetText("The shared game database, and the core of the suite")
  page.dbLine = UI.Text(page, "body", 13, C.faint)
  page.dbLine:SetPoint("TOPLEFT", mark, "BOTTOMLEFT", 0, -10)

  local suiteHead = UI.Text(page, "title", 16, C.goldSoft)
  suiteHead:SetPoint("TOPLEFT", page.dbLine, "BOTTOMLEFT", 0, -18)
  suiteHead:SetText("The suite")

  page.rows = {}
  local previous = suiteHead
  local list = {}
  for _, info in ipairs(Core.SUITE) do table.insert(list, info) end
  table.insert(list, Core.FAMILY[2])   -- the collector (NorgannonDB itself is the header)
  for _, info in ipairs(list) do
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(560, 40)
    row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, previous == suiteHead and -8 or -4)
    row.mark = UI.Mark(row, info.key, 32)
    row.mark:SetPoint("LEFT")
    local accent = UI.Hex(info.accent)
    row.name = UI.Text(row, "title", 16, accent)
    row.name:SetPoint("TOPLEFT", row.mark, "TOPRIGHT", 10, -1)
    row.name:SetText(info.kicker and (info.kicker .. " " .. info.name) or info.name)
    row.role = UI.Text(row, "body", 13, C.muted)
    row.role:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.role:SetText(info.role .. (info.slash and ("  " .. UI.Code(C.faint) .. info.slash .. "|r") or ""))
    row.state = UI.Text(row, "body", 13)
    row.state:SetPoint("RIGHT", 0, 0)
    row.state:SetJustifyH("RIGHT")
    row.key = info.key
    table.insert(page.rows, row)
    previous = row
  end

  local creditsHead = UI.Text(page, "title", 16, C.goldSoft)
  creditsHead:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -18)
  creditsHead:SetText("Credits")
  local credits = UI.Text(page, "body", 13, C.text)
  credits:SetPoint("TOPLEFT", creditsHead, "BOTTOMLEFT", 0, -6)
  credits:SetWidth(560)
  credits:SetWordWrap(true)
  credits:SetText("Designed and built by " .. UI.Code(C.goldSoft) .. "Maro|r.\n"
    .. UI.Code(C.muted) .. "Quest, NPC, object and item data from Questie and QuestieDB (GPL-3.0) and pfQuest by Shagu (MIT). "
    .. "Fonts: Marcellus and Alegreya Sans (SIL Open Font License).|r")

  page.credits = credits

  local gallery = UI.Button(page, "Open the UI gallery", "quiet", function() Core:ShowGallery() end)
  gallery:SetPoint("TOPLEFT", credits, "BOTTOMLEFT", 0, -16)

  local debugLabel = UI.Text(page, "body", 13, C.muted)
  debugLabel:SetPoint("LEFT", gallery, "RIGHT", 20, 0)
  debugLabel:SetText("Debug log")
  page.debug = UI.Toggle(page, function(on) if Core.db then Core.db.debug = on end end)
  page.debug:SetPoint("LEFT", debugLabel, "RIGHT", 8, 0)

  function page:OnRefresh()
    local info = NorgannonDB and NorgannonDB.info
    local stats = info and info.stats or {}
    self.dbLine:SetText(string.format("Core %s  ·  data %s (%s)  ·  %s quests, %s NPCs, %s objects, %s items",
      Core:Version(), info and info.generated or "?", info and info.build or "?", stats.quests or "?",
      stats.npcs or "?", stats.objects or "?", stats.items or "?"))
    for _, row in ipairs(self.rows) do
      local state = Core:AddonState(row.key)
      local text, c = STATE_TEXT[state][1], STATE_TEXT[state][2]
      local version = state ~= "missing" and Core:AddonVersion(row.key)
      row.state:SetText(UI.Code(c) .. text .. "|r" .. (version and (UI.Code(C.faint) .. "  v" .. version .. "|r") or ""))
      row:SetAlpha(state == "missing" and .6 or 1)
    end
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

---Opens the suite's Settings page.
function Core:OpenSettings()
  if self.settingsCategory and Settings and Settings.OpenToCategory then
    Settings.OpenToCategory(self.settingsCategory:GetID())
  end
end

---Adds an addon's own page under the suite's Settings page; returns the category.
function Core:AddSettingsPage(frame, name)
  if not (self.settingsCategory and Settings and Settings.RegisterCanvasLayoutSubcategory) then return end
  return Settings.RegisterCanvasLayoutSubcategory(self.settingsCategory, frame, name)
end
