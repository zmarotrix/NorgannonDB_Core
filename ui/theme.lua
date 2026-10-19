-- Design tokens (the same values as design/suite/suite.css) and fonts.
-- Fonts: Marcellus for titles, Alegreya Sans for text (SIL OFL, media/fonts). Marcellus has
-- Latin only and Alegreya Sans adds Cyrillic, so ruRU titles use Alegreya Sans and the CJK
-- locales use the game's own fonts throughout.

local Core = NorgannonCore
local UI = {}
Core.UI = UI

local MEDIA = "Interface\\AddOns\\NorgannonDB_Core\\media\\"
UI.MEDIA = MEDIA
UI.TEX = {
  circle = MEDIA .. "ui\\circle", glow = MEDIA .. "ui\\glow", rivet = MEDIA .. "ui\\rivet",
  search = MEDIA .. "ui\\search", close = MEDIA .. "ui\\close", check = MEDIA .. "ui\\check",
  chevron = MEDIA .. "ui\\chevron", db = MEDIA .. "ui\\db", white = "Interface\\Buttons\\WHITE8X8",
  pin = MEDIA .. "ui\\pin", pinDiamond = MEDIA .. "ui\\pin-diamond", ring = MEDIA .. "ui\\ring",
  arrow = MEDIA .. "ui\\arrow", exclaim = MEDIA .. "ui\\exclaim", question = MEDIA .. "ui\\question",
  round = MEDIA .. "ui\\round", roundLine = MEDIA .. "ui\\round-line",
  viewDetailed = MEDIA .. "ui\\view-detailed", viewCompact = MEDIA .. "ui\\view-compact",
  gear = MEDIA .. "ui\\gear",
}

---{r, g, b, a} from "rrggbb".
local function hex(s, a)
  return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255, a or 1 }
end
UI.Hex = hex

UI.C = {
  void = hex("050403"), stone = hex("17130e"), stone2 = hex("1f1912"), inset = hex("0d0a07"),
  line = hex("3d3220"), lineStrong = hex("5c4a2c"), frameGold = hex("9c7a3c"), frameDark = hex("2b1f10"),
  parch = hex("ead9ae"), parchInk = hex("3a250f"),
  gold = hex("ffd100"), goldSoft = hex("e7c66c"), text = hex("f0ead8"), muted = hex("a8a08a"), faint = hex("6e6552"),
  black = hex("000000"),
  -- quest difficulty, the game's own scale
  trivial = hex("8a8a8a"), easy = hex("40bf40"), fair = hex("ffd100"), hard = hex("ff8040"), impossible = hex("ff2a2a"),
  -- buttons
  redTop = hex("b0261d"), redBottom = hex("5c0d09"), redBorder = hex("e0b049"),
  quietTop = hex("3b302a"), quietBottom = hex("1d1714"), quietBorder = hex("8a7344"), quietText = hex("d8c79a"),
}

---The accent colour of a suite addon, by key (gold for anything unknown).
function UI.Accent(key)
  local info = key and Core:GetAddonInfo(key)
  return info and hex(info.accent) or UI.C.goldSoft
end

---Mix two colours: t = 0 gives a, 1 gives b.
function UI.Mix(a, b, t)
  return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t }
end

---|cffrrggbb colour code for a colour table.
function UI.Code(c)
  return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + .5), math.floor(c[2] * 255 + .5), math.floor(c[3] * 255 + .5))
end

-------------------------------------------------------------------------------------------
-- Fonts
-------------------------------------------------------------------------------------------

local locale = GetLocale()
local CJK = locale == "koKR" or locale == "zhCN" or locale == "zhTW"
local FILES = {
  title = MEDIA .. "fonts\\Marcellus-Regular.ttf",
  body = MEDIA .. "fonts\\AlegreyaSans-Regular.ttf",
  bold = MEDIA .. "fonts\\AlegreyaSans-Bold.ttf",
}
if locale == "ruRU" then FILES.title = FILES.bold end
if CJK then
  local game = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  FILES = { title = game, body = game, bold = game }
end
UI.FONT_FILES = FILES

local fonts = {}
local serial = 0

---A shared font object: role "title", "body" or "bold", size in points, optional flags.
function UI.Font(role, size, flags)
  local key = role .. size .. (flags or "")
  local font = fonts[key]
  if font then return font end
  serial = serial + 1
  font = CreateFont("NorgannonCoreFont" .. serial)
  font:SetFont(FILES[role] or FILES.body, size, flags or "")
  font:SetShadowOffset(1, -1)
  font:SetShadowColor(0, 0, 0, .9)
  fonts[key] = font
  return font
end

---A FontString in a role and colour: UI.Text(parent, "body", 13, UI.C.muted).
function UI.Text(parent, role, size, color, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFontObject(UI.Font(role, size))
  local c = color or UI.C.text
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  return fs
end

---A soft outer glow behind a FontString (default black): faint copies of the text in two rings,
---1 px out and 2 px out, drawn under it. They follow the text, font and visibility of the
---original. Turns the FontString's own drop shadow off. Returns the copies.
local GLOW_RINGS = { { 1, .42 }, { 2, .14 } }   -- radius, opacity of each copy
local GLOW_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { .71, .71 }, { -.71, .71 }, { .71, -.71 }, { -.71, -.71 } }
function UI.Glow(fs, color, strength)
  if fs.glow then return fs.glow end
  local c = color or UI.C.black
  local parent = fs:GetParent()
  local copies = {}
  for _, ring in ipairs(GLOW_RINGS) do
    for _, d in ipairs(GLOW_DIRS) do
      local g = parent:CreateFontString(nil, "ARTWORK")
      g:SetFontObject(fs:GetFontObject())
      g:SetJustifyH(fs:GetJustifyH())
      g:SetWordWrap(false)
      g:SetShadowOffset(0, 0)
      g:SetTextColor(c[1], c[2], c[3], ring[2] * (strength or 1))
      g:SetPoint("CENTER", fs, "CENTER", d[1] * ring[1], d[2] * ring[1])
      copies[#copies + 1] = g
    end
  end
  fs:SetShadowOffset(0, 0)
  fs.glow = copies
  hooksecurefunc(fs, "SetText", function(_, text) for _, g in ipairs(copies) do g:SetText(text) end end)
  hooksecurefunc(fs, "SetFontObject", function(_, font) for _, g in ipairs(copies) do g:SetFontObject(font) end end)
  hooksecurefunc(fs, "Show", function() for _, g in ipairs(copies) do g:Show() end end)
  hooksecurefunc(fs, "Hide", function() for _, g in ipairs(copies) do g:Hide() end end)
  hooksecurefunc(fs, "SetShown", function(_, on) for _, g in ipairs(copies) do g:SetShown(on) end end)
  local text = fs:GetText()
  if text then for _, g in ipairs(copies) do g:SetText(text) end end
  return copies
end

-------------------------------------------------------------------------------------------
-- Quest difficulty colour, the game's rules
-------------------------------------------------------------------------------------------

-- The game's own colour classes (QuestDifficultyColors keys) mapped to our palette.
local GAME_CLASSES = { impossible = "impossible", verydifficult = "hard", difficult = "fair", standard = "easy", trivial = "trivial" }

-- Asks the client, so we match the quest log exactly (Forever's rules may differ from Era's).
local function gameDifficulty(level)
  if not (GetQuestDifficultyColor and QuestDifficultyColors) then return end
  local ok, c = pcall(GetQuestDifficultyColor, level)
  if not ok or type(c) ~= "table" or Core.IsSecret(c) then return end
  for key, ours in pairs(GAME_CLASSES) do
    local g = QuestDifficultyColors[key]
    if g == c or (g and g.r == c.r and g.g == c.g and g.b == c.b) then return UI.C[ours] end
  end
end

-- Classic rules, for clients without the API (and the offline harness).
local function greenRange(level)
  if level <= 5 then return 5 elseif level <= 39 then return 5 + math.floor(level / 10) end
  return 1 + math.floor(level / 5)
end

---Colour for content of a level, as the game colours quests for the player.
---playerLevel is only used when the client can't tell us (it always rates the player).
function UI.Difficulty(level, playerLevel)
  if not level or level <= 0 then return UI.C.muted end
  local game = playerLevel == UnitLevel("player") and gameDifficulty(level)
  if game then return game end
  local diff = level - playerLevel
  if diff >= 5 then return UI.C.impossible end
  if diff >= 3 then return UI.C.hard end
  if diff >= -2 then return UI.C.fair end
  if -diff <= greenRange(playerLevel) then return UI.C.easy end
  return UI.C.trivial
end
