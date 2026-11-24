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

---Lets a texture with curves in it sit between pixels (1.32). The client snaps textures to whole pixels by default, which
---squashes small circles and turns their edges into steps.
local function smooth(t)
  if t.SetSnapToPixelGrid then
    t:SetSnapToPixelGrid(false)
    t:SetTexelSnappingBias(0)
  end
  return t
end
UI.Smooth = smooth

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
  p.left = smooth(frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0))
  p.left:SetTexture(h <= 24 and TEX.dot or TEX.circle)
  p.left:SetTexCoord(0, .5, 0, 1)
  p.left:SetSize(h / 2, h)
  p.left:SetPoint("LEFT", inset, 0)
  p.right = smooth(frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0))
  p.right:SetTexture(h <= 24 and TEX.dot or TEX.circle)
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

local CORNER = .25   -- the rounded rectangle's corner slice, as a share of its size

local function setPiecesColor(self, c, alpha)
  for _, piece in ipairs(self.pieces) do piece:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1) end
end

---A rounded rectangle filling frame: UI.Round(frame, layer, sub, radius[, "line"][, outset]).
---:SetColor(c, alpha). "line" draws the outline texture instead of the fill. outset (1.31) reaches that many pixels
---past the frame's edges (a shadow).
function UI.Round(frame, layer, sub, radius, style, outset)
  return UI.Slice(frame, layer, sub, style == "line" and TEX.roundLine or TEX.round, CORNER, radius or 6, outset)
end

---A nine-slice: file's corners (a share of it, 0 to .5) stay size units across while the rest stretches, reaching outset
---units past the frame's edges (1.32). :SetColor(c, alpha), :SetShown(on), .pieces.
function UI.Slice(frame, layer, sub, file, m, r, outset)
  local o = outset or 0
  local p = {}
  local function piece(texLeft, texRight, texTop, texBottom)
    local tx = smooth(frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0))
    tx:SetTexture(file)
    tx:SetTexCoord(texLeft, texRight, texTop, texBottom)
    p[#p + 1] = tx
    return tx
  end
  -- fixed-size corners; the edges and the centre stretch between them
  local tl, tr = piece(0, m, 0, m), piece(1 - m, 1, 0, m)
  local bl, br = piece(0, m, 1 - m, 1), piece(1 - m, 1, 1 - m, 1)
  for _, corner in ipairs({ tl, tr, bl, br }) do corner:SetSize(r, r) end
  tl:SetPoint("TOPLEFT", -o, o)
  tr:SetPoint("TOPRIGHT", o, o)
  bl:SetPoint("BOTTOMLEFT", -o, -o)
  br:SetPoint("BOTTOMRIGHT", o, -o)
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

---A rounded box with the same :Set(border, fill) as UI.Box (1.31): a flat fill, and an outline unless border is nil.
function UI.SoftBox(frame, layer, sub, radius)
  local box = { fill = UI.Round(frame, layer, sub or 0, radius or 5), line = UI.Round(frame, layer, (sub or 0) + 1, radius or 5, "line") }
  function box:Set(border, fill)
    self.fill:SetColor(fill)
    self.line:SetShown(border ~= nil)
    if border then self.line:SetColor(border) end
  end
  return box
end

---The colour at the top of a rounded panel, fading out downwards (1.31): the accent wash of a window or a card.
---:SetColor(c, alpha). radius is the panel's, so the wash keeps to its round corners.
function UI.Wash(frame, layer, sub, radius, height)
  local r = radius
  local function corner(left, right)
    local t = smooth(frame:CreateTexture(nil, layer, nil, sub))
    t:SetTexture(TEX.round)
    t:SetTexCoord(left, right, 0, CORNER)
    t:SetSize(r, r)
    return t
  end
  local tl, tr = corner(0, CORNER), corner(1 - CORNER, 1)
  tl:SetPoint("TOPLEFT")
  tr:SetPoint("TOPRIGHT")
  local strip, fade = tex(frame, layer, sub), tex(frame, layer, sub)
  strip:SetPoint("TOPLEFT", tl, "TOPRIGHT")
  strip:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  fade:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
  fade:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
  fade:SetHeight(height)
  local wash = {}
  function wash:SetColor(c, alpha)
    tl:SetVertexColor(c[1], c[2], c[3], alpha)
    tr:SetVertexColor(c[1], c[2], c[3], alpha)
    strip:SetColorTexture(c[1], c[2], c[3], alpha)
    gradient(fade, c, c, alpha, 0)
  end
  return wash
end

---A soft shadow around a rounded panel (1.31), on the frame itself, falling a little downwards.
function UI.Shadow(frame, sub)
  return UI.Slice(frame, "BACKGROUND", sub, TEX.shadow, .4375, 56, 28)
end

---The light on a panel (radius 10): its top edge catches it, and it darkens towards the foot (1.32).
function UI.Sheen(frame, layer, sub)
  return UI.Slice(frame, layer, sub, TEX.sheen, .375, 12)
end

local function art(frame, layer, sub, name)   -- a control's nine-slice: 4 to spare outside, radius 6
  return UI.Slice(frame, layer, sub, TEX[name], .375, 12, 4)
end

---A recessed field, for text boxes and dropdowns (1.32). :Set(line colour, lit): lit adds a halo in that colour.
function UI.Field(frame, layer, sub)
  local box = { halo = art(frame, layer, sub or 0, "halo"), well = art(frame, layer, (sub or 0) + 1, "field"),
    line = art(frame, layer, (sub or 0) + 2, "line") }
  function box:Set(border, lit)
    self.line:SetColor(border, 1)
    self.halo:SetColor(border, .45)
    self.halo:SetShown(lit and true or false)
  end
  return box
end

---A raised button face: a drop shadow, a colour and the light on it (1.32). :Set(fill), :Press(down).
function UI.Face(frame, layer, sub)
  local box = { drop = art(frame, layer, sub or 0, "drop"), fill = art(frame, layer, (sub or 0) + 1, "fill"),
    gloss = art(frame, layer, (sub or 0) + 2, "gloss") }
  function box:Set(fill) self.fill:SetColor(fill, 1) end
  function box:Press(down)
    self.drop:SetShown(not down)
    self.gloss:SetColor({ 1, 1, 1 }, down and .35 or 1)
  end
  return box
end

---A round knob, as on switches and sliders: 18 across in a 28 cell, shadow included (1.32).
function UI.Knob(parent, scale)
  local t = smooth(parent:CreateTexture(nil, "OVERLAY", nil, 2))
  t:SetTexture(TEX.knob)
  t:SetTexCoord(0, .875, 0, .875)
  t:SetSize(28 * (scale or 1), 28 * (scale or 1))
  return t
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
  local t = smooth(parent:CreateTexture(nil, layer or "ARTWORK"))
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
  local t = smooth(parent:CreateTexture(nil, layer or "ARTWORK"))
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
