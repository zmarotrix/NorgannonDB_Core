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

-- Since 1.27 the helpers are LibForever-1.0's Secret (Secret.lua in ForeverAPI's lib/), the same table. UI.UnitBar,
-- which wears the suite's look, stays here.
local Secret = Core.LibForever.Secret
Core.Secret = Secret

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
