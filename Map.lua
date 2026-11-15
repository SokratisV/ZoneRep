-- ZoneRep map marks: click a quest in the list and its quest giver (or, once you have the quest, its
-- turn-in) is marked on the world map. Positions come from Questie (quest -> NPC/object -> spawn).
-- Like the Dungeon Journal's "Show on map", the pins are the addon's own, drawn on the Blizzard map:
-- this client's user-waypoint API is not reliable. Several pins can stand at once; right-click one to
-- remove it, and one clears itself once its quest is picked up or handed in.
local _, ns = ...

local pins = {}         -- questId -> { questId, mapID, x, y (0-1), label, title, turnIn }
local markers = {}      -- questId -> pin frame
local order = {}        -- questIds in the order they were marked
local locations = {}    -- questId -> resolved location (or false)

local CHAT = "|cffffd36bZoneRep:|r "
local function Say(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(CHAT .. text) end
end

-- ---------------------------------------------------------------------------------------------
-- Where a quest is: Questie's quest giver (or turn-in) -> NPC/object -> spawn, on a zone map
-- ---------------------------------------------------------------------------------------------
-- Questie's spawns are { [areaId] = { {x, y}, ... } } with x, y in 0..100.
local function SpawnOn(Q, spawns, preferArea)
    if type(spawns) ~= "table" then return nil end
    local areas = {}
    for areaId in pairs(spawns) do areas[#areas + 1] = areaId end
    table.sort(areas, function(a, b)
        local pa, pb = a == preferArea and 0 or 1, b == preferArea and 0 or 1
        if pa ~= pb then return pa < pb end
        return a < b
    end)
    for _, areaId in ipairs(areas) do
        local mapID = Q.zone and Q.zone.GetUiMapIdByAreaId and Q.zone:GetUiMapIdByAreaId(areaId)
        local coords = spawns[areaId]
        local c = type(coords) == "table" and coords[1]
        -- Questie maps areas it hides (Deeprun Tram and the like) to map 0
        if mapID and mapID > 0 and c and type(c[1]) == "number" and type(c[2]) == "number" and c[1] >= 0 then
            return mapID, c[1] / 100, c[2] / 100, areaId
        end
    end
end

-- Returns { mapID, x, y, label, giver, turnIn } or nil plus a reason.
function ns.QuestLocation(questId)
    -- once you have the quest the turn-in is wanted, so the cached pickup spot no longer applies
    local turnIn = C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(questId) and true or false
    local cached = not turnIn and locations[questId]
    if cached then return cached end
    local Q = ns.Questie and ns.Questie()
    if not Q then return nil, "Questie is not ready yet." end
    local db = Q.db
    local zoneArea = db.QueryQuestSingle(questId, "zoneOrSort")
    local givers = db.QueryQuestSingle(questId, turnIn and "finishedBy" or "startedBy")
    local function try(list, query, queryName)
        if type(list) ~= "table" then return nil end
        for _, id in ipairs(list) do
            local mapID, x, y, areaId = SpawnOn(Q, query(id, "spawns"), zoneArea)
            if mapID then
                local name = query(id, "name") or queryName
                return { mapID = mapID, x = x, y = y, giver = name, turnIn = turnIn, areaId = areaId }
            end
        end
    end
    -- startedBy / finishedBy are { npcIds, objectIds, ... }
    local loc = try(givers and givers[1], db.QueryNPCSingle, "NPC") or try(givers and givers[2], db.QueryObjectSingle, "Object")
    if not loc then
        return nil, turnIn and "Questie has no known place to hand this quest in."
            or "Questie has no known place to pick this quest up (an item or a world event starts it)."
    end
    local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(loc.mapID)
    loc.zoneName = mapInfo and mapInfo.name
    loc.label = loc.giver and (loc.zoneName and (loc.giver .. " - " .. loc.zoneName) or loc.giver) or (loc.zoneName or "marked spot")
    if not turnIn then locations[questId] = loc end   -- a turn-in spot changes once the quest is done
    return loc
end

-- ---------------------------------------------------------------------------------------------
-- The pins
-- ---------------------------------------------------------------------------------------------
local function Canvas()
    if not WorldMapFrame then return nil end
    if type(WorldMapFrame.GetCanvas) == "function" then
        local ok, canvas = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
        if ok and canvas then return canvas end
    end
    local sc = WorldMapFrame.ScrollContainer
    return sc and (sc.Child or sc) or nil
end

local function DisplayedMap()
    if not WorldMapFrame or type(WorldMapFrame.GetMapID) ~= "function" then return nil end
    local ok, id = pcall(WorldMapFrame.GetMapID, WorldMapFrame)
    return ok and id or nil
end

-- The pin's place on the map being shown: the same map directly, a parent (continent) map through
-- world coordinates, nil when it falls outside.
local function Project(pin, shown)
    if not shown then return nil end
    if pin.mapID == shown then return pin.x, pin.y end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, x, y = pcall(function()
        local continent, world = C_Map.GetWorldPosFromMapPos(pin.mapID, CreateVector2D(pin.x, pin.y))
        if not continent or not world then return nil end
        local pos = select(2, C_Map.GetMapPosFromWorldPos(continent, world, shown))
        if not pos then pos = C_Map.GetMapPosFromWorldPos(continent, world, shown) end
        if type(pos) ~= "table" or not pos.GetXY then return nil end
        return pos:GetXY()
    end)
    if not ok or not x or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

local function Tooltip(self)
    local pin = self.pin
    if not pin or not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(pin.title or "Quest", 1, 0.82, 0)
    GameTooltip:AddLine((pin.turnIn and "Hand in to " or "Pick up from ") .. (pin.label or "this spot"), 1, 1, 1, true)
    GameTooltip:AddLine("Right-click to remove", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function CreateMarker(questId)
    local canvas = Canvas()
    if not canvas then return nil end
    local m = CreateFrame("Button", nil, canvas)
    m:SetSize(44, 44)
    m:SetFrameLevel(10000)
    m:EnableMouse(true)
    m:RegisterForClicks("RightButtonUp")
    m.questId = questId

    -- a dark disc under the glyph so it reads on pale map tiles
    m.backing = m:CreateTexture(nil, "BACKGROUND", nil, -2)
    m.backing:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    m.backing:SetVertexColor(0, 0, 0, 0.62)
    m.backing:SetSize(32, 32)
    m.backing:SetPoint("CENTER")
    -- a soft ring that ripples outwards
    m.pulse = m:CreateTexture(nil, "BACKGROUND", nil, -3)
    m.pulse:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    m.pulse:SetVertexColor(1.00, 0.30, 0.10, 0.55)
    m.pulse:SetBlendMode("ADD")
    m.pulse:SetSize(32, 32)
    m.pulse:SetPoint("CENTER")
    m.pulse:SetAlpha(0)
    pcall(function()
        local group = m.pulse:CreateAnimationGroup()
        group:SetLooping("REPEAT")
        local grow = group:CreateAnimation("Scale")
        grow:SetDuration(1.8)
        if grow.SetScaleFrom then grow:SetScaleFrom(0.9, 0.9); grow:SetScaleTo(2.0, 2.0) else grow:SetScale(2.0, 2.0) end
        grow:SetOrigin("CENTER", 0, 0)
        grow:SetEndDelay(0.7)
        local fadeIn = group:CreateAnimation("Alpha")
        fadeIn:SetDuration(0.45)
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(0.55)
        local fadeOut = group:CreateAnimation("Alpha")
        fadeOut:SetStartDelay(0.45)
        fadeOut:SetDuration(1.35)
        fadeOut:SetFromAlpha(0.55)
        fadeOut:SetToAlpha(0)
        fadeOut:SetEndDelay(0.7)
        m.pulseAnim = group
    end)
    -- the glyph: a gold X to pick up from, a gold ? to hand in to, on a black outline
    m.outline = {}
    for i, o in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
        local shadow = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        shadow:SetPoint("CENTER", m, "CENTER", o[1], o[2])
        shadow:SetTextColor(0, 0, 0, 1)
        shadow:SetScale(1.35)
        m.outline[i] = shadow
    end
    m.glyph = m:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    m.glyph:SetPoint("CENTER", m, "CENTER", 0, 0)
    m.glyph:SetTextColor(1.00, 0.88, 0.10, 1)
    m.glyph:SetScale(1.35)

    m:SetScript("OnEnter", Tooltip)
    m:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    m:SetScript("OnClick", function(self) ns.RemoveMark(self.questId, true) end)
    return m
end

local function Update()
    if not next(pins) then return end
    local canvas = Canvas()
    if not canvas then return end
    local shown = DisplayedMap()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    for _, questId in ipairs(order) do
        local pin = pins[questId]
        local m = markers[questId]
        if pin and not m then
            m = CreateMarker(questId)
            markers[questId] = m
        end
        if m then
            local x, y = Project(pin, shown)
            if x and w and h and w > 1 and h > 1 then
                if m:GetParent() ~= canvas then m:SetParent(canvas) end
                m.pin = pin
                local glyph = pin.turnIn and "?" or "X"
                m.glyph:SetText(glyph)
                for _, shadow in ipairs(m.outline) do shadow:SetText(glyph) end
                m:ClearAllPoints()
                m:SetPoint("CENTER", canvas, "TOPLEFT", w * x, -h * y)
                m:SetFrameLevel(10000)
                m:Show()
                if m.pulseAnim and not m.pulseAnim:IsPlaying() then m.pulseAnim:Play() end
            else
                m:Hide()
            end
        end
    end
end
ns.UpdateMarks = Update

-- The map redraws its own pins when it changes; ours follow. Nothing of Blizzard's is written to.
local hooked = false
local function HookMap()
    if hooked or not WorldMapFrame then return end
    hooked = true
    pcall(function() WorldMapFrame:HookScript("OnShow", Update) end)
    if type(WorldMapFrame.OnMapChanged) == "function" then
        pcall(hooksecurefunc, WorldMapFrame, "OnMapChanged", Update)
    end
end

local driver = CreateFrame("Frame")
local elapsed = 0
driver:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.25 then return end
    elapsed = 0
    if next(pins) and WorldMapFrame and WorldMapFrame:IsShown() then Update() end
end)

local function ForceMap(mapID)
    if not WorldMapFrame or type(WorldMapFrame.SetMapID) ~= "function" then return false end
    return (pcall(WorldMapFrame.SetMapID, WorldMapFrame, mapID))
end

local function Forget(questId)
    pins[questId] = nil
    for i, id in ipairs(order) do
        if id == questId then table.remove(order, i) break end
    end
    local m = markers[questId]
    if m then m:Hide() end
end

-- ---------------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------------
function ns.ShowQuestOnMap(questId, title)
    local loc, why = ns.QuestLocation(questId)
    if not loc then
        Say((title and (title .. ": ") or "") .. (why or "no known location."))
        return false
    end
    HookMap()
    if pins[questId] then Forget(questId) end
    pins[questId] = { questId = questId, mapID = loc.mapID, x = loc.x, y = loc.y, label = loc.label, title = title, turnIn = loc.turnIn }
    order[#order + 1] = questId

    local opened = false
    local inCombat = InCombatLockdown and InCombatLockdown()
    if not inCombat then
        if C_Map and type(C_Map.OpenWorldMap) == "function" then
            opened = (pcall(C_Map.OpenWorldMap, loc.mapID))
        elseif type(OpenWorldMap) == "function" then
            opened = (pcall(OpenWorldMap, loc.mapID))
        end
    end
    ForceMap(loc.mapID)
    -- "opened" means the map is on screen now, whether this call opened it or it already was
    opened = opened or (WorldMapFrame and WorldMapFrame:IsShown() and true) or false
    Update()
    -- the map settles over a few frames after it opens: set the view and the pins again
    for _, delay in ipairs({ 0.03, 0.10, 0.25, 0.50 }) do
        C_Timer.After(delay, function()
            if not pins[questId] then return end
            ForceMap(loc.mapID)
            Update()
        end)
    end
    if opened then
        Say("Marked " .. loc.label .. (title and (" for " .. title) or "") .. ".")
    elseif inCombat then
        Say("Marked " .. loc.label .. ". Open the map after combat to see it.")
    else
        Say("Marked " .. loc.label .. ", but the map would not open; open it yourself.")
    end
    return true
end

function ns.RemoveMark(questId, byPlayer)
    if not pins[questId] then return end
    Forget(questId)
    if byPlayer and GameTooltip then GameTooltip:Hide() end
end

function ns.ClearMarks()
    local n = #order
    for _, questId in ipairs({ unpack(order) }) do Forget(questId) end
    return n
end

function ns.MarkCount() return #order end
function ns.IsMarked(questId) return pins[questId] ~= nil end

-- a pin goes away by itself once its quest is picked up (pickup pins) or handed in
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("QUEST_ACCEPTED")
watcher:RegisterEvent("QUEST_TURNED_IN")
watcher:RegisterEvent("QUEST_REMOVED")
watcher:SetScript("OnEvent", function(_, event, a, b)
    if event == "QUEST_ACCEPTED" then
        local id = b or a      -- (logIndex, questId) on some clients, (questId) on others
        local pin = pins[id]
        if pin and not pin.turnIn then Forget(id) end
        locations[id] = nil
    else
        Forget(a)
        locations[a] = nil
    end
end)
