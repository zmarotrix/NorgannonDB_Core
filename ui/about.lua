-- The "Powered by NorgannonDB" card: what NorgannonDB is (an open, crowd-sourced database)
-- and an invitation to contribute with the Collector. Opens from any window's Powered line.

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

local WIDTH = 340
local card

local function plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

local function collectorStats()
  local collector = _G.NorgannonDBCollector
  if not (collector and collector.Stats and collector.sv) then return nil end
  local ok, s = pcall(collector.Stats)
  return ok and s or nil
end

local function build()
  local f = CreateFrame("Frame", "NorgannonCoreAbout", UIParent)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:SetWidth(WIDTH)
  f.box = UI.Box(f, "BACKGROUND", 0)
  f.box:Set(C.frameGold, { .114, .09, .067 }, { .06, .047, .035 })
  local glow = UI.Tex(f, "BACKGROUND", 2)
  glow:SetPoint("TOPLEFT", 1, -1)
  glow:SetPoint("TOPRIGHT", -1, -1)
  glow:SetHeight(70)
  UI.Gradient(glow, C.goldSoft, C.goldSoft, .1, 0)

  f.mark = UI.Mark(f, "norgannondb", 36)
  f.mark:SetPoint("TOPLEFT", 14, -14)
  f.title = UI.Text(f, "title", 19, C.goldSoft)
  f.title:SetPoint("TOPLEFT", f.mark, "TOPRIGHT", 10, -2)
  f.title:SetText("NorgannonDB")
  f.tagline = UI.Text(f, "body", 12, C.muted)
  f.tagline:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
  f.tagline:SetText("Open, crowd-sourced game data")
  f.close = UI.CloseButton(f, function() f:Hide() end)
  f.close:SetSize(18, 18)
  f.close:SetPoint("TOPRIGHT", -8, -8)

  f.about = UI.Text(f, "body", 13, C.text)
  f.about:SetPoint("TOPLEFT", f.mark, "BOTTOMLEFT", 0, -12)
  f.about:SetWidth(WIDTH - 28)
  f.about:SetWordWrap(true)
  f.about:SetText("One open database of the quests, NPCs, objects, items, drops and spawns in WoW Forever. "
    .. "Every suite addon reads from it, and any other addon is welcome to. It is free and open source, "
    .. "and it grows from what players see in the game.")

  f.rule = UI.Rule(f)
  f.rule:SetPoint("TOPLEFT", f.about, "BOTTOMLEFT", 0, -12)
  f.rule:SetWidth(WIDTH - 28)

  local green = UI.Accent("collector")
  f.cmark = UI.Mark(f, "collector", 28)
  f.cmark:SetPoint("TOPLEFT", f.rule, "BOTTOMLEFT", 0, -12)
  f.chead = UI.Text(f, "title", 15, green)
  f.chead:SetPoint("LEFT", f.cmark, "RIGHT", 10, 0)
  f.ctext = UI.Text(f, "body", 13, C.text)
  f.ctext:SetPoint("TOPLEFT", f.cmark, "BOTTOMLEFT", 0, -8)
  f.ctext:SetWidth(WIDTH - 28)
  f.ctext:SetWordWrap(true)

  f.action = UI.Button(f, "Export my data", "quiet", function()
    local collector = _G.NorgannonDBCollector
    if collector and collector.ShowExport then
      f:Hide()
      collector.ShowExport()
    end
  end)
  f.action:SetPoint("TOPLEFT", f.ctext, "BOTTOMLEFT", 0, -10)
  f.credit = UI.Text(f, "body", 11, C.faint)
  f.credit:SetPoint("BOTTOMRIGHT", -14, 12)
  f.credit:SetText("Made by Maro")

  function f:Refresh()
    local state = Core:AddonState("collector")
    local stats = state == "loaded" and collectorStats()
    if stats then
      self.chead:SetText("Thank you for helping map Azeroth")
      self.ctext:SetText(string.format("You have recorded %s, %s, %s and %s. Send them in with the button below "
        .. "(or /ndbc export) now and then.", plural(stats.npcs, "NPC"), plural(stats.objects, "object"),
        plural(stats.quests, "quest"), plural(stats.items, "item")))
      self.action:Show()
    elseif state == "installed" then
      self.chead:SetText("Help map Azeroth")
      self.ctext:SetText("NorgannonDB Collector is installed but turned off. Turn it on in the AddOns list "
        .. "on the character screen to start contributing.")
      self.action:Hide()
    else
      self.chead:SetText("Help map Azeroth")
      self.ctext:SetText("Install NorgannonDB Collector. It quietly records the NPCs, quests and drops you see "
        .. "as you play: no setup, nothing recorded in combat, and no character names. Every contribution "
        .. "makes the database more accurate for everyone.")
      self.action:Hide()
    end
    -- size to the text
    local h = 14 + 36 + 12 + (self.about:GetStringHeight() or 60) + 12 + 1 + 12 + 28 + 8
      + (self.ctext:GetStringHeight() or 60) + (self.action:IsShown() and 34 or 0) + 34
    self:SetHeight(math.floor(h))
  end

  table.insert(UISpecialFrames, "NorgannonCoreAbout")
  f:Hide()
  return f
end

---Shows the NorgannonDB card next to anchor (a Powered line), or hides it if it is open there.
function Core:ShowAbout(anchor)
  card = card or build()
  if card:IsShown() and card.anchor == anchor then
    card:Hide()
    return card
  end
  card.anchor = anchor
  card:ClearAllPoints()
  if anchor then
    card:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -10)
  else
    card:SetPoint("CENTER")
  end
  card:Refresh()
  card:Show()
  self.aboutCard = card
  return card
end
