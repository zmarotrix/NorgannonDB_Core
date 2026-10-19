-- The shared action menu: a right-click menu for any entity, built with the game's own context
-- menus (MenuUtil). The caller adds its own items; the menu then adds the actions other suite
-- add-ons registered for the entity (Core:RegisterAction), and at most one quiet line about a
-- suite add-on that isn't installed but could help ("Oracle can open this dungeon").
--
--   Core:ShowActionMenu(owner, "quest", 788, { title = "Cutting Teeth", items = {
--     { text = "Show on map", func = fn }, "-", { text = "Abandon quest…", func = fn, disabled = false },
--   } })

local Core = NorgannonCore

-- what each suite add-on would offer, to mention it once when it is missing
local HINTS = {
  { addon = "clairvoyance", kinds = { npc = true, object = true, item = true }, text = "Clairvoyance can show this on the map" },
  { addon = "oracle", kinds = { instance = true, zone = true }, text = "Oracle can open this" },
  { addon = "archivum", kinds = { quest = true, npc = true, object = true, item = true, zone = true, faction = true }, text = "Archivum can look this up" },
  { addon = "foresight", kinds = { quest = true, item = true, faction = true, skill = true }, text = "Foresight can set this as a goal" },
}

local function addItems(root, items)
  for _, item in ipairs(items or {}) do
    if item == "-" then
      root:CreateDivider()
    else
      local button = root:CreateButton(item.text, function() Core.SafeCall(item.func) end)
      if item.disabled and button.SetEnabled then button:SetEnabled(false) end
    end
  end
end

---The suite part of a menu: registered actions for the entity, then one hint for a missing add-on.
function Core:SuiteMenuItems(kind, id)
  local items = {}
  for _, action in ipairs(self:ActionsFor(kind, id)) do
    items[#items + 1] = { text = action.label, func = function() action.run(kind, id) end }
  end
  for _, hint in ipairs(HINTS) do
    if hint.kinds[kind] and self:AddonState(hint.addon) == "missing" then
      items[#items + 1] = { text = hint.text, disabled = true }
      break
    end
  end
  return items
end

---Opens the menu at the cursor. opts = { title, items = { {text, func, disabled} | "-" } }.
---Returns false where the client has no context menus.
function Core:ShowActionMenu(owner, kind, id, opts)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return false end
  opts = opts or {}
  local suite = self:SuiteMenuItems(kind, id)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    if opts.title then root:CreateTitle(opts.title) end
    addItems(root, opts.items)
    if #suite > 0 then
      if opts.items and #opts.items > 0 then root:CreateDivider() end
      addItems(root, suite)
    end
  end)
  return true
end
