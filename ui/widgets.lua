-- The UI kit's controls: buttons, the search field, chips, toggles, tabs and the segmented control.
-- Widgets inside a window follow its accent colour (Window:SetAccent).

local Core = NorgannonCore
local UI = Core.UI
local C, TEX = UI.C, UI.TEX
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
    f.hint.box = UI.SoftBox(f.hint, "BACKGROUND", 3, 4)
    f.hint.box:Set(nil, { 1, 1, 1, .05 })
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
  b.well = UI.Band(b, "BACKGROUND", 0, "pillWell", true)
  b.line = UI.Band(b, "BACKGROUND", 1, "pillLine", true)
  b.face = UI.Face(b, "BACKGROUND", 0, true)
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
    -- on: raised, in a deep accent; off: an empty recess
    self.face:SetShown(self.on)
    self.well:SetShown(not self.on)
    self.line:SetShown(not self.on)
    if self.on then
      self.face:Set(UI.Mix({ .106, .078, .063 }, self.accent, self.hover and .5 or .38))
      self.label:SetTextColor(1, 1, 1)
    else
      self.line:SetColor(UI.Mix(C.line, self.accent, self.hover and .6 or .2))
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
    t.wash = t:CreateTexture(nil, "BACKGROUND")       -- the selected tab's light, rising from its line
    t.wash:SetTexture(TEX.tabGlow)
    t.wash:SetAllPoints()
    t.line = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t.line:SetTexture(TEX.tabLine)
    t.line:SetHeight(2)
    t.line:SetPoint("BOTTOMLEFT", 0, 0)
    t.line:SetPoint("BOTTOMRIGHT", 0, 0)
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
      -- the mouse gets a fainter light
      t.line:SetVertexColor(self.accent[1], self.accent[2], self.accent[3], on and 1 or .35)
      t.line:SetShown(on or t.hover or false)
      t.wash:SetVertexColor(self.accent[1], self.accent[2], self.accent[3], on and .34 or .12)
      t.wash:SetShown(on or t.hover or false)
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
-- Segmented control: a recessed pill of options with one raised key, which slides to the one selected
-------------------------------------------------------------------------------------------

local KEY_INSET = 2   -- the key's gap to the pill's edge

local function newSegment(seg, item, inner)
  local b = CreateFrame("Button", nil, seg)
  b:SetFrameLevel(seg.thumb:GetFrameLevel() + 1)   -- its words over the key
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
  seg.well = UI.Band(seg, "BACKGROUND", 0, "pillWell", true)
  seg.line = UI.Band(seg, "BACKGROUND", 1, "pillLine", true)
  seg.thumb = CreateFrame("Frame", nil, seg)
  seg.thumb:SetHeight(h - KEY_INSET * 2)
  seg.thumb.face = UI.Face(seg.thumb, "BACKGROUND", 0, true)
  seg.thumb:Hide()
  seg.buttons = {}
  local x = KEY_INSET
  for i, item in ipairs(items) do
    local b = newSegment(seg, item, inner)
    b:SetPoint("LEFT", seg, "LEFT", x, 0)
    b.x, b.w = x, b:GetWidth()
    x = x + b.w
    seg.buttons[i] = b
  end
  seg:SetWidth(x + KEY_INSET)
  seg.accent = C.goldSoft

  local function moveKey(left, width)
    seg.keyX, seg.keyW = left, width
    seg.thumb:SetPoint("LEFT", seg, "LEFT", left, 0)
    seg.thumb:SetWidth(width)
  end
  local function slide(self, elapsed)
    self.time = self.time + elapsed
    local t = math.min(1, self.time / SLIDE)
    local eased = 1 - (1 - t) ^ 3
    moveKey(self.fromX + (self.target.x - self.fromX) * eased, self.fromW + (self.target.w - self.fromW) * eased)
    if t >= 1 then self:SetScript("OnUpdate", nil) end
  end
  local function settle()
    seg:SetScript("OnUpdate", nil)
    if seg.target then moveKey(seg.target.x, seg.target.w) end
  end

  function seg:Paint()
    local fill = UI.Mix({ .1, .08, .06 }, self.accent, .8)
    local on = UI.OnColor(fill)
    self.thumb.face:Set(fill)
    self.line:SetColor(UI.Mix(C.line, self.accent, .22))
    for _, b in ipairs(self.buttons) do
      local selected = b.key == self.selected
      local tc = selected and on or (b.hover and C.text or C.muted)
      if b.text then
        b.text:SetTextColor(tc[1], tc[2], tc[3])
        b.text:SetShadowColor(0, 0, 0, tc[1] > .5 and .9 or 0)
      end
      if b.icon then b.icon:SetVertexColor(tc[1], tc[2], tc[3]) end
    end
  end
  seg.ApplyAccent = applyAccent
  ---silent (or out of sight) the key is simply there
  function seg:Select(key, silent)
    local target
    for _, b in ipairs(self.buttons) do if b.key == key then target = b end end
    local slides = not silent and target and self.target and target ~= self.target and self:IsVisible()
    self.selected, self.target = key, target
    self.thumb:SetShown(target ~= nil)
    if slides then
      self.fromX, self.fromW, self.time = self.keyX, self.keyW, 0
      self:SetScript("OnUpdate", slide)
    else
      settle()
    end
    self:Paint()
    if not silent and onSelect then onSelect(key) end
  end
  function seg:GetSelected() return self.selected end
  seg:SetScript("OnHide", settle)
  attachAccent(seg)
  return seg
end
