-- /norg ui: the UI kit in game, the counterpart of design/suite/index.html. Switch the accent
-- between the suite addons, try every control, and scroll the full NorgannonDB quest list in a
-- virtual list to check the look and the performance on the real client.

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

local gallery

local NO_LEVEL = 1000                -- sorts a quest with no level at all after every other

local function section(parent, text, anchor, y)
  local label = UI.Text(parent, "title", 15, C.goldSoft)
  if anchor == parent then
    label:SetPoint("TOPLEFT", anchor, "TOPLEFT", 16, y)
  else
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
  end
  label:SetText(text)
  return label
end

-- a row of widgets under an anchor: each one sits to the right of the one before
local function placeInRow(widget, previous, anchor, gap, y)
  if previous then
    widget:SetPoint("TOPLEFT", previous, "TOPRIGHT", gap, 0)
  else
    widget:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
  end
end

-- Every quest with its localized name and level, sorted by level then name (built once).
local quests
local function questList()
  if quests then return quests end
  quests = {}
  local DB = NorgannonDB
  if not (DB and DB.quests) then return quests end
  for id in pairs(DB.quests) do
    local q = DB:Peek("quests", id)
    if q and q.name and q.hidden ~= true then   -- hidden = not obtainable in the game (SPEC 1.2)
      local name = DB.L and DB:L("quests", id, "name") or q.name
      local level = q.level or 0
      -- -1 scales with the player: sort it by its minimum level
      local sortLevel = level > 0 and level or q.minLevel or NO_LEVEL
      table.insert(quests, { id = id, name = name, lower = string.lower(name), level = level, minLevel = q.minLevel, sortLevel = sortLevel })
    end
  end
  table.sort(quests, function(a, b)
    if a.sortLevel ~= b.sortLevel then return a.sortLevel < b.sortLevel end
    return a.name < b.name
  end)
  return quests
end

-------------------------------------------------------------------------------------------
-- Left column: the controls
-------------------------------------------------------------------------------------------

-- progress: yours in the accent, a party member's dimmer (suite.css .az-bar / .party)
local function progressRow(parent, anchor, name, current, total, kind, y)
  local label = UI.Text(parent, "body", 14, kind and C.muted or C.text)
  label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
  label:SetText(name)
  local bar = UI.Bar(parent, kind)
  bar:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -5)
  bar:SetWidth(350)
  bar:SetProgress(current, total)
  local count = UI.Text(parent, "body", 13, C.muted)
  count:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 4)
  count:SetJustifyH("RIGHT")
  count:SetText(current .. "/" .. total)
  bar.label, bar.count = label, count
  return bar
end

local function buildControls(w, tabs)
  local left = CreateFrame("Frame", nil, w.body)
  left:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -6)
  left:SetPoint("BOTTOMLEFT", 0, 8)
  left:SetWidth(380)

  local s = section(left, "Buttons", left, -8)
  local b1 = UI.Button(left, "Track", "primary")
  b1:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -8)
  local b2 = UI.Button(left, "Show on map", "quiet")
  b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
  local b3 = UI.Button(left, "Set as goal", "accent")
  b3:SetPoint("LEFT", b2, "RIGHT", 8, 0)

  s = section(left, "Filters", b1, -18)
  local chips = {}
  local chipDefs = { { "Quests", C.gold, true }, { "Herbs", { .55, .9, .45 } }, { "Ore", { .75, .78, .85 } }, { "Rares", { 1, .5, .3 } }, { "Services" } }
  for i, def in ipairs(chipDefs) do
    local chip = UI.Chip(left, def[1], def[2])
    chip:SetOn(def[3], true)
    placeInRow(chip, chips[i - 1], s, 6, -8)
    chips[i] = chip
  end

  s = section(left, "Settings", chips[1], -18)
  local prev = s
  for i, label in ipairs({ "Auto-accept quests", "Skip gossip for known NPCs", "Waypoint arrow" }) do
    local toggle = UI.Toggle(left)
    toggle:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -10 or -8)
    toggle:SetOn(i == 3, true)
    local text = UI.Text(left, "body", 14, C.text)
    text:SetPoint("LEFT", toggle, "RIGHT", 10, 0)
    text:SetText(label)
    prev = toggle
  end

  s = section(left, "Marks", prev, -18)
  local firstMark, lastMark
  for _, list in ipairs({ Core.SUITE, Core.FAMILY }) do
    for _, info in ipairs(list) do
      local m = UI.Mark(left, info.key, 36)
      placeInRow(m, lastMark, s, 10, -8)
      firstMark = firstMark or m
      lastMark = m
    end
  end

  s = section(left, "Difficulty at your level", firstMark, -18)
  local diff = UI.Text(left, "body", 14)
  diff:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -8)
  w.diff = diff

  s = section(left, "Progress", diff, -18)
  -- yours is live (Core.Player); the party row is a fixed sample
  w.bar = progressRow(left, s, "No quest objective with a count", 0, 1, nil, -8)
  w.partyBar = progressRow(left, w.bar, "Party member (sample)", 2, 10, "party", -10)

  function w:ShowLiveProgress()
    for _, id in ipairs(Core.Player:QuestIds()) do
      for _, o in ipairs(Core.Player:GetQuest(id).objectives) do
        if o.required and o.required > 0 then
          self.bar.label:SetText(o.name or o.text or "?")
          self.bar.count:SetText(o.current .. "/" .. o.required)
          self.bar:SetProgress(o.current, o.required)
          return id
        end
      end
    end
  end
  Core:Listen("NORGANNON_QUESTLOG_UPDATED", "gallery", function()
    if w:IsShown() then w:ShowLiveProgress() end
  end)
  return left
end

-------------------------------------------------------------------------------------------
-- Right column: search over all of NorgannonDB, and with no query every quest
-------------------------------------------------------------------------------------------

local KIND_LABEL = { quest = "Quest", npc = "NPC", object = "Object", item = "Item" }

local function levelBracket(sortLevel)
  if sortLevel >= NO_LEVEL then return "No level" end
  local from = math.floor(sortLevel / 10) * 10
  return string.format("Levels %d–%d", from, from + 9)
end

-- every quest, under a header per level bracket
local function questsByBracket()
  local shown, bracket = {}, nil
  for _, q in ipairs(questList()) do
    local b = levelBracket(q.sortLevel)
    if b ~= bracket then
      table.insert(shown, { group = b })
      bracket = b
    end
    table.insert(shown, q)
  end
  return shown
end

local function createBrowserRow(row, content)
  row.level = UI.Text(content, "body", 14)
  row.level:SetPoint("LEFT", 8, 0)
  row.level:SetWidth(34)
  row.level:SetJustifyH("RIGHT")
  row.name = UI.Text(content, "body", 14, C.text)
  row.name:SetPoint("LEFT", row.level, "RIGHT", 10, 0)
  row.name:SetPoint("RIGHT", -60, 0)
  row.id = UI.Text(content, "body", 12, C.faint)
  row.id:SetPoint("RIGHT", -8, 0)
  row.id:SetJustifyH("RIGHT")
end

local function updateResultRow(row, result)
  local quest = result.kind == "quest" and #result.ids == 1 and NorgannonDB:Peek("quests", result.ids[1])
  local level = quest and quest.level
  local c = (level and level > 0) and UI.Difficulty(level, UnitLevel("player") or 1) or C.faint
  row.level:SetTextColor(c[1], c[2], c[3])
  row.level:SetText((level and level > 0) and level or "")
  row.name:SetText(result.name)
  row.id:SetText(KIND_LABEL[result.kind] .. (#result.ids > 1 and (" ×" .. #result.ids) or ""))
end

local function updateQuestRow(row, q)
  local scales = q.level <= 0 and q.minLevel
  local c = scales and UI.C.muted or UI.Difficulty(q.level, UnitLevel("player") or 1)
  row.level:SetTextColor(c[1], c[2], c[3])
  -- a quest that scales with the player shows its minimum level with a "+"
  row.level:SetText(q.level > 0 and q.level or (scales and (q.minLevel .. "+")) or "–")
  row.name:SetText(q.name)
  row.id:SetText(q.id)
end

local function showResultTooltip(row, result)
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(result.name, 1, 1, 1)
  local detail = #result.ids > 1 and (", " .. #result.ids .. " with this name") or (" " .. result.ids[1])
  GameTooltip:AddLine(KIND_LABEL[result.kind] .. detail, C.muted[1], C.muted[2], C.muted[3])
  GameTooltip:Show()
end

-- the game's own tooltip, with the suite's colours for its lines
local function showQuestTooltip(row, q, accent)
  local rec = NorgannonDB:Peek("quests", q.id) or {}
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(q.name, 1, 1, 1)
  local level = q.level > 0 and ("Level " .. q.level) or "Scales with you"
  GameTooltip:AddLine(level .. (q.minLevel and ("  ·  requires " .. q.minLevel) or ""), C.muted[1], C.muted[2], C.muted[3])
  local objective = rec.text and rec.text.objectives and rec.text.objectives[1]
  if objective then GameTooltip:AddLine(objective, .81, .81, .81, true) end
  GameTooltip:AddLine("Quest " .. q.id, accent[1], accent[2], accent[3])
  GameTooltip:Show()
end

local function buildBrowser(w, left)
  local column = CreateFrame("Frame", nil, w.body)
  column:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, -8)
  column:SetPoint("BOTTOMRIGHT", -12, 10)
  local pane = UI.Pane(column)
  pane:SetAllPoints()

  local list
  local search = UI.Search(pane, "Search all of NorgannonDB", function(text)
    local all = questList()   -- built once, and not part of the time shown below
    local needle = string.lower(text or "")
    local start = debugprofilestop and debugprofilestop()
    if needle ~= "" then
      -- Core.DB:Search: every kind, ranked, same-named entities grouped
      local results, total = Core.DB:Search(needle, { limit = 200 })
      list:SetData(results)
      local ms = start and (debugprofilestop() - start)
      w.footerText:SetText(string.format("%d matches%s%s", total, total > #results and (", showing " .. #results) or "",
        ms and string.format("  ·  searched in %.1f ms", ms) or ""))
      return
    end
    list:SetData(questsByBracket())
    local ms = start and (debugprofilestop() - start)
    w.footerText:SetText(string.format("%d of %d quests%s", #all, #all, ms and string.format("  ·  filtered in %.1f ms", ms) or ""))
  end, nil, "/norg ui")
  search:SetPoint("TOPLEFT", 8, -8)
  search:SetPoint("TOPRIGHT", -8, -8)

  -- an item is a search result (it has a kind) or a quest from questList
  list = UI.List(pane, {
    rowHeight = 22,
    createRow = createBrowserRow,
    updateRow = function(row, item)
      if item.kind then updateResultRow(row, item) else updateQuestRow(row, item) end
    end,
    onClick = function(item) list:Select(item) end,
    onEnter = function(row, item)
      if item.kind then showResultTooltip(row, item) else showQuestTooltip(row, item, w.accent) end
    end,
    onLeave = function() GameTooltip:Hide() end,
  })
  list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -8)
  list:SetPoint("BOTTOMRIGHT", -2, 2)
  return list, search
end

-------------------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------------------

local function build()
  local w = UI.Window({ name = "NorgannonCoreGallery", addon = "core", title = "UI kit", sub = "NorgannonDB_Core " .. Core:Version(),
    width = 940, height = 700, footer = true })

  -- accent switcher across the top
  local keys = {}
  for _, info in ipairs(Core.SUITE) do table.insert(keys, { key = info.key, label = info.name }) end
  for _, info in ipairs(Core.FAMILY) do table.insert(keys, { key = info.key, label = info.name }) end
  local tabs = UI.Tabs(w.body, keys, function(key)
    w:SetAccent(key)
    w:SetTitle(Core:GetAddonInfo(key).name)
    if Core.db then Core.db.galleryAccent = key end
  end)
  tabs:SetPoint("TOPLEFT", 8, -4)
  tabs:SetPoint("TOPRIGHT", -8, -4)

  local left = buildControls(w, tabs)
  local list, search = buildBrowser(w, left)

  w:SetScript("OnShow", function()
    local level = UnitLevel("player") or 1
    local parts = {}
    for _, d in ipairs({ -12, -6, 0, 3, 5 }) do
      local l = math.max(1, level + d)
      table.insert(parts, UI.Code(UI.Difficulty(l, level)) .. "Level " .. l .. "|r")
    end
    w.diff:SetText(table.concat(parts, "   "))
    -- the first time: fill the list by running the empty search
    if #list.items == 0 then search.edit:GetScript("OnTextChanged")(search.edit) end
    w:ShowLiveProgress()
  end)
  w.tabs, w.list, w.search = tabs, list, search
  -- open on the accent last chosen, Clairvoyance's by default (as in design/suite/index.html)
  local saved = Core.db and Core.db.galleryAccent
  tabs:Select(saved and Core:GetAddonInfo(saved) and saved or "clairvoyance")
  return w
end

function Core:ShowGallery()
  gallery = gallery or build()
  gallery:Show()
  self.gallery = gallery
  return gallery
end
