-- Secure item buttons ("use quest item" in trackers). A click on them uses the item through the
-- game's secure action system, so they work in combat. The game forbids creating, configuring or
-- moving them in combat, so every protected step waits for combat to end (Core:AfterCombat), and
-- buttons are pooled by key so a tracker row keeps its button.
--
--   Core.ItemButtons:Show("q5441", 16114, function(button) button:SetPoint("RIGHT", row, "LEFT", -4, 0) end)
--   Core.ItemButtons:Hide("q5441")

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

local ItemButtons = { buttons = {} }
Core.ItemButtons = ItemButtons

local serial = 0

local function itemIcon(itemId)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemId) end
  return GetItemIcon and GetItemIcon(itemId)
end

local function updateCooldown(b)
  if not b.itemId or not b:IsShown() then return end
  local start, duration, enabled
  if C_Container and C_Container.GetItemCooldown then
    start, duration, enabled = C_Container.GetItemCooldown(b.itemId)
  elseif GetItemCooldown then
    start, duration, enabled = GetItemCooldown(b.itemId)
  end
  if start and duration and duration > 0 and enabled ~= 0 and enabled ~= false then
    b.cooldown:SetCooldown(start, duration)
  else
    b.cooldown:Clear()
  end
end

local function create()
  serial = serial + 1
  local b = CreateFrame("Button", "NorgannonCoreItemButton" .. serial, UIParent, "SecureActionButtonTemplate")
  b:SetSize(24, 24)
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("type", "item")
  b.box = UI.Box(b, "BACKGROUND", 0)
  b.box:Set(C.lineStrong, C.inset)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 1, -1)
  b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
  b.icon:SetTexCoord(.08, .92, .08, .92)
  b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
  b.cooldown:SetAllPoints(b.icon)
  b:SetScript("OnEnter", function(self)
    self.box:Set(C.quietBorder, C.inset)
    if self.itemId then
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetItemByID(self.itemId)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self) self.box:Set(C.lineStrong, C.inset) GameTooltip:Hide() end)
  b:Hide()
  return b
end

---Shows the button for key with an item, placed by place(button) (all after combat if needed).
function ItemButtons:Show(key, itemId, place)
  Core:AfterCombat(function()
    local b = self.buttons[key]
    if not b then
      b = create()
      self.buttons[key] = b
    end
    if b.itemId ~= itemId then
      b.itemId = itemId
      b:SetAttribute("item", "item:" .. itemId)
      b.icon:SetTexture(itemIcon(itemId))
    end
    b:ClearAllPoints()
    if place then place(b) end
    b:Show()
    updateCooldown(b)
  end, "itembutton:" .. key)
end

function ItemButtons:Hide(key)
  Core:AfterCombat(function()
    local b = self.buttons[key]
    if b then b:Hide() b:ClearAllPoints() end
  end, "itembutton:" .. key)
end

function ItemButtons:Get(key) return self.buttons[key] end

Core:On("BAG_UPDATE_COOLDOWN", "itembuttons", function()
  for _, b in pairs(ItemButtons.buttons) do updateCooldown(b) end
end)
