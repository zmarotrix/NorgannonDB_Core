-- The UI kit's progress bar.

local Core = NorgannonCore
local UI = Core.UI
local C, TEX = UI.C, UI.TEX
local pill = UI.Pill
local attachAccent, applyAccent = UI.AttachAccent, UI.ApplyAccent

local MAX_TICKS = 20
local PARTY_GREY, PARTY_GREY_SHARE = { .53, .53, .53 }, .55   -- the party variant: the accent, greyed
local MARKER_GREY = { .78, .78, .78 }

-- a dividing line between every two steps, in the frame above the fill
local function paintTicks(bar, width, height)
  local steps = (bar.steps >= 2 and bar.steps <= MAX_TICKS) and bar.steps or 0
  for i = 1, math.max(steps - 1, #bar.ticks) do
    local tick = bar.ticks[i]
    if i < steps then
      if not tick then
        tick = bar.over:CreateTexture(nil, "OVERLAY", nil, 1)
        tick:SetColorTexture(0, 0, 0, .55)
        tick:SetSize(1, height)
        bar.ticks[i] = tick
      end
      tick:ClearAllPoints()
      tick:SetPoint("CENTER", bar, "LEFT", width * i / steps, 0)
      tick:Show()
    elseif tick then
      tick:Hide()
    end
  end
end

local function paintMarker(bar, width)
  if not bar.markerRatio then
    bar.marker:Hide()
    return
  end
  bar.marker:ClearAllPoints()
  bar.marker:SetPoint("CENTER", bar, "LEFT", width * bar.markerRatio, 0)
  local c = bar.markerColor or MARKER_GREY
  bar.marker:SetVertexColor(c[1], c[2], c[3], 1)
  bar.marker:Show()
end

---A rounded progress bar: UI.Bar(parent[, "party"][, height]). :SetProgress(current, total).
---Track and fill have rounded ends. Steps show as ticks (2 to 20 steps; more would be noise).
---:SetMarker(ratio or nil[, colour]) adds a round dot, e.g. a party member's progress.
---The party variant is a dimmer accent, for other players' progress next to yours.
function UI.Bar(parent, kind, height)
  local h = height or 5
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(h)
  -- a dark outline, a pixel beyond the track all round, so the bar reads on any background
  f.outline = pill(f, h, "BACKGROUND", -1, -1)
  f.outline:SetColor({ 0, 0, 0 }, .9)
  f.track = pill(f, h, "BACKGROUND", 0)
  f.track:SetColor(C.track)
  -- the fill: its own frame with a pill, so both ends are round at any width
  f.fillFrame = CreateFrame("Frame", nil, f)
  f.fillFrame:SetPoint("TOPLEFT")
  f.fillFrame:SetHeight(h)
  f.fill = pill(f.fillFrame, h, "ARTWORK", 0)
  -- the dividing lines and the party marker: on a frame above the fill (a child frame draws over
  -- its parent's textures whatever their layer)
  f.over = CreateFrame("Frame", nil, f)
  f.over:SetAllPoints()
  f.over:SetFrameLevel(f.fillFrame:GetFrameLevel() + 1)
  f.ticks = {}
  f.marker = f.over:CreateTexture(nil, "OVERLAY", nil, 2)
  f.marker:SetTexture(TEX.circle)
  f.marker:SetSize(h + 3, h + 3)
  f.marker:Hide()
  f.kind = kind
  f.ratio, f.steps = 0, 0
  function f:Paint()
    local c = self.kind == "party" and UI.Mix(self.accent, PARTY_GREY, PARTY_GREY_SHARE) or self.accent
    self.fill:SetColor(c)
    self.over:SetFrameLevel(self.fillFrame:GetFrameLevel() + 1)   -- the lines stay over the fill
    local width = self:GetWidth() or 0
    -- never narrower than its round ends
    self.fillFrame:SetWidth(math.max(width * self.ratio, h))
    self.fillFrame:SetShown(self.ratio > 0)
    paintTicks(self, width, h)
    paintMarker(self, width)
  end
  f.ApplyAccent = applyAccent
  function f:SetProgress(current, total)
    self.ratio = (total and total > 0) and math.max(0, math.min(1, (current or 0) / total)) or 0
    self.steps = total or 0
    self:Paint()
  end
  function f:SetMarker(ratio, markerColor)
    self.markerRatio = ratio and math.max(0, math.min(1, ratio)) or nil
    self.markerColor = markerColor
    self:Paint()
  end
  f:SetScript("OnSizeChanged", f.Paint)
  attachAccent(f)
  return f
end
