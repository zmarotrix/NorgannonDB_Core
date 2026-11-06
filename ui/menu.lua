-- The shared action menu: a right-click menu for any entity, built with the game's own context
-- menus (MenuUtil). The caller adds its own items; the menu then adds the actions other suite
-- add-ons registered for the entity (Core:RegisterAction).
--
--   Core:ShowActionMenu(owner, "quest", 788, { title = "Cutting Teeth", items = {
--     { text = "Show on map", func = fn }, "-", { text = "Abandon quest…", func = fn, disabled = false },
--   } })

local Core = NorgannonCore

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

---The suite part of a menu: the actions registered for the entity.
function Core:SuiteMenuItems(kind, id)
  local items = {}
  for _, action in ipairs(self:ActionsFor(kind, id)) do
    items[#items + 1] = { text = action.label, func = function() action.run(kind, id) end }
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
