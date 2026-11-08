-- UI.UnitAuras (1.24): a unit's buffs and debuffs, drawn by the game itself, in and out of combat.
--
-- On WoW Forever an add-on can't read auras in combat: every C_UnitAuras reader errors with "Auras cannot be
-- accessed when secret while tainted" (ForeverAPI). What it can do is ask the game to draw them: the call Blizzard's
-- own raid frames make, C_UnitAuras.AddPrivateAuraAnchor with isContainer, puts a container on a frame of ours, and
-- Blizzard's secure Blizzard_PrivateAurasUI fills it with icons, cooldown swipes and the dispel display. Mercy's
-- frames have drawn debuffs this way since 0.2.14. Settings are attributes on the container frame.
--
--   local auras = UI.UnitAuras(myFrame, "party1", { debuffs = 3, buffs = 0, size = 16, dispel = "mine" })
--   auras:SetAllPoints(myFrame.healthBar)

local Core = NorgannonCore
local UI = Core.UI

local function enum(group, key, fallback)
  local e = rawget(_G, "Enum") and Enum[group]
  return e and e[key] ~= nil and e[key] or fallback
end

local function attributes(opts)
  local size = opts.size or 14
  local dispel = opts.dispel or "mine"
  local groups = rawget(_G, "CompactRaidGroupTypeEnum")
  return {
    ["max-buffs"] = opts.buffs or 0, ["max-debuffs"] = opts.debuffs or 3, ["max-dispel-debuffs"] = dispel ~= "off" and 3 or 0,
    ["aura-organization-type"] = enum("RaidAuraOrganizationType", "BuffsRightDebuffsLeft", 2),
    ["display-only-dispellable-debuffs"] = opts.onlyDispellable == true,
    ["ignore-buffs"] = (opts.buffs or 0) == 0, ["ignore-debuffs"] = (opts.debuffs or 3) == 0, ["ignore-dispel-debuffs"] = false,
    ["dispel-indicator-option"] = dispel == "any" and enum("RaidDispelDisplayType", "DisplayAll", 2)
      or dispel == "mine" and enum("RaidDispelDisplayType", "DispellableByMe", 1) or enum("RaidDispelDisplayType", "Disabled", 0),
    ["display-larger-role-specific-debuffs"] = true,
    ["dispel-indicator-overlay-type"] = enum("RaidDispelOverlayType", "UseDebuffColor", 1),
    ["dispel-indicator-overlay-animation"] = false, ["dispel-indicator-animated-border"] = false,
    ["show-big-defensive"] = false, ["big-defensive-size"] = size + 4,
    ["debuff-size"] = size, ["buff-size"] = size - 2, ["debuff-border-scale"] = 1, ["buff-border-scale"] = 1,
    ["always-hide-duration"] = true, ["set-aura-size-to-icon-size"] = true,
    ["power-bar-used-height"] = 0, ["group-type"] = groups and groups.Raid or nil,
  }
end

---A frame the game fills with a unit's auras. opts: debuffs (3), buffs (0; your own buffs that can go on others),
---size (14), dispel "mine" (debuffs you can remove are lit), "any" or "off", onlyDispellable. Position it like any
---frame. :SetUnit(unit) changes the unit; :Release() removes it. Both wait for combat to end, as the anchor does.
---.state is "working", "missing" (the client lacks the call), "refused" or "error", once tried.
function UI.UnitAuras(parent, unit, opts)
  opts = opts or {}
  local container = CreateFrame("Frame", nil, parent)
  container:SetFrameLevel(parent:GetFrameLevel() + 4)
  local key = tostring(container)

  local function release()
    if container.anchorID then
      Core.Call(Core.Fn("C_UnitAuras", "RemovePrivateAuraAnchor"), container.anchorID)
      container.anchorID = nil
    end
  end

  local function attach()
    release()
    if not container.unit then return end
    local add = Core.Fn("C_UnitAuras", "AddPrivateAuraAnchor")
    if not add then container.state = "missing" return end
    for k, v in pairs(attributes(opts)) do container:SetAttribute(k, v) end
    local size = opts.size or 14
    local ok, id = pcall(add, {
      unitToken = container.unit, auraIndex = 1, parent = container,
      showCooldownFrame = true, showCooldownEdge = false, showCountdownNumbers = false, showDispelIcon = false,
      isContainer = true,
      iconInfo = { iconAnchor = { point = "BOTTOMRIGHT", relativeTo = container, relativePoint = "BOTTOMRIGHT", offsetX = 0,
        offsetY = 0 }, iconWidth = size, iconHeight = size, borderScale = 1 },
    })
    if ok and id ~= nil and not Core.IsSecret(id) then
      container.anchorID, container.state = id, "working"
    else
      container.state = ok and "refused" or "error"
      Core:Debug("core", "private aura container refused for %s", tostring(container.unit))
    end
  end

  function container:SetUnit(newUnit)
    self.unit = newUnit
    Core:AfterCombat(attach, key)
  end

  function container:Release()
    self.unit = nil
    Core:AfterCombat(release, key)
  end

  ---New options (sizes, counts, dispel): the game reads the attributes again.
  function container:SetOptions(newOpts)
    opts = newOpts or opts
    Core:AfterCombat(attach, key)
  end

  container:SetUnit(unit)
  return container
end
