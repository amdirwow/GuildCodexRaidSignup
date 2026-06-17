local APP_PREFIX = "GCRSIG"
local APP_NAME = "Guild Codex: рейди"

local RAID_SIZES = {5, 10, 15, 20, 25, 30, 35, 40}
local ROLE_CODE = { tank = "t", heal = "h", mdd = "m", rdd = "r" }
local ROLE_FROM_CODE = { t = "tank", h = "heal", d = "mdd", m = "mdd", r = "rdd" }

local ROLES = {
    { key = "tank", label = "Танки", short = "Т", icon = "Interface\\Icons\\Ability_Defend", classes = {1, 6, 2, 11} },
    { key = "heal", label = "Хіли", short = "Х", icon = "Interface\\Icons\\Spell_Holy_FlashHeal", classes = {7, 5, 11, 2} },
    { key = "mdd", label = "МДД", short = "М", icon = "Interface\\Icons\\Ability_DualWield", classes = {1, 6, 4, 2, 7, 11} },
    { key = "rdd", label = "РДД", short = "Р", icon = "Interface\\Icons\\Spell_Fire_Fireball02", classes = {9, 5, 8, 3, 7, 11} },
}

local CLASSES = {
    [1] = { id = 1, label = "Воїн", color = {0.78, 0.61, 0.43}, icon = "Interface\\Icons\\INV_Sword_27" },
    [2] = { id = 2, label = "Паладін", color = {0.96, 0.55, 0.73}, icon = "Interface\\Icons\\Spell_Holy_SealOfMight" },
    [3] = { id = 3, label = "Мисливець", color = {0.67, 0.83, 0.45}, icon = "Interface\\Icons\\INV_Weapon_Bow_07" },
    [4] = { id = 4, label = "Розбійник", color = {1.00, 0.96, 0.41}, icon = "Interface\\Icons\\INV_ThrowingKnife_04" },
    [5] = { id = 5, label = "Прист", color = {1.00, 1.00, 1.00}, icon = "Interface\\Icons\\Spell_Holy_PowerWordShield" },
    [6] = { id = 6, label = "ДК", color = {0.77, 0.12, 0.23}, icon = "Interface\\Icons\\Spell_Deathknight_ClassIcon" },
    [7] = { id = 7, label = "Шаман", color = {0.00, 0.44, 0.87}, icon = "Interface\\Icons\\Spell_Nature_BloodLust" },
    [8] = { id = 8, label = "Маг", color = {0.41, 0.80, 0.94}, icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    [9] = { id = 9, label = "Варлок", color = {0.58, 0.51, 0.79}, icon = "Interface\\Icons\\Spell_Nature_FaerieFire" },
    [11] = { id = 11, label = "Друїд", color = {1.00, 0.49, 0.04}, icon = "Interface\\Icons\\Ability_Druid_Maul" },
}

local State = {
    mode = "simple",
    raidSize = 25,
    repeatWeekly = false,
    selectedTemplate = nil,
    selectedEvent = nil,
    selectedEventId = 0,
    formMode = "new",
    signups = {},
    templates = {},
    events = {},
    simple = { tank = 2, heal = 5, mdd = 8, rdd = 10 },
    advanced = {},
    dayOffset = 0,
    hour = 20,
    minute = 0,
}

local roleByKey = {}
for _, role in ipairs(ROLES) do roleByKey[role.key] = role end

local WEEKDAYS = { "Нд", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб" }

local function GetDB()
    if type(GuildCodexRaidSignupDB) ~= "table" then GuildCodexRaidSignupDB = {} end
    return GuildCodexRaidSignupDB
end

local function Trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SplitTabs(s)
    local out, start = {}, 1
    s = tostring(s or "")
    while true do
        local pos = string.find(s, "\t", start, true)
        if not pos then out[#out + 1] = string.sub(s, start); break end
        out[#out + 1] = string.sub(s, start, pos - 1)
        start = pos + 1
    end
    return out
end

local function SendToServer(payload)
    payload = tostring(payload or "")

    -- У 3.3.5 addon-message бажано тримати коротким.
    -- Якщо payload занадто довгий, краще не слати битий/обрізаний пакет.
    if string.len(payload) > 240 then
        Notice("Запит до сервера занадто довгий: " .. tostring(string.len(payload)) .. " байт.", 1, 0.25, 0.25)
        return
    end

    local playerName = UnitName("player")
    if not playerName or playerName == "" then
        return
    end

    SendAddonMessage(APP_PREFIX, payload, "WHISPER", playerName)
end

local function Notice(text, r, g, b)
    if UIErrorsFrame then UIErrorsFrame:AddMessage(text, r or 1, g or 0.85, b or 0.2, 1) end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[Кодекс]|r " .. text)
end

local function SaveFramePosition(frame)
    local db = GetDB()
    db.frame = db.frame or {}
    local fx, fy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if fx and fy and ux and uy then db.frame.x = fx - ux; db.frame.y = fy - uy end
end

local function PlaceFrame(frame)
    local db = GetDB()
    frame:ClearAllPoints()
    if db.frame and db.frame.x and db.frame.y then
        frame:SetPoint("CENTER", UIParent, "CENTER", db.frame.x, db.frame.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function CreateWindow()
    local frame = CreateFrame("Frame", "GuildCodexRaidSignupFrame", UIParent)
    frame:SetSize(930, 680)
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetFrameLevel(7)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SaveFramePosition(self) end)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.03, 0.04, 0.06, 0.97)
    frame:SetBackdropBorderColor(0.45, 0.39, 0.18, 1)

    frame.closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.closeBtn:SetPoint("TOPRIGHT", -6, -6)

    frame.header = CreateFrame("Frame", nil, frame)
    frame.header:SetPoint("TOPLEFT", 12, -12)
    frame.header:SetPoint("TOPRIGHT", -12, -12)
    frame.header:SetHeight(58)
    frame.header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    frame.header:SetBackdropColor(0.12, 0.10, 0.06, 0.94)

    frame.title = frame.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.title:SetPoint("TOPLEFT", 14, -8)
    frame.title:SetText(APP_NAME)

    frame.subtitle = frame.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.subtitle:SetPoint("TOPLEFT", 14, -31)
    frame.subtitle:SetText("Створення запису РЛом")

    frame.status = frame.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.status:SetPoint("RIGHT", -14, 0)
    frame.status:SetText("Очікування сервера")
    frame:Hide()
    return frame
end

local function CreatePanel(parent, x, y, w, h)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", x, y)
    panel:SetSize(w, h)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 11,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    panel:SetBackdropColor(0.055, 0.065, 0.085, 0.88)
    panel:SetBackdropBorderColor(0.25, 0.22, 0.13, 0.9)
    return panel
end

local function Label(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function EditBox(parent, x, y, w)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetPoint("TOPLEFT", x, y)
    box:SetSize(w, 24)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetTextInsets(6, 6, 0, 0)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    box:SetBackdropColor(0.015, 0.018, 0.025, 0.96)
    box:SetBackdropBorderColor(0.36, 0.32, 0.18, 0.85)
    return box
end

local function SetButtonEnabled(button, enabled)
    if button.SetEnabled then button:SetEnabled(enabled)
    elseif enabled then button:Enable()
    else button:Disable() end
end

local function SetVisible(frame, visible)
    if not frame then return end
    if visible then frame:Show() else frame:Hide() end
end

local Frame = CreateWindow()
local TemplatesPanel = CreatePanel(Frame, 14, -84, 230, 570)
local FormPanel = CreatePanel(Frame, 256, -84, 660, 570)

local raidsHeader = Label(TemplatesPanel, "Мої рейди", 12, -12, "GameFontHighlight")
local newRaidBtn = CreateFrame("Button", nil, TemplatesPanel, "UIPanelButtonTemplate")
newRaidBtn:SetPoint("TOPRIGHT", -14, -8)
newRaidBtn:SetSize(70, 22)
newRaidBtn:SetText("Новий")
local templatesHeader = Label(TemplatesPanel, "Мої шаблони", 12, -302, "GameFontHighlight")
local newTemplateBtn = CreateFrame("Button", nil, TemplatesPanel, "UIPanelButtonTemplate")
newTemplateBtn:SetPoint("TOPRIGHT", -14, -298)
newTemplateBtn:SetSize(70, 22)
newTemplateBtn:SetText("Новий")
local templateScroll = CreateFrame("ScrollFrame", "GuildCodexRaidSignupTemplateScroll", TemplatesPanel, "UIPanelScrollFrameTemplate")
templateScroll:SetPoint("TOPLEFT", 8, -36)
templateScroll:SetPoint("BOTTOMRIGHT", TemplatesPanel, "TOPRIGHT", -28, -288)
local templateContent = CreateFrame("Frame", nil, templateScroll)
templateContent:SetSize(185, 245)
templateScroll:SetScrollChild(templateContent)
local templateListScroll = CreateFrame("ScrollFrame", "GuildCodexRaidSignupTemplateListScroll", TemplatesPanel, "UIPanelScrollFrameTemplate")
templateListScroll:SetPoint("TOPLEFT", 8, -326)
templateListScroll:SetPoint("BOTTOMRIGHT", -28, 10)
local templateListContent = CreateFrame("Frame", nil, templateListScroll)
templateListContent:SetSize(185, 230)
templateListScroll:SetScrollChild(templateListContent)

local raidNameLabel = Label(FormPanel, "Назва рейду", 14, -14)
local raidNameBox = EditBox(FormPanel, 14, -34, 220)
raidNameBox:SetText("ЦКК 25")

local dateLabel = Label(FormPanel, "Дата", 252, -14)
local dateText = Label(FormPanel, "", 294, -16, "GameFontHighlight")
dateText:SetWidth(92)
local datePrev = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
datePrev:SetPoint("TOPLEFT", 252, -34)
datePrev:SetSize(28, 22)
datePrev:SetText("<")
local dateNext = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
dateNext:SetPoint("TOPLEFT", 392, -34)
dateNext:SetSize(28, 22)
dateNext:SetText(">")
local dateToday = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
dateToday:SetPoint("TOPLEFT", 286, -34)
dateToday:SetSize(100, 22)
dateToday:SetText("Сьогодні")

local timeLabel = Label(FormPanel, "Час", 438, -14)
local hourMinus = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
hourMinus:SetPoint("TOPLEFT", 438, -34)
hourMinus:SetSize(24, 22)
hourMinus:SetText("-")
local hourText = Label(FormPanel, "", 468, -38, "GameFontHighlight")
hourText:SetWidth(22)
local hourPlus = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
hourPlus:SetPoint("TOPLEFT", 492, -34)
hourPlus:SetSize(24, 22)
hourPlus:SetText("+")
local minuteMinus = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
minuteMinus:SetPoint("TOPLEFT", 528, -34)
minuteMinus:SetSize(24, 22)
minuteMinus:SetText("-")
local minuteText = Label(FormPanel, "", 558, -38, "GameFontHighlight")
minuteText:SetWidth(22)
local minutePlus = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
minutePlus:SetPoint("TOPLEFT", 580, -34)
minutePlus:SetSize(24, 22)
minutePlus:SetText("+")

local raidSizeLabel = Label(FormPanel, "Розмір", 14, -72)
local sizeButtons = {}
for i, size in ipairs(RAID_SIZES) do
    local b = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
    b:SetSize(34, 22)
    b:SetPoint("TOPLEFT", 74 + (i - 1) * 38, -70)
    b:SetText(tostring(size))
    b:SetScript("OnClick", function() State.raidSize = size; RefreshAll() end)
    sizeButtons[#sizeButtons + 1] = b
end

local repeatCheck = CreateFrame("CheckButton", nil, FormPanel, "UICheckButtonTemplate")
repeatCheck:SetPoint("TOPLEFT", 390, -68)
repeatCheck.text = repeatCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
repeatCheck.text:SetPoint("LEFT", repeatCheck, "RIGHT", -2, 1)
repeatCheck.text:SetText("повтор")
repeatCheck:SetScript("OnClick", function(self) State.repeatWeekly = self:GetChecked() and true or false end)

local modeSimple = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
modeSimple:SetPoint("TOPLEFT", 14, -128)
modeSimple:SetSize(100, 24)
modeSimple:SetText("Простий")
local modeAdvanced = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
modeAdvanced:SetPoint("LEFT", modeSimple, "RIGHT", 8, 0)
modeAdvanced:SetSize(120, 24)
modeAdvanced:SetText("Розширений")
local resetBtn = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
resetBtn:SetPoint("LEFT", modeAdvanced, "RIGHT", 12, 0)
resetBtn:SetSize(90, 24)
resetBtn:SetText("Скинути")
local summary = Label(FormPanel, "", 450, -132, "GameFontDisableSmall")
summary:SetWidth(190)
summary:SetJustifyH("RIGHT")

local SlotsPanel = CreatePanel(FormPanel, 14, -164, 390, 320)
SlotsPanel:SetBackdropColor(0.03, 0.035, 0.05, 0.65)
local SlotsScroll = CreateFrame("ScrollFrame", "GuildCodexRaidSignupSlotsScroll", SlotsPanel, "UIPanelScrollFrameTemplate")
SlotsScroll:SetPoint("TOPLEFT", 6, -8)
SlotsScroll:SetPoint("BOTTOMRIGHT", -28, 8)
local SlotsContent = CreateFrame("Frame", nil, SlotsScroll)
SlotsContent:SetSize(342, 760)
SlotsScroll:SetScrollChild(SlotsContent)

local SignupsPanel = CreatePanel(FormPanel, 414, -164, 230, 320)
SignupsPanel:SetBackdropColor(0.03, 0.035, 0.05, 0.65)
Label(SignupsPanel, "Підписники", 10, -10, "GameFontHighlight")
local signupSummary = Label(SignupsPanel, "", 10, -30, "GameFontDisableSmall")
signupSummary:SetWidth(205)
signupSummary:SetJustifyH("LEFT")
local SignupsScroll = CreateFrame("ScrollFrame", "GuildCodexRaidSignupSignupsScroll", SignupsPanel, "UIPanelScrollFrameTemplate")
SignupsScroll:SetPoint("TOPLEFT", 8, -52)
SignupsScroll:SetPoint("BOTTOMRIGHT", -28, 8)
local SignupsContent = CreateFrame("Frame", nil, SignupsScroll)
SignupsContent:SetSize(185, 250)
SignupsScroll:SetScrollChild(SignupsContent)

local simpleRows, advancedRows, advancedGrid = {}, {}, {}
local createBtn, deleteBtn, inviteBtn, refreshBtn
local saveTemplateLabel, saveTemplateName, saveTemplateBtn

local function SlotValue(role, classId)
    if State.mode == "simple" then return State.simple[role] or 0 end
    State.advanced[role] = State.advanced[role] or {}
    return State.advanced[role][classId] or 0
end

local function SetSlotValue(role, classId, value)
    value = tonumber(value) or 0
    if value < 0 then value = 0 end
    if value > 40 then value = 40 end
    if State.mode == "simple" then State.simple[role] = value
    else State.advanced[role] = State.advanced[role] or {}; State.advanced[role][classId] = value end
end

local function ClosestRaidSize(total)
    for _, size in ipairs(RAID_SIZES) do
        if total <= size then return size end
    end
    return 40
end

local function CurrentSlots()
    local slots = {}
    if State.mode == "simple" then
        for _, role in ipairs(ROLES) do
            local count = tonumber(State.simple[role.key] or 0) or 0
            if count > 0 then slots[#slots + 1] = { role = role.key, classId = 0, count = count } end
        end
    else
        for _, role in ipairs(ROLES) do
            local byClass = State.advanced[role.key] or {}
            for _, classId in ipairs(role.classes) do
                local count = tonumber(byClass[classId] or 0) or 0
                if count > 0 then slots[#slots + 1] = { role = role.key, classId = classId, count = count } end
            end
        end
    end
    return slots
end

local function CountTotal()
    local total = 0
    for _, slot in ipairs(CurrentSlots()) do total = total + (slot.count or 0) end
    return total
end

local function EncodeSlots()
    local out = {}
    for _, slot in ipairs(CurrentSlots()) do
        out[#out + 1] = string.format("%s%d=%d", ROLE_CODE[slot.role], slot.classId or 0, slot.count or 0)
    end
    return table.concat(out, ",")
end

local function DecodeSlots(spec)
    local slots = {}
    for raw in string.gmatch(spec or "", "[^;,]+") do
        local role, classId, count = raw:match("^([%a_]+):(%d+):(%d+)$")
        if role == "dd" then role = "mdd" end
        if not role then
            local code
            code, classId, count = raw:match("^([thdmr])(%d*)=(%d+)$")
            role = ROLE_FROM_CODE[code or ""]
        end
        if role and roleByKey[role] then
            slots[#slots + 1] = { role = role, classId = tonumber(classId) or 0, count = tonumber(count) or 0 }
        end
    end
    return slots
end

local function SlotSummary(spec)
    local totals = { tank = 0, heal = 0, mdd = 0, rdd = 0 }
    for _, slot in ipairs(DecodeSlots(spec)) do totals[slot.role] = (totals[slot.role] or 0) + (slot.count or 0) end
    return string.format("Т%d Х%d М%d Р%d", totals.tank, totals.heal, totals.mdd, totals.rdd)
end

local function StartText()
    local ts = time() + State.dayOffset * 86400
    return date("%d.%m", ts) .. string.format(" %02d:%02d", State.hour, State.minute)
end

local function ApplyStartTs(ts)
    ts = tonumber(ts or 0) or 0
    if ts <= 0 then return end
    local nowDay = date("*t", time())
    nowDay.hour, nowDay.min, nowDay.sec = 0, 0, 0
    local evDay = date("*t", ts)
    evDay.hour, evDay.min, evDay.sec = 0, 0, 0
    State.dayOffset = math.max(0, math.floor((time(evDay) - time(nowDay)) / 86400 + 0.5))
    local t = date("*t", ts)
    State.hour = t.hour or State.hour
    State.minute = t.min or State.minute
end

local function ResetSlots()
    State.simple = { tank = 0, heal = 0, mdd = 0, rdd = 0 }
    State.advanced = {}
end

local function DefaultSlotsForSize(size)
    ResetSlots()
    State.simple.tank = size >= 10 and 2 or 1
    State.simple.heal = size >= 25 and 5 or (size >= 10 and 2 or 1)
    local rest = size - State.simple.tank - State.simple.heal
    State.simple.mdd = math.floor(rest * 0.45)
    State.simple.rdd = rest - State.simple.mdd
end

function RefreshAll()
    local templateMode = State.formMode == "template" or State.formMode == "newTemplate"
    local editing = State.formMode == "edit" and State.selectedEvent and State.selectedEvent.id
    local total = CountTotal()
    local ok = total == State.raidSize
    local color = ok and "|cff55ff55" or (total > State.raidSize and "|cffff5555" or "|cffffff99")
    summary:SetText(color .. "Склад: " .. total .. "/" .. State.raidSize .. "|r")
    local selectedDay = time() + State.dayOffset * 86400
    local weekday = WEEKDAYS[tonumber(date("%w", selectedDay)) + 1] or ""
    dateText:SetText(weekday .. " " .. date("%d.%m", selectedDay))
    hourText:SetText(string.format("%02d", State.hour))
    minuteText:SetText(string.format("%02d", State.minute))
    repeatCheck:SetChecked(State.repeatWeekly)

    for i, b in ipairs(sizeButtons) do SetButtonEnabled(b, RAID_SIZES[i] ~= State.raidSize) end
    local simple = State.mode == "simple"
    for _, row in ipairs(simpleRows) do if simple then row:Show() else row:Hide() end end
    for _, row in ipairs(advancedRows) do if simple then row:Hide() else row:Show() end end
    for _, row in ipairs(simpleRows) do row.value:SetText(tostring(SlotValue(row.role, 0))) end
    for _, cell in ipairs(advancedGrid) do cell.value:SetText(tostring(SlotValue(cell.role, cell.classId))) end
    SetButtonEnabled(modeSimple, not simple)
    SetButtonEnabled(modeAdvanced, simple)
    SlotsContent:SetHeight(simple and 230 or 860)
    createBtn:SetText(editing and "Зберегти" or "Створити рейд")
    SetVisible(raidNameLabel, not templateMode)
    SetVisible(raidNameBox, not templateMode)
    SetVisible(dateLabel, not templateMode)
    SetVisible(dateText, not templateMode)
    SetVisible(datePrev, not templateMode)
    SetVisible(dateToday, not templateMode)
    SetVisible(dateNext, not templateMode)
    SetVisible(timeLabel, not templateMode)
    SetVisible(hourMinus, not templateMode)
    SetVisible(hourText, not templateMode)
    SetVisible(hourPlus, not templateMode)
    SetVisible(minuteMinus, not templateMode)
    SetVisible(minuteText, not templateMode)
    SetVisible(minutePlus, not templateMode)
    SetVisible(repeatCheck, not templateMode)
    SetVisible(SignupsPanel, editing)
    SetVisible(createBtn, not templateMode)
    SetVisible(deleteBtn, editing)
    SetVisible(inviteBtn, editing)
    SetVisible(refreshBtn, not templateMode)
    SetVisible(saveTemplateLabel, templateMode)
    SetVisible(saveTemplateName, templateMode)
    SetVisible(saveTemplateBtn, templateMode)
end

local function MakeCounter(parent, role, classId, x, y, label, icon, color)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", x, y)
    row:SetSize(330, 30)
    row.role, row.classId = role, classId
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetSize(22, 22)
    row.icon:SetTexture(icon)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.label:SetWidth(160)
    row.label:SetJustifyH("LEFT")
    row.label:SetText(label)
    if color then row.label:SetTextColor(color[1], color[2], color[3]) end
    row.minus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.minus:SetPoint("LEFT", row.label, "RIGHT", 4, 0)
    row.minus:SetSize(26, 22)
    row.minus:SetText("-")
    row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.value:SetPoint("LEFT", row.minus, "RIGHT", 8, 0)
    row.value:SetWidth(24)
    row.value:SetJustifyH("CENTER")
    row.plus = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.plus:SetPoint("LEFT", row.value, "RIGHT", 8, 0)
    row.plus:SetSize(26, 22)
    row.plus:SetText("+")
    row.minus:SetScript("OnClick", function() SetSlotValue(role, classId, SlotValue(role, classId) - 1); RefreshAll() end)
    row.plus:SetScript("OnClick", function()
        if CountTotal() >= State.raidSize then
            Notice("Досягнуто максимум рейду.", 1, 0.25, 0.25)
            return
        end
        SetSlotValue(role, classId, SlotValue(role, classId) + 1)
        RefreshAll()
    end)
    return row
end

for i, role in ipairs(ROLES) do
    simpleRows[#simpleRows + 1] = MakeCounter(SlotsContent, role.key, 0, 18, -12 - (i - 1) * 42, role.label, role.icon)
end

local y = -14
for _, role in ipairs(ROLES) do
    local header = SlotsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 14, y)
    header:SetText(role.label)
    advancedRows[#advancedRows + 1] = header
    y = y - 28
    for _, classId in ipairs(role.classes) do
        local cls = CLASSES[classId]
        local cell = MakeCounter(SlotsContent, role.key, classId, 52, y, cls.label, cls.icon, cls.color)
        advancedRows[#advancedRows + 1] = cell
        advancedGrid[#advancedGrid + 1] = cell
        y = y - 34
    end
    y = y - 12
end

saveTemplateLabel = Label(FormPanel, "Назва шаблону", 14, -500)
saveTemplateName = EditBox(FormPanel, 120, -496, 190)
saveTemplateName:SetText("ЦКК 25")
saveTemplateBtn = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
saveTemplateBtn:SetPoint("LEFT", saveTemplateName, "RIGHT", 10, 0)
saveTemplateBtn:SetSize(135, 24)
saveTemplateBtn:SetText("Зберегти шаблон")

createBtn = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
createBtn:SetPoint("BOTTOMRIGHT", -16, 16)
createBtn:SetSize(150, 28)
createBtn:SetText("Створити рейд")
deleteBtn = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
deleteBtn:SetPoint("RIGHT", createBtn, "LEFT", -10, 0)
deleteBtn:SetSize(100, 28)
deleteBtn:SetText("Видалити")
refreshBtn = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
refreshBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -10, 0)
refreshBtn:SetSize(110, 28)
refreshBtn:SetText("Оновити")
inviteBtn = CreateFrame("Button", nil, FormPanel, "UIPanelButtonTemplate")
inviteBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -10, 0)
inviteBtn:SetSize(120, 28)
inviteBtn:SetText("Запросити всіх")

local listButtons = {}
local listButtonCount = 0
local templateButtons = {}
local templateButtonCount = 0
local signupRows = {}
local signupRowCount = 0
local RenderSignups
local UseTemplateForRaid

local function RequestSignups()
    if State.formMode == "edit" and State.selectedEvent and State.selectedEvent.id then
        SendToServer("SIGNUPS\t" .. tostring(State.selectedEvent.id))
    else
        State.signups = {}
        if RenderSignups then RenderSignups() end
    end
end

local function NewRaid()
    State.formMode = "new"
    State.selectedEvent = nil
    State.selectedEventId = 0
    State.selectedTemplate = nil
    State.signups = {}
    State.mode = "simple"
    DefaultSlotsForSize(State.raidSize)
    raidNameBox:SetText("ЦКК " .. tostring(State.raidSize))
    saveTemplateName:SetText("ЦКК " .. tostring(State.raidSize))
    RefreshAll()
    if RenderSignups then RenderSignups() end
end

local function NewTemplate()
    State.formMode = "newTemplate"
    State.selectedEvent = nil
    State.selectedEventId = 0
    State.selectedTemplate = nil
    State.signups = {}
    State.mode = "simple"
    DefaultSlotsForSize(State.raidSize)
    saveTemplateName:SetText("Новий шаблон")
    RefreshAll()
    if RenderSignups then RenderSignups() end
end

local function ApplyTemplate(tpl)
    if not tpl then return end
    State.formMode = "template"
    State.selectedTemplate = tpl
    State.selectedEvent = nil
    State.selectedEventId = 0
    State.signups = {}
    State.mode = tpl.mode == "advanced" and "advanced" or "simple"
    ResetSlots()
    State.selectedTemplate = tpl
    local total = 0
    for _, slot in ipairs(DecodeSlots(tpl.spec)) do
        total = total + slot.count
        if slot.classId == 0 then
            State.simple[slot.role] = slot.count
        else
            State.advanced[slot.role] = State.advanced[slot.role] or {}
            State.advanced[slot.role][slot.classId] = slot.count
        end
    end
    if total > 0 then State.raidSize = total end
    State.raidSize = ClosestRaidSize(State.raidSize)
    saveTemplateName:SetText(tpl.name or "")
    RefreshAll()
    if RenderSignups then RenderSignups() end
end

UseTemplateForRaid = function(tpl)
    if not tpl then return end
    State.formMode = "new"
    State.selectedTemplate = tpl
    State.selectedEvent = nil
    State.selectedEventId = 0
    State.signups = {}
    State.mode = tpl.mode == "advanced" and "advanced" or "simple"
    ResetSlots()
    local total = 0
    for _, slot in ipairs(DecodeSlots(tpl.spec)) do
        total = total + slot.count
        if slot.classId == 0 then
            State.simple[slot.role] = slot.count
        else
            State.advanced[slot.role] = State.advanced[slot.role] or {}
            State.advanced[slot.role][slot.classId] = slot.count
        end
    end
    State.raidSize = ClosestRaidSize(total)
    raidNameBox:SetText(tpl.name or "")
    RefreshAll()
    if RenderSignups then RenderSignups() end
end

local function ApplyEvent(ev)
    if not ev then return end
    State.formMode = "edit"
    State.selectedEvent = ev
    State.selectedEventId = ev.id or 0
    State.selectedTemplate = nil
    State.mode = ev.mode == "advanced" and "advanced" or "simple"
    ResetSlots()
    State.selectedEvent = ev
    raidNameBox:SetText(ev.name or "")
    State.repeatWeekly = ev.repeatWeekly and true or false
    ApplyStartTs(ev.startsAt)
    local total = 0
    for _, slot in ipairs(DecodeSlots(ev.spec)) do
        total = total + slot.count
        if slot.classId == 0 then
            State.simple[slot.role] = slot.count
        else
            State.advanced[slot.role] = State.advanced[slot.role] or {}
            State.advanced[slot.role][slot.classId] = slot.count
        end
    end
    State.raidSize = ClosestRaidSize(total)
    RefreshAll()
    RequestSignups()
end

local function NextListButton(parent, buttons, index)
    local b = buttons[index]
    if not b then
        b = CreateFrame("Button", nil, parent)
        b:SetSize(184, 38)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        b.title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.title:SetPoint("TOPLEFT", 6, -5)
        b.title:SetWidth(118)
        b.title:SetJustifyH("LEFT")
        b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.sub:SetPoint("TOPLEFT", 6, -20)
        b.sub:SetWidth(172)
        b.sub:SetJustifyH("LEFT")
        b.create = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
        b.create:SetPoint("TOPRIGHT", -2, -3)
        b.create:SetSize(52, 20)
        b.create:SetText("Рейд")
        buttons[index] = b
    end
    b:Show()
    return b
end

local function RenderLists()
    for _, b in ipairs(listButtons) do b:Hide() end
    for _, b in ipairs(templateButtons) do b:Hide() end
    listButtonCount = 0
    templateButtonCount = 0
    local y = -2
    for _, ev in ipairs(State.events) do
        listButtonCount = listButtonCount + 1
        local b = NextListButton(templateContent, listButtons, listButtonCount)
        b:SetPoint("TOPLEFT", 0, y)
        b.create:Hide()
        b.title:SetWidth(172)
        b.title:SetText(ev.name)
        b.sub:SetText((ev.startText or "") .. "  " .. SlotSummary(ev.spec))
        b:SetScript("OnClick", function() ApplyEvent(ev) end)
        y = y - 40
    end
    templateContent:SetHeight(math.max(245, -y + 20))

    y = -2
    for _, tpl in ipairs(State.templates) do
        templateButtonCount = templateButtonCount + 1
        local b = NextListButton(templateListContent, templateButtons, templateButtonCount)
        b:SetPoint("TOPLEFT", 0, y)
        b.create:Show()
        b.title:SetWidth(118)
        b.title:SetText(tpl.name)
        b.sub:SetText(SlotSummary(tpl.spec))
        b:SetScript("OnClick", function() ApplyTemplate(tpl) end)
        b.create:SetScript("OnClick", function() UseTemplateForRaid(tpl) end)
        y = y - 40
    end
    templateListContent:SetHeight(math.max(230, -y + 20))
end

local function NextSignupRow()
    signupRowCount = signupRowCount + 1
    local row = signupRows[signupRowCount]
    if not row then
        row = CreateFrame("Frame", nil, SignupsContent)
        row:SetSize(182, 28)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", 0, -2)
        row.name:SetWidth(120)
        row.name:SetJustifyH("LEFT")
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.sub:SetPoint("TOPLEFT", 0, -15)
        row.sub:SetWidth(138)
        row.sub:SetJustifyH("LEFT")
        row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.remove:SetPoint("RIGHT", 0, 0)
        row.remove:SetSize(36, 20)
        row.remove:SetText("X")
        signupRows[signupRowCount] = row
    end
    row:Show()
    return row
end

RenderSignups = function()
    for _, row in ipairs(signupRows) do row:Hide() end
    signupRowCount = 0

    local totals = { tank = 0, heal = 0, mdd = 0, rdd = 0 }
    for _, signup in ipairs(State.signups) do
        if totals[signup.role] ~= nil then totals[signup.role] = totals[signup.role] + 1 end
    end
    signupSummary:SetText(string.format("МДД: %d  РДД: %d  Танк: %d  Хіл: %d", totals.mdd, totals.rdd, totals.tank, totals.heal))

    local y = 0
    for _, signup in ipairs(State.signups) do
        local row = NextSignupRow()
        row:SetPoint("TOPLEFT", 0, y)
        row.name:SetText(signup.name or "?")
        row.sub:SetText((signup.className or "") .. " - " .. (signup.roleLabel or signup.role or ""))
        row.remove:SetScript("OnClick", function()
            if State.selectedEvent and signup.guid then
                SendToServer("REMOVE_SIGNUP\t" .. tostring(State.selectedEvent.id) .. "\t" .. tostring(signup.guid))
            end
        end)
        y = y - 31
    end
    SignupsContent:SetHeight(math.max(250, -y + 12))
end

local function RequestTemplates()
    SendToServer("TEMPLATES")
    SendToServer("EVENTS")
    RequestSignups()
end

modeSimple:SetScript("OnClick", function() State.mode = "simple"; RefreshAll() end)
modeAdvanced:SetScript("OnClick", function() State.mode = "advanced"; RefreshAll() end)
resetBtn:SetScript("OnClick", function() DefaultSlotsForSize(State.raidSize); RefreshAll() end)
refreshBtn:SetScript("OnClick", RequestTemplates)
newRaidBtn:SetScript("OnClick", NewRaid)
newTemplateBtn:SetScript("OnClick", NewTemplate)
datePrev:SetScript("OnClick", function() if State.dayOffset > 0 then State.dayOffset = State.dayOffset - 1 end; RefreshAll() end)
dateNext:SetScript("OnClick", function() State.dayOffset = State.dayOffset + 1; RefreshAll() end)
dateToday:SetScript("OnClick", function() State.dayOffset = 0; RefreshAll() end)
hourMinus:SetScript("OnClick", function() State.hour = (State.hour + 23) % 24; RefreshAll() end)
hourPlus:SetScript("OnClick", function() State.hour = (State.hour + 1) % 24; RefreshAll() end)
minuteMinus:SetScript("OnClick", function() State.minute = (State.minute + 45) % 60; RefreshAll() end)
minutePlus:SetScript("OnClick", function() State.minute = (State.minute + 15) % 60; RefreshAll() end)

saveTemplateBtn:SetScript("OnClick", function()
    local name = Trim(saveTemplateName:GetText())
    if name == "" then Notice("Вкажіть назву шаблону.", 1, 0.2, 0.2); return end
    if CountTotal() ~= State.raidSize then Notice("Склад має дорівнювати розміру рейду.", 1, 0.2, 0.2); return end
    if State.formMode == "template" and State.selectedTemplate and State.selectedTemplate.id then
        SendToServer(table.concat({ "UPDATE_TEMPLATE", tostring(State.selectedTemplate.id), name, State.mode, EncodeSlots() }, "\t"))
    else
        SendToServer(table.concat({ "SAVE_TEMPLATE", name, State.mode, EncodeSlots() }, "\t"))
    end
end)

createBtn:SetScript("OnClick", function()
    local raidName = Trim(raidNameBox:GetText())
    if raidName == "" then Notice("Вкажіть назву рейду.", 1, 0.2, 0.2); return end
    if CountTotal() ~= State.raidSize then Notice("Склад має дорівнювати розміру рейду.", 1, 0.2, 0.2); return end
    local tplId = State.selectedTemplate and State.selectedTemplate.id or 0
    local tplName = State.selectedTemplate and State.selectedTemplate.name or ""
    local editing = State.formMode == "edit" and State.selectedEvent and State.selectedEvent.id
    SendToServer(table.concat({
        editing and "SAVE_EVENT" or "CREATE",
        editing and tostring(State.selectedEvent.id) or raidName,
        editing and raidName or StartText(),
        editing and StartText() or (State.repeatWeekly and "1" or "0"),
        editing and (State.repeatWeekly and "1" or "0") or State.mode,
        editing and State.mode or EncodeSlots(),
        editing and EncodeSlots() or tostring(State.raidSize),
        editing and tostring(State.raidSize) or tostring(tplId),
        editing and tostring(tplId) or tplName,
        editing and tplName or "",
    }, "\t"))
end)

StaticPopupDialogs["GCRSIG_DELETE_EVENT"] = {
    text = "Видалити запис рейду?",
    button1 = "Так",
    button2 = "Ні",
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    OnAccept = function()
        if State.selectedEvent then
            SendToServer("DELETE_EVENT\t" .. tostring(State.selectedEvent.id))
        end
    end,
}

deleteBtn:SetScript("OnClick", function()
    if State.formMode == "edit" and State.selectedEvent then StaticPopup_Show("GCRSIG_DELETE_EVENT") end
end)

inviteBtn:SetScript("OnClick", function()
    if State.formMode == "edit" and State.selectedEvent then
        SendToServer("INVITE_EVENT\t" .. tostring(State.selectedEvent.id))
    end
end)

local function ShowFrame()
    PlaceFrame(Frame)
    Frame:Show()
    RefreshAll()
    RequestTemplates()
end

local function HandlePayload(message)
    local args = SplitTabs(message)
    local cmd = args[1] or ""
    if cmd == "OPEN" then ShowFrame(); return end
    if cmd == "CLOSE" then Frame:Hide(); return end
    if cmd == "READY" then Frame.status:SetText("Сервер готовий"); return end
    if cmd == "OK" then Notice(args[2] or "Готово.", 0.3, 1, 0.3); RequestTemplates(); return end
    if cmd == "ERR" then Notice(args[2] or "Помилка.", 1, 0.25, 0.25); return end
    if cmd == "TEMPLATES_BEGIN" then State.templates = {}; return end
    if cmd == "EVENTS_BEGIN" then State.events = {}; return end
    if cmd == "SIGNUPS_BEGIN" then
        local eventId = tonumber(args[2] or 0) or 0
        if State.formMode == "edit" and State.selectedEvent and State.selectedEvent.id == eventId then
            State.signups = {}
        elseif State.formMode ~= "edit" then
            State.signups = {}
            RenderSignups()
        end
        return
    end
    if cmd == "SIG" then
        local eventId = tonumber(args[2] or 0) or 0
        if not (State.formMode == "edit" and State.selectedEvent and State.selectedEvent.id == eventId) then return end
        State.signups[#State.signups + 1] = {
            eventId = eventId,
            guid = tonumber(args[3] or 0) or 0,
            name = args[4] or "",
            classId = tonumber(args[5] or 0) or 0,
            className = args[6] or "",
            role = args[7] or "",
            roleLabel = args[8] or "",
            slotKey = args[9] or "",
            slotLabel = args[10] or "",
            signedAt = tonumber(args[11] or 0) or 0,
        }
        return
    end
    if cmd == "SIGNUPS_END" then
        local eventId = tonumber(args[2] or 0) or 0
        if State.formMode == "edit" and State.selectedEvent and State.selectedEvent.id == eventId then
            RenderSignups()
        elseif State.formMode ~= "edit" then
            State.signups = {}
            RenderSignups()
        end
        return
    end
    if cmd == "EVT" then
        State.events[#State.events + 1] = {
            id = tonumber(args[2] or 0) or 0,
            name = args[3] or "",
            startsAt = tonumber(args[4] or 0) or 0,
            startText = args[5] or "",
            repeatWeekly = args[6] == "1",
            mode = args[7] or "simple",
            spec = args[8] or "",
        }
        return
    end
    if cmd == "EVENTS_END" then RenderLists(); return end
    if cmd == "TPL" then
        State.templates[#State.templates + 1] = {
            id = tonumber(args[2] or 0) or 0,
            name = args[3] or "",
            mode = args[4] or "simple",
            spec = args[5] or "",
        }
        return
    end
    if cmd == "TEMPLATES_END" then RenderLists(); return end
end

local ev = CreateFrame("Frame")

if RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(APP_PREFIX)
end

ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("CHAT_MSG_WHISPER")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then SendToServer("HELLO"); return end
    if event == "CHAT_MSG_ADDON" then
        local prefix, message = ...
        if prefix == APP_PREFIX and type(message) == "string" then HandlePayload(message) end
        return
    end
    if event == "CHAT_MSG_WHISPER" then
        local msg = ...
        local prefix = APP_PREFIX .. "\t"
        if type(msg) == "string" and string.sub(msg, 1, string.len(prefix)) == prefix then
            HandlePayload(string.sub(msg, string.len(prefix) + 1))
        end
    end
end)

if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "GuildCodexRaidSignupFrame" end

SLASH_GUILDCODEXRAIDSIGNUP1 = "/gcraidui"
SLASH_GUILDCODEXRAIDSIGNUP2 = "/raidui"
SlashCmdList.GUILDCODEXRAIDSIGNUP = function() ShowFrame() end

DefaultSlotsForSize(State.raidSize)
RefreshAll()
