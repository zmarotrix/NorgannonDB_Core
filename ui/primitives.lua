-- The UI kit's foundations: the suite's design system (design/suite/index.html) is drawn with
-- plain textures and the Core's media, never Blizzard art, so every suite window looks the same.
-- These are the drawing primitives, and the accent colour widgets follow (Window:SetAccent).

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

-------------------------------------------------------------------------------------------
-- Rounded boxes: a 9-slice of one rounded-rectangle texture (corner = a quarter of it), so
-- corners stay round at any size. The game has no rounded borders of its own.
-------------------------------------------------------------------------------------------

local CORNER = .25   -- the texture's corner slice, as a share of its size

local function setPiecesColor(self, c, alpha)
  for _, piece in ipairs(self.pieces) do piece:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1) end
end

---A rounded rectangle filling frame: UI.Round(frame, layer, sub, radius[, "line"]).
---:SetColor(c, alpha). "line" draws the outline texture instead of the fill.
function UI.Round(frame, layer, sub, radius, style)
  local file = style == "line" and TEX.roundLine or TEX.round
  local r = radius or 6
  local p = {}
  local function piece(texLeft, texRight, texTop, texBottom)
    local tx = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    tx:SetTexture(file)
    tx:SetTexCoord(texLeft, texRight, texTop, texBottom)
    p[#p + 1] = tx
    return tx
  end
  local m = CORNER
  -- fixed-size corners; the edges and the centre stretch between them
  local tl, tr = piece(0, m, 0, m), piece(1 - m, 1, 0, m)
  local bl, br = piece(0, m, 1 - m, 1), piece(1 - m, 1, 1 - m, 1)
  for _, corner in ipairs({ tl, tr, bl, br }) do corner:SetSize(r, r) end
  tl:SetPoint("TOPLEFT")
  tr:SetPoint("TOPRIGHT")
  bl:SetPoint("BOTTOMLEFT")
  br:SetPoint("BOTTOMRIGHT")
  local top, bottom = piece(m, 1 - m, 0, m), piece(m, 1 - m, 1 - m, 1)
  top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
  top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
  bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local left, right = piece(0, m, m, 1 - m), piece(1 - m, 1, m, 1 - m)
  left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
  left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
  right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  local center = piece(m, 1 - m, m, 1 - m)
  center:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
  center:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
  local box = { pieces = p, SetColor = setPiecesColor }
  function box:SetShown(on) for _, tx in ipairs(self.pieces) do tx:SetShown(on) end end
  return box
end

---The left edge of a rounded box, `width` wide, following its curve (a colour stripe on a card).
function UI.RoundEdge(frame, layer, sub, radius, width)
  local r, w = radius or 6, width or 3
  local u = CORNER * w / r   -- texture width of the stripe
  local function piece(t, b)
    local tx = frame:CreateTexture(nil, layer or "BORDER", nil, sub or 0)
    tx:SetTexture(TEX.round)
    tx:SetTexCoord(0, u, t, b)
    tx:SetWidth(w)
    return tx
  end
  local top, mid, bottom = piece(0, CORNER), piece(CORNER, 1 - CORNER), piece(1 - CORNER, 1)
  top:SetHeight(r)
  bottom:SetHeight(r)
  top:SetPoint("TOPLEFT")
  bottom:SetPoint("BOTTOMLEFT")
  mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
  mid:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
  return { pieces = { top, mid, bottom }, SetColor = setPiecesColor }
end

---An icon texture from the Core's media, tinted.
function UI.Icon(parent, name, size, c, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(TEX[name] or name)
  t:SetSize(size, size)
  if c then t:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
  return t
end

---The texture of an add-on's mark: its own (an add-on outside the suite passes `mark` to Core:NewAddon), else the
---Core's marks\<key>.
function UI.MarkPath(key)
  local info = key and Core:GetAddonInfo(key)
  if info and info.mark then return info.mark end
  -- the Core has a mark for each add-on in its registry; anything else shows the Core's star
  return UI.MEDIA .. "marks\\" .. ((info and not info.external) and key or "core")
end

---A suite addon's mark (gold disc with its symbol).
function UI.Mark(parent, key, size, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(UI.MarkPath(key))
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

---The suite window a frame sits in, or nil.
local function windowOf(frame)
  local f = frame
  while f do
    if f._norgWindow then return f end
    f = f:GetParent()
  end
end
UI.WindowOf = windowOf

local function attachAccent(widget)
  local window = windowOf(widget)
  if window then
    table.insert(window._accentWidgets, widget)
    widget:ApplyAccent(window.accent or C.goldSoft)
  else
    widget:ApplyAccent(C.goldSoft)
  end
end

-- For the widgets that keep their whole look in a Paint method: b.ApplyAccent = applyAccent.
local function applyAccent(self, c)
  self.accent = c
  self:Paint()
end

local function hoverOn(self)
  self.hover = true
  self:Paint()
end

local function hoverOff(self)
  self.hover = false
  self:Paint()
end

local function repaintOnHover(widget)
  widget:SetScript("OnEnter", hoverOn)
  widget:SetScript("OnLeave", hoverOff)
end

UI.AttachAccent, UI.ApplyAccent, UI.RepaintOnHover = attachAccent, applyAccent, repaintOnHover
