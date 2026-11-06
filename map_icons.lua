-- The map layer's pin icons: what each icon name means, and which source of it the client has.
-- map.lua exposes these as Map.ICONS, Map.SERVICE_ICONS, Map.IconSource and Map.SetIcon.

local Core = NorgannonCore
local UI = Core.UI

local Icons = {}
Core.MapIcons = Icons

-- Pin icons. Quest givers use the game's own marks so they read like the default UI: the
-- client's atlas first, the classic gossip icon second, our own glyph only as a last resort.
-- grey = desaturated (low-level available quests, turn-ins that are not complete yet).
local ICONS = {
  pin = { file = UI.TEX.pin, tint = true },
  diamond = { file = UI.TEX.pinDiamond, tint = true },
  exclaim = { atlas = "QuestNormal", file = "Interface\\GossipFrame\\AvailableQuestIcon", fallback = UI.TEX.exclaim },
  exclaimDaily = { atlas = "QuestDaily", file = "Interface\\GossipFrame\\DailyQuestIcon", fallback = UI.TEX.exclaim },
  exclaimGrey = { atlas = "QuestNormal", file = "Interface\\GossipFrame\\AvailableQuestIcon", fallback = UI.TEX.exclaim, grey = true },
  question = { atlas = "QuestTurnin", file = "Interface\\GossipFrame\\ActiveQuestIcon", fallback = UI.TEX.question },
  questionRepeat = { atlas = "QuestRepeatableTurnin", file = "Interface\\GossipFrame\\DailyActiveQuestIcon", fallback = UI.TEX.question },
  questionGrey = { atlas = "QuestTurnin", file = "Interface\\GossipFrame\\IncompleteQuestIcon", fallback = UI.TEX.question, grey = true },
}
Icons.ICONS = ICONS

-- Town services and gathering (Core 1.8): the client's own icons, the ones pfQuest copied.
-- The modern minimap-tracking atlas first, the classic Minimap\Tracking file second, then a
-- spell or item icon cropped round. Never tinted. `/norg icons` shows which one loaded.
local TRACKING, ICON = "Interface\\Minimap\\Tracking\\", "Interface\\Icons\\"
local SERVICE_ICONS = {
  auctioneer = { atlas = "Auctioneer", files = { TRACKING .. "Auctioneer" }, round = ICON .. "INV_Misc_Coin_02" },
  banker = { atlas = "Banker", files = { TRACKING .. "Banker" }, round = ICON .. "INV_Misc_Bag_10" },
  battlemaster = { atlas = "BattleMaster", files = { TRACKING .. "BattleMaster" }, round = ICON .. "INV_BannerPVP_01" },
  flight = { atlas = "FlightMaster", files = { TRACKING .. "FlightMaster", "Interface\\TaxiFrame\\UI-Taxi-Icon-Green" },
    round = ICON .. "Ability_Mount_Wyvern_01" },
  innkeeper = { atlas = "Innkeeper", files = { TRACKING .. "Innkeeper" }, round = ICON .. "INV_Misc_Rune_01" },
  mailbox = { atlas = "Mailbox", files = { TRACKING .. "Mailbox" }, round = ICON .. "INV_Letter_15" },
  repair = { atlas = "Repair", files = { TRACKING .. "Repair" }, round = ICON .. "Trade_BlackSmithing" },
  stablemaster = { atlas = "StableMaster", files = { TRACKING .. "StableMaster" }, round = ICON .. "Ability_Hunter_BeastTaming" },
  vendor = { atlas = "Food", files = { TRACKING .. "Food" }, round = ICON .. "INV_Misc_Food_14" },
  trainer = { atlas = "Class", files = { TRACKING .. "Class" }, round = ICON .. "INV_Misc_Book_09" },
  spirithealer = { round = ICON .. "Spell_Holy_Resurrection" },
  meetingstone = { round = ICON .. "Spell_Shadow_Twilight" },      -- Ritual of Summoning
  chests = { round = ICON .. "Racial_Dwarf_FindTreasure" },
  herbs = { round = ICON .. "INV_Misc_Flower_02" },                 -- Find Herbs
  mines = { round = ICON .. "Spell_Nature_Earthquake" },            -- Find Minerals
  fish = { round = ICON .. "Trade_Fishing" },
}
for key, spec in pairs(SERVICE_ICONS) do
  spec.fallback = UI.TEX.pinDiamond
  ICONS["service." .. key] = spec
end
Icons.SERVICE_ICONS = SERVICE_ICONS

local function hasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- a square icon cropped to a circle: trimmed border and a round mask (made once per frame)
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function setRound(tex, round)
  local parent = tex:GetParent()
  local mask = parent and parent.ndbRoundMask
  if round and not mask and parent and parent.CreateMaskTexture then
    mask = parent:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIONAL", "CLAMPTOBLACKADDITIONAL")
    mask:SetAllPoints(tex)
    parent.ndbRoundMask = mask
  end
  if round then
    tex:SetTexCoord(.08, .92, .08, .92)
    if mask and not tex.ndbMasked then tex:AddMaskTexture(mask) tex.ndbMasked = true end
  else
    tex:SetTexCoord(0, 1, 0, 1)
    if mask and tex.ndbMasked then tex:RemoveMaskTexture(mask) tex.ndbMasked = nil end
  end
end

-- SetTexture reports false for a missing file on modern clients
local function tryFile(tex, file) return file and tex:SetTexture(file) ~= false end

local probe   -- a hidden texture to try files on

---Which source of an icon the client has: "atlas", "file", "round" or "fallback" (and the name).
function Icons.Source(name)
  local spec = ICONS[name]
  if not spec then return nil end
  if spec.atlas and hasAtlas(spec.atlas) then return "atlas", spec.atlas end
  if not probe then
    probe = UIParent:CreateTexture()
    probe:Hide()
  end
  for _, file in ipairs(spec.files or { spec.file }) do
    if tryFile(probe, file) then return "file", file end
  end
  if tryFile(probe, spec.round) then return "round", spec.round end
  return "fallback", spec.fallback
end

-- Sets a pin texture from ICONS (or a plain texture path); returns whether it may be tinted.
local function setIcon(tex, name)
  local spec = ICONS[name or "pin"]
  tex:SetDesaturated(false)
  local round = false
  if not spec then
    tex:SetTexture(name)
  elseif spec.atlas and hasAtlas(spec.atlas) then
    tex:SetAtlas(spec.atlas)
  else
    local done = false
    for _, file in ipairs(spec.files or { spec.file }) do
      if tryFile(tex, file) then done = true break end
    end
    if not done and tryFile(tex, spec.round) then done, round = true, true end
    if not done then tex:SetTexture(spec.fallback or UI.TEX.pin) end
  end
  setRound(tex, round)
  if spec and spec.grey then tex:SetDesaturated(true) end
  if not spec then return true end
  return spec.tint or false
end
Icons.Set = setIcon
