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

---UI.Slider(parent, min, max, step, onChange). :SetValue(v, silent), .value. Drag, click or wheel.
function UI.Slider(parent, min, max, step, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(160, 18)
  f:EnableMouse(true)
  f:EnableMouseWheel(true)
  f.track = UI.Pill(f, 6, "BACKGROUND", 0)
  f.track:SetColor({ .165, .137, .102 })
  f.fill = UI.Tex(f, "ARTWORK", 0)
  f.fill:SetHeight(4)
  f.fill:SetPoint("LEFT", 2, 0)
  f.knob = UI.Icon(f, "circle", 14, nil, "OVERLAY")
  f.min, f.max, f.step, f.value = min, max, step or 1, min

  local function snap(v)
    v = math.max(min, math.min(max, v))
    local s = f.step
    return math.floor((v - min) / s + .5) * s + min
  end
  function f:Paint()
    local w = (self:GetWidth() or 160) - 14
    local t = (self.value - min) / ((max - min) ~= 0 and (max - min) or 1)
    self.knob:ClearAllPoints()
    self.knob:SetPoint("CENTER", self, "LEFT", 7 + w * t, 0)
    self.fill:SetWidth(math.max(.01, w * t))
    local a = self.accent or C.goldSoft
    self.fill:SetColorTexture(a[1], a[2], a[3], 1)
    self.knob:SetVertexColor(self.hover and 1 or .92, self.hover and 1 or .9, self.hover and 1 or .86)
  end
  function f:ApplyAccent(c) self.accent = c self:Paint() end
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
    local w = (self:GetWidth() or 160) - 14
    self:SetValue(min + (x - left - 7) / (w ~= 0 and w or 1) * (max - min))
  end
  f:SetScript("OnMouseDown", function(self)
    fromCursor(self)
    self:SetScript("OnUpdate", fromCursor)
  end)
  f:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  f:SetScript("OnMouseWheel", function(self, delta) self:SetValue(self.value + delta * self.step) end)
  f:SetScript("OnEnter", function(self) self.hover = true self:Paint() end)
  f:SetScript("OnLeave", function(self) self.hover = false self:Paint() end)
  f:SetScript("OnSizeChanged", f.Paint)
  local window = parent
  while window and not window._norgWindow do window = window:GetParent() end
  if window then table.insert(window._accentWidgets, f) f.accent = window.accent end
  f:Paint()
  return f
end

-------------------------------------------------------------------------------------------
-- Dropdown (the game's context menu with radio entries)
-------------------------------------------------------------------------------------------

---UI.Dropdown(parent, { {value, label}, ... }, onChange). :SetValue(v, silent), .value.
function UI.Dropdown(parent, options, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(160, 24)
  b.box = UI.Box(b, "BACKGROUND", 0)
  b.box:Set(C.lineStrong, C.inset)
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
  b:SetScript("OnEnter", function(self) self.box:Set(C.quietBorder, C.inset) end)
  b:SetScript("OnLeave", function(self) self.box:Set(C.lineStrong, C.inset) end)
  b:SetScript("OnClick", function(self)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(self, function(_, root)
      for _, o in ipairs(self.options) do
        root:CreateRadio(o[2], function() return self.value == o[1] end, function() self:SetValue(o[1]) end)
      end
    end)
  end)
  return b
end

-------------------------------------------------------------------------------------------
-- Scroll area: a content frame that scrolls with the mouse wheel (native ScrollFrame)
-------------------------------------------------------------------------------------------

function UI.ScrollArea(parent)
  local s = CreateFrame("ScrollFrame", nil, parent)
  s.content = CreateFrame("Frame", nil, s)
  s.content:SetSize(1, 1)
  s:SetScrollChild(s.content)
  s:EnableMouseWheel(true)
  s:SetScript("OnMouseWheel", function(self, delta)
    local range = math.max(0, (self.content:GetHeight() or 0) - (self:GetHeight() or 0))
    local v = math.max(0, math.min(range, (self:GetVerticalScroll() or 0) - delta * 40))
    self:SetVerticalScroll(v)
  end)
  s:SetScript("OnSizeChanged", function(self, w) self.content:SetWidth(w or self:GetWidth() or 1) end)
  return s
end

-------------------------------------------------------------------------------------------
-- Settings list
-------------------------------------------------------------------------------------------

local ROW_GAP, CONTROL_W = 14, 170

---A vertical list of setting rows inside a scroll area; see the example at the top.
function UI.SettingsList(parent)
  local area = UI.ScrollArea(parent)
  area:SetAllPoints()
  local list = { area = area, content = area.content, rows = {}, y = -8, items = {} }

  -- each item: { region, height = number or function() (measured again on every layout), gap }
  local function place(region, height, gap)
    table.insert(list.items, { region = region, height = height, gap = gap or 0 })
    list:Layout()
  end

  ---Stacks the rows again. A description's wrapped height is only right once the page has its
  ---real width, so this runs when the list is resized or shown (and after every row is added).
  function list:Layout()
    local y = -8
    for _, item in ipairs(self.items) do
      y = y - item.gap
      local h = type(item.height) == "function" and item.height() or item.height
      item.region:ClearAllPoints()
      item.region:SetPoint("TOPLEFT", self.content, "TOPLEFT", 12, y)
      item.region:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", -12, y)
      if item.region.SetHeight and item.region.desc then item.region:SetHeight(h) end
      y = y - h - ROW_GAP
    end
    self.y = y
    self.content:SetHeight(-y + 8)
  end
  area:HookScript("OnSizeChanged", function() list:Layout() end)
  area:HookScript("OnShow", function() list:Layout() C_Timer.After(0, function() list:Layout() end) end)

  function list:Header(text)
    local h = UI.Text(self.content, "title", 16, C.goldSoft)
    h:SetText(text)
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
      r.desc:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -3)
      r.desc:SetPoint("TOPRIGHT", r.label, "BOTTOMRIGHT", 0, -3)
      r.desc:SetWordWrap(true)
      r.desc:SetText(desc)
    end
    local function height()
      if not r.desc then return 18 end
      return 18 + 3 + math.max(14, r.desc:GetStringHeight() or 14)
    end
    local h = height()
    control:SetParent(r)
    control:ClearAllPoints()
    control:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    r.control, r.refresh = control, refresh
    r:SetHeight(h)
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
    local s = UI.Slider(holder, min, max, step, function(v)
      set(v)
      holder.value:SetText(string.format(fmt or "%s", v * (scale or 1)))
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
      holder.value:SetText(string.format(fmt or "%s", v * (scale or 1)))
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
    for _, r in ipairs(self.rows) do if r.refresh then r.refresh() end end
    self:Layout()
  end

  return list
end
