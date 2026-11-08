-- UI.ActionList and UI.Input (1.20). The list of rows Council and Muster each built their own copy of: a title, a line
-- under it, text on the right and buttons at the end, with an item's icon and tooltip when the row is an item.

local Core = NorgannonCore
local UI = Core.UI
local C = UI.C

local ROW_H = 38
local BUTTON_W, BUTTON_H, BUTTON_GAP = 72, 22, 4
local ICON = 24

local function tip(owner, text)
  if type(text) == "function" then text = text() end
  if not text or text == "" then return end
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  GameTooltip:AddLine(text, 1, 1, 1, true)
  GameTooltip:Show()
end
UI.Tip = tip

local function actionButton(row, i)
  local b = UI.Button(row, "", "quiet", function(self)
    local action = self.action
    if action and not action.off then action.run(IsShiftKeyDown and IsShiftKeyDown()) end
  end)
  b:SetHeight(BUTTON_H)
  b:SetScript("OnEnter", function(self) tip(self, self.action and self.action.tip) end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row.buttons[i] = b
  return b
end

local function createRow(row, content)
  row.buttons = {}
  row.icon = content:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ICON, ICON)
  row.icon:SetPoint("LEFT", 8, 0)
  row.icon:SetTexCoord(.07, .93, .07, .93)
  row.title = UI.Text(content, "body", 14)
  row.title:SetWordWrap(false)
  row.sub = UI.Text(content, "body", 12, C.muted)
  row.sub:SetWordWrap(false)
  row.right = UI.Text(content, "body", 12, C.muted)
  row.right:SetJustifyH("RIGHT")
end

local function itemIcon(item)
  if item.icon then return item.icon end
  if item.id then return Core.In("C_Item", "GetItemIconByID", item.id) or 134400 end
end

local function updateRow(row, item, titleY)
  local icon = itemIcon(item)
  row.icon:SetShown(icon ~= nil)
  if icon then row.icon:SetTexture(icon) end
  local left = icon and (ICON + 16) or 10
  local hasSub = item.sub ~= nil and item.sub ~= ""
  local top = hasSub and -4 or titleY
  row.title:SetText(item.title or "")
  row.sub:SetText(item.sub or "")

  local previous, reserve = nil, 12
  for i = 1, math.max(#row.buttons, #(item.actions or {})) do
    local action = item.actions and item.actions[i]
    local b = row.buttons[i] or (action and actionButton(row, i))
    if b then
      b.action = action
      b:SetShown(action ~= nil)
      if action then
        local width = action.width or BUTTON_W
        b:SetLabel(action.text)
        b:SetWidth(width)
        b:SetAlpha(action.off and .4 or 1)
        b:ClearAllPoints()
        if previous then b:SetPoint("RIGHT", previous, "LEFT", -BUTTON_GAP, 0) else b:SetPoint("RIGHT", row, "RIGHT", -12, 0) end
        previous = b
        reserve = reserve + width + BUTTON_GAP
      end
    end
  end
  row.right:ClearAllPoints()
  if previous then row.right:SetPoint("RIGHT", previous, "LEFT", -10, 0) else row.right:SetPoint("RIGHT", row, "RIGHT", -12, 0) end
  row.right:SetText(item.right or "")
  if item.right and item.right ~= "" then reserve = reserve + math.floor(row.right:GetStringWidth()) + 18 end

  -- the title and the line under it stop short of the buttons and the right-hand text
  row.title:ClearAllPoints()
  row.title:SetPoint("TOPLEFT", row, "TOPLEFT", left, top)
  row.title:SetPoint("TOPRIGHT", row, "TOPRIGHT", -reserve, top)
  row.sub:ClearAllPoints()
  row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
  row.sub:SetPoint("TOPRIGHT", row.title, "BOTTOMRIGHT", 0, -2)
end

---A virtual list of action rows. Items: { group = "Heading" } for a section header, or
---{ title, sub, right, id (an item: its icon and tooltip), link, icon, tip (text or fn), onClick(button),
---  actions = { { text, run(shift), off, tip (text or fn), width } } }. Buttons run right to left from the row's end.
---opts: rowHeight (38), groupBand (true). Returns a UI.List (:SetData, :Refresh, ...).
function UI.ActionList(parent, opts)
  opts = opts or {}
  local height = opts.rowHeight or ROW_H
  local titleY = -math.floor((height - 14) / 2)
  return UI.List(parent, {
    rowHeight = height,
    createRow = createRow,
    updateRow = function(row, item) updateRow(row, item, titleY) end,
    groupBand = opts.groupBand ~= false,
    onClick = function(item, _, button) if item.onClick then item.onClick(button) end end,
    onEnter = function(row, item)
      if item.id or item.link then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if item.link then GameTooltip:SetHyperlink(item.link) else GameTooltip:SetItemByID(item.id) end
        GameTooltip:Show()
      elseif item.tip then
        tip(row, item.tip)
      end
    end,
    onLeave = function() GameTooltip:Hide() end,
  })
end

---A text field in the suite's look (an inset pane), single line or multi-line. onChange(text) on every edit the player
---makes; onSubmit(text) on Enter (single line). Methods :SetText, :GetText, :SetFocus, :ClearFocus; .edit is the EditBox.
function UI.Input(parent, opts)
  opts = opts or {}
  local holder = UI.Pane(parent)
  local edit = CreateFrame("EditBox", nil, holder)
  edit:SetAutoFocus(false)
  edit:SetFontObject(UI.Font("body", opts.size or 13))
  edit:SetTextColor(C.text[1], C.text[2], C.text[3])
  edit:SetTextInsets(6, 6, 4, 4)
  edit:SetPoint("TOPLEFT", 2, -2)
  edit:SetPoint("BOTTOMRIGHT", -2, 2)
  if opts.multiline then edit:SetMultiLine(true) end
  if opts.maxLetters then edit:SetMaxLetters(opts.maxLetters) end
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  if not opts.multiline then
    edit:SetScript("OnEnterPressed", function(self)
      self:ClearFocus()
      if opts.onSubmit then opts.onSubmit(self:GetText()) end
    end)
  end
  edit:SetScript("OnTextChanged", function(self, user) if user and opts.onChange then opts.onChange(self:GetText()) end end)
  holder.edit = edit
  function holder:SetText(text) edit:SetText(text or "") end
  function holder:GetText() return edit:GetText() end
  function holder:SetFocus() edit:SetFocus() end
  function holder:ClearFocus() edit:ClearFocus() end
  return holder
end
