-- The suite registry: which suite addons exist, which are installed, and the actions each one
-- offers on entities (docs/suite-plan.md section 8). Every addon shows only the actions of the
-- addons that are installed, so "Show on map" appears only with Clairvoyance, and so on.

local Core = NorgannonCore

-- The suite and its companions, in display order. accent is the brand colour (brand/README.md).
Core.SUITE = {
  { key = "clairvoyance", name = "Clairvoyance", folder = "Clairvoyance", accent = "4fe3cf", role = "Quest helper", slash = "/clair" },
  { key = "oracle", name = "Oracle", folder = "Oracle", accent = "b48cff", role = "Dungeon & zone atlas", slash = "/oracle" },
  { key = "foresight", name = "Foresight", folder = "Foresight", accent = "ffb35c", role = "Goal planner", slash = "/fore" },
  { key = "archivum", name = "Archivum", folder = "Archivum", accent = "7cc4ff", role = "Database browser", slash = "/arch" },
}
Core.FAMILY = {
  { key = "norgannondb", name = "NorgannonDB", folder = "NorgannonDB", accent = "e7c66c", role = "The shared game database" },
  { key = "collector", name = "Collector", folder = "NorgannonDBCollector", accent = "6fdc8c", role = "Help map Azeroth", kicker = "NorgannonDB", slash = "/ndbc" },
}

local byKey = {}
for _, list in ipairs({ Core.SUITE, Core.FAMILY }) do
  for _, info in ipairs(list) do byKey[info.key] = info end
end

function Core:GetAddonInfo(key)
  return byKey[key]
end

-- Addons register themselves at load with their version and anything they want to expose.
local registered = {}

---Called by each suite addon at load: Core:RegisterAddon("oracle", { version = "1.0.0", open = fn }).
function Core:RegisterAddon(key, info)
  registered[key] = info or {}
  self:Send("NORGANNON_ADDON_REGISTERED", key)
end

---"loaded" when the addon is running, "installed" when it is present but not loaded (disabled
---or load on demand), otherwise "missing".
function Core:AddonState(key)
  if registered[key] then return "loaded" end
  local info = byKey[key]
  if not info or not C_AddOns then return "missing" end
  local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, info.folder)
  if ok and loaded then return "loaded" end
  local okInfo, name, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, info.folder)
  if okInfo and name and reason ~= "MISSING" then return "installed" end
  return "missing"
end

function Core:AddonVersion(key)
  local info = byKey[key]
  if registered[key] and registered[key].version then return registered[key].version end
  if info and C_AddOns and C_AddOns.GetAddOnMetadata then
    local ok, version = pcall(C_AddOns.GetAddOnMetadata, info.folder, "Version")
    if ok then return version end
  end
end

-------------------------------------------------------------------------------------------
-- Actions on entities ("Show on map", "Open in Oracle", "Look up", "Set as goal")
-------------------------------------------------------------------------------------------

local actions = {}   -- ordered list of { id, addon, label, kinds = {kind=true}, run, available }

---Registers an action an addon offers. spec = { addon = key, label = "Show on map",
---kinds = { "npc", "item", ... }, run = function(kind, id) end, available = function(kind, id) end }.
function Core:RegisterAction(id, spec)
  local kinds = {}
  for _, kind in ipairs(spec.kinds or {}) do kinds[kind] = true end
  for i, existing in ipairs(actions) do
    if existing.id == id then table.remove(actions, i) break end
  end
  table.insert(actions, { id = id, addon = spec.addon, label = spec.label, kinds = kinds, run = spec.run, available = spec.available })
end

---The actions that apply to an entity, in registration order.
function Core:ActionsFor(kind, id)
  local out = {}
  for _, action in ipairs(actions) do
    if action.kinds[kind] and (not action.available or action.available(kind, id)) then
      table.insert(out, action)
    end
  end
  return out
end
