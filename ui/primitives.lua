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

-- A disc drawn for about this size: the client has no smaller copies of a texture, so a big one shrunk a lot turns jagged.
local function discFor(size)
  return size <= 5 and TEX.disc8 or size <= 10 and TEX.disc16 or size <= 24 and TEX.dot or TEX.circle
end

---A pill (rounded ends) of a fixed height, optionally inset (for a fill inside a border pill).
local function pill(frame, height, layer, sub, inset)
  inset = inset or 0
  local h = height - inset * 2
  local file = discFor(h)
  -- all three are the same disc, its middle column stretched: a plain colour between smooth ends would be snapped to
  -- whole pixels when they aren't, and overlap or miss them by one
  local function part(left, right)
    local t = smooth(frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0))
    t:SetTexture(file)
    t:SetTexCoord(left, right, 0, 1)
    return t
  end
  local p = { left = part(0, .5), right = part(.5, 1), mid = part(.49, .51) }
  p.left:SetSize(h / 2, h)
  p.left:SetPoint("LEFT", inset, 0)
  p.right:SetSize(h / 2, h)
  p.right:SetPoint("RIGHT", -inset, 0)
  p.mid:SetPoint("TOPLEFT", p.left, "TOPRIGHT")
  p.mid:SetPoint("BOTTOMRIGHT", p.right, "BOTTOMLEFT")
  function p:SetColor(c, alpha)
    local a = alpha or c[4] or 1
    self.left:SetVertexColor(c[1], c[2], c[3], a)
    self.right:SetVertexColor(c[1], c[2], c[3], a)
    self.mid:SetVertexColor(c[1], c[2], c[3], a)
  end
  return p
end

---A pill standing up, filling its frame, w wide: a scrollbar's thumb (1.33). :SetColor(c, alpha).
function UI.VPill(frame, w, layer, sub)
  local file = discFor(w)
  local function part(top, bottom)
    local t = smooth(frame:CreateTexture(nil, layer or "ARTWORK", nil, sub or 0))
    t:SetTexture(file)
    t:SetTexCoord(0, 1, top, bottom)
    return t
  end
  local a, b, mid = part(0, .5), part(.5, 1), part(.49, .51)
  a:SetSize(w, w / 2)
  a:SetPoint("TOP")
  b:SetSize(w, w / 2)
  b:SetPoint("BOTTOM")
  mid:SetPoint("TOPLEFT", a, "BOTTOMLEFT")
  mid:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT")
  local p = { pieces = { a, b, mid } }
  function p:SetColor(c, alpha)
    for _, t in ipairs(self.pieces) do t:SetVertexColor(c[1], c[2], c[3], alpha or c[4] or 1) end
  end
  function p:SetShown(on) for _, t in ipairs(self.pieces) do t:SetShown(on) end end
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
  local strip, fade = smooth(tex(frame, layer, sub)), smooth(tex(frame, layer, sub))
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

---The same shadow, only where it falls outside a panel with round corners of 10 (1.35): for a panel you can see through,
---since UI.Shadow's art is filled inside and would darken what's behind. Any size from 20 units. Fade it with
---:SetColor({ 1, 1, 1 }, alpha).
function UI.ShadowRing(frame, sub)
  -- a corner slice holds the whole of the cut-out's curve, so nothing but the straight edge stretches
  local ring = UI.Slice(frame, "BACKGROUND", sub, TEX.shadowRing, 38 / 128, 38, 28)
  table.remove(ring.pieces):Hide()   -- the middle is empty
  return ring
end

---The light on a panel (radius 10): its top edge catches it, and it darkens towards the foot (1.32).
function UI.Sheen(frame, layer, sub)
  return UI.Slice(frame, layer, sub, TEX.sheen, .375, 12)
end

-- Bands: a control's art as three pieces, its ends and a stretched middle, the height of the control. A nine-slice would
-- be three times the textures for the same picture. The art's shape is 48 of its 64 texels high, 8 to spare all round.
local bandsOf = setmetatable({}, { __mode = "k" })

local function fitBands(frame, _, h)
  h = h or frame:GetHeight() or 0
  local bands = bandsOf[frame]
  if not bands or h <= 0 or bands.height == h then return end
  bands.height = h
  for _, b in ipairs(bands) do b:Fit(h) end
end

---A band over frame from a control's art (a key of UI.TEX, or a file), round-ended when pill is true (1.33). It follows
---the frame's height. inset shrinks it. :SetColor(c, alpha), :SetShown(on).
function UI.Band(frame, layer, sub, name, isPill, inset)
  inset = inset or 0
  local cut = isPill and .5 or .375
  local function part(left, right)
    local t = smooth(frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0))
    t:SetTexture(TEX[name] or name)
    t:SetTexCoord(left, right, 0, 1)
    return t
  end
  local b = { pieces = { part(0, cut), part(1 - cut, 1), part(isPill and .49 or cut, isPill and .51 or 1 - cut) },
    SetColor = setPiecesColor }
  local left, right, mid = b.pieces[1], b.pieces[2], b.pieces[3]
  mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
  mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
  function b:Fit(height)
    local h = height - inset * 2
    local s = h / 48
    local o = (isPill and 8 * s or 4) - inset
    local w = isPill and 32 * s or 12
    left:SetSize(w, 64 * s)
    right:SetSize(w, 64 * s)
    left:SetPoint("LEFT", -o, 0)
    right:SetPoint("RIGHT", o, 0)
  end
  function b:SetShown(on) for _, t in ipairs(self.pieces) do t:SetShown(on) end end
  local bands = bandsOf[frame]
  if not bands then
    bands = {}
    bandsOf[frame] = bands
    frame:HookScript("OnSizeChanged", fitBands)
  end
  bands[#bands + 1] = b
  local h = frame:GetHeight() or 0
  b:Fit(h > 0 and h or 24)
  return b
end

local function art(frame, layer, sub, name)   -- a control's nine-slice: 4 to spare outside, radius 6
  return UI.Slice(frame, layer, sub, TEX[name], .375, 12, 4)
end

---A recessed field, for text boxes and dropdowns (1.32). :Set(line colour, lit): lit adds a halo in that colour.
---tall (1.33): for one of several lines; it keeps its round corners at any height.
function UI.Field(frame, layer, sub, tall)
  local part = tall and art or UI.Band
  sub = sub or 0
  local box = { well = part(frame, layer, sub + 1, "field"), line = part(frame, layer, sub + 2, "line") }
  function box:Set(border, lit)
    self.line:SetColor(border, 1)
    if lit and not self.halo then self.halo = part(frame, layer, sub, "halo") end   -- made when it first lights
    if self.halo then
      self.halo:SetColor(border, .45)
      self.halo:SetShown(lit and true or false)
    end
  end
  return box
end

local FACE, FACE_DOWN = { 1, 1, 1 }, { .55, .55, .55 }

---A raised button face: its colour, with the light on it and its shadow (1.32). :Set(fill), :Press(down). pill (1.33)
---gives it round ends.
function UI.Face(frame, layer, sub, isPill, inset)
  local box = { fill = UI.Band(frame, layer, sub or 0, isPill and "pillFill" or "fill", isPill, inset),
    face = UI.Band(frame, layer, (sub or 0) + 1, isPill and "pillFace" or "face", isPill, inset) }
  function box:Set(fill, alpha) self.fill:SetColor(fill, alpha or 1) end
  function box:Press(down) self.face:SetColor(down and FACE_DOWN or FACE, down and .5 or 1) end
  function box:SetShown(on)
    self.fill:SetShown(on)
    self.face:SetShown(on)
  end
  return box
end

---A recessed panel (1.33), :Set(border, fill) as UI.Box: what lists and text sit in.
function UI.Well(frame, layer, sub)
  local box = { fill = art(frame, layer, sub or 0, "well"), line = art(frame, layer, (sub or 0) + 1, "line") }
  function box:Set(border, fill)
    self.fill:SetColor(fill)
    self.line:SetShown(border ~= nil)
    if border then self.line:SetColor(border) end
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
    local tx = smooth(frame:CreateTexture(nil, layer or "BORDER", nil, sub or 0))
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
  t:SetTexture(name == "circle" and discFor(size) or TEX[name] or name)
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

---An inset pane (lists sit in these): a recess with round corners, its outline tinted with the window's accent.
function UI.Pane(parent)
  local f = CreateFrame("Frame", nil, parent)
  f.box = UI.Well(f, "BACKGROUND", 0)
  local set = f.box.Set
  function f:ApplyAccent(c)
    if not self.ownLook then set(self.box, UI.Mix(C.line, c, .16), C.inset) end
  end
  UI.AttachAccent(f)
  -- a caller that colours it itself keeps its own colours
  function f.box:Set(border, fill)
    f.ownLook = true
    set(self, border, fill)
  end
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
