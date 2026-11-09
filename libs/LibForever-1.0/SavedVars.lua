-- LibForever:SavedVars: an add-on's saved variable with defaults and ordered upgrades.
--
--   MyAddonDB = LF:SavedVars("MyAddonDB", { version = 2, defaults = { scale = 1, shown = true },
--     migrate = { [2] = function(sv) sv.scale, sv.size = sv.size, nil end } })
--
-- Call it at or after the add-on's own ADDON_LOADED, when the game has put the saved table in place.

local LF = LibStub("LibForever-1.0", true)
if not (LF and LF._loading) then return end

local function fill(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then
      if type(v) == "table" then
        target[k] = {}
        fill(target[k], v)
      else
        target[k] = v
      end
    elseif type(v) == "table" and type(target[k]) == "table" then
      fill(target[k], v)
    end
  end
  return target
end

---Fills target's missing keys from defaults, deep. A value already there always stays; tables are copied, never shared.
---@param target table
---@param defaults table
---@return table target
function LF.FillDefaults(target, defaults) return fill(target, defaults) end

---@class LibForever.SavedVarsOptions
---@field defaults table|nil filled in where missing, deep
---@field version number|nil this add-on's save version (default 1)
---@field migrate table<number, fun(sv: table)>|nil migrate[v] upgrades a save from v - 1 to v

---Loads the saved variable `name`: runs each migration it hasn't had, in order, fills in missing defaults (a player's
---own values always stay) and stores the version in `_v`. Saves from before versioning count as version 1; a brand-new
---save starts at `version` and runs no migration. A failed migration is logged (LF:Debug) and the rest still run.
---Returns the table, which is also _G[name].
---@param name string the SavedVariables name in the TOC
---@param opts LibForever.SavedVarsOptions|nil
---@return table
function LF.SavedVars(_, name, opts)
  opts = opts or {}
  local saved = rawget(_G, name)
  local fresh = type(saved) ~= "table" or next(saved) == nil
  local sv = type(saved) == "table" and saved or {}
  local version = opts.version or 1
  local from = tonumber(sv._v) or (fresh and version or 1)
  if from > version then
    LF:Debug(name, "saved at version %d, newer than this add-on's %d: left as it is", from, version)
  end
  for v = from + 1, version do
    local step = opts.migrate and opts.migrate[v]
    if step then
      local ok, err = pcall(step, sv)
      if not ok then LF:Debug(name, "migration to %d failed: %s", v, tostring(err)) end
    end
  end
  if (tonumber(sv._v) or 0) < version then sv._v = version end
  fill(sv, opts.defaults or {})
  _G[name] = sv
  return sv
end

LF._loading = nil   -- the last file: this copy has finished loading
