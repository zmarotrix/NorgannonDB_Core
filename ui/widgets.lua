-- The UI kit: the suite's design system (design/suite/index.html) as widgets. Everything is
-- drawn with plain textures and the Core's media, never Blizzard art, so every suite window
-- looks the same. Widgets inside a window follow its accent colour (Window:SetAccent).

local Core = NorgannonCore
local UI = Core.UI
local C, TEX = UI.C, UI.TEX

-------------------------------------------------------------------------------------------
-- Primitives
-------------------------------------------------------------------------------------------

local function color(t, c, alpha)
  t:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
end

local function tex(parent, layer, sub, c)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  if c then color(t, c) end
  return t
end
UI.Tex = tex

local function colorObject(c, alpha)
  return CreateColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

---Vertical gradient from top to bottom colour.
local function gradient(t, top, bottom, topAlpha, bottomAlpha)
  t:SetColorTexture(1, 1, 1, 1)
  t:SetGradient("VERTICAL", colorObject(bottom, bottomAlpha), colorObject(top, topAlpha))
end
UI.Gradient = gradient

---Horizontal fade of one colour, from alpha at the left to nothing at the right.
function UI.GradientH(t, c, alpha)
  t:SetColorTexture(1, 1, 1, 1)
  t:SetGradient("HORIZONTAL", colorObject(c, alpha), colorObject(c, 0))
end

---A 1px border with a fill inside: box:Set(border, fillTop, fillBottom).
function UI.Box(frame, layer, sub)
  local box = { border = tex(frame, layer, sub or 0), fill = tex(frame, layer, (sub or 0) + 1) }
  box.border:SetAllPoints()
  box.fill:SetPoint("TOPLEFT", 1, -1)
  box.fill:SetPoint("BOTTOMRIGHT", -1, 1)
  function box:Set(border, top, bottom)
    color(self.border, border)
    if bottom then gradient(self.fill, top, bottom) else color(self.fill, top) end
  end
  return box
end

---A pill (rounded ends) of a fixed height, optionally inset (for a fill inside a border pill).
local function pill(frame, height, layer, sub, inset)
  inset = inset or 0
  local h = height - inset * 2
  local p = {}
  p.left = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  p.left:SetTexture(TEX.circle)
  p.left:SetTexCoord(0, .5, 0, 1)
  p.left:SetSize(h / 2, h)
  p.left:SetPoint("LEFT", inset, 0)
  p.right = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  p.right:SetTexture(TEX.circle)
  p.right:SetTexCoord(.5, 1, 0, 1)
  p.right:SetSize(h / 2, h)
  p.right:SetPoint("RIGHT", -inset, 0)
  p.mid = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
  p.mid:SetPoint("TOPLEFT", p.left, "TOPRIGHT")
  p.mid:SetPoint("BOTTOMRIGHT", p.right, "BOTTOMLEFT")
  function p:SetColor(c, alpha)
    local a = alpha or c[4] or 1
    self.left:SetVertexColor(c[1], c[2], c[3], a)
    self.right:SetVertexColor(c[1], c[2], c[3], a)
    self.mid:SetColorTexture(c[1], c[2], c[3], a)
  end
  return p
end
UI.Pill = pill

---An icon texture from the Core's media, tinted.
function UI.Icon(parent, name, size, c, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(TEX[name] or name)
  t:SetSize(size, size)
  if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
  return t
end

---A suite addon's mark (gold disc with its symbol).
function UI.Mark(parent, key, size, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(UI.MEDIA .. "marks\\" .. key)
  t:SetSize(size, size)
  return t
end

---A 1px horizontal rule in the line colour.
function UI.Rule(parent, c)
  local t = tex(parent, "ARTWORK", 0, c or C.line)
  t:SetHeight(1)
  return t
end

---An inset pane (lists sit in these): dark fill, 1px line border.
function UI.Pane(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.box = UI.Box(f, "BACKGROUND", 0)
  f.box:Set(C.line, C.inset)
  return f
end

-------------------------------------------------------------------------------------------
-- Accent: widgets register with their window and are recoloured by Window:SetAccent
-------------------------------------------------------------------------------------------

local function windowOf(frame)
  local f = frame
  while f do
    if f._norgWindow then return f end
    f = f:GetParent()
  end
end

local function attachAccent(widget)
  local window = windowOf(widget)
  if window then
    table.insert(window._accentWidgets, widget)
    widget:ApplyAccent(window.accent or C.goldSoft)
  else
    widget:ApplyAccent(C.goldSoft)
  end
end

-------------------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------------------

local BUTTON_STYLES = {
  -- style = function(accent, hover) -> border, fillTop, fillBottom, text
  primary = function(_, hover)
    if hover then return C.redBorder, UI.Mix(C.redTop, { 1, 1, 1 }, .12), UI.Mix(C.redBottom, { 1, 1, 1 }, .08), { 1, .95, .69 } end
    return C.redBorder, C.redTop, C.redBottom, C.gold
  end,
  quiet = function(accent, hover)
    return hover and accent or C.quietBorder, C.quietTop, C.quietBottom, hover and { 1, 1, 1 } or C.quietText
  end,
  accent = function(accent, hover)
    local top = UI.Mix({ .106, .078, .063 }, accent, hover and .55 or .4)
    return accent, top, { .07, .05, .035 }, { 1, 1, 1 }
  end,
}

---A text button: style "primary" (red and gold), "quiet" or "accent".
function UI.Button(parent, text, style, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(24)
  b.style = BUTTON_STYLES[style] and style or "primary"
  b.box = UI.Box(b, "BACKGROUND", 0)
  b.label = UI.Text(b, "title", 13)
  b.label:SetPoint("CENTER", 0, 0)
  b.label:SetJustifyH("CENTER")
  b.accent = C.goldSoft

  function b:Paint()
    local border, top, bottom, textColor = BUTTON_STYLES[self.style](self.accent, self.hover)
    self.box:Set(border, top, bottom)
    self.label:SetTextColor(textColor[1], textColor[2], textColor[3])
  end
  function b:ApplyAccent(c) self.accent = c self:Paint() end
  function b:SetLabel(value)
    self.label:SetText(value)
    self:SetWidth(math.max(64, math.floor(self.label:GetStringWidth() + 30)))
  end

  b:SetScript("OnEnter", function(self) self.hover = true self:Paint() end)
  b:SetScript("OnLeave", function(self) self.hover = false self:Paint() end)
  b:SetScript("OnMouseDown", function(self) self.label:SetPoint("CENTER", 1, -1) end)
  b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
  if onClick then b:SetScript("OnClick", onClick) end
  b:SetLabel(text)
  attachAccent(b)
  return b
end

---The red close button with a gold cross.
function UI.CloseButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(22, 22)
  b.box = UI.Box(b, "BACKGROUND", 0)
  b.box:Set(C.redBorder, C.redTop, C.redBottom)
  b.icon = UI.Icon(b, "close", 12, C.gold)
  b.icon:SetPoint("CENTER")
  b:SetScript("OnEnter", function(self) self.box:Set(C.redBorder, UI.Mix(C.redTop, { 1, 1, 1 }, .15), C.redBottom) self.icon:SetVertexColor(1, .95, .7) end)
  b:SetScript("OnLeave", function(self) self.box:Set(C.redBorder, C.redTop, C.redBottom) self.icon:SetVertexColor(C.gold[1], C.gold[2], C.gold[3]) end)
  b:SetScript("OnClick", onClick)
  return b
end

-------------------------------------------------------------------------------------------
-- Search field
-------------------------------------------------------------------------------------------

---A search box: UI.Search(parent, "Search…", function(text) end[, onSubmit, hint]).
---:GetText, :SetText, :SetFocus. hint is a small key label at the right, e.g. "/clair".
function UI.Search(parent, placeholder, onChange, onSubmit, hint)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(28)
  f.box = UI.Box(f, "BACKGROUND", 0)
  f.icon = UI.Icon(f, "search", 14, C.muted)
  f.icon:SetPoint("LEFT", 9, 0)
  f.icon:SetAlpha(.8)

  local edit = CreateFrame("EditBox", nil, f)
  f.edit = edit
  edit:SetPoint("LEFT", f.icon, "RIGHT", 7, 0)
  edit:SetPoint("RIGHT", -26, 0)
  edit:SetHeight(22)
  edit:SetFontObject(UI.Font("body", 14))
  edit:SetTextColor(C.text[1], C.text[2], C.text[3])
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(80)

  f.placeholder = UI.Text(f, "body", 14, C.faint)
  f.placeholder:SetPoint("LEFT", edit, "LEFT", 0, 0)
  f.placeholder:SetText(placeholder or "")

  f.clear = CreateFrame("Button", nil, f)
  f.clear:SetSize(18, 18)
  f.clear:SetPoint("RIGHT", -6, 0)
  f.clear.icon = UI.Icon(f.clear, "close", 10, C.muted)
  f.clear.icon:SetPoint("CENTER")
  f.clear:Hide()
  f.clear:SetScript("OnClick", function() edit:SetText("") edit:ClearFocus() end)

  if hint then
    f.hint = CreateFrame("Frame", nil, f)
    f.hint.text = UI.Text(f.hint, "body", 11, C.faint)
    f.hint.text:SetPoint("CENTER", 0, 0)
    f.hint.text:SetText(hint)
    f.hint:SetSize(math.floor(f.hint.text:GetStringWidth() + 10), 16)
    f.hint:SetPoint("RIGHT", -6, 0)
    f.hint.box = UI.Box(f.hint, "BACKGROUND", 0)
    f.hint.box:Set(C.line, C.inset)
    edit:SetPoint("RIGHT", f.hint, "LEFT", -6, 0)
  end

  function f:Paint()
    self.box:Set(self.focused and self.accent or C.lineStrong, C.inset)
  end
  function f:ApplyAccent(c) self.accent = c self:Paint() end
  function f:GetText() return edit:GetText() end
  function f:SetText(text) edit:SetText(text or "") end
  function f:SetFocus() edit:SetFocus() end

  edit:SetScript("OnTextChanged", function(self)
    local text = self:GetText()
    f.placeholder:SetShown(text == "")
    f.clear:SetShown(text ~= "")
    if f.hint then f.hint:SetShown(text == "") end
    if onChange then onChange(text) end
  end)
  edit:SetScript("OnEditFocusGained", function() f.focused = true f:Paint() end)
  edit:SetScript("OnEditFocusLost", function() f.focused = false f:Paint() end)
  edit:SetScript("OnEscapePressed", function(self)
    if self:GetText() ~= "" then self:SetText("") else self:ClearFocus() end
  end)
  edit:SetScript("OnEnterPressed", function(self)
    if onSubmit then onSubmit(self:GetText()) end
    self:ClearFocus()
  end)
  f:EnableMouse(true)
  f:SetScript("OnMouseDown", function() edit:SetFocus() end)
  attachAccent(f)
  return f
end

-------------------------------------------------------------------------------------------
-- Chips, toggles, tabs
-------------------------------------------------------------------------------------------

---A filter chip: UI.Chip(parent, "Herbs", dotColor, function(on) end). :SetOn(on, silent).
function UI.Chip(parent, text, dot, onToggle)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(20)
  b.border = pill(b, 20, "BACKGROUND", 0)
  b.fill = pill(b, 20, "BACKGROUND", 1, 1)
  b.label = UI.Text(b, "body", 13, C.muted)
  if dot then
    b.dot = UI.Icon(b, "circle", 8, dot)
    b.dot:SetPoint("LEFT", 9, 0)
    b.label:SetPoint("LEFT", b.dot, "RIGHT", 5, 0)
  else
    b.label:SetPoint("LEFT", 10, 0)
  end
  b.label:SetText(text)
  b:SetWidth(math.floor(b.label:GetStringWidth() + (dot and 33 or 20)))
  b.on = false

  function b:Paint()
    if self.on then
      self.border:SetColor(UI.Mix(C.line, self.accent, .7))
      self.fill:SetColor(UI.Mix(C.inset, self.accent, self.hover and .22 or .14))
      self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
    else
      self.border:SetColor(self.hover and UI.Mix(C.lineStrong, self.accent, .5) or C.lineStrong)
      self.fill:SetColor(C.inset)
      self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    end
  end
  function b:ApplyAccent(c) self.accent = c self:Paint() end
  function b:SetOn(on, silent)
    self.on = on and true or false
    self:Paint()
    if not silent and onToggle then onToggle(self.on) end
  end
  b:SetScript("OnClick", function(self) self:SetOn(not self.on) end)
  b:SetScript("OnEnter", function(self) self.hover = true self:Paint() end)
  b:SetScript("OnLeave", function(self) self.hover = false self:Paint() end)
  attachAccent(b)
  return b
end

---An on/off switch: UI.Toggle(parent, function(on) end). :SetOn(on, silent).
function UI.Toggle(parent, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(34, 18)
  b.border = pill(b, 18, "BACKGROUND", 0)
  b.fill = pill(b, 18, "BACKGROUND", 1, 1)
  b.knob = UI.Icon(b, "circle", 12, nil, "ARTWORK")
  b.on = false
  function b:Paint()
    self.knob:ClearAllPoints()
    if self.on then
      self.border:SetColor(self.accent)
      self.fill:SetColor(UI.Mix({ .106, .086, .063 }, self.accent, .45))
      self.knob:SetPoint("LEFT", 19, 0)
      self.knob:SetVertexColor(1, 1, 1)
    else
      self.border:SetColor(C.lineStrong)
      self.fill:SetColor({ .165, .137, .102 })
      self.knob:SetPoint("LEFT", 3, 0)
      self.knob:SetVertexColor(.54, .49, .38)
    end
  end
  function b:ApplyAccent(c) self.accent = c self:Paint() end
  function b:SetOn(on, silent)
    self.on = on and true or false
    self:Paint()
    if not silent and onChange then onChange(self.on) end
  end
  b:SetScript("OnClick", function(self) self:SetOn(not self.on) end)
  attachAccent(b)
  return b
end

---A tab bar: UI.Tabs(parent, { {key = "bosses", label = "Bosses"}, ... }, function(key) end).
---:Select(key, silent), :SetCount(key, n), :GetSelected().
function UI.Tabs(parent, items, onSelect)
  local bar = CreateFrame("Frame", nil, parent)
  bar:SetHeight(32)
  bar.rule = UI.Rule(bar)
  bar.rule:SetPoint("BOTTOMLEFT")
  bar.rule:SetPoint("BOTTOMRIGHT")
  bar.tabs = {}
  local previous
  for _, item in ipairs(items) do
    local t = CreateFrame("Button", nil, bar)
    t.key = item.key
    t:SetHeight(32)
    t.label = UI.Text(t, "title", 14, C.muted)
    t.label:SetPoint("LEFT", 12, 1)
    t.label:SetText(item.label)
    t.count = UI.Text(t, "body", 12, C.faint)
    t.count:SetPoint("LEFT", t.label, "RIGHT", 4, 0)
    t.line = tex(t, "ARTWORK", 1)
    t.line:SetHeight(2)
    t.line:SetPoint("BOTTOMLEFT", 4, 0)
    t.line:SetPoint("BOTTOMRIGHT", -4, 0)
    t:SetPoint("BOTTOMLEFT", previous or bar, previous and "BOTTOMRIGHT" or "BOTTOMLEFT", previous and 2 or 0, 0)
    t:SetScript("OnClick", function(self) bar:Select(self.key) end)
    t:SetScript("OnEnter", function(self) self.hover = true bar:Paint() end)
    t:SetScript("OnLeave", function(self) self.hover = false bar:Paint() end)
    function t:Resize()
      local w = self.label:GetStringWidth() + 24
      if (self.count:GetText() or "") ~= "" then w = w + self.count:GetStringWidth() + 4 end
      self:SetWidth(math.floor(w))
    end
    t:Resize()
    table.insert(bar.tabs, t)
    previous = t
  end

  function bar:Paint()
    for _, t in ipairs(self.tabs) do
      local on = t.key == self.selected
      local c = on and C.gold or (t.hover and C.text or C.muted)
      t.label:SetTextColor(c[1], c[2], c[3])
      t.line:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 1)
      t.line:SetShown(on)
    end
  end
  function bar:ApplyAccent(c) self.accent = c self:Paint() end
  function bar:Select(key, silent)
    self.selected = key
    self:Paint()
    if not silent and onSelect then onSelect(key) end
  end
  function bar:GetSelected() return self.selected end
  function bar:SetCount(key, n)
    for _, t in ipairs(self.tabs) do
      if t.key == key then
        t.count:SetText(n and tostring(n) or "")
        t:Resize()
      end
    end
  end
  attachAccent(bar)
  bar.selected = items[1] and items[1].key
  bar:Paint()
  return bar
end

-------------------------------------------------------------------------------------------
-- Progress bar and card
-------------------------------------------------------------------------------------------

---A 4px progress bar: UI.Bar(parent[, "party"]). :SetProgress(current, total).
---The party variant is a dimmer accent, for other players' progress next to yours.
function UI.Bar(parent, kind)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(4)
  f.track = pill(f, 4, "BACKGROUND", 0)
  f.track:SetColor({ .165, .137, .102 })
  f.fill = tex(f, "ARTWORK", 0)
  f.fill:SetPoint("TOPLEFT")
  f.fill:SetPoint("BOTTOMLEFT")
  f.kind = kind
  f.ratio = 0
  function f:Paint()
    local c = self.kind == "party" and UI.Mix(self.accent, { .53, .53, .53 }, .55) or self.accent
    self.fill:SetColorTexture(c[1], c[2], c[3], 1)
    local w = (self:GetWidth() or 0) * self.ratio
    self.fill:SetWidth(math.max(w, .01))
    self.fill:SetShown(self.ratio > 0)
  end
  function f:ApplyAccent(c) self.accent = c self:Paint() end
  function f:SetProgress(current, total)
    self.ratio = (total and total > 0) and math.max(0, math.min(1, (current or 0) / total)) or 0
    self:Paint()
  end
  f:SetScript("OnSizeChanged", f.Paint)
  attachAccent(f)
  return f
end

---A card: raised panel with an optional gold title. .title, .body (the area under the title).
function UI.Card(parent, title)
  local f = CreateFrame("Frame", nil, parent)
  f.box = UI.Box(f, "BACKGROUND", 0)
  f.box:Set(C.lineStrong, { .114, .09, .067 }, { .07, .055, .04 })
  f.title = UI.Text(f, "title", 15, C.gold)
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText(title or "")
  f.body = CreateFrame("Frame", nil, f)
  f.body:SetPoint("TOPLEFT", 12, title and -32 or -10)
  f.body:SetPoint("BOTTOMRIGHT", -12, 10)
  return f
end

-------------------------------------------------------------------------------------------
-- "Powered by NorgannonDB"
-------------------------------------------------------------------------------------------

---"Powered by NorgannonDB": click it for what NorgannonDB is and how to contribute.
function UI.Powered(parent)
  local f = CreateFrame("Button", nil, parent)
  f:SetHeight(16)
  f.icon = UI.Icon(f, "db", 12, C.faint)
  f.icon:SetPoint("LEFT")
  f.text = UI.Text(f, "body", 11, C.faint)
  f.text:SetPoint("LEFT", f.icon, "RIGHT", 5, 0)
  local function paint(hover)
    local small, name = hover and C.muted or C.faint, hover and C.goldSoft or C.muted
    f.text:SetText(UI.Code(small) .. "POWERED BY|r " .. UI.Code(name) .. "NORGANNONDB|r")
    f.icon:SetVertexColor(small[1], small[2], small[3])
  end
  paint(false)
  f:SetWidth(math.floor(f.text:GetStringWidth() + 18))
  f:SetScript("OnEnter", function() paint(true) end)
  f:SetScript("OnLeave", function() paint(false) end)
  f:SetScript("OnClick", function(self) Core:ShowAbout(self) end)
  return f
end

-------------------------------------------------------------------------------------------
-- Window: the one container every suite addon uses
-------------------------------------------------------------------------------------------

local function savePosition(f)
  local db = Core.db
  if not (db and f.saveKey) then return end
  local point, _, relativePoint, x, y = f:GetPoint()
  db.windows[f.saveKey] = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function restorePosition(f)
  local db = Core.db
  local saved = db and f.saveKey and db.windows[f.saveKey]
  if saved and saved.point then
    f:ClearAllPoints()
    f:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
  end
end

---A suite window. opts = { name = "GlobalName", addon = "clairvoyance", title = "Clairvoyance",
---sub = "Durotar", width, height, footer = true }. Fields: .header .body .footer .footerText.
---Methods: :SetAccent(addonKey), :SetSub(text). Esc closes it; its position is remembered.
function UI.Window(opts)
  local f = CreateFrame("Frame", opts.name, opts.parent or UIParent)
  f:SetSize(opts.width or 640, opts.height or 440)
  f:SetPoint("CENTER")
  f:SetFrameStrata(opts.strata or "HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f._norgWindow = true
  f._accentWidgets = {}
  f.saveKey = opts.name
  f.addon = opts.addon

  -- frame: black, frame-dark, gold, black outlines, then the stone body (suite.css .az-window)
  local function outline(inset, c, sub)
    local t = tex(f, "BACKGROUND", sub, c)
    t:SetPoint("TOPLEFT", -inset, inset)
    t:SetPoint("BOTTOMRIGHT", inset, -inset)
    return t
  end
  outline(5, C.black, -8)
  f.gold = outline(4, C.frameGold, -7)
  outline(3, C.frameDark, -6)
  outline(1, C.black, -5)
  f.bg = outline(0, nil, -4)
  gradient(f.bg, C.stone2, C.stone)
  f.glow = tex(f, "BACKGROUND", -3)
  f.glow:SetPoint("TOPLEFT")
  f.glow:SetPoint("TOPRIGHT")
  f.glow:SetHeight(math.min(160, (opts.height or 440) * .5))
  for _, side in ipairs({ "LEFT", "RIGHT" }) do
    local rivet = f:CreateTexture(nil, "OVERLAY", nil, 7)
    rivet:SetTexture(TEX.rivet)
    rivet:SetSize(14, 14)
    rivet:SetPoint("CENTER", f, "TOP" .. side, side == "LEFT" and -2 or 2, 2)
  end

  -- header
  local header = CreateFrame("Frame", nil, f)
  f.header = header
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(44)
  local shade = tex(header, "BACKGROUND", 0)
  shade:SetAllPoints()
  gradient(shade, C.black, C.black, .25, 0)
  local rule = UI.Rule(header)
  rule:SetPoint("BOTTOMLEFT")
  rule:SetPoint("BOTTOMRIGHT")
  f.mark = UI.Mark(header, opts.addon or "norgannondb", 28)
  f.mark:SetPoint("LEFT", 10, 0)
  f.title = UI.Text(header, "title", 20)
  f.title:SetPoint("LEFT", f.mark, "RIGHT", 10, 0)
  f.title:SetText(opts.title or "")
  f.sub = UI.Text(header, "body", 13, C.muted)
  f.sub:SetPoint("LEFT", f.title, "RIGHT", 10, -1)
  f.sub:SetText(opts.sub or "")
  f.close = UI.CloseButton(header, function() f:Hide() end)
  f.close:SetPoint("RIGHT", -10, 0)
  f.powered = UI.Powered(header)
  f.powered:SetPoint("RIGHT", f.close, "LEFT", -12, 0)

  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() if not f.locked then f:StartMoving() end end)
  header:SetScript("OnDragStop", function() f:StopMovingOrSizing() savePosition(f) end)

  -- footer and body
  if opts.footer then
    local footer = CreateFrame("Frame", nil, f)
    f.footer = footer
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(30)
    local top = UI.Rule(footer)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    f.footerText = UI.Text(footer, "body", 12, C.faint)
    f.footerText:SetPoint("LEFT", 12, 0)
  end
  local body = CreateFrame("Frame", nil, f)
  f.body = body
  body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
  body:SetPoint("BOTTOMRIGHT", f.footer or f, f.footer and "TOPRIGHT" or "BOTTOMRIGHT")

  function f:SetAccent(key)
    self.addon = key
    self.accent = UI.Accent(key)
    local c = self.accent
    self.title:SetTextColor(c[1], c[2], c[3])
    gradient(self.glow, c, c, .1, 0)
    self.mark:SetTexture(UI.MEDIA .. "marks\\" .. (key or "norgannondb"))
    for _, widget in ipairs(self._accentWidgets) do widget:ApplyAccent(c) end
  end
  function f:SetSub(text) self.sub:SetText(text or "") end
  function f:SetTitle(text) self.title:SetText(text or "") end

  if opts.name then
    table.insert(UISpecialFrames, opts.name)
    Core:OnReady(function() restorePosition(f) end)
  end
  f:SetAccent(opts.addon or "norgannondb")
  f:Hide()
  return f
end
