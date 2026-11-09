-- Client layer: which client this is, secret-value safety, the combat lockdown queue and next-frame scheduling.
-- WoW Forever runs Classic content on the modern client (interface 16000-16999). Some values are "secret" in combat
-- and instances: they may be passed along but never compared or used in a branch, so everything that reads unit or
-- quest data goes through these helpers.
--
-- Since 1.27 they are LibForever-1.0's (Base.lua in ForeverAPI's lib/), under the names they always had here.

local Core = NorgannonCore
local LF = Core.LibForever

local Client = LF.Client
Core.Client = Client
Core.client = {
  interface = Client.Interface(),
  isForever = Client.IsForever(),
  locale = GetLocale(),
}

-- secret values and calling the client (1.19)
Core.IsSecret, Core.Safe = LF.IsSecret, LF.Safe
Core.Fn, Core.Has, Core.Call, Core.Plain = LF.Fn, LF.Has, LF.Call, LF.Plain
Core.Global, Core.In, Core.SetSecret, Core.Now = LF.Global, LF.In, LF.SetSecret, LF.Now

-- combat lockdown, the next frame, and "may we act now?" (1.20)
Core.AfterCombat, Core.NextFrame, Core.Restricted = LF.AfterCombat, LF.NextFrame, LF.Restricted

-- NORGANNON_RESTRICTIONS_CHANGED, the suite's name for LibForever's message: combat or a restriction started or ended
Core:Listen(LF.RESTRICTIONS_CHANGED, "core.restrictions", function() Core:Send("NORGANNON_RESTRICTIONS_CHANGED") end)

-------------------------------------------------------------------------------------------
-- Minimap shapes: which quadrants of the minimap are round, for the map layer and the buttons
-------------------------------------------------------------------------------------------

local MINIMAP_SHAPES = {
  -- { upper-left, lower-left, upper-right, lower-right }
  ["SQUARE"] = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { true, false, false, false }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { false, false, false, true },
  ["SIDE-LEFT"] = { true, true, false, false }, ["SIDE-RIGHT"] = { false, false, true, true },
  ["SIDE-TOP"] = { true, false, true, false }, ["SIDE-BOTTOM"] = { false, true, false, true },
  ["TRICORNER-TOPLEFT"] = { true, true, true, false }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { false, true, true, true },
}

---The minimap's shape for Core.IsMinimapRoundAt, or nil for a plain round minimap.
function Core.MinimapShape()
  return GetMinimapShape and MINIMAP_SHAPES[GetMinimapShape() or "ROUND"]
end

---Whether a shape is round at a point (x right, y up, from the minimap's centre).
function Core.IsMinimapRoundAt(shape, x, y)
  local column = x < 0 and 1 or 3
  if y > 0 then return shape[column] end
  return shape[column + 1]
end
