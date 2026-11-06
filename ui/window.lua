-- The UI kit's containers: the window every suite addon uses, the card, the "Powered by
-- NorgannonDB" line in a window's header, and saving where a frame was left.

local Core = NorgannonCore
local UI = Core.UI
local C, TEX = UI.C, UI.TEX
local tex, gradient = UI.Tex, UI.Gradient

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

---Remembers where a frame is, under key (NorgannonCoreDB.windows[key]).
function UI.SavePosition(f, key)
  local db = Core.db
  if not (db and key) then return end
  local point, _, relativePoint, x, y = f:GetPoint()
  db.windows[key] = { point = point, relativePoint = relativePoint, x = x, y = y }
end

---Puts a frame back where UI.SavePosition left it; a frame never saved stays where it is.
function UI.RestorePosition(f, key)
  local db = Core.db
  local saved = db and key and db.windows[key]
  if saved and saved.point then
    f:ClearAllPoints()
    f:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
  end
end

---A suite window. opts = { name = "GlobalName", addon = "clairvoyance", title = "Clairvoyance",
---sub = "Durotar", width, height, footer = true }. Fields: .header .body .footer .footerText.
---Methods: :SetAccent(addonKey), :SetTitle(text), :SetSub(text). Esc closes it; its position is
---remembered. An addon can set .locked to stop the header dragging it.
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
  header:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    UI.SavePosition(f, f.saveKey)
  end)

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
    Core:OnReady(function() UI.RestorePosition(f, f.saveKey) end)
  end
  f:SetAccent(opts.addon or "norgannondb")
  f:Hide()
  return f
end
