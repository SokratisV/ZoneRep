--------------------------------------------------
-- ZONEREP WINDOW
-- Zones (or factions) as collapsible headers, one row per faction (or zone) under each with a
-- progress bar of what the quests have given so far, and under that row the quests still to do:
-- click one to mark its quest giver on the map. Drawn in FlareUI's look: the game's rock tile in warm
-- dark bronze under a bronze frame, gold titles, dark rounded plates for rows, grey plate buttons with
-- a bronze rim. FlareUI's own art (thin border, rounded plate, circle) is used when it is loaded; without
-- it the same layout is drawn from Blizzard's textures. Nothing of FlareUI's is copied into this
-- addon, and nothing of Blizzard's is written to.
--------------------------------------------------
local _, ns = ...

local FLARE = C_AddOns.IsAddOnLoaded("FlareUI")
local FLARE_MEDIA = "Interface\\AddOns\\FlareUI\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local TOOLTIP_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"

-- FlareUI's colours
local EDGE_COLOR = { 0.55, 0.42, 0.24 }      -- a box's rim at rest
local EDGE_HOVER = { 0.98, 0.74, 0.36 }      -- under the pointer
local BRONZE_MUTED = { 0.61, 0.48, 0.29 }
local GOLD = { 1, 0.82, 0 }
local GREY = { 0.64, 0.60, 0.54 }
local GREEN = { 0.55, 0.95, 0.55 }

local WIDTH, HEIGHT = 700, 620
local EDGE = 14                  -- window edge to the boxes inside it
local ROW_H = 24
local GUTTER = 18                -- room right of the list for the scroll bar
local LIST_TOP, FOOTER_H = 150, 30
local LIST_H = HEIGHT - LIST_TOP - EDGE - FOOTER_H
local NUM_ROWS = math.floor((LIST_H - 8) / ROW_H)
local SCROLL_SCALE = 0.7
local INDENT = { header = 24, cell = 38, quest = 58 }

--------------------------------------------------
-- 1. FONTS
-- The window's own font objects (never copies of Blizzard's, which would change the game's text),
-- on the client's own face so every language has its letters.
--------------------------------------------------
local FACE = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local function MakeFont(name, size, color)
    local font = CreateFont(name)
    font:SetFont(FACE, size, "")
    font:SetShadowColor(0, 0, 0, 1)
    font:SetShadowOffset(1, -1)
    font:SetTextColor(color[1], color[2], color[3])
    return font
end
MakeFont("ZoneRep_Text", 12, { 1, 1, 1 })
MakeFont("ZoneRep_Gold", 12, GOLD)
MakeFont("ZoneRep_Small", 11, { 1, 1, 1 })
MakeFont("ZoneRep_Grey", 11, GREY)
MakeFont("ZoneRep_Title", 17, GOLD)

--------------------------------------------------
-- 2. SKIN PIECES
--------------------------------------------------
local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- A dark box with a bronze rim: FlareUI Thin (8 px edge, fills 4 px in) or the tooltip edge
local function Box(frame, alpha)
    if FLARE then
        frame:SetBackdrop({ bgFile = WHITE, edgeFile = FLARE_MEDIA .. "Borders\\FlareUI-Thin.tga", edgeSize = 8,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    else
        frame:SetBackdrop({ bgFile = WHITE, edgeFile = TOOLTIP_EDGE, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    end
    frame:SetBackdropColor(0, 0, 0, alpha or 0.28)
    frame:SetBackdropBorderColor(EDGE_COLOR[1], EDGE_COLOR[2], EDGE_COLOR[3], 1)
end

-- FlareUI's rounded plate as a nine-slice (row backgrounds and highlights); a flat fill without it
local function Rounded(texture, r, g, b, a)
    if FLARE then
        texture:SetTexture(FLARE_MEDIA .. "Panel\\RoundRect.tga")
        if texture.SetTextureSliceMargins then
            texture:SetTextureSliceMargins(8, 8, 8, 8)
            if Enum.UITextureSliceMode then texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched) end
        end
        texture:SetVertexColor(r, g, b, a or 1)
    else
        texture:SetColorTexture(r, g, b, a or 1)
    end
end

-- The grey plate every FlareUI button wears: Blizzard's dropdown face, in its states
local FACE_ATLAS = "common-dropdown-c-button"
local function PaintFace(button)
    local face = button.face
    -- the chosen one of a set of view buttons: a warm wash over the plate, a bright line along its
    -- foot and a gold label, which the plate's own "open" art is too faint to show
    if button.wash then
        button.wash:SetShown(button.selected and true or false)
        button.bar:SetShown(button.selected and true or false)
    end
    if button.text then
        if button.selected then button.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        else button.text:SetTextColor(1, 1, 1) end
    end
    if button.flat then
        local shade = not button:IsEnabled() and 0.08 or (button.down and 0.10) or (button.over and 0.22) or 0.15
        face:SetColorTexture(shade, shade, shade, 0.95)
        button.rim:SetBackdropBorderColor(button.over and EDGE_HOVER[1] or EDGE_COLOR[1],
            button.over and EDGE_HOVER[2] or EDGE_COLOR[2], button.over and EDGE_HOVER[3] or EDGE_COLOR[3], 1)
        return
    end
    local atlas
    if not button:IsEnabled() then atlas = FACE_ATLAS .. "-disabled"
    elseif button.down and button.over then atlas = FACE_ATLAS .. "-pressedhover-1"
    elseif button.down then atlas = FACE_ATLAS .. "-pressed-1"
    elseif button.over then atlas = FACE_ATLAS .. "-hover-1"
    elseif button.selected then atlas = FACE_ATLAS .. "-open"
    else atlas = FACE_ATLAS end
    face:SetAtlas(atlas)
end

local function GreyPlate(button)
    local flat = not HasAtlas(FACE_ATLAS)
    button.flat = flat
    local face = button:CreateTexture(nil, "BACKGROUND", nil, 2)
    if flat then
        face:SetAllPoints()
        button.rim = CreateFrame("Frame", nil, button, "BackdropTemplate")
        button.rim:SetAllPoints()
        button.rim:SetBackdrop({ edgeFile = TOOLTIP_EDGE, edgeSize = 10 })
    else
        -- the art reaches 7 px past the button, as on Blizzard's dropdown
        face:SetPoint("TOPLEFT", -7, 7)
        face:SetPoint("BOTTOMRIGHT", 7, -7)
    end
    button.face = face
    button.wash = button:CreateTexture(nil, "ARTWORK", nil, 1)
    button.wash:SetPoint("TOPLEFT", 2, -2)
    button.wash:SetPoint("BOTTOMRIGHT", -2, 2)
    button.wash:SetColorTexture(EDGE_HOVER[1], EDGE_HOVER[2], EDGE_HOVER[3], 0.28)
    button.wash:SetBlendMode("ADD")
    button.wash:Hide()
    button.bar = button:CreateTexture(nil, "OVERLAY")
    button.bar:SetHeight(2)
    button.bar:SetPoint("BOTTOMLEFT", 5, 2)
    button.bar:SetPoint("BOTTOMRIGHT", -5, 2)
    button.bar:SetColorTexture(EDGE_HOVER[1], EDGE_HOVER[2], EDGE_HOVER[3], 1)
    button.bar:Hide()
    button:HookScript("OnEnter", function(self) self.over = true; PaintFace(self) end)
    button:HookScript("OnLeave", function(self) self.over = nil; PaintFace(self) end)
    button:HookScript("OnMouseDown", function(self) if self:IsEnabled() then self.down = true; PaintFace(self) end end)
    button:HookScript("OnMouseUp", function(self) self.down = nil; PaintFace(self) end)
    button:HookScript("OnShow", PaintFace)
    PaintFace(button)
end

local function SetSelected(button, selected)
    button.selected = selected and true or false
    PaintFace(button)
end

-- Blizzard's thin MinimalScrollBar at 70%, as FlareUI draws it; with a client that lacks the
-- template the mouse wheel still scrolls.
local function CreateScrollBar(parent)
    local ok, bar = pcall(CreateFrame, "EventFrame", nil, parent, "MinimalScrollBar")
    if not ok or not bar then return nil end
    bar:SetScale(SCROLL_SCALE)
    local setting = false
    function bar:SetValues(visible, position)
        if visible >= 0.999 then self:Hide() return end
        self:Show()
        setting = true
        self:SetVisibleExtentPercentage(visible)
        self:SetPanExtentPercentage(math.max(0.01, visible * 0.25))
        self:SetScrollPercentage(math.max(0, math.min(1, position)), true)
        setting = false
    end
    bar:RegisterCallback("OnScroll", function(_, position)
        if setting or not bar.onScroll then return end
        bar.onScroll(math.max(0, math.min(1, position or 0)))
    end, bar)
    return bar
end

-- the heavy bronze frame the settings window wears, else FlareUI's Thick edge, else the tooltip edge
local function ApplyFrameArt(frame)
    if HasAtlas("heavybronze-frame-basic") then
        local bronze = CreateFrame("Frame", nil, frame)
        bronze:SetAllPoints()
        bronze:SetFrameLevel(frame:GetFrameLevel() + 30)
        bronze.edge = bronze:CreateTexture(nil, "BORDER")
        bronze.edge:SetAtlas("heavybronze-frame-basic")
        bronze.edge:SetPoint("TOPLEFT", -9, 15)
        bronze.edge:SetPoint("BOTTOMRIGHT", 9, -15)
        for _, corner in ipairs({ { "TL", "TOPLEFT" }, { "BR", "BOTTOMRIGHT" } }) do
            local bracket = bronze:CreateTexture(nil, "ARTWORK")
            bracket:SetAtlas("heavybronze-horz-cornerbracket-" .. corner[1], true)
            bracket:SetPoint(corner[2], bronze.edge, corner[2])
        end
        frame.bronze = bronze
        return 8   -- the stone reaches under the frame's top and bottom bars
    end
    if FLARE then
        frame:SetBackdrop({ edgeFile = FLARE_MEDIA .. "Borders\\FlareUI-Thick.tga", edgeSize = 16 })
        frame:SetBackdropBorderColor(0.65, 0.49, 0.27, 1)
    else
        frame:SetBackdrop({ edgeFile = TOOLTIP_EDGE, edgeSize = 16 })
        frame:SetBackdropBorderColor(0.80, 0.60, 0.34, 1)
    end
    return -3
end

--------------------------------------------------
-- 3. WHAT THE LIST SHOWS
--------------------------------------------------
local win, rows = nil, {}
local lines, result = {}, nil
local offset = 0
local expanded = { zone = {}, faction = {}, cells = {} }
local search = ""

local function Num(n)
    local s = tostring(math.floor(n + 0.5))
    local k
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end

local function Settings_()
    local ui = ns.DB().ui
    if ui.mode ~= "zone" and ui.mode ~= "faction" then ui.mode = "zone" end
    return ui
end

local function Visible(left)
    return not Settings_().hideDone or left > 0
end

local function Has(text, query)
    return type(text) == "string" and text:lower():find(query, 1, true) ~= nil
end

local function CellKey(c) return tostring(c.zone.key) .. "|" .. tostring(c.faction) end

-- A cell is shown while searching when its zone, its faction or one of its quests matches.
local function QuestHits(c, query)
    local hits = {}
    for _, p in ipairs(c.pending) do
        if Has(p.title, query) then hits[#hits + 1] = p end
    end
    return hits
end

local function BuildLines()
    lines = {}
    if not result then return end
    local mode = Settings_().mode
    local open = expanded[mode]
    local groups = mode == "zone" and result.zones or result.factions
    local query = search:lower()
    local searching = query ~= ""
    for _, g in ipairs(groups) do
        if Visible(g.left) then
            local key = mode == "zone" and g.key or g.id
            local groupHit = searching and Has(g.name, query)
            local show = {}
            for _, c in ipairs(g.cells) do
                if Visible(c.left) then
                    local nameHit = searching and (Has(c.name, query) or Has(c.zone.name, query))
                    local questHits = searching and QuestHits(c, query) or nil
                    if not searching or groupHit or nameHit or #questHits > 0 then
                        show[#show + 1] = { cell = c, nameHit = groupHit or nameHit, questHits = questHits }
                    end
                end
            end
            if not searching or groupHit or #show > 0 then
                -- while searching, every header with a hit is open so the hits are visible
                local isOpen = searching and true or open[key]
                lines[#lines + 1] = { header = true, group = g, key = key, open = isOpen }
                if isOpen then
                    for _, s in ipairs(show) do
                        local c = s.cell
                        local cellOpen = expanded.cells[CellKey(c)]
                        -- a quest-name hit opens its row; a zone or faction hit leaves it as it was
                        if searching and #s.questHits > 0 and not s.nameHit then cellOpen = true end
                        if #c.pending == 0 then cellOpen = false end
                        lines[#lines + 1] = { cell = c, label = mode == "zone" and c.name or c.zone.name, open = cellOpen }
                        if cellOpen then
                            local list = c.pending
                            if searching and not s.nameHit and #s.questHits > 0 then list = s.questHits end
                            for _, p in ipairs(list) do
                                lines[#lines + 1] = { quest = p, cell = c }
                            end
                        end
                    end
                end
            end
        end
    end
end

--------------------------------------------------
-- 4. ROWS
--------------------------------------------------
local function MaxOffset() return math.max(0, #lines - NUM_ROWS) end

local function UpdateScrollBar()
    if not (win and win.scrollBar) then return end
    local total = #lines
    if total <= NUM_ROWS then
        win.scrollBar:Hide()
        return
    end
    local max = MaxOffset()
    win.scrollBar:SetValues(NUM_ROWS / total, max > 0 and offset / max or 0)
end

local function Fill(row, frac, r, g, b, a)
    if frac > 0 then
        row.fill:SetColorTexture(r, g, b, a)
        row.fill:SetWidth(math.max(1, (row:GetWidth() - 2) * math.min(frac, 1)))
        row.fill:Show()
    else
        row.fill:Hide()
    end
end

local function Place(row, kind)
    row.arrow:ClearAllPoints()
    row.arrow:SetPoint("LEFT", INDENT[kind] - 14, 0)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", INDENT[kind], 0)
    row.name:SetPoint("RIGHT", row.value, "LEFT", -8, 0)
end

local function Paint(row, line)
    row.line = line
    if not line then
        row:Hide()
        return
    end
    row:Show()
    if line.header then
        local g = line.group
        Place(row, "header")
        row.arrow:SetText(line.open and "-" or "+")
        row.arrow:Show()
        row.name:SetFontObject("ZoneRep_Gold")
        row.name:SetText(g.name)
        Rounded(row.plate, 0.26, 0.19, 0.09, 0.78)
        Fill(row, g.total > 0 and g.earned / g.total or 0, 0.78, 0.6, 0.2, 0.30)
        local text = ("%s / %s  -  %s left"):format(Num(g.earned), Num(g.total), Num(g.left))
        if g.other > 0 then text = text .. ("  +%s"):format(Num(g.other)) end
        row.value:SetFontObject("ZoneRep_Small")
        row.value:SetText(text)
        row.value:SetTextColor(1, 1, 1)
    elseif line.quest then
        local p = line.quest
        Place(row, "quest")
        row.arrow:Hide()
        local inLog = C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(p.id)
        row.name:SetFontObject("ZoneRep_Small")
        row.name:SetText(p.title .. (inLog and "  |cff9a9a9a(in your log)|r" or ""))
        if ns.IsMarked(p.id) then row.name:SetTextColor(1, 0.88, 0.1)
        elseif inLog then row.name:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        else row.name:SetTextColor(0.92, 0.92, 0.92) end
        Rounded(row.plate, 0, 0, 0, 0.16)
        row.fill:Hide()
        row.value:SetFontObject("ZoneRep_Small")
        row.value:SetText("+" .. Num(p.value))
        row.value:SetTextColor(0.9, 0.9, 0.5)
    else
        local c = line.cell
        Place(row, "cell")
        local expandable = #c.pending > 0
        row.arrow:SetText(line.open and "-" or "+")
        row.arrow:SetShown(expandable)
        row.name:SetFontObject("ZoneRep_Text")
        row.name:SetText(line.label)
        local finished = c.total > 0 and c.left == 0
        if finished then row.name:SetTextColor(GREEN[1], GREEN[2], GREEN[3]) else row.name:SetTextColor(1, 1, 1) end
        Rounded(row.plate, 0, 0, 0, 0.30)
        Fill(row, c.total > 0 and c.earned / c.total or 0, 0.10, 0.55, 0.20, 0.50)
        local text
        if c.total > 0 then
            text = ("%s / %s  -  %s left"):format(Num(c.earned), Num(c.total), Num(c.left))
        else
            text = "no quest rep"
        end
        if c.other > 0 then text = text .. ("  +%s"):format(Num(c.other)) end
        row.value:SetFontObject("ZoneRep_Small")
        row.value:SetText(text)
        if finished then row.value:SetTextColor(GREEN[1], GREEN[2], GREEN[3]) else row.value:SetTextColor(1, 1, 1) end
    end
end

local function Render()
    if not win then return end
    if offset > MaxOffset() then offset = MaxOffset() end
    if offset < 0 then offset = 0 end
    for i = 1, NUM_ROWS do
        Paint(rows[i], lines[offset + i])
    end
    UpdateScrollBar()
end

local function ShowTooltip(row)
    row.hover:Show()
    local line = row.line
    if not line or line.header then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if line.quest then
        local p = line.quest
        GameTooltip:AddLine(p.title, GOLD[1], GOLD[2], GOLD[3])
        GameTooltip:AddLine(("+%s reputation with %s"):format(Num(p.value), line.cell.name), 1, 1, 1)
        local loc, why = ns.QuestLocation(p.id)
        if loc then
            GameTooltip:AddLine((loc.turnIn and "Hand in to " or "Pick up from ") .. loc.label, 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Click to mark it on the map", 0.5, 1, 0.5)
        else
            GameTooltip:AddLine(why or "No known location.", 0.8, 0.5, 0.5, true)
        end
        GameTooltip:Show()
        return
    end
    local c = line.cell
    GameTooltip:AddLine(c.name .. " - " .. c.zone.name, GOLD[1], GOLD[2], GOLD[3])
    GameTooltip:AddDoubleLine("Earned from quests", Num(c.earned) .. " / " .. Num(c.total), 1, 1, 1, 0.5, 1, 0.5)
    GameTooltip:AddDoubleLine("Left to earn", Num(c.left), 1, 1, 1, 1, 1, 1)
    if c.other > 0 then
        GameTooltip:AddDoubleLine("Kills and other sources", "+" .. Num(c.other), 1, 1, 1, 0.6, 0.8, 1)
    end
    if #c.pending > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(("Click to list the %d quests still giving rep"):format(#c.pending), 0.8, 0.8, 0.8)
    elseif c.total > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Every quest done.", 0.5, 1, 0.5)
    end
    GameTooltip:Show()
end

local function CreateRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H - 2)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4 - (index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -4 - (index - 1) * ROW_H)

    row.plate = row:CreateTexture(nil, "BACKGROUND")
    row.plate:SetAllPoints()
    Rounded(row.plate, 0, 0, 0, 0.30)
    row.fill = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.fill:SetPoint("TOPLEFT", 1, -1)
    row.fill:SetPoint("BOTTOMLEFT", 1, 1)
    row.fill:SetWidth(1)
    row.hover = row:CreateTexture(nil, "BACKGROUND", nil, 2)
    row.hover:SetAllPoints()
    Rounded(row.hover, EDGE_HOVER[1], EDGE_HOVER[2], EDGE_HOVER[3], 0.22)
    row.hover:Hide()

    row.arrow = row:CreateFontString(nil, "OVERLAY", "ZoneRep_Gold")
    row.value = row:CreateFontString(nil, "OVERLAY", "ZoneRep_Small")
    row.value:SetPoint("RIGHT", -8, 0)
    row.value:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "ZoneRep_Text")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Render()
    end)
    row:SetScript("OnEnter", ShowTooltip)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
        GameTooltip:Hide()
    end)
    row:SetScript("OnClick", function(self)
        local line = self.line
        if not line then return end
        if line.header then
            local open = expanded[Settings_().mode]
            open[line.key] = not open[line.key] or nil
            BuildLines()
            Render()
        elseif line.quest then
            PlaySound(852)
            ns.ShowQuestOnMap(line.quest.id, line.quest.title)
            Render()        -- the marked quest turns gold
        elseif #line.cell.pending > 0 then
            local key = CellKey(line.cell)
            expanded.cells[key] = not expanded.cells[key] or nil
            BuildLines()
            Render()
        end
    end)
    return row
end

--------------------------------------------------
-- 5. REFRESH AND ACTIONS
--------------------------------------------------
local function Refresh()
    if not win or not win:IsShown() then return end
    if not ns.IndexReady() then
        result = nil
        lines = {}
        win.summary:SetText(ns.indexError and ("Waiting for Questie: " .. ns.indexError) or "Reading Questie's quest data...")
        win.count:SetText("")
        Render()
        return
    end
    result = ns.Compute()
    BuildLines()
    if result then
        win.summary:SetText(("Quests:  %s earned of %s   -   %s left to earn"):format(Num(result.earned), Num(result.total), Num(result.left)))
        local extra = result.other > 0 and ("+%s from kills and other sources"):format(Num(result.other)) or ""
        local marks = ns.MarkCount()
        if marks > 0 then extra = extra .. (extra ~= "" and "   " or "") .. ("%d on the map"):format(marks) end
        win.count:SetText(extra)
    end
    Render()
end

local pendingRefresh = false
ns.OnChange = function()
    if not win or not win:IsShown() or pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0.2, function()
        pendingRefresh = false
        Refresh()
    end)
end

local function SetMode(mode)
    Settings_().mode = mode
    offset = 0
    SetSelected(win.modeZone, mode == "zone")
    SetSelected(win.modeFaction, mode == "faction")
    Refresh()
end

local function SetAll(open)
    if not result then return end
    local mode = Settings_().mode
    local set = {}
    if open then
        for _, g in ipairs(mode == "zone" and result.zones or result.factions) do
            set[mode == "zone" and g.key or g.id] = true
        end
    end
    expanded[mode] = set
    expanded.cells = {}
    offset = 0
    Refresh()
end

local function GoToCurrentZone()
    if not result then return end
    local zone = GetRealZoneText()
    if not zone or zone == "" or (issecretvalue and issecretvalue(zone)) then return end
    if search ~= "" then win.search:SetText("") end      -- a search would hide the zone being jumped to
    search = ""
    if Settings_().mode ~= "zone" then SetMode("zone") end
    for _, z in ipairs(result.zones) do
        if z.name == zone then
            expanded.zone[z.key] = true
            BuildLines()
            for i, line in ipairs(lines) do
                if line.header and line.key == z.key then offset = i - 1 break end
            end
            Render()
            return
        end
    end
    print("|cffffd200ZoneRep|r No reputation quests are listed for " .. zone .. ".")
end

--------------------------------------------------
-- 6. BUILDING THE WINDOW
--------------------------------------------------
local function Button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    GreyPlate(b)
    b.text = b:CreateFontString(nil, "OVERLAY", "ZoneRep_Text")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    b._label = label
    b:SetScript("OnClick", function(self)
        PlaySound(852)
        onClick(self)
    end)
    -- a plain text label also answers GetText, as the real button template would
    b.GetText = function(self) return self._label end
    return b
end

local function Build()
    win = CreateFrame("Frame", "ZoneRepFrame", UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, HEIGHT)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    local function SavePosition()
        local ui = Settings_()
        ui.left, ui.top = win:GetLeft(), win:GetTop()
    end
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    win:Hide()
    local ui = Settings_()
    if ui.left and ui.top then
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ui.left, ui.top)
    else
        win:SetPoint("CENTER")
    end

    -- FlareUI's ground: the rock tile in warm dark bronze, a glow under the header, a shade below
    local under = ApplyFrameArt(win)
    local art = win:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetPoint("TOPLEFT", 3, under)
    art:SetPoint("BOTTOMRIGHT", -3, -under)
    art:SetTexture("Interface\\FrameGeneral\\UI-Background-Rock", "REPEAT", "REPEAT")
    art:SetHorizTile(true)
    art:SetVertTile(true)
    art:SetDesaturated(true)
    art:SetVertexColor(0.85, 0.68, 0.47)
    local wash = win:CreateTexture(nil, "BACKGROUND", nil, 2)
    wash:SetAllPoints(art)
    wash:SetColorTexture(0.05, 0.038, 0.026, 0.3)
    local glow = win:CreateTexture(nil, "BACKGROUND", nil, 3)
    glow:SetPoint("TOPLEFT", art)
    glow:SetPoint("TOPRIGHT", art)
    glow:SetHeight(200)
    -- a gradient multiplies its texture: white underneath, so the colours come out as given; a flat
    -- tint stands in on a client whose SetGradient takes other arguments
    glow:SetColorTexture(1, 1, 1)
    if not pcall(glow.SetGradient, glow, "VERTICAL", CreateColor(0.55, 0.41, 0.22, 0), CreateColor(0.55, 0.41, 0.22, 0.20)) then
        glow:SetColorTexture(0.55, 0.41, 0.22, 0.10)
    end
    local shade = win:CreateTexture(nil, "BACKGROUND", nil, 3)
    shade:SetPoint("BOTTOMLEFT", art)
    shade:SetPoint("BOTTOMRIGHT", art)
    shade:SetHeight(240)
    shade:SetColorTexture(1, 1, 1)
    if not pcall(shade.SetGradient, shade, "VERTICAL", CreateColor(0, 0, 0, 0.5), CreateColor(0, 0, 0, 0)) then
        shade:SetColorTexture(0, 0, 0, 0.2)
    end

    -- header: a round icon, the title in WoW's yellow, what the list shows
    local logo = win:CreateTexture(nil, "ARTWORK", nil, 2)
    logo:SetTexture("Interface\\Icons\\Achievement_Reputation_01")
    logo:SetSize(30, 30)
    logo:SetPoint("TOPLEFT", EDGE + 8, -12)
    local mask = win:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(logo)
    logo:AddMaskTexture(mask)
    if FLARE then
        local rim = win:CreateTexture(nil, "ARTWORK", nil, 1)
        rim:SetTexture(FLARE_MEDIA .. "Panel\\Circle.tga")
        rim:SetSize(35, 35)
        rim:SetPoint("CENTER", logo)
        rim:SetVertexColor(0.78, 0.6, 0.34)
    end

    -- the title bar: drag the window by it
    local bar = CreateFrame("Button", nil, win)
    bar:SetPoint("TOPLEFT", EDGE, -6)
    bar:SetPoint("TOPRIGHT", -(EDGE + 30), -6)
    bar:SetHeight(40)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() win:StartMoving() end)
    bar:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        SavePosition()
    end)
    bar:SetFrameLevel(win:GetFrameLevel() + 2)

    win.title = win:CreateFontString(nil, "OVERLAY", "ZoneRep_Title")
    win.title:SetPoint("LEFT", logo, "RIGHT", 10, 1)
    win.title:SetText("ZoneRep")
    win.subtitle = win:CreateFontString(nil, "OVERLAY", "ZoneRep_Grey")
    win.subtitle:SetPoint("LEFT", win.title, "RIGHT", 8, -2)
    win.subtitle:SetText("reputation by zone")

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    if win.bronze then
        close:SetPoint("TOPRIGHT", win.bronze.edge, "TOPRIGHT", -2, -2)
    else
        close:SetPoint("CENTER", win, "TOPRIGHT", -5, -3)
    end
    close:SetFrameLevel(win:GetFrameLevel() + 40)
    close:SetScript("OnClick", function() PlaySound(854); win:Hide() end)

    -- summary
    win.summary = win:CreateFontString(nil, "OVERLAY", "ZoneRep_Text")
    win.summary:SetPoint("TOPLEFT", EDGE + 6, -58)
    win.count = win:CreateFontString(nil, "OVERLAY", "ZoneRep_Grey")
    win.count:SetPoint("TOPRIGHT", -(EDGE + 6), -58)
    win.count:SetJustifyH("RIGHT")

    -- mode, jump and expand buttons
    win.modeZone = Button(win, "By zone", 84, function() SetMode("zone") end)
    win.modeZone:SetPoint("TOPLEFT", EDGE + 8, -82)
    win.modeFaction = Button(win, "By faction", 92, function() SetMode("faction") end)
    win.modeFaction:SetPoint("LEFT", win.modeZone, "RIGHT", 8, 0)
    local here = Button(win, "Current zone", 104, GoToCurrentZone)
    here:SetPoint("LEFT", win.modeFaction, "RIGHT", 16, 0)
    local expand = Button(win, "Expand all", 88, function() SetAll(true) end)
    expand:SetPoint("LEFT", here, "RIGHT", 8, 0)
    local collapse = Button(win, "Collapse all", 94, function() SetAll(false) end)
    collapse:SetPoint("LEFT", expand, "RIGHT", 8, 0)
    local clearMarks = Button(win, "Clear marks", 90, function()
        ns.ClearMarks()
        Refresh()
    end)
    clearMarks:SetPoint("TOPRIGHT", -(EDGE + 8), -82)

    -- search row: a boxed edit field, a clear button, Hide finished
    local searchLabel = win:CreateFontString(nil, "OVERLAY", "ZoneRep_Gold")
    searchLabel:SetPoint("TOPLEFT", EDGE + 10, -114)
    searchLabel:SetText("Search")
    local boxFrame = CreateFrame("Frame", nil, win, "BackdropTemplate")
    boxFrame:SetSize(250, 22)
    boxFrame:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    Box(boxFrame, 0.45)
    local box = CreateFrame("EditBox", "ZoneRepSearch", boxFrame)
    box:SetPoint("TOPLEFT", 8, -2)
    box:SetPoint("BOTTOMRIGHT", -8, 2)
    box:SetFontObject("ZoneRep_Text")
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text == search then return end
        search = text
        offset = 0
        Refresh()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function() boxFrame:SetBackdropBorderColor(EDGE_HOVER[1], EDGE_HOVER[2], EDGE_HOVER[3], 1) end)
    box:SetScript("OnEditFocusLost", function() boxFrame:SetBackdropBorderColor(EDGE_COLOR[1], EDGE_COLOR[2], EDGE_COLOR[3], 1) end)
    win.search = box
    local clear = Button(win, "Clear", 56, function()
        box:SetText("")
        box:ClearFocus()
    end)
    clear:SetPoint("LEFT", boxFrame, "RIGHT", 10, 0)
    local hint = win:CreateFontString(nil, "OVERLAY", "ZoneRep_Grey")
    hint:SetPoint("LEFT", clear, "RIGHT", 10, 0)
    hint:SetText("a zone, a faction or a quest")

    local hide = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    hide:SetSize(24, 24)
    hide:SetChecked(Settings_().hideDone and true or false)
    local hideText = hide:CreateFontString(nil, "OVERLAY", "ZoneRep_Text")
    hideText:SetPoint("LEFT", hide, "RIGHT", 1, 0)
    hideText:SetText("Hide finished")
    hide:SetHitRectInsets(0, -(hideText:GetStringWidth() + 6), 0, 0)
    hide:SetPoint("TOPRIGHT", -(EDGE + 8 + (hideText:GetStringWidth() or 80) + 6), -112)
    hide:SetScript("OnClick", function(self)
        PlaySound(852)
        Settings_().hideDone = self:GetChecked() and true or false
        offset = 0
        Refresh()
    end)
    win.hide = hide

    local line = win:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(BRONZE_MUTED[1], BRONZE_MUTED[2], BRONZE_MUTED[3], 0.6)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", EDGE + 4, -(LIST_TOP - 6))
    line:SetPoint("TOPRIGHT", -(EDGE + GUTTER + 4), -(LIST_TOP - 6))

    -- the list
    local list = CreateFrame("Frame", nil, win, "BackdropTemplate")
    list:SetPoint("TOPLEFT", EDGE, -LIST_TOP)
    list:SetPoint("BOTTOMRIGHT", -(EDGE + GUTTER), EDGE + FOOTER_H)
    Box(list, 0.28)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Render()
    end)
    win.list = list
    for i = 1, NUM_ROWS do rows[i] = CreateRow(list, i) end

    win.scrollBar = CreateScrollBar(win)
    if win.scrollBar then
        win.scrollBar:SetPoint("TOPLEFT", list, "TOPRIGHT", 5 / SCROLL_SCALE, 0)
        win.scrollBar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 5 / SCROLL_SCALE, 0)
        win.scrollBar.onScroll = function(position)
            offset = math.floor(position * MaxOffset() + 0.5)
            Render()
        end
    end

    win.footer = win:CreateFontString(nil, "OVERLAY", "ZoneRep_Grey")
    win.footer:SetPoint("BOTTOMLEFT", EDGE + 6, EDGE + 4)
    win.footer:SetPoint("BOTTOMRIGHT", -(EDGE + 6), EDGE + 4)
    win.footer:SetJustifyH("LEFT")
    win.footer:SetWordWrap(false)
    win.footer:SetText("Quest data from Questie, one-time quests your race and class can take. Click a faction row for its quests, a quest to mark it on the map.")

    SetSelected(win.modeZone, Settings_().mode == "zone")
    SetSelected(win.modeFaction, Settings_().mode == "faction")

    -- one Escape closes it with the other UISpecialFrames windows
    tinsert(UISpecialFrames, "ZoneRepFrame")
    win:SetScript("OnShow", function()
        ns.EnsureIndex(function() Refresh() end)
        Refresh()
    end)
    win:SetScript("OnHide", function() GameTooltip:Hide() end)
end

function ns.Toggle()
    if not win then Build() end
    if win:IsShown() then
        win:Hide()
    else
        -- Blizzard's Settings window shares Escape with this one; do not open on top of it
        if not InCombatLockdown() and SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        PlaySound(850)
        win:Show()
    end
end
