-- Settings controls for the suite's pages: a slider, a dropdown, a scroll area and a settings
-- list that lays out rows (label, description, control) the same way on every add-on's page.
--
--   local list = UI.SettingsList(page)
--   list:Header("Tracker")
--   list:Toggle("Show the tracker", "Replaces Blizzard's while on.", get, set)
--   list:Slider("Scale", nil, .6, 1.6, .05, get, set, "%.0f%%", 100)
--   list:Dropdown("Sort quests by", nil, { {"near", "Nearest"}, {"zone", "Zone"} }, get, set)
--   list:Refresh()   -- re-reads every getter (e.g. on the page's OnShow)

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

-------------------------------------------------------------------------------------------
-- Slider
-------------------------------------------------------------------------------------------

local KNOB = 14    -- the knob's size; its centre travels from KNOB / 2 to the width minus KNOB / 2

---UI.Slider(parent, min, max, step, onChange). :SetValue(v, silent), .value. Drag, click or wheel.
function UI.Slider(parent, min, max, step, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(160, 18)
  f:EnableMouse(true)
  f:EnableMouseWheel(true)
  f.track = UI.Pill(f, 6, "BACKGROUND", 0)
  f.track:SetColor({ .02, .016, .012 })
  f.floor = UI.Pill(f, 6, "BACKGROUND", 1, 1)
  f.floor:SetColor({ .085, .07, .054 })
  f.fill = UI.Tex(f, "ARTWORK", 0)
  f.fill:SetHeight(4)
  f.fill:SetPoint("LEFT", 2, 0)
  f.knob = UI.Knob(f, KNOB / 18)
  f.min, f.max, f.step, f.value = min, max, step or 1, min

  local function snap(v)
    v = math.max(min, math.min(max, v))
    local s = f.step
    return math.floor((v - min) / s + .5) * s + min
  end
  function f:Paint()
    local travel = (self:GetWidth() or 160) - KNOB
    local range = max - min
    local share = (self.value - min) / (range ~= 0 and range or 1)
    self.knob:ClearAllPoints()
    self.knob:SetPoint("CENTER", self, "LEFT", KNOB / 2 + travel * share, 0)
    self.fill:SetWidth(math.max(.01, travel * share))   -- never exactly 0: the client reads that as "no width set"
    local a = self.accent or C.goldSoft
    UI.Gradient(self.fill, UI.Mix(a, C.black, .25), a)
    self.knob:SetVertexColor(self.hover and 1 or .92, self.hover and 1 or .9, self.hover and 1 or .86)
  end
  function f:ApplyAccent(c)
    self.accent = c
    self:Paint()
  end
  function f:SetValue(v, silent)
    v = snap(v)
    local changed = v ~= self.value
    self.value = v
    self:Paint()
    if changed and not silent and onChange then onChange(v) end
  end
  local function fromCursor(self)
    local x = GetCursorPosition() / self:GetEffectiveScale()
    local left = self:GetLeft() or 0
    local travel = (self:GetWidth() or 160) - KNOB
    self:SetValue(min + (x - left - KNOB / 2) / (travel ~= 0 and travel or 1) * (max - min))
  end
  f:SetScript("OnMouseDown", function(self)
    fromCursor(self)
    self:SetScript("OnUpdate", fromCursor)
  end)
  f:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  f:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self.value + delta * self.step) end)
  f:SetScript("OnEnter", function(self)
    self.hover = true
    self:Paint()
  end)
  f:SetScript("OnLeave", function(self)
    self.hover = false
    self:Paint()
  end)
  f:SetScript("OnSizeChanged", f.Paint)
  local window = UI.WindowOf(parent)
  if window then
    table.insert(window._accentWidgets, f)
    f.accent = window.accent
  end
  f:Paint()
  return f
end

-------------------------------------------------------------------------------------------
-- Dropdown (its options open in the suite's own panel)
-------------------------------------------------------------------------------------------

-- The options of a dropdown (1.33): one panel for them all, in the add-on's accent, as wide as its dropdown.
local OPTION_H, MAX_OPTIONS = 24, 12
local popup

local function buildOptions()
  local f = CreateFrame("Frame", "NorgannonCoreOptions", UIParent)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:Hide()
  UI.Shadow(f, -8)
  f.bg = UI.Round(f, "BACKGROUND", -4, 6)
  f.line = UI.Round(f, "BACKGROUND", -3, 6, "line")
  f.list = UI.List(f, {
    rowHeight = OPTION_H,
    createRow = function(row, content)
      row.check = UI.Icon(content, "check", 11)
      row.check:SetPoint("LEFT", 7, 0)
      row.text = UI.Text(content, "body", 13, C.text)
      row.text:SetPoint("LEFT", 24, 0)
      row.text:SetPoint("RIGHT", -8, 0)
      row.text:SetWordWrap(false)
    end,
    updateRow = function(row, item)
      local on, a = item.value == f.owner.value, f.list.accent
      row.check:SetShown(on)
      row.check:SetVertexColor(a[1], a[2], a[3])
      row.text:SetText(item.text)
      local c = on and UI.Readable(a) or C.text
      row.text:SetTextColor(c[1], c[2], c[3])
    end,
    onClick = function(item)
      local owner = f.owner
      f:Hide()
      owner:SetValue(item.value)
    end,
  })
  f.list:SetPoint("TOPLEFT", 4, -4)
  f.list:SetPoint("TOPRIGHT", -4, -4)
  table.insert(UISpecialFrames, "NorgannonCoreOptions")   -- Escape closes it
  -- a click anywhere else closes it (the dropdown's own click toggles it)
  pcall(f.RegisterEvent, f, "GLOBAL_MOUSE_DOWN")
  f:SetScript("OnEvent", function(self)
    if self:IsShown() and not self:IsMouseOver() and not self.owner:IsMouseOver() then self:Hide() end
  end)
  -- and so does its dropdown going away
  f:SetScript("OnUpdate", function(self) if not self.owner:IsVisible() then self:Hide() end end)
  return f
end

local function toggleOptions(owner)
  popup = popup or buildOptions()
  if popup:IsShown() then
    local was = popup.owner
    popup:Hide()
    if was == owner then return end
  end
  local f = popup
  f.owner = owner
  local a = owner.accent or C.goldSoft
  f.bg:SetColor(UI.Mix(C.stone2, a, .06))
  f.line:SetColor(UI.Mix(C.line, a, .35))
  local items, width = {}, owner:GetWidth() or 160
  for i, o in ipairs(owner.options) do
    items[i] = { value = o[1], text = o[2] }
  end
  f:SetScale(owner:GetEffectiveScale() / UIParent:GetEffectiveScale())   -- as big as the window it belongs to
  local h = math.min(#items, MAX_OPTIONS) * OPTION_H
  f:SetSize(width, h + 8)
  f.list:SetHeight(h)
  f:ClearAllPoints()
  f:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -3)
  f.list:ApplyAccent(a)
  f:Show()
  f.list:SetData(items)
  for i, item in ipairs(items) do if item.value == owner.value then f.list:ScrollToIndex(i) end end
end
UI.ToggleOptions = toggleOptions

---UI.Dropdown(parent, { {value, label}, ... }, onChange). :SetValue(v, silent), .value.
function UI.Dropdown(parent, options, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(160, 24)
  b.box = UI.Field(b, "BACKGROUND", 0)
  function b:Paint()
    self.box:Set(self.hover and self.accent or UI.Mix(C.line, self.accent, .22), self.hover)
  end
  b.ApplyAccent = UI.ApplyAccent
  b.label = UI.Text(b, "body", 13, C.text)
  b.label:SetPoint("LEFT", 9, 0)
  b.label:SetPoint("RIGHT", -24, 0)
  b.chevron = UI.Icon(b, "chevron", 12, C.muted)
  b.chevron:SetPoint("RIGHT", -8, 0)
  b.options = options
  local function labelOf(v)
    for _, o in ipairs(b.options) do if o[1] == v then return o[2] end end
    return tostring(v)
  end
  function b:SetValue(v, silent)
    local changed = v ~= self.value
    self.value = v
    self.label:SetText(labelOf(v))
    if changed and not silent and onChange then onChange(v) end
  end
  UI.RepaintOnHover(b)
  UI.AttachAccent(b)
  b:SetScript("OnClick", function(self)
    toggleOptions(self)
  end)
  return b
end

-------------------------------------------------------------------------------------------
-- Scroll area: a content frame that scrolls with the mouse wheel (native ScrollFrame)
-------------------------------------------------------------------------------------------

local WHEEL_STEP = 40   -- pixels
local BAR_W, BAR_MIN = 4, 24

function UI.ScrollArea(parent)
  local s = CreateFrame("ScrollFrame", nil, parent)
  s.content = CreateFrame("Frame", nil, s)
  s.content:SetSize(1, 1)
  s:SetScrollChild(s.content)
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, delta)
    local range = math.max(0, (self.content:GetHeight() or 0) - (self:GetHeight() or 0))
    local v = math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * WHEEL_STEP))
    self:SetVerticalScroll(v)
  end)
  s:SetScript("OnSizeChanged", function(self, w) self.content:SetWidth(w or self:GetWidth() or 1) end)

  -- a thumb over its right edge while there's more than fits (1.33)
  local thumb = CreateFrame("Frame", nil, s)
  s.thumb = thumb
  thumb:SetWidth(BAR_W + 4)                   -- a little wider than it looks, to catch the mouse
  thumb:EnableMouse(true)
  thumb:Hide()
  thumb.inner = CreateFrame("Frame", nil, thumb)
  thumb.inner:SetPoint("TOP")
  thumb.inner:SetPoint("BOTTOM")
  thumb.inner:SetWidth(BAR_W)
  thumb.pill = UI.VPill(thumb.inner, BAR_W, "OVERLAY")
  function thumb:Paint() self.pill:SetColor(self.hover and self.accent or UI.Mix(C.lineStrong, self.accent, .25), 1) end
  thumb.ApplyAccent = UI.ApplyAccent
  UI.AttachAccent(thumb)
  UI.RepaintOnHover(thumb)
  local function place()
    local view, all = s:GetHeight() or 0, s.content:GetHeight() or 0
    local range = all - view
    thumb:SetShown(range > 1 and view > BAR_MIN)
    if not thumb:IsShown() then return end
    local h = math.max(BAR_MIN, view * view / all)
    thumb.travel, thumb.range = view - h, range
    thumb:SetHeight(h)
    thumb:SetPoint("TOPRIGHT", s, "TOPRIGHT", 1, -(view - h) * math.min(1, (s:GetVerticalScroll() or 0) / range))
  end
  s:HookScript("OnVerticalScroll", place)
  s:HookScript("OnScrollRangeChanged", place)
  s:HookScript("OnSizeChanged", place)
  s:HookScript("OnShow", place)
  thumb:SetScript("OnMouseDown", function(self)
    local _, y = GetCursorPosition()
    self.y, self.from = y / self:GetEffectiveScale(), s:GetVerticalScroll() or 0
    self:SetScript("OnUpdate", function(t)
      local _, cy = GetCursorPosition()
      if (t.travel or 0) <= 0 then return end
      local v = t.from + (t.y - cy / t:GetEffectiveScale()) / t.travel * t.range
      s:SetVerticalScroll(math.max(0, math.min(t.range, v)))
    end)
  end)
  local function release(self) self:SetScript("OnUpdate", nil) end
  thumb:SetScript("OnMouseUp", release)
  thumb:SetScript("OnHide", release)
  return s
end

-------------------------------------------------------------------------------------------
-- Settings list
-------------------------------------------------------------------------------------------

local ROW_GAP, CONTROL_W = 14, 170
local TOP, SIDE = 8, 12          -- the list's margins
local LABEL_H, DESC_GAP = 18, 3  -- a row's first line, and the gap above its description

---A vertical list of setting rows inside a scroll area; see the example at the top.
function UI.SettingsList(parent)
  local area = UI.ScrollArea(parent)
  area:SetAllPoints()
  local list = { area = area, content = area.content, rows = {}, y = -TOP, items = {} }

  -- each item: { region, height = number or function() (measured again on every layout), gap }
  local function place(region, height, gap)
    table.insert(list.items, { region = region, height = height, gap = gap or 0 })
    list:Layout()
  end

  ---Stacks the rows again. A description's wrapped height is only right once the page has its
  ---real width, so this runs when the list is resized or shown (and after every row is added).
  function list:Layout()
    local y = -TOP
    for _, item in ipairs(self.items) do
      y = y - item.gap
      local h = type(item.height) == "function" and item.height() or item.height
      item.region:ClearAllPoints()
      item.region:SetPoint("TOPLEFT", self.content, "TOPLEFT", SIDE, y)
      item.region:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -SIDE, y)
      if item.region.SetHeight and item.region.desc then item.region:SetHeight(h) end   -- only a description's height changes
      y = y - h - ROW_GAP
    end
    self.y = y
    self.content:SetHeight(-y + TOP)
  end
  area:HookScript("OnSizeChanged", function() list:Layout() end)
  area:HookScript("OnShow", function()
    list:Layout()
    C_Timer.After(0, function() list:Layout() end)   -- again once the client has sized the text
  end)

  function list:Header(text)
    local h = UI.Text(self.content, "title", 16, C.goldSoft)
    h:SetText(text)
    -- a heading in the window's accent (gold on the game's own Settings pages, which have none)
    if UI.WindowOf(self.content) then
      function h:ApplyAccent(c)
        local t = UI.Readable(c)
        self:SetTextColor(t[1], t[2], t[3])
      end
      UI.AttachAccent(h)
    end
    -- and a line under it, fading away
    local rule = UI.Tex(self.content, "ARTWORK", 0)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)
    rule:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", 0, -4)
    rule.ApplyAccent = function(t, c) UI.GradientH(t, c, .4) end
    if UI.WindowOf(self.content) then UI.AttachAccent(rule) else UI.GradientH(rule, C.goldSoft, .4) end
    place(h, 18, 6)
    return h
  end

  local function row(label, desc, control, refresh)
    local r = CreateFrame("Frame", nil, list.content)
    r.label = UI.Text(r, "body", 14, C.text)
    r.label:SetPoint("TOPLEFT", 0, 0)
    r.label:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(CONTROL_W + 16), 0)
    r.label:SetText(label)
    if desc then
      r.desc = UI.Text(r, "body", 12, C.muted)
      r.desc:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -DESC_GAP)
      r.desc:SetPoint("TOPRIGHT", r.label, "BOTTOMRIGHT", 0, -DESC_GAP)
      r.desc:SetWordWrap(true)
      r.desc:SetText(desc)
    end
    local function height()
      if not r.desc then return LABEL_H end
      return LABEL_H + DESC_GAP + math.max(14, r.desc:GetStringHeight() or 14)
    end
    control:SetParent(r)
    control:ClearAllPoints()
    control:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    r.control, r.refresh = control, refresh
    r:SetHeight(height())
    place(r, height)
    table.insert(list.rows, r)
    return r
  end

  function list:Toggle(label, desc, get, set)
    local t = UI.Toggle(self.content, function(on) set(on) end)
    return row(label, desc, t, function() t:SetOn(get(), true) end)
  end

  ---fmt formats value * scale (e.g. "%.0f%%" with scale 100 shows 0.85 as 85%).
  function list:Slider(label, desc, min, max, step, get, set, fmt, scale)
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetSize(CONTROL_W, 18)
    local function showValue(v)
      holder.value:SetText(string.format(fmt or "%s", v * (scale or 1)))
    end
    local s = UI.Slider(holder, min, max, step, function(v)
      set(v)
      showValue(v)
    end)
    s:SetPoint("LEFT")
    s:SetWidth(CONTROL_W - 46)
    holder.value = UI.Text(holder, "body", 13, C.muted)
    holder.value:SetPoint("RIGHT")
    holder.value:SetJustifyH("RIGHT")
    holder.slider = s
    return row(label, desc, holder, function()
      local v = get()
      s:SetValue(v, true)
      showValue(v)
    end)
  end

  function list:Dropdown(label, desc, options, get, set)
    local d = UI.Dropdown(self.content, options, set)
    d:SetWidth(CONTROL_W)
    return row(label, desc, d, function() d:SetValue(get(), true) end)
  end

  ---A row with one or more buttons: list:Buttons(label, desc, { {text, func[, style]}, ... }).
  function list:Buttons(label, desc, buttons)
    local holder = CreateFrame("Frame", nil, self.content)
    holder:SetSize(CONTROL_W, 24)
    local previous
    for i = #buttons, 1, -1 do
      local def = buttons[i]
      local b = UI.Button(holder, def[1], def[3] or "quiet", function() def[2]() end)
      b:SetPoint("RIGHT", previous or holder, previous and "LEFT" or "RIGHT", previous and -6 or 0, 0)
      previous = b
      holder["button" .. i] = b
    end
    return row(label, desc, holder)
  end

  function list:Refresh()
    for _, r in ipairs(self.rows) do
      if r.refresh then r.refresh() end
    end
    self:Layout()
  end

  return list
end
