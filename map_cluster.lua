-- Clustering the map layer's pins, for the soft glow over a quest's dense spawns: single-link
-- within CLUSTER_DISTANCE, per cluster key, through a grid so it stays linear in the number of
-- pins. No game state or frames here; map.lua draws the result (Map.Cluster).

local Core = NorgannonCore

local CLUSTER_DISTANCE = 7        -- percent of the map: pins this close join one cluster
local CLUSTER_AREA_MIN = 6        -- a cluster this big gets a glow
local CLUSTER_GLOW_MARGIN = 3     -- percent of the map: how far a glow reaches past its outermost pins
local GRID_STRIDE = 1024          -- packs a grid cell's column and row into one key

-- A group's pins as sets linked by steps of at most CLUSTER_DISTANCE (a union-find). Each pin
-- only compares with those in its own and the neighbouring grid cells.
local function linkedSets(group)
  local parent, grid = {}, {}
  local function find(i)
    while parent[i] ~= i do
      parent[i] = parent[parent[i]]
      i = parent[i]
    end
    return i
  end
  local d2 = CLUSTER_DISTANCE * CLUSTER_DISTANCE
  for i, pin in ipairs(group) do
    parent[i] = i
    local ri = i   -- the root of i's set, kept current so each pair needs one find
    local px, py = pin.x, pin.y
    local cx, cy = math.floor(px / CLUSTER_DISTANCE), math.floor(py / CLUSTER_DISTANCE)
    for gx = cx - 1, cx + 1 do
      for gy = cy - 1, cy + 1 do
        local cell = grid[gx * GRID_STRIDE + gy]
        if cell then
          for n = 1, #cell do
            local j = cell[n]
            local o = group[j]
            local dx, dy = px - o.x, py - o.y
            if dx * dx + dy * dy <= d2 then
              local rj = find(j)
              if ri ~= rj then
                parent[ri] = rj
                ri = rj
              end
            end
          end
        end
      end
    end
    local key = cx * GRID_STRIDE + cy
    local cell = grid[key]
    if not cell then
      cell = {}
      grid[key] = cell
    end
    cell[#cell + 1] = i
  end
  local sets = {}
  for i in ipairs(group) do
    local root = find(i)
    sets[root] = sets[root] or {}
    table.insert(sets[root], group[i])
  end
  return sets
end

-- the glow's ellipse around a set of pins
local function clusterOf(members)
  local sx, sy = 0, 0
  for _, p in ipairs(members) do sx, sy = sx + p.x, sy + p.y end
  local mx, my = sx / #members, sy / #members
  local rx, ry = 0, 0
  for _, p in ipairs(members) do
    rx, ry = math.max(rx, math.abs(p.x - mx)), math.max(ry, math.abs(p.y - my))
  end
  return { x = mx, y = my, rx = rx + CLUSTER_GLOW_MARGIN, ry = ry + CLUSTER_GLOW_MARGIN, members = members,
    color = members[1].color }
end

local function clusterPins(pins)
  local groups = {}
  for _, pin in ipairs(pins) do
    if pin.cluster then
      groups[pin.cluster] = groups[pin.cluster] or {}
      table.insert(groups[pin.cluster], pin)
    end
  end
  local clusters = {}
  for _, group in pairs(groups) do
    if #group >= CLUSTER_AREA_MIN then
      for _, members in pairs(linkedSets(group)) do
        if #members >= CLUSTER_AREA_MIN then table.insert(clusters, clusterOf(members)) end
      end
    end
  end
  return clusters
end
Core.ClusterPins = clusterPins
