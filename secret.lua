-- Core.Secret and UI.UnitBar (1.24): showing values the client keeps secret, the way Mercy and Bulwark do.
--
-- On WoW Forever health is always secret, and in combat so are about 90 other getters (cooldowns, charges, stats,
-- threat). Add-on code may not compare, add or format a secret value. It can hand one to a widget, but only to the
-- calls Blizzard marks "AllowedWhenTainted" (ForeverAPI docs/widgets): StatusBar SetValue / SetMinMaxValues /
-- SetStatusBarColor, FontString SetText / SetFormattedText / SetTextColor, Texture SetVertexColor / SetAlpha, and
-- SetAlphaFromBoolean on textures and frames. Not SetShown, and no Cooldown setter: those take secrets only from
-- Blizzard's own code, so a cooldown swipe fed by a secret duration can't be built by an add-on.
--
-- Maths on a secret goes through a curve: the client evaluates it and returns a (secret) result a widget can take.

local Core = NorgannonCore
local UI = Core.UI

local Secret = {}
Core.Secret = Secret

local function curveType(kind)
  local types = rawget(_G, "Enum") and Enum.LuaCurveType
  return types and types[kind or "Linear"] or nil
end

---A number curve: points { {x, y}, ... }, kind "Linear" (default) or "Step". nil where the client has no curves.
---UnitHealthPercent(unit, true, curve) evaluates it on the unit's health (0-1) without our reading it.
function Secret.Curve(points, kind)
  local create = Core.Fn("C_CurveUtil", "CreateCurve")
  if not create then return nil end
  local ok, curve = pcall(function()
    local c = create()
    local t = curveType(kind)
    if t ~= nil and c.SetType then c:SetType(t) end
    for _, p in ipairs(points) do c:AddPoint(p[1], p[2]) end
    return c
  end)
  return ok and curve or nil
end

---A colour curve: points { {x, r, g, b[, a]}, ... }. Evaluated on a secret it gives a (secret) ColorMixin.
function Secret.ColorCurve(points, kind)
  local create = Core.Fn("C_CurveUtil", "CreateColorCurve")
  if not (create and CreateColor) then return nil end
  local ok, curve = pcall(function()
    local c = create()
    local t = curveType(kind)
    if t ~= nil and c.SetType then c:SetType(t) end
    for _, p in ipairs(points) do c:AddPoint(p[1], CreateColor(p[2], p[3], p[4], p[5] or 1)) end
    return c
  end)
  return ok and curve or nil
end

---Text from values that may be secret: fs:SetFormattedText(fmt, ...). false (and the text cleared) if refused.
function Secret.Text(fs, fmt, ...)
  if Core.SetSecret(fs, "SetFormattedText", fmt, ...) then return true end
  fs:SetText("")
  return false
end

---A number that may be secret, in full ("1339") or short ("1.3K", the client's AbbreviateNumbers). prefix is plain text.
function Secret.Number(fs, value, short, prefix)
  prefix = prefix or ""
  if not short and Core.SetSecret(fs, "SetFormattedText", prefix .. "%d", value) then return true end
  local ok, text = pcall(AbbreviateNumbers, value)
  return Secret.Text(fs, prefix .. "%s", ok and text or value)
end

---Shows or fades a texture or frame by a boolean that may be secret: alpha `on` (default 1) when true, `off`
---(default 0) when false. This is the way to "show if" with a secret, since SetShown won't take one.
function Secret.Alpha(region, bool, on, off)
  on, off = on or 1, off or 0
  if Core.SetSecret(region, "SetAlphaFromBoolean", bool, on, off) then return true end
  if Core.IsSecret(bool) then return false end
  region:SetAlpha(bool and on or off)
  return true
end

---A colour that may be secret (a ColorMixin from a curve, or plain {r, g, b}) onto a texture, status bar or font
---string. false if the client refused, and nothing changes.
function Secret.Color(region, color)
  local kind = region.GetObjectType and region:GetObjectType()
  local method = (kind == "StatusBar" and "SetStatusBarColor") or (kind == "FontString" and "SetTextColor") or "SetVertexColor"
  if type(color) == "table" and not Core.IsSecret(color) and color[1] then
    return Core.SetSecret(region, method, color[1], color[2], color[3], color[4] or 1)
  end
  return (pcall(function() region[method](region, color:GetRGBA()) end))
end

---One of two colours by a boolean that may be secret (C_CurveUtil.EvaluateColorFromBoolean): a ColorMixin for
---Secret.Color. Bulwark colours a plate by "is it targeting me" this way. Plain booleans work too.
function Secret.ColorFromBoolean(bool, whenTrue, whenFalse)
  if not CreateColor then return nil end
  local a = CreateColor(whenTrue[1], whenTrue[2], whenTrue[3], whenTrue[4] or 1)
  local b = CreateColor(whenFalse[1], whenFalse[2], whenFalse[3], whenFalse[4] or 1)
  if not Core.IsSecret(bool) then return bool and a or b end
  local ok, color = Core.Call(Core.Fn("C_CurveUtil", "EvaluateColorFromBoolean"), bool, a, b)
  return ok and color or nil
end

-------------------------------------------------------------------------------------------
-- UI.UnitBar: a health or power bar that works in and out of combat
-------------------------------------------------------------------------------------------

local HEALTH_COLORS = { { 0, .85, .15, .1 }, { .35, .9, .35, .1 }, { .6, .85, .75, .15 }, { 1, .15, .85, .1 } }

---A StatusBar for a unit's health (or power) that never reads the secret numbers. opts: kind "health" (default) or
---"power"; color = {r, g, b} or "gradient" (red to green by health); text = "current" | "percent" | "missing" |
---"none" (default); short = true for 1.3K; height. Call :SetUnit(unit), then :Update() on UNIT_HEALTH and the like.
function UI.UnitBar(parent, opts)
  opts = opts or {}
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetStatusBarTexture(UI.TEX.white)
  bar:SetHeight(opts.height or 14)
  bar:SetMinMaxValues(0, 1)
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints()
  bar.bg:SetColorTexture(UI.C.track[1], UI.C.track[2], UI.C.track[3], 1)
  bar.text = UI.Text(bar, "bold", opts.textSize or 11)
  bar.text:SetPoint("CENTER")
  bar.opts = opts
  local color = opts.color
  if type(color) == "table" then bar:SetStatusBarColor(color[1], color[2], color[3]) end
  if color == "gradient" then bar.gradient = Secret.ColorCurve(opts.points or HEALTH_COLORS) end
  bar.percent = Secret.Curve({ { 0, 0 }, { 1, 100 } })

  function bar:SetUnit(unit)
    self.unit = unit
    self:Update()
  end

  function bar:Update()
    local unit = self.unit
    if not unit then return end
    local power = self.opts.kind == "power"
    local okV, value = Core.Call(power and UnitPower or UnitHealth, unit)
    local okM, max = Core.Call(power and UnitPowerMax or UnitHealthMax, unit)
    if okV and okM then
      Core.SetSecret(self, "SetMinMaxValues", 0, max)
      Core.SetSecret(self, "SetValue", value)
    end
    if not power and self.gradient then
      local ok, c = Core.Call(UnitHealthPercent, unit, true, self.gradient)
      if ok and c then Secret.Color(self, c) end
    end
    local mode = self.opts.text or "none"
    if mode == "none" then
      self.text:SetText("")
    elseif mode == "current" and okV then
      Secret.Number(self.text, value, self.opts.short)
    elseif mode == "percent" and not power and self.percent then
      local ok, p = Core.Call(UnitHealthPercent, unit, true, self.percent)
      if ok then Secret.Text(self.text, "%.0f%%", p) end
    elseif mode == "missing" and not power then
      local ok, missing = Core.Call(UnitHealthMissing, unit, true)
      if ok then Secret.Number(self.text, missing, self.opts.short, "-") end
    end
  end
  return bar
end
