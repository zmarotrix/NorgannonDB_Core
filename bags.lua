-- Core.Bags: where a character's items live and what kind each one is, for every add-on that reads
-- bags. It only reads: moving items is up to the add-on that wants to.
--
-- The client's bank has been tabs and classic bank bags on different builds, so bank lists try the
-- purchased tabs from C_Bank first and fall back to whichever bank containers the client names.

local Core = NorgannonCore

local Bags = {}
Core.Bags = Bags

local TAB_CONTAINERS = 9     -- Enum.BagIndex names CharacterBankTab_1..9 and AccountBankTab_1..9
local CLASSIC_BANK_BAGS = 7
local BAG_SLOTS = 4
local POOR = 0               -- Enum.ItemQuality.Poor: greys

-- the kinds of item, in the order people expect to read them
Bags.KINDS = {
  { key = "gear", label = "Gear" }, { key = "consumable", label = "Consumables" }, { key = "trade", label = "Trade goods" },
  { key = "recipe", label = "Recipes" }, { key = "quest", label = "Quest items" }, { key = "key", label = "Keys" },
  { key = "junk", label = "Junk" }, { key = "other", label = "Other" },
}
-- Enum.ItemClass: what each class of item goes under
local BY_CLASS = { [0] = "consumable", [2] = "gear", [4] = "gear", [5] = "trade", [7] = "trade", [9] = "recipe", [12] = "quest", [13] = "key" }

---ns.name(...) with errors and secret values turned into nil, and nil when the client lacks it.
local function try(ns, name, ...)
  local t = rawget(_G, ns)
  local fn = t and t[name]
  if not fn then return nil end
  local ok, a, b, c, d, e, f, g = pcall(fn, ...)
  if not ok or Core.IsSecret(a) then return nil end
  return a, b, c, d, e, f, g
end

local function bagIndex()
  return (rawget(_G, "Enum") and Enum.BagIndex) or {}
end

---A bag's own name ("Small Silk Pack"), from the item in its slot.
local function bagName(id, fallback)
  local slot = try("C_Container", "ContainerIDToInventoryID", id)
  local read = rawget(_G, "GetInventoryItemLink")
  if not (slot and read) then return fallback end
  local ok, link = pcall(read, "player", slot)
  if not ok or Core.IsSecret(link) or type(link) ~= "string" then return fallback end
  return link:match("%[(.-)%]") or fallback
end

---The containers a character carries: { { id, name, keyring? } }, backpack first. The reagent bag is
---marked `reagent`; the keyring is listed only if the client has one, and keys go nowhere else, so
---add-ons counting bag space should skip it.
function Bags:BagList()
  local B = bagIndex()
  local list = { { id = B.Backpack or 0, name = "Backpack" } }
  for i = 1, BAG_SLOTS do
    local id = B["Bag_" .. i] or i
    list[#list + 1] = { id = id, name = bagName(id, "Bag " .. i) }
  end
  if B.ReagentBag then list[#list + 1] = { id = B.ReagentBag, name = bagName(B.ReagentBag, "Reagent bag"), reagent = true } end
  if B.Keyring then list[#list + 1] = { id = B.Keyring, name = "Keyring", keyring = true } end
  return list
end

---Bank containers: `kind` is "Character" or "Account". The purchased tabs if the client answers,
---else every bank container it names (only those with slots hold anything). The bank must be open
---for its slots to be readable.
function Bags:BankList(kind)
  local B = bagIndex()
  local list = {}
  local bankType = rawget(_G, "Enum") and Enum.BankType and Enum.BankType[kind]
  if bankType ~= nil then
    local tabs = try("C_Bank", "FetchPurchasedBankTabData", bankType)
    if type(tabs) == "table" then
      for _, tab in ipairs(tabs) do
        if type(tab) == "table" and tab.ID then list[#list + 1] = { id = tab.ID, name = tab.name } end
      end
    end
    if #list == 0 then
      local ids = try("C_Bank", "FetchPurchasedBankTabIDs", bankType)
      if type(ids) == "table" then
        for i, id in ipairs(ids) do list[#list + 1] = { id = id, name = "Tab " .. i } end
      end
    end
  end
  if #list > 0 then return list end
  local prefix = kind == "Account" and "AccountBankTab_" or "CharacterBankTab_"
  for i = 1, TAB_CONTAINERS do
    if B[prefix .. i] then list[#list + 1] = { id = B[prefix .. i], name = "Tab " .. i } end
  end
  if kind == "Character" then
    if B.Bank then list[#list + 1] = { id = B.Bank, name = "Bank" } end
    for i = 1, CLASSIC_BANK_BAGS do
      if B["BankBag_" .. i] then list[#list + 1] = { id = B["BankBag_" .. i], name = "Bank bag " .. i } end
    end
  end
  return list
end

---Which kind an item is: from the client, else NorgannonDB; poor quality is junk unless a quest wants it.
---`quality` may be nil if the caller doesn't know it, and then only the client is asked.
function Bags.Kind(id, quality)
  local _, _, _, _, _, class = try("C_Item", "GetItemInfoInstant", id)
  if class == nil and NorgannonDB and NorgannonDB.Peek then
    local record = NorgannonDB:Peek("items", id)
    class = record and record.class
  end
  local kind = BY_CLASS[class] or "other"
  if quality == nil then quality = try("C_Item", "GetItemQualityByID", id) end
  if quality == POOR and kind ~= "quest" then return "junk" end
  return kind
end
