-- LibForever.Secret: showing values the client keeps secret.
--
-- On WoW Forever health is always secret, and in combat so are about 90 other getters (cooldowns, charges, stats,
-- threat). Add-on code may not compare, add or format a secret value. It can hand one to a widget, but only to the
-- calls Blizzard marks "AllowedWhenTainted" (ForeverAPI's widgets page): StatusBar SetValue / SetMinMaxValues /
-- SetStatusBarColor, FontString SetText / SetFormattedText / SetTextColor, Texture SetVertexColor / SetAlpha, and
-- SetAlphaFromBoolean on textures and frames. Not SetShown, and no Cooldown setter: those take secrets only from
-- Blizzard's own code, so a cooldown swipe fed by a secret duration can't be built by an add-on.
--
-- Maths on a secret goes through a curve: the client evaluates it and returns a (secret) result a widget can take.
-- LF.IsSecret, LF.Call and LF.SetSecret (Base.lua) are the primitives under these.

local LF = LibStub("LibForever-1.0", true)
if not (LF and LF._loading) then return end

---@class LibForever.Secret
local Secret = LF.Secret or {}
LF.Secret = Secret

local function curveType(kind)
  local types = rawget(_G, "Enum") and Enum.LuaCurveType
  return types and types[kind or "Linear"] or nil
end

---A number curve: points { {x, y}, ... }, kind "Linear" (default) or "Step". nil where the client has no curves.
---UnitHealthPercent(unit, true, curve) evaluates it on the unit's health (0-1) without our reading it.
---@param points number[][] { {x, y}, ... }
---@param kind "Linear"|"Step"|nil
---@return table|nil curve
function Secret.Curve(points, kind)
  local create = LF.Fn("C_CurveUtil", "CreateCurve")
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
---@param points number[][] { {x, r, g, b[, a]}, ... }
---@param kind "Linear"|"Step"|nil
---@return table|nil curve
function Secret.ColorCurve(points, kind)
  local create = LF.Fn("C_CurveUtil", "CreateColorCurve")
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
---@param fs table a FontString
---@param fmt string
---@param ... any values that may be secret
---@return boolean shown
function Secret.Text(fs, fmt, ...)
  if LF.SetSecret(fs, "SetFormattedText", fmt, ...) then return true end
  fs:SetText("")
  return false
end

---A number that may be secret, in full ("1339") or short ("1.3K", the client's AbbreviateNumbers). prefix is plain text.
---@param fs table a FontString
---@param value any a number that may be secret
---@param short boolean|nil
---@param prefix string|nil
---@return boolean shown
function Secret.Number(fs, value, short, prefix)
  prefix = prefix or ""
  if not short and LF.SetSecret(fs, "SetFormattedText", prefix .. "%d", value) then return true end
  local ok, text = pcall(AbbreviateNumbers, value)
  return Secret.Text(fs, prefix .. "%s", ok and text or value)
end

---Shows or fades a texture or frame by a boolean that may be secret: alpha `on` (default 1) when true, `off`
---(default 0) when false. This is the way to "show if" with a secret, since SetShown won't take one.
---@param region table a texture or frame
---@param bool any a boolean that may be secret
---@param on number|nil
---@param off number|nil
---@return boolean done
function Secret.Alpha(region, bool, on, off)
  on, off = on or 1, off or 0
  if LF.SetSecret(region, "SetAlphaFromBoolean", bool, on, off) then return true end
  if LF.IsSecret(bool) then return false end
  region:SetAlpha(bool and on or off)
  return true
end

---A colour that may be secret (a ColorMixin from a curve, or plain {r, g, b}) onto a texture, status bar or font
---string. false if the client refused, and nothing changes.
---@param region table a Texture, StatusBar or FontString
---@param color table a ColorMixin (secret or not) or {r, g, b[, a]}
---@return boolean done
function Secret.Color(region, color)
  local kind = region.GetObjectType and region:GetObjectType()
  local method = (kind == "StatusBar" and "SetStatusBarColor") or (kind == "FontString" and "SetTextColor") or "SetVertexColor"
  if type(color) == "table" and not LF.IsSecret(color) and color[1] then
    return LF.SetSecret(region, method, color[1], color[2], color[3], color[4] or 1)
  end
  return (pcall(function() region[method](region, color:GetRGBA()) end))
end

---One of two colours by a boolean that may be secret (C_CurveUtil.EvaluateColorFromBoolean): a ColorMixin for
---Secret.Color. NorgannonDB's Bulwark colours a plate by "is it targeting me" this way. Plain booleans work too.
---@param bool any a boolean that may be secret
---@param whenTrue number[] {r, g, b[, a]}
---@param whenFalse number[] {r, g, b[, a]}
---@return table|nil color a ColorMixin
function Secret.ColorFromBoolean(bool, whenTrue, whenFalse)
  if not CreateColor then return nil end
  local a = CreateColor(whenTrue[1], whenTrue[2], whenTrue[3], whenTrue[4] or 1)
  local b = CreateColor(whenFalse[1], whenFalse[2], whenFalse[3], whenFalse[4] or 1)
  if not LF.IsSecret(bool) then return bool and a or b end
  local ok, color = LF.Call(LF.Fn("C_CurveUtil", "EvaluateColorFromBoolean"), bool, a, b)
  return ok and color or nil
end
