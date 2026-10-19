-- Quest colours, shared by the whole suite: the map, the minimap, the compass and Clairvoyance's
-- tracker all show a quest in the same colour. Each quest gets a stable default from a curated
-- 100-colour palette; players can roll a new one (click a pin) or pick their own (right-click).
-- Choices are saved (account-wide) and announced with NORGANNON_QUEST_COLOR_CHANGED (questId).

local Core = NorgannonCore

local Colors = {}
Core.Colors = Colors

-------------------------------------------------------------------------------------------
-- Palette: 100 colours that read on the map art. Hues step by the golden angle so neighbours
-- differ; saturation and lightness cycle through bands that stay clear of muddy darks and
-- washed-out lights.
-------------------------------------------------------------------------------------------

local function hsl(h, s, l)
  local function channel(p, q, t)
    t = t % 1
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  local q = l < .5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return { channel(p, q, h + 1 / 3), channel(p, q, h), channel(p, q, h - 1 / 3) }
end

local PALETTE = {}
local SATURATION = { .85, .7, .95, .6 }
local LIGHTNESS = { .62, .55, .7, .66, .58 }
local function luminance(c) return .3 * c[1] + .59 * c[2] + .11 * c[3] end
for i = 0, 99 do
  local h, s, l = (i * 0.6180339887) % 1, SATURATION[i % 4 + 1], LIGHTNESS[i % 5 + 1]
  local c = hsl(h, s, l)
  -- blues and violets are dark at any given lightness, yellows bright: nudge each hue into
  -- a band that reads on the map art
  while luminance(c) < .42 and l < .85 do l = l + .03 c = hsl(h, s, l) end
  while luminance(c) > .82 and l > .35 do l = l - .03 c = hsl(h, s, l) end
  PALETTE[i + 1] = c
end
Colors.PALETTE = PALETTE

local function saved()
  local db = Core.db
  if not db then return nil end
  db.questColors = db.questColors or {}
  return db.questColors
end

---The colour of a quest {r, g, b}: the player's choice, or a stable default.
function Colors:ForQuest(questId)
  local s = saved()
  local c = s and s[questId]
  if c then return c end
  return PALETTE[(questId * 37) % #PALETTE + 1]
end

function Colors:Set(questId, color)
  local s = saved()
  if not s or not color then return end
  s[questId] = { color[1], color[2], color[3] }
  Core:Send("NORGANNON_QUEST_COLOR_CHANGED", questId)
end

local function close(a, b)
  local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
  return dr * dr + dg * dg + db * db < .04
end

---A new random palette colour for the quest, unlike its current one and, where possible,
---unlike the colours of the other quests in the log.
function Colors:Randomize(questId)
  local current = self:ForQuest(questId)
  local inUse = { current }
  for _, id in ipairs(Core.Player and Core.Player:QuestIds() or {}) do
    if id ~= questId then inUse[#inUse + 1] = self:ForQuest(id) end
  end
  local candidates = {}
  for _, c in ipairs(PALETTE) do
    local free = true
    for _, used in ipairs(inUse) do if close(c, used) then free = false break end end
    if free then candidates[#candidates + 1] = c end
  end
  if #candidates == 0 then
    for _, c in ipairs(PALETTE) do if not close(c, current) then candidates[#candidates + 1] = c end end
  end
  local pick = candidates[math.random(#candidates)]
  self:Set(questId, pick)
  return pick
end

---Opens the game's colour picker for a quest; cancelling restores the previous colour.
function Colors:Pick(questId)
  if not ColorPickerFrame then return end
  local before = self:ForQuest(questId)
  local function apply()
    local r, g, b = ColorPickerFrame:GetColorRGB()
    Colors:Set(questId, { r, g, b })
  end
  local function cancel() Colors:Set(questId, before) end
  if ColorPickerFrame.SetupColorPickerAndShow then
    ColorPickerFrame:SetupColorPickerAndShow({
      r = before[1], g = before[2], b = before[3], hasOpacity = false,
      swatchFunc = apply, cancelFunc = cancel,
    })
  else
    -- older clients: the frame's fields, then show it
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.func, ColorPickerFrame.cancelFunc = apply, cancel
    ColorPickerFrame.previousValues = { r = before[1], g = before[2], b = before[3] }
    ColorPickerFrame:SetColorRGB(before[1], before[2], before[3])
    ColorPickerFrame:Hide()
    ColorPickerFrame:Show()
  end
end
