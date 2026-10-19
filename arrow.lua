-- The waypoint arrow: one for the whole suite, shown only when something asks for it (the
-- suite never routes you to "the next quest"; decision 9 in docs/suite-plan.md).
--
--   Core.Arrow:SetTarget({ area = 14, x = 52.1, y = 43.0, title = "Mottled Boar", owner = "clairvoyance" })
--   Core.Arrow:Clear()
--
-- It points with HereBeDragons' world vector minus the player's facing, turns from red (behind
-- you) through gold to green (ahead), shows the distance, and clears itself on arrival.
-- Drag to move, right-click to dismiss. The target survives /reload.
-- Messages: NORGANNON_ARROW_SET (target), NORGANNON_ARROW_ARRIVED (target), NORGANNON_ARROW_CLEARED (reason).

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C
local HBD = LibStub("HereBeDragons-NorgannonCore-2.0")

local Arrow = {}
Core.Arrow = Arrow

local ARRIVE_YARDS = 6
local THROTTLE = 0.03
local GREEN, GOLD, RED = { .35, 1, .45 }, { 1, .82, .2 }, { 1, .3, .25 }

local f = CreateFrame("Button", "NorgannonCoreArrow", UIParent)
f:SetSize(80, 92)
f:SetPoint("TOP", UIParent, "TOP", 0, -160)
f:SetFrameStrata("MEDIUM")
f:SetMovable(true)
f:SetClampedToScreen(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:RegisterForClicks("RightButtonUp")
f:Hide()
Arrow.frame = f

f.shadow = f:CreateTexture(nil, "BACKGROUND")
f.shadow:SetTexture(UI.TEX.glow)
f.shadow:SetVertexColor(0, 0, 0, .55)
f.shadow:SetSize(76, 76)
f.shadow:SetPoint("TOP", 0, 6)
f.arrow = f:CreateTexture(nil, "ARTWORK")
f.arrow:SetTexture(UI.TEX.arrow)
f.arrow:SetSize(56, 56)
f.arrow:SetPoint("TOP", 0, -4)
f.distance = UI.Text(f, "bold", 14, C.text)
f.distance:SetPoint("TOP", f.arrow, "BOTTOM", 0, -2)
f.distance:SetJustifyH("CENTER")
f.title = UI.Text(f, "body", 12, C.muted)
f.title:SetPoint("TOP", f.distance, "BOTTOM", 0, -1)
f.title:SetJustifyH("CENTER")

local function db() return Core.db end

local function savePosition()
  local point, _, relativePoint, x, y = f:GetPoint()
  if db() then db().windows.NorgannonCoreArrow = { point = point, relativePoint = relativePoint, x = x, y = y } end
end

f:SetScript("OnDragStart", function(self) if not (db() and db().arrowLocked) then self:StartMoving() end end)
f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePosition() end)
f:SetScript("OnClick", function(_, button) if button == "RightButton" then Arrow:Clear("dismissed") end end)
f:SetScript("OnEnter", function(self)
  local t = Arrow.target
  if not t then return end
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
  GameTooltip:AddLine(t.title or "Waypoint", 1, 1, 1)
  local info = t.owner and Core:GetAddonInfo(t.owner)
  if info then
    local c = UI.Accent(t.owner)
    GameTooltip:AddLine("Set by " .. info.name, c[1], c[2], c[3])
  end
  GameTooltip:AddLine("Drag to move, right-click to dismiss", C.muted[1], C.muted[2], C.muted[3])
  GameTooltip:Show()
end)
f:SetScript("OnLeave", function() GameTooltip:Hide() end)

-------------------------------------------------------------------------------------------
-- Target
-------------------------------------------------------------------------------------------

local function resolve(target)
  local uiMap = target.uiMap or Core.Map.AreaToUiMap(target.area)
  if not uiMap then return nil end
  local x, y, instance = HBD:GetWorldCoordinatesFromZone(target.x / 100, target.y / 100, uiMap)
  if not x then return nil end
  return { x = x, y = y, instance = instance }
end

---Points the arrow at a spot. target = { area | uiMap, x, y (percent), title, owner, arrive (yards) }.
---Returns false if the spot can't be placed on the world.
function Arrow:SetTarget(target)
  local world = target and resolve(target)
  if not world then return false end
  self.target, self.world, self.arrived = target, world, nil
  if db() then
    db().arrowTarget = { area = target.area, uiMap = target.uiMap, x = target.x, y = target.y,
      title = target.title, owner = target.owner, arrive = target.arrive }
  end
  f.title:SetText(target.title or "")
  f:Show()
  Core:Send("NORGANNON_ARROW_SET", target)
  Arrow:Update()
  return true
end

function Arrow:GetTarget() return self.target end

function Arrow:Clear(reason)
  if not self.target then return end
  self.target, self.world = nil, nil
  if db() then db().arrowTarget = nil end
  f:Hide()
  Core:Send("NORGANNON_ARROW_CLEARED", reason or "cleared")
end

-------------------------------------------------------------------------------------------
-- Update
-------------------------------------------------------------------------------------------

local function headingColor(rotation)
  -- 0 = straight ahead, 1 = directly behind
  local turn = math.abs(((rotation + math.pi) % (2 * math.pi)) - math.pi) / math.pi
  if turn < .5 then return UI.Mix(GREEN, GOLD, turn * 2) end
  return UI.Mix(GOLD, RED, (turn - .5) * 2)
end

local function yards(d)
  if d >= 1000 then return string.format("%.1fk yd", d / 1000) end
  return string.format("%d yd", d)
end

function Arrow:Update()
  local target, world = self.target, self.world
  if not target then return end
  local px, py, instance = HBD:GetPlayerWorldPosition()
  if not px or Core.IsSecret(px) or Core.IsSecret(py) then
    -- instances and other places without a position: say so instead of guessing
    f.arrow:SetVertexColor(.5, .5, .5)
    f.arrow:SetRotation(0)
    f.distance:SetText("?")
    return
  end
  if instance ~= world.instance then
    f.arrow:SetVertexColor(.5, .5, .5)
    f.arrow:SetRotation(0)
    f.distance:SetText("Another continent")
    return
  end
  local angle, distance = HBD:GetWorldVector(instance, px, py, world.x, world.y)
  if not angle then return end
  if distance <= (target.arrive or ARRIVE_YARDS) then
    if not self.arrived then
      self.arrived = true
      Core:Send("NORGANNON_ARROW_ARRIVED", target)
      Arrow:Clear("arrived")
    end
    return
  end
  local facing = GetPlayerFacing()
  if facing and not Core.IsSecret(facing) then
    local rotation = angle - facing
    f.arrow:SetRotation(rotation)
    local c = headingColor(rotation)
    f.arrow:SetVertexColor(c[1], c[2], c[3])
    self.rotation = rotation
  else
    f.arrow:SetVertexColor(.75, .75, .75)
    f.arrow:SetRotation(0)
  end
  f.distance:SetText(yards(distance))
  self.distance = distance
end

local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + dt
  if elapsed < THROTTLE then return end
  elapsed = 0
  Arrow:Update()
end)

---Arrow size (scale), saved.
function Arrow:SetSize(scale)
  if db() then db().arrowScale = scale end
  f:SetScale(scale)
end
function Arrow:GetSize() return db() and db().arrowScale or 1 end

-- restore the position, size and target after /reload or login
Core:OnLogin(function()
  f:SetScale(Arrow:GetSize())
  local saved = db() and db().windows.NorgannonCoreArrow
  if saved and saved.point then
    f:ClearAllPoints()
    f:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
  end
  local target = db() and db().arrowTarget
  if target then Arrow:SetTarget(target) end
end)
