-- A virtual list: any number of items, only the visible rows exist. Smooth pixel scrolling with
-- the mouse wheel and a draggable thumb, hover and selection in the window's accent.
--
--   local list = UI.List(parent, { rowHeight = 22,
--     createRow = function(row, content) row.text = UI.Text(content, "body", 14) ... end,
--     updateRow = function(row, item, index) row.text:SetText(item.name) end,
--     onClick = function(item, index, button) end,
--     onGroupClick = function(group, index, button) end })      -- a section header clicked (to fold it)
--   list:SetData(items)
--
-- Build row contents on `content` (not on the row): an item { group = "Kalimdor" } is drawn as a
-- section header instead, and hides the row's content.

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

local SCROLLBAR = 6

function UI.List(parent, opts)
  local f = CreateFrame("Frame", nil, parent)
  f:SetClipsChildren(true)
  f:EnableMouseWheel(true)
  f.rowHeight = opts.rowHeight or 22
  f.items = {}
  f.offset = 0
  f.rows = {}
  f.accent = C.goldSoft

  -- scrollbar
  f.track = UI.Tex(f, "ARTWORK", 0, { 1, 1, 1, .04 })
  f.track:SetPoint("TOPRIGHT", -1, -2)
  f.track:SetPoint("BOTTOMRIGHT", -1, 2)
  f.track:SetWidth(SCROLLBAR)
  f.thumb = CreateFrame("Frame", nil, f)
  f.thumb:SetWidth(SCROLLBAR)
  f.thumb:EnableMouse(true)
  f.thumb.tex = UI.Tex(f.thumb, "ARTWORK", 1)
  f.thumb.tex:SetAllPoints()

  local function contentHeight() return #f.items * f.rowHeight end
  local function maxOffset() return math.max(0, contentHeight() - (f:GetHeight() or 0)) end

  local function makeRow()
    local row = CreateFrame("Button", nil, f)
    row:SetHeight(f.rowHeight)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- hover and selection fade out from the left in the accent (suite.css .az-row)
    row.hl = UI.Tex(row, "BACKGROUND", 0)
    row.hl:SetAllPoints()
    row.hl:Hide()
    row.sel = UI.Tex(row, "BACKGROUND", 1)
    row.sel:SetAllPoints()
    row.sel:Hide()
    row.bar = UI.Tex(row, "ARTWORK", 0)
    row.bar:SetWidth(2)
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:Hide()
    row.content = CreateFrame("Frame", nil, row)
    row.content:SetAllPoints()
    row.groupLabel = UI.Text(row, "title", 13, C.goldSoft)
    row.groupLabel:SetPoint("BOTTOMLEFT", 10, 3)
    row.groupLabel:Hide()
    row:SetScript("OnEnter", function(self)
      if not self.item or self.item.group then return end
      self.hl:Show()
      if opts.onEnter and self.item then opts.onEnter(self, self.item, self.index) end
    end)
    row:SetScript("OnLeave", function(self)
      self.hl:Hide()
      if opts.onLeave then opts.onLeave(self, self.item, self.index) end
    end)
    row:SetScript("OnClick", function(self, button)
      if not self.item then return end
      if self.item.group then
        if opts.onGroupClick then opts.onGroupClick(self.item, self.index, button) end
      elseif opts.onClick then
        opts.onClick(self.item, self.index, button)
      end
    end)
    if opts.createRow then opts.createRow(row, row.content) end
    return row
  end

  function f:Refresh()
    local h = self:GetHeight() or 0
    local rowH = self.rowHeight
    self.offset = math.max(0, math.min(self.offset, maxOffset()))
    local first = math.floor(self.offset / rowH)
    local shift = self.offset - first * rowH
    local needed = math.ceil(h / rowH) + 1
    local scrollable = contentHeight() > h
    for i = 1, needed do
      local row = self.rows[i]
      if not row then
        row = makeRow()
        self.rows[i] = row
      end
      local index = first + i
      local item = self.items[index]
      row:ClearAllPoints()
      -- two top corners: the row keeps its own height (an edge plus a centre on one
      -- axis would let the client derive the height from the anchors instead)
      local top = -((i - 1) * rowH - shift)
      row:SetPoint("TOPLEFT", 0, top)
      row:SetPoint("TOPRIGHT", scrollable and -(SCROLLBAR + 4) or 0, top)
      if item then
        row.item, row.index = item, index
        local a = self.accent
        UI.GradientH(row.hl, a, .14)
        UI.GradientH(row.sel, a, .26)
        row.bar:SetColorTexture(a[1], a[2], a[3], 1)
        if item.group then
          row.groupLabel:SetText(item.group)
          row.groupLabel:Show()
          row.content:Hide()
          row.sel:Hide()
          row.bar:Hide()
          row.hl:Hide()
        else
          local selected = self.selected ~= nil and self.selected == item
          row.groupLabel:Hide()
          row.content:Show()
          row.sel:SetShown(selected)
          row.bar:SetShown(selected)
          if opts.updateRow then opts.updateRow(row, item, index) end
        end
        row:Show()
      else
        row.item, row.index = nil, nil
        row:Hide()
      end
    end
    for i = needed + 1, #self.rows do self.rows[i]:Hide() end

    self.track:SetShown(scrollable)
    self.thumb:SetShown(scrollable)
    if scrollable then
      local trackH = h - 4
      local thumbH = math.max(24, trackH * h / contentHeight())
      local ratio = maxOffset() > 0 and self.offset / maxOffset() or 0
      self.thumb:SetHeight(thumbH)
      self.thumb:ClearAllPoints()
      self.thumb:SetPoint("TOPRIGHT", -1, -2 - (trackH - thumbH) * ratio)
      local c = self.thumbHover and self.accent or C.lineStrong
      self.thumb.tex:SetColorTexture(c[1], c[2], c[3], 1)
    end
  end

  function f:SetData(items, keepOffset)
    self.items = items or {}
    if not keepOffset then self.offset = 0 end
    self:Refresh()
  end

  function f:SetOffset(px)
    self.offset = px
    self:Refresh()
  end

  function f:ScrollToIndex(index)
    local top = (index - 1) * self.rowHeight
    local h = self:GetHeight() or 0
    if top < self.offset then
      self:SetOffset(top)
    elseif top + self.rowHeight > self.offset + h then
      self:SetOffset(top + self.rowHeight - h)
    end
  end

  function f:Select(item)
    self.selected = item
    self:Refresh()
  end

  function f:ApplyAccent(c)
    self.accent = c
    self:Refresh()
  end

  f:SetScript("OnMouseWheel", function(self, delta)
    self:SetOffset(self.offset - delta * self.rowHeight * 3)
  end)
  f:SetScript("OnSizeChanged", function(self) self:Refresh() end)

  -- thumb dragging
  f.thumb:SetScript("OnEnter", function() f.thumbHover = true f:Refresh() end)
  f.thumb:SetScript("OnLeave", function() f.thumbHover = false f:Refresh() end)
  f.thumb:SetScript("OnMouseDown", function(self)
    local _, y = GetCursorPosition()
    self.dragFrom = y / f:GetEffectiveScale()
    self.dragOffset = f.offset
    self:SetScript("OnUpdate", function(thumb)
      local _, cy = GetCursorPosition()
      cy = cy / f:GetEffectiveScale()
      local trackH = (f:GetHeight() or 0) - 4 - thumb:GetHeight()
      if trackH > 0 then
        f:SetOffset(thumb.dragOffset + (thumb.dragFrom - cy) / trackH * maxOffset())
      end
    end)
  end)
  f.thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

  -- follow the window accent like the other widgets
  local window = parent
  while window and not window._norgWindow do window = window:GetParent() end
  if window then
    table.insert(window._accentWidgets, f)
    f.accent = window.accent or C.goldSoft
  end
  return f
end
