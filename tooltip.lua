-- Item tooltips across the suite: each add-on says one line by default and the rest while Shift is held,
-- so a tooltip hovered with four Norgannon add-ons on doesn't fill the screen.
--
--   if Core.Tooltip.Detail() then ...the extra lines... end
--   Core.Tooltip.Head(tt, "Fortune: 90c each", colour, hasMore)   -- adds a faint "Shift: more" on the right
--
-- The hint goes on the first line that has more behind Shift, once per tooltip. Pressing or letting go of
-- Shift redraws the tooltip under the mouse.

local Core = NorgannonCore
local Tip = {}
Core.Tooltip = Tip

Tip.HINT = "Shift: more"
local FAINT = { 0.5, 0.5, 0.5 }

---true while Shift is held: show the detail.
function Tip.Detail()
  return IsShiftKeyDown and IsShiftKeyDown() and true or false
end

local hooked = setmetatable({}, { __mode = "k" })
local hinted = setmetatable({}, { __mode = "k" })

local function watch(tt)
  if hooked[tt] or not tt.HookScript then return end
  hooked[tt] = true
  pcall(tt.HookScript, tt, "OnTooltipCleared", function(self) hinted[self] = nil end)
end

---An add-on's heading line, in colour c. more: there are lines behind Shift, so say so (once per tooltip).
function Tip.Head(tt, text, c, more)
  watch(tt)
  if more and not Tip.Detail() and not hinted[tt] and tt.AddDoubleLine then
    hinted[tt] = true
    tt:AddDoubleLine(text, Tip.HINT, c[1], c[2], c[3], FAINT[1], FAINT[2], FAINT[3])
  else
    tt:AddLine(text, c[1], c[2], c[3])
  end
end

-- Shift pressed or let go: draw the tooltip under the mouse again, so the detail appears or goes.
-- Only item tooltips: others (Mercy's frames, units) draw themselves and handle Shift on their own.
local function redraw(tt)
  if not (tt and tt.IsShown and tt:IsShown()) then return end
  local get = tt.GetPrimaryTooltipData or tt.GetTooltipData
  local items = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item
  if get and items then
    local ok, data = pcall(get, tt)
    if not (ok and type(data) == "table" and not Core.IsSecret(data) and data.type == items) then return end
    if tt.RefreshData and pcall(tt.RefreshData, tt) then return end
  end
  local owner = tt.GetOwner and tt:GetOwner()
  local enter = owner and owner.GetScript and owner:GetScript("OnEnter")
  if enter then pcall(enter, owner) end
end

Core:On("MODIFIER_STATE_CHANGED", Tip, function(_, key)
  if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
  redraw(rawget(_G, "GameTooltip"))
end)
