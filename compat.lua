-- Core.Compat (1.23; the generated list 1.26): the classic functions WoW Forever's client no longer has, with their classic answers.
--
-- Forever runs Classic content on the modern client, and many classic globals are gone there: GetSpellInfo,
-- GetItemInfo, GetContainerItemInfo and the rest moved into C_Spell, C_Item, C_Container, C_SpellBook and C_AddOns,
-- often returning a table where classic returned several values. ForeverAPI's dump (G:\Projects\ForeverAPI,
-- client 1.60.1.70862) shows every classic name in Compat.MAP missing and its replacement present.
--
--   local name, _, icon = Core.Compat.GetSpellInfo(8936)
--
-- Each function uses the client's own global when it has one (so code using Compat runs on other clients too),
-- else the replacement, reshaped to the classic return values. Nothing is written into the global namespace:
-- another add-on that defines or checks GetSpellInfo is left alone. Values the client keeps secret in combat (spell
-- cooldown durations, charges) come back secret: hand them to widgets, don't compare them.

local Core = NorgannonCore

local Compat = {}
Core.Compat = Compat

-- the hand-kept list: classic name -> where it lives now. tools/harness/platform_test.py checks it against
-- ForeverAPI's api.json (the classic name missing, the replacement verified in game).
Compat.MAP = {
  GetSpellInfo = "C_Spell.GetSpellInfo", GetSpellTexture = "C_Spell.GetSpellTexture", GetSpellLink = "C_Spell.GetSpellLink",
  GetSpellDescription = "C_Spell.GetSpellDescription", GetSpellCooldown = "C_Spell.GetSpellCooldown",
  GetSpellCharges = "C_Spell.GetSpellCharges", IsUsableSpell = "C_Spell.IsSpellUsable", GetSpellCount = "C_Spell.GetSpellCastCount",
  IsSpellInRange = "C_Spell.IsSpellInRange", GetSpellPowerCost = "C_Spell.GetSpellPowerCost",
  GetItemInfo = "C_Item.GetItemInfo", GetItemInfoInstant = "C_Item.GetItemInfoInstant", GetItemStats = "C_Item.GetItemStats",
  GetItemCooldown = "C_Container.GetItemCooldown", GetItemIcon = "C_Item.GetItemIconByID", GetItemCount = "C_Item.GetItemCount",
  IsUsableItem = "C_Item.IsUsableItem", GetItemSpell = "C_Item.GetItemSpell", GetItemQualityColor = "C_Item.GetItemQualityColor",
  IsItemInRange = "C_Item.IsItemInRange",
  GetContainerNumSlots = "C_Container.GetContainerNumSlots", GetContainerNumFreeSlots = "C_Container.GetContainerNumFreeSlots",
  GetContainerItemInfo = "C_Container.GetContainerItemInfo", GetContainerItemLink = "C_Container.GetContainerItemLink",
  PickupContainerItem = "C_Container.PickupContainerItem", UseContainerItem = "C_Container.UseContainerItem",
  GetNumSpellTabs = "C_SpellBook.GetNumSpellBookSkillLines", GetSpellTabInfo = "C_SpellBook.GetSpellBookSkillLineInfo",
  GetSpellBookItemName = "C_SpellBook.GetSpellBookItemName", GetSpellBookItemInfo = "C_SpellBook.GetSpellBookItemInfo",
  GetSpellBookItemTexture = "C_SpellBook.GetSpellBookItemTexture",
  GetAddOnMetadata = "C_AddOns.GetAddOnMetadata", IsAddOnLoaded = "C_AddOns.IsAddOnLoaded", GetNumAddOns = "C_AddOns.GetNumAddOns",
  GetAddOnInfo = "C_AddOns.GetAddOnInfo", EnableAddOn = "C_AddOns.EnableAddOn", DisableAddOn = "C_AddOns.DisableAddOn",
  UnitAura = "C_UnitAuras.GetAuraDataByIndex", UnitBuff = "C_UnitAuras.GetAuraDataByIndex",
  UnitDebuff = "C_UnitAuras.GetAuraDataByIndex", GetMouseFocus = "GetMouseFoci",
}

local function fn(path)
  local ns, name = path:match("^([%w_]+)%.([%w_]+)$")
  if ns then return Core.Fn(ns, name) end
  return Core.Fn(nil, path)
end

-- The client's own classic global when it has one; else nil.
local function native(name)
  local f = rawget(_G, name)
  return type(f) == "function" and f or nil
end

-- A function that returns what the replacement returns, unchanged (same arguments and the same classic values).
local function same(name)
  return function(...)
    local f = native(name) or fn(Compat.MAP[name])
    if f then return f(...) end
  end
end

-- A function that calls the replacement and reshapes its answer: reshape(answer, ...) -> classic values.
local function reshaped(name, reshape)
  return function(...)
    local f = native(name)
    if f then return f(...) end
    local ok, answer = Core.Call(fn(Compat.MAP[name]), ...)
    if not ok then return nil end
    return reshape(answer, ...)
  end
end

-------------------------------------------------------------------------------------------
-- The ones that return the same values as classic did
-------------------------------------------------------------------------------------------

for _, name in ipairs({ "GetSpellTexture", "GetSpellLink", "GetSpellDescription", "IsUsableSpell", "GetSpellCount",
  "IsSpellInRange", "GetSpellPowerCost", "GetItemInfo", "GetItemInfoInstant", "GetItemStats", "GetItemCooldown",
  "GetItemIcon", "GetItemCount", "IsUsableItem", "GetItemSpell", "GetItemQualityColor", "IsItemInRange",
  "GetContainerNumSlots", "GetContainerNumFreeSlots", "GetContainerItemLink", "PickupContainerItem", "UseContainerItem",
  "GetNumSpellTabs", "GetAddOnMetadata", "IsAddOnLoaded", "GetNumAddOns", "GetAddOnInfo", "EnableAddOn", "DisableAddOn" }) do
  Compat[name] = same(name)
end

-- and the generated ones (compat_list.lua, made by tools/compat_gen.py from ForeverAPI's relocated-API table): gone
-- on Forever, replaced by a function called the same way with the same answers
for name, target in pairs(Core.CompatSame or {}) do
  if not Compat.MAP[name] then
    Compat.MAP[name] = target
    Compat[name] = same(name)
  end
end

-------------------------------------------------------------------------------------------
-- Spells
-------------------------------------------------------------------------------------------

---name, rank, icon, castTime, minRange, maxRange, spellID, originalIcon. The rank is the spell's subtext ("Rank 3").
Compat.GetSpellInfo = reshaped("GetSpellInfo", function(info, spell)
  if type(info) ~= "table" then return nil end
  local rank = Core.In("C_Spell", "GetSpellSubtext", spell)
  return info.name, rank, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID, info.originalIconID
end)

---start, duration, enabled (1 or 0), modRate. In combat the duration (and start) may be secret.
Compat.GetSpellCooldown = reshaped("GetSpellCooldown", function(info)
  if type(info) ~= "table" then return nil end
  local enabled = info.isEnabled
  if not Core.IsSecret(enabled) then enabled = enabled and 1 or 0 end
  return info.startTime, info.duration, enabled, info.modRate
end)

---currentCharges, maxCharges, cooldownStart, cooldownDuration, chargeModRate; nil for a spell without charges.
Compat.GetSpellCharges = reshaped("GetSpellCharges", function(info)
  if type(info) ~= "table" then return nil end
  return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration, info.chargeModRate
end)

-------------------------------------------------------------------------------------------
-- Bags
-------------------------------------------------------------------------------------------

---texture, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID, isBound.
Compat.GetContainerItemInfo = reshaped("GetContainerItemInfo", function(info)
  if type(info) ~= "table" then return nil end
  return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.isReadable, info.hasLoot, info.hyperlink,
    info.isFiltered, info.hasNoValue, info.itemID, info.isBound
end)

-------------------------------------------------------------------------------------------
-- The spellbook: classic said "spell" or "pet" (BOOKTYPE_SPELL / BOOKTYPE_PET); the client wants a bank
-------------------------------------------------------------------------------------------

local function bank(bookType)
  local banks = rawget(_G, "Enum") and Enum.SpellBookSpellBank
  local pet = bookType == "pet" or bookType == rawget(_G, "BOOKTYPE_PET")
  if banks then return pet and banks.Pet or banks.Player end
  return pet and 1 or 0
end

---name, texture, offset, numSlots, isGuild, offspecID.
Compat.GetSpellTabInfo = reshaped("GetSpellTabInfo", function(info)
  if type(info) ~= "table" then return nil end
  return info.name, info.iconID, info.itemIndexOffset, info.numSpellBookItems, info.isGuild, info.offSpecID or 0
end)

---name, subName (the rank).
function Compat.GetSpellBookItemName(index, bookType)
  local f = native("GetSpellBookItemName")
  if f then return f(index, bookType) end
  return Core.In("C_SpellBook", "GetSpellBookItemName", index, bank(bookType))
end

---texture.
function Compat.GetSpellBookItemTexture(index, bookType)
  local f = native("GetSpellBookItemTexture")
  if f then return f(index, bookType) end
  return Core.In("C_SpellBook", "GetSpellBookItemTexture", index, bank(bookType))
end

-- Enum.SpellBookItemType's names in classic's words: Spell -> "SPELL", FutureSpell -> "FUTURESPELL", ...
local function itemTypeName(value)
  local types = rawget(_G, "Enum") and Enum.SpellBookItemType
  for name, v in pairs(types or {}) do
    if v == value then return string.upper(name) end
  end
end

---spellType ("SPELL", "FUTURESPELL", "PETACTION", "FLYOUT"), id (the spell's id, or the action's for a pet).
function Compat.GetSpellBookItemInfo(index, bookType)
  local f = native("GetSpellBookItemInfo")
  if f then return f(index, bookType) end
  local info = Core.In("C_SpellBook", "GetSpellBookItemInfo", index, bank(bookType))
  if type(info) ~= "table" then return nil end
  local kind = itemTypeName(info.itemType)
  if not kind or kind == "NONE" then return nil end
  return kind, info.spellID or info.actionID
end

-------------------------------------------------------------------------------------------
-- Auras. In combat, add-ons can't read auras at all on this client (the call errors: "Auras cannot be accessed when
-- secret while tainted"), so these answer nil there. Mercy draws debuffs in combat through Blizzard's own anchors.
-------------------------------------------------------------------------------------------

local function aura(unit, index, filter)
  local ok, a = Core.Call(Core.Fn("C_UnitAuras", "GetAuraDataByIndex"), unit, index, filter)
  if not ok or type(a) ~= "table" or Core.IsSecret(a) then return nil end
  return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime, a.sourceUnit, a.isStealable,
    a.nameplateShowPersonal, a.spellId, a.canApplyAura, a.isBossAura, a.isFromPlayerOrPlayerPet, a.nameplateShowAll,
    a.timeMod
end

---name, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId, ...
function Compat.UnitAura(unit, index, filter)
  local f = native("UnitAura")
  if f then return f(unit, index, filter) end
  return aura(unit, index, filter)
end

function Compat.UnitBuff(unit, index, filter)
  local f = native("UnitBuff")
  if f then return f(unit, index, filter) end
  return aura(unit, index, filter and ("HELPFUL|" .. filter) or "HELPFUL")
end

function Compat.UnitDebuff(unit, index, filter)
  local f = native("UnitDebuff")
  if f then return f(unit, index, filter) end
  return aura(unit, index, filter and ("HARMFUL|" .. filter) or "HARMFUL")
end

-------------------------------------------------------------------------------------------
-- Other
-------------------------------------------------------------------------------------------

---The frame under the mouse (the first of GetMouseFoci on this client).
function Compat.GetMouseFocus()
  local f = native("GetMouseFocus")
  if f then return f() end
  local foci = Core.Global("GetMouseFoci")
  return type(foci) == "table" and foci[1] or nil
end
