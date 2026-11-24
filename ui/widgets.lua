-- The UI kit's controls: buttons, the search field, chips, toggles, tabs and the segmented control.
-- Widgets inside a window follow its accent colour (Window:SetAccent).

local Core = NorgannonCore
local UI = Core.UI
local C, TEX = UI.C, UI.TEX
local tex, pill = UI.Tex, UI.Pill
local attachAccent, applyAccent, repaintOnHover = UI.AttachAccent, UI.ApplyAccent, UI.RepaintOnHover

local WHITE = { 1, 1, 1 }

-------------------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------------------

local BUTTON_STYLES = {
  -- style = function(accent, hover) -> fill, text
  primary = function(accent, hover)
    local fill = hover and UI.Mix(accent, WHITE, .2) or accent
    return fill, UI.OnColor(fill)
  end,
  quiet = function(accent, hover)
    return UI.Mix({ .165, .14, .115 }, accent, hover and .24 or .09), hover and WHITE or C.quietText
  end,
  accent = function(accent, hover)
    return UI.Mix({ .106, .078, .063 }, accent, hover and .48 or .34), WHITE
  end,
}

---A text button: style "primary" (filled with the window's accent), "quiet" or "accent" (a darker accent).
function UI.Button(parent, text, style, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(24)
  b.style = BUTTON_STYLES[style] and style or "primary"
  b.box = UI.Face(b, "BACKGROUND", 0)
  b.label = UI.Text(b, "title", 13)
  b.label:SetPoint("CENTER", 0, 0)
  b.label:SetJustifyH("CENTER")
  b.accent = C.goldSoft

  function b:Paint()
    local fill, textColor = BUTTON_STYLES[self.style](self.accent, self.hover)
    self.box:Set(self.down and UI.Mix(fill, C.black, .14) or fill)
    -- dark text on a light button reads cleaner without the drop shadow
    self.label:SetShadowColor(0, 0, 0, textColor[1] > .5 and .9 or 0)
    self.label:SetTextColor(textColor[1], textColor[2], textColor[3])
  end
  b.ApplyAccent = applyAccent
  function b:SetLabel(value)
    self.label:SetText(value)
    self:SetWidth(math.max(64, math.floor(self.label:GetStringWidth() + 30)))
  end

  repaintOnHover(b)
  -- the button sinks while it's held
  local function press(down)
    return function(self)
      self.down = down
      self.label:SetPoint("CENTER", 0, down and -1 or 0)
      self.box:Press(down)
      self:Paint()
    end
  end
  b:SetScript("OnMouseDown", press(true))
  b:SetScript("OnMouseUp", press(false))
  if onClick then b:SetScript("OnClick", onClick) end
  b:SetLabel(text)
  attachAccent(b)
  return b
end

---The close button: a quiet cross that turns red under the mouse.
function UI.CloseButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(22, 22)
  b.box = UI.SoftBox(b, "BACKGROUND", 0, 5)
  b.box:Set(nil, { 1, 1, 1, .06 })
  b.icon = UI.Icon(b, "close", 12, C.muted)
  b.icon:SetPoint("CENTER")
  b:SetScript("OnEnter", function(self)
    self.box:Set(nil, C.redTop)
    self.icon:SetVertexColor(1, 1, 1)
  end)
  b:SetScript("OnLeave", function(self)
    self.box:Set(nil, { 1, 1, 1, .06 })
    self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
  end)
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
  f.box = UI.Field(f, "BACKGROUND", 0)
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
  f.clear:SetScript("OnClick", function()
    edit:SetText("")
    edit:ClearFocus()
  end)

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
    self.box:Set(self.focused and self.accent or UI.Mix(C.line, self.accent, .22), self.focused)
  end
  f.ApplyAccent = applyAccent
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
  edit:SetScript("OnEditFocusGained", function()
    f.focused = true
    f:Paint()
  end)
  edit:SetScript("OnEditFocusLost", function()
    f.focused = false
    f:Paint()
  end)
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
  b.ApplyAccent = applyAccent
  function b:SetOn(on, silent)
    self.on = on and true or false
    self:Paint()
    if not silent and onToggle then onToggle(self.on) end
  end
  b:SetScript("OnClick", function(self) self:SetOn(not self.on) end)
  repaintOnHover(b)
  attachAccent(b)
  return b
end

local SLIDE = .14          -- seconds for a switch to cross
local KNOB_OFF, KNOB_ON = 11, 29

local function switchArt(b, name, sub)
  local t = UI.Smooth(b:CreateTexture(nil, "ARTWORK", nil, sub))
  t:SetTexture(TEX[name])
  t:SetTexCoord(0, .75, 0, .9375)      -- a 48x30 cell: the 40x22 switch and 4 to spare for its glow
  t:SetPoint("TOPLEFT", -4, 4)
  t:SetSize(48, 30)
  return t
end

---An on/off switch: UI.Toggle(parent, function(on) end). :SetOn(on, silent). The knob slides and the track fills with the
---window's accent; silent (or out of sight) it is simply there.
function UI.Toggle(parent, onChange)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(40, 22)
  b.glow = switchArt(b, "switchGlow", 0)
  b.well = switchArt(b, "switchWell", 1)
  b.fill = switchArt(b, "switchFill", 2)
  b.knob = UI.Knob(b)
  b.on, b.at = false, 0

  -- at: 0 off, 1 on, between while it slides
  function b:Paint()
    local at, a = self.at, self.accent
    local x = KNOB_OFF + (KNOB_ON - KNOB_OFF) * at
    self.knob:ClearAllPoints()
    self.knob:SetPoint("CENTER", self, "LEFT", x, 0)
    local lit = math.min(1, .64 + .36 * at + (self.hover and .14 or 0))
    self.knob:SetVertexColor(lit, lit * (.975 + .025 * at), lit * (.92 + .08 * at))
    self.fill:SetVertexColor(a[1], a[2], a[3], at)
    self.glow:SetVertexColor(a[1], a[2], a[3], .34 * at + (self.hover and .16 or 0))
  end
  b.ApplyAccent = applyAccent

  local function slide(self, elapsed)
    self.time = self.time + elapsed
    local t = math.min(1, self.time / SLIDE)
    local eased = 1 - (1 - t) ^ 3
    self.at = self.from + ((self.on and 1 or 0) - self.from) * eased
    if t >= 1 then self:SetScript("OnUpdate", nil) end
    self:Paint()
  end
  function b:SetOn(on, silent)
    self.on = on and true or false
    if silent or not self:IsVisible() then
      self.at = self.on and 1 or 0
      self:SetScript("OnUpdate", nil)
      self:Paint()
    else
      self.from, self.time = self.at, 0
      self:SetScript("OnUpdate", slide)
    end
    if not silent and onChange then onChange(self.on) end
  end
  b:SetScript("OnHide", function(self)
    self:SetScript("OnUpdate", nil)
    self.at = self.on and 1 or 0
    self:Paint()
  end)
  b:SetScript("OnClick", function(self)
    local kit = rawget(_G, "SOUNDKIT")
    if kit and PlaySound then
      pcall(PlaySound, self.on and kit.IG_MAINMENU_OPTION_CHECKBOX_OFF or kit.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
    self:SetOn(not self.on)
  end)
  repaintOnHover(b)
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
    t.wash = tex(t, "BACKGROUND", 0)       -- the selected tab's glow, rising from its line
    t.wash:SetAllPoints()
    t.line = tex(t, "ARTWORK", 1)
    t.line:SetHeight(2)
    t.line:SetPoint("BOTTOMLEFT", 4, 0)
    t.line:SetPoint("BOTTOMRIGHT", -4, 0)
    t:SetPoint("BOTTOMLEFT", previous or bar, previous and "BOTTOMRIGHT" or "BOTTOMLEFT", previous and 2 or 0, 0)
    t:SetScript("OnClick", function(self) bar:Select(self.key) end)
    t:SetScript("OnEnter", function(self)
      self.hover = true
      bar:Paint()
    end)
    t:SetScript("OnLeave", function(self)
      self.hover = false
      bar:Paint()
    end)
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
    local selected = UI.Readable(self.accent)
    for _, t in ipairs(self.tabs) do
      local on = t.key == self.selected
      local c = on and selected or (t.hover and C.text or C.muted)
      t.label:SetTextColor(c[1], c[2], c[3])
      t.line:SetColorTexture(self.accent[1], self.accent[2], self.accent[3], 1)
      t.line:SetShown(on)
      UI.Gradient(t.wash, self.accent, self.accent, 0, .18)
      t.wash:SetShown(on)
    end
  end
  bar.ApplyAccent = applyAccent
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
-- Segmented control: a pill of options, one selected. The selection fills the pill's rounded
-- ends exactly (end segments get rounded highlight caps).
-------------------------------------------------------------------------------------------

-- The highlight behind a segment: rounded on the pill's outer ends, square between segments.
-- b.hl holds every part; b.mid is the middle (a solid colour, where the caps are tinted textures).
local function addSegmentHighlight(b, inner, first, last)
  b.hl = {}
  local function cap(texLeft, texRight)
    local t = UI.Smooth(b:CreateTexture(nil, "ARTWORK"))
    t:SetTexture(TEX.dot)
    t:SetTexCoord(texLeft, texRight, 0, 1)
    t:SetSize(inner / 2, inner)
    b.hl[#b.hl + 1] = t
    return t
  end
  local leftCap = first and cap(0, .5)
  local rightCap = last and cap(.5, 1)
  if leftCap then leftCap:SetPoint("LEFT") end
  if rightCap then rightCap:SetPoint("RIGHT") end
  local mid = b:CreateTexture(nil, "ARTWORK")
  mid:SetColorTexture(1, 1, 1, 1)
  mid:SetPoint("TOPLEFT", leftCap or b, leftCap and "TOPRIGHT" or "TOPLEFT")
  mid:SetPoint("BOTTOMRIGHT", rightCap or b, rightCap and "BOTTOMLEFT" or "BOTTOMRIGHT")
  b.mid = mid
  b.hl[#b.hl + 1] = mid
end

local function newSegment(seg, item, inner, first, last)
  local b = CreateFrame("Button", nil, seg)
  b.key, b.tip = item.key, item.tip
  if item.icon then
    b.icon = UI.Icon(b, item.icon, inner - 5, C.muted, "OVERLAY")
    b.icon:SetPoint("CENTER")
    b:SetSize(inner + 6, inner)
  else
    b.text = UI.Text(b, "body", 12, C.muted, "OVERLAY")
    b.text:SetPoint("CENTER")
    b.text:SetJustifyH("CENTER")
    b.text:SetText(item.label)
    b:SetSize(math.floor(b.text:GetStringWidth() + 16), inner)
  end
  addSegmentHighlight(b, inner, first, last)
  b:SetScript("OnClick", function(self) seg:Select(self.key) end)
  b:SetScript("OnEnter", function(self)
    self.hover = true
    seg:Paint()
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(self.tip, 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    self.hover = false
    seg:Paint()
    GameTooltip:Hide()
  end)
  return b
end

---UI.Segmented(parent, items, onSelect[, height]). items = { {key = "near", label = "Nearest"} |
---{key = "compact", icon = "viewCompact", tip = "Compact view"} }. :Select(key, silent),
---:GetSelected(), .buttons. Follows the window accent.
function UI.Segmented(parent, items, onSelect, height)
  local h = height or 18
  local inner = h - 2
  local seg = CreateFrame("Frame", nil, parent)
  seg:SetHeight(h)
  seg.border = pill(seg, h, "BACKGROUND", 0)
  seg.border:SetColor(C.lineStrong)
  seg.fill = pill(seg, h, "BACKGROUND", 1, 1)
  seg.fill:SetColor({ 0, 0, 0, .55 })
  seg.buttons = {}
  local x = 1
  for i, item in ipairs(items) do
    local b = newSegment(seg, item, inner, i == 1, i == #items)
    b:SetPoint("LEFT", seg, "LEFT", x, 0)
    x = x + b:GetWidth()
    seg.buttons[i] = b
  end
  seg:SetWidth(x + 1)
  seg.accent = C.goldSoft

  function seg:Paint()
    local a = self.accent
    for _, b in ipairs(self.buttons) do
      local on = b.key == self.selected
      local alpha = on and .42 or 0
      for _, t in ipairs(b.hl) do
        if t == b.mid then
          t:SetColorTexture(a[1], a[2], a[3], alpha)
        else
          t:SetVertexColor(a[1], a[2], a[3], alpha)
        end
      end
      local tc = on and WHITE or (b.hover and C.text or C.muted)
      if b.text then b.text:SetTextColor(tc[1], tc[2], tc[3]) end
      if b.icon then b.icon:SetVertexColor(tc[1], tc[2], tc[3]) end
    end
  end
  seg.ApplyAccent = applyAccent
  function seg:Select(key, silent)
    self.selected = key
    self:Paint()
    if not silent and onSelect then onSelect(key) end
  end
  function seg:GetSelected() return self.selected end
  attachAccent(seg)
  return seg
end
