-- /norg ui: the UI kit in game, the counterpart of design/suite/index.html. Switch the accent
-- between the suite addons, try every control, and scroll the full NorgannonDB quest list in a
-- virtual list to check the look and the performance on the real client.

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

local gallery

local function section(parent, text, anchor, y)
  local label = UI.Text(parent, "title", 15, C.goldSoft)
  label:SetPoint("TOPLEFT", anchor, anchor == parent and "TOPLEFT" or "BOTTOMLEFT", anchor == parent and 16 or 0, y)
  label:SetText(text)
  return label
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
      -- and a quest with no level at all goes last
      local sortLevel = level > 0 and level or q.minLevel or 1000
      table.insert(quests, { id = id, name = name, lower = string.lower(name), level = level, minLevel = q.minLevel, sortLevel = sortLevel })
    end
  end
  table.sort(quests, function(a, b)
    if a.sortLevel ~= b.sortLevel then return a.sortLevel < b.sortLevel end
    return a.name < b.name
  end)
  return quests
end

local function build()
  local w = UI.Window({ name = "NorgannonCoreGallery", addon = "norgannondb", title = "UI kit", sub = "NorgannonDB_Core " .. Core:Version(),
    width = 940, height = 700, footer = true })
  local body = w.body

  -- accent switcher across the top
  local keys = {}
  for _, info in ipairs(Core.SUITE) do table.insert(keys, { key = info.key, label = info.name }) end
  for _, info in ipairs(Core.FAMILY) do table.insert(keys, { key = info.key, label = info.name }) end
  local tabs = UI.Tabs(body, keys, function(key)
    w:SetAccent(key)
    w:SetTitle(Core:GetAddonInfo(key).name)
    if Core.db then Core.db.galleryAccent = key end
  end)
  tabs:SetPoint("TOPLEFT", 8, -4)
  tabs:SetPoint("TOPRIGHT", -8, -4)

  -- left column: the controls
  local left = CreateFrame("Frame", nil, body)
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
    chip:SetPoint("TOPLEFT", chips[i - 1] or s, chips[i - 1] and "TOPRIGHT" or "BOTTOMLEFT", chips[i - 1] and 6 or 0, chips[i - 1] and 0 or -8)
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
      m:SetPoint("TOPLEFT", lastMark or s, lastMark and "TOPRIGHT" or "BOTTOMLEFT", lastMark and 10 or 0, lastMark and 0 or -8)
      firstMark = firstMark or m
      lastMark = m
    end
  end

  s = section(left, "Difficulty at your level", firstMark, -18)
  local diff = UI.Text(left, "body", 14)
  diff:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -8)
  w.diff = diff

  -- progress: yours in the accent, a party member's dimmer (suite.css .az-bar / .party)
  s = section(left, "Progress", diff, -18)
  local function progressRow(anchor, name, current, total, kind, y)
    local label = UI.Text(left, "body", 14, kind and C.muted or C.text)
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
    label:SetText(name)
    local bar = UI.Bar(left, kind)
    bar:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -5)
    bar:SetWidth(350)
    bar:SetProgress(current, total)
    local count = UI.Text(left, "body", 13, C.muted)
    count:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 4)
    count:SetJustifyH("RIGHT")
    count:SetText(current .. "/" .. total)
    bar.label, bar.count = label, count
    return bar
  end
  -- yours is live (Core.Player); the party row is a sample until party comms land
  w.bar = progressRow(s, "No quest objective with a count", 0, 1, nil, -8)
  w.partyBar = progressRow(w.bar, "Party member (sample)", 2, 10, "party", -10)

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
  Core:Listen("NORGANNON_QUESTLOG_UPDATED", "gallery", function() if w:IsShown() then w:ShowLiveProgress() end end)

  -- right column: search + virtual list of every quest
  local right = CreateFrame("Frame", nil, body)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, -8)
  right:SetPoint("BOTTOMRIGHT", -12, 10)
  local pane = UI.Pane(right)
  pane:SetAllPoints()
  right = pane

  local list
  local KIND_LABEL = { quest = "Quest", npc = "NPC", object = "Object", item = "Item" }
  local search = UI.Search(right, "Search all of NorgannonDB", function(text)
    local all = questList()
    local needle = string.lower(text or "")
    local start = debugprofilestop and debugprofilestop()
    if needle ~= "" then
      -- Core.DB:Search: every kind, ranked, same-named entities grouped
      local results, total = Core.DB:Search(needle, { limit = 200 })
      list:SetData(results)
      w.shownCount = #results
      local ms = start and (debugprofilestop() - start)
      w.footerText:SetText(string.format("%d matches%s%s", total, total > #results and (", showing " .. #results) or "",
        ms and string.format("  ·  searched in %.1f ms", ms) or ""))
      return
    end
    -- matching quests under a header per level bracket
    local shown, count, bracket = {}, 0, nil
    for _, q in ipairs(all) do
      if needle == "" or string.find(q.lower, needle, 1, true) then
        local b = q.sortLevel >= 1000 and "No level" or string.format("Levels %d–%d", math.floor(q.sortLevel / 10) * 10, math.floor(q.sortLevel / 10) * 10 + 9)
        if b ~= bracket then
          table.insert(shown, { group = b })
          bracket = b
        end
        table.insert(shown, q)
        count = count + 1
      end
    end
    list:SetData(shown)
    w.shownCount = count
    local ms = start and (debugprofilestop() - start)
    w.footerText:SetText(string.format("%d of %d quests%s", count, #all, ms and string.format("  ·  filtered in %.1f ms", ms) or ""))
  end, nil, "/norg ui")
  search:SetPoint("TOPLEFT", 8, -8)
  search:SetPoint("TOPRIGHT", -8, -8)

  list = UI.List(right, {
    rowHeight = 22,
    createRow = function(row, content)
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
    end,
    updateRow = function(row, q)
      if q.kind then   -- a search result
        local level = q.kind == "quest" and #q.ids == 1 and NorgannonDB:Peek("quests", q.ids[1])
        local lvl = level and level.level
        local c = (lvl and lvl > 0) and UI.Difficulty(lvl, UnitLevel("player") or 1) or C.faint
        row.level:SetTextColor(c[1], c[2], c[3])
        row.level:SetText((lvl and lvl > 0) and lvl or "")
        row.name:SetText(q.name)
        row.id:SetText(KIND_LABEL[q.kind] .. (#q.ids > 1 and (" ×" .. #q.ids) or ""))
        return
      end
      local scales = q.level <= 0 and q.minLevel
      local c = scales and UI.C.muted or UI.Difficulty(q.level, UnitLevel("player") or 1)
      row.level:SetTextColor(c[1], c[2], c[3])
      -- a quest that scales with the player shows its minimum level with a "+"
      row.level:SetText(q.level > 0 and q.level or (scales and (q.minLevel .. "+")) or "–")
      row.name:SetText(q.name)
      row.id:SetText(q.id)
    end,
    onClick = function(q) list:Select(q) end,
    onEnter = function(row, q)
      if q.kind then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(q.name, 1, 1, 1)
        GameTooltip:AddLine(KIND_LABEL[q.kind] .. (#q.ids > 1 and (", " .. #q.ids .. " with this name") or (" " .. q.ids[1])), C.muted[1], C.muted[2], C.muted[3])
        GameTooltip:Show()
        return
      end
      -- the game's own tooltip, with the suite's colours for its lines
      local rec = NorgannonDB:Peek("quests", q.id) or {}
      GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
      GameTooltip:AddLine(q.name, 1, 1, 1)
      local level = q.level > 0 and ("Level " .. q.level) or "Scales with you"
      GameTooltip:AddLine(level .. (q.minLevel and ("  ·  requires " .. q.minLevel) or ""), C.muted[1], C.muted[2], C.muted[3])
      local objective = rec.text and rec.text.objectives and rec.text.objectives[1]
      if objective then GameTooltip:AddLine(objective, .81, .81, .81, true) end
      local a = w.accent
      GameTooltip:AddLine("Quest " .. q.id, a[1], a[2], a[3])
      GameTooltip:Show()
    end,
    onLeave = function() GameTooltip:Hide() end,
  })
  list:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -8)
  list:SetPoint("BOTTOMRIGHT", -2, 2)

  w:SetScript("OnShow", function()
    local level = UnitLevel("player") or 1
    local parts = {}
    for _, d in ipairs({ -12, -6, 0, 3, 5 }) do
      local l = math.max(1, level + d)
      table.insert(parts, UI.Code(UI.Difficulty(l, level)) .. "Level " .. l .. "|r")
    end
    diff:SetText(table.concat(parts, "   "))
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
