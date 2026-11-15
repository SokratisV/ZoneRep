-- ZoneRep core. Questie supplies everything about quests (which ones give reputation, how much, in
-- which zone, for which races and classes, which are hidden or repeatable, which are done); this file
-- adds up, per zone and faction, what the zone's one-time quests give, what this character has earned
-- and what is left. Rep from kills and other sources is in no database, so it is measured while you
-- play and filed under the zone you were standing in.
local ADDON, ns = ...
ns.name = ADDON

local floor = math.floor

-- ---------------------------------------------------------------------------------------------
-- Saved variables. They arrive EMPTY at ADDON_LOADED on this client and the real table replaces the
-- global a little later, so the table is never cached: it is looked up through the global each time.
-- ---------------------------------------------------------------------------------------------
local function DB()
    local db = _G.ZoneRepDB
    if type(db) ~= "table" then
        db = {}
        _G.ZoneRepDB = db
    end
    db.ui = db.ui or {}
    db.chars = db.chars or {}
    return db
end
ns.DB = DB

local function CharData()
    local chars = DB().chars
    local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    local c = chars[key]
    if not c then
        c = {}
        chars[key] = c
    end
    c.other = c.other or {}
    return c
end

-- ---------------------------------------------------------------------------------------------
-- Questie. Looked up late (at first use), because its database finishes initialising after login.
-- ---------------------------------------------------------------------------------------------
local function Import(name)
    if QuestieLoader and QuestieLoader.ImportModule then
        local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, name)
        if ok then return mod end
    end
end

-- Returns the Questie pieces, or nil and a reason while Questie is not ready.
local function Questie_()
    local QuestieDB = Import("QuestieDB")
    if not QuestieDB or not QuestieDB.QueryQuestSingle then return nil, "Questie's database is not loaded yet." end
    local Rep = Import("QuestieReputation")
    local Corr = Import("QuestieCorrections")
    if not Rep or not Rep.GetReputationReward then return nil, "This Questie has no reputation module." end
    local hidden = Corr and Corr.hiddenQuests
    if not hidden or not _G.Questie or not Questie.db or not Questie.db.char then
        return nil, "Questie is still starting up."
    end
    local ids = (_G.LibQuestieDB and LibQuestieDB.Quest and LibQuestieDB.Quest.GetAllIds(true)) or QuestieDB.QuestPointers
    if type(ids) ~= "table" then return nil, "Questie has not listed its quests yet." end
    return {
        db = QuestieDB, rep = Rep, hidden = hidden, ids = ids, l10n = Import("l10n"),
        player = Import("QuestiePlayer"), zone = Import("ZoneDB"),
    }
end
ns.Questie = Questie_

-- ---------------------------------------------------------------------------------------------
-- Client lookups, all feature-detected (this client only has the namespaced API).
-- ---------------------------------------------------------------------------------------------
-- The client only names factions that are in this character's reputation list (other race's
-- capitals, factions not yet discovered, newer factions come back empty). Questie's own faction
-- enum (keys like DUROTAR_SUPPLY_AND_LOGISTICS) names most of the rest.
local factionNames = {}
local enumNames
local SMALL = { ["and"] = true, ["of"] = true, ["the"] = true, ["to"] = true, ["in"] = true }
local function PrettyKey(key)
    local words = {}
    for word in key:gmatch("[^_]+") do words[#words + 1] = word:lower() end
    if #words > 1 and words[#words] == "forever" then words[#words] = nil end   -- disambiguation suffix
    for i, w in ipairs(words) do
        if i == 1 or not SMALL[w] then words[i] = w:sub(1, 1):upper() .. w:sub(2) end
    end
    return table.concat(words, " ")
end
local function EnumName(id)
    if not enumNames then
        enumNames = {}
        local db = Import("QuestieDB")
        local enum = db and db.factionIDs
        if type(enum) ~= "table" then
            enum = _G.LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.factionIDs
        end
        if type(enum) == "table" then
            local keys = {}
            for key in pairs(enum) do keys[#keys + 1] = key end
            table.sort(keys)
            for _, key in ipairs(keys) do
                local fid = enum[key]
                if type(fid) == "number" and not enumNames[fid] then enumNames[fid] = PrettyKey(key) end
            end
        end
    end
    return enumNames[id]
end

local function FactionName(id)
    local n = factionNames[id]
    if n then return n end
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local d = C_Reputation.GetFactionDataByID(id)
        n = d and d.name
    end
    if not n and GetFactionInfoByID then n = (GetFactionInfoByID(id)) end
    if type(n) == "string" and n ~= "" then
        factionNames[id] = n
        return n
    end
end
-- The client's name, else Questie's enum name, else "Faction <id>".
ns.FactionName = function(id)
    local n = FactionName(id)
    if n then return n end
    n = EnumName(id)
    if n then return n end
    return "Faction " .. id
end
ns.PrettyKey = PrettyKey

-- The absolute reputation value (-42000 .. 42000), nil when unreadable.
local function Standing(id)
    local v
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local d = C_Reputation.GetFactionDataByID(id)
        v = d and d.currentStanding
    elseif GetFactionInfoByID then
        v = select(6, GetFactionInfoByID(id))
    end
    if type(v) ~= "number" or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function IsDone(questId)
    if C_QuestLog.IsQuestFlaggedCompleted(questId) then return true end
    local q = _G.Questie
    return (q and q.db and q.db.char and q.db.char.complete and q.db.char.complete[questId]) and true or false
end

-- Can this character take the quest by race and class? Questie decides: its race masks are not
-- simply bit (raceId - 1) (Forever's Skyborne races, ids 95/96, sit on bits 32/33), so its own
-- QuestiePlayer functions are used. Without them, its published id -> mask table is the fallback.
local function Allowed(Q, e)
    local p = Q and Q.player
    if p and p.HasRequiredRace and p.HasRequiredClass then
        return p.HasRequiredRace(e.races) and p.HasRequiredClass(e.classes)
    end
    local _, _, raceId = UnitRace("player")
    local _, _, classId = UnitClass("player")
    local enum = _G.LibQuestieDB and LibQuestieDB.Enum
    local raceFlag = enum and enum.raceMaskById and enum.raceMaskById[raceId] or 2 ^ ((raceId or 1) - 1)
    local classFlag = 2 ^ ((classId or 1) - 1)
    local raceOk = not e.races or e.races == 0 or e.races % (raceFlag * 2) >= raceFlag
    local classOk = not e.classes or e.classes == 0 or e.classes % (classFlag * 2) >= classFlag
    return raceOk and classOk
end

local SPECIAL, UNKNOWN = "special", "unknown"
local function ZoneKey(z)
    if type(z) ~= "number" or z == 0 then return UNKNOWN end
    if z < 0 then return SPECIAL end
    return z
end

local function Localised(Q, text)
    if Q.l10n and type(text) == "string" then
        local ok, out = pcall(Q.l10n, text)
        if ok and type(out) == "string" then return out end
    end
    return text
end

local areaNames = {}
local function ZoneLabel(Q, key)
    if key == SPECIAL then return "Class, profession and event quests" end
    if key == UNKNOWN then return "Unsorted quests" end
    local n = areaNames[key]
    if n then return n end
    if C_Map and C_Map.GetAreaInfo then
        n = C_Map.GetAreaInfo(key)
    elseif GetAreaInfo then
        n = GetAreaInfo(key)
    end
    if type(n) ~= "string" or n == "" then
        local lookup = Q.l10n and Q.l10n.zoneLookup
        n = lookup and lookup[key] and Localised(Q, lookup[key])
    end
    if type(n) == "string" and n ~= "" then
        areaNames[key] = n
        return n
    end
    return "Zone " .. key
end

-- ---------------------------------------------------------------------------------------------
-- The quest index: every one-time, visible quest that gives positive reputation, built once from
-- Questie in slices so the game does not stall, then reused.
-- ---------------------------------------------------------------------------------------------
-- index = { quests = { {id, zone, races, classes, name, rewards = {faction, value, ...}, exclusive = {ids}} },
--           byId = {}, factions = {ids} }
local index, building
ns.indexError = nil

local function BuildEntry(Q, id)
    local db = Q.db
    local raw = db.QueryQuestSingle(id, "reputationReward")
    if type(raw) ~= "table" or #raw == 0 then return nil end
    if Q.hidden[id] then return nil end
    local flags = db.QueryQuestSingle(id, "specialFlags")
    if type(flags) == "number" and flags % 2 >= 1 then return nil end       -- repeatable
    if db.IsDailyQuest and db.IsDailyQuest(id) then return nil end
    if db.IsWeeklyQuest and db.IsWeeklyQuest(id) then return nil end
    -- Questie's own reading of the reward (race bonuses, scaling); the raw pairs if that fails
    local ok, pairs_ = pcall(Q.rep.GetReputationReward, id)
    if not ok or type(pairs_) ~= "table" then pairs_ = raw end
    local rewards = {}
    for _, p in ipairs(pairs_) do
        if type(p[1]) == "number" and type(p[2]) == "number" and p[2] > 0 then
            rewards[#rewards + 1] = p[1]
            rewards[#rewards + 1] = floor(p[2] + 0.5)
        end
    end
    if #rewards == 0 then return nil end
    local ex = db.QueryQuestSingle(id, "exclusiveTo")
    return {
        id = id,
        zone = ZoneKey(db.QueryQuestSingle(id, "zoneOrSort")),
        races = db.QueryQuestSingle(id, "requiredRaces"),
        classes = db.QueryQuestSingle(id, "requiredClasses"),
        name = db.QueryQuestSingle(id, "name") or ("Quest " .. id),
        rewards = rewards,
        exclusive = type(ex) == "table" and ex or nil,
    }
end

local function Finish(Q, quests)
    local byId, factionSet = {}, {}
    for _, e in ipairs(quests) do
        byId[e.id] = e
        for i = 1, #e.rewards, 2 do factionSet[e.rewards[i]] = true end
    end
    -- every faction Questie knows by name too, so kill-only factions are watched as well
    local named = Q.db.factionIDs
    if type(named) == "table" then
        for _, fid in pairs(named) do
            if type(fid) == "number" then factionSet[fid] = true end
        end
    end
    local factions = {}
    for fid in pairs(factionSet) do factions[#factions + 1] = fid end
    table.sort(factions)
    -- Exclusive quests (only one of a set can ever be done) are tied into groups.
    local parent = {}
    local function find(x)
        while parent[x] and parent[x] ~= x do
            parent[x] = parent[parent[x]] or parent[x]
            x = parent[x]
        end
        return x
    end
    for _, e in ipairs(quests) do
        if e.exclusive then
            for _, other in ipairs(e.exclusive) do
                if byId[other] then
                    parent[e.id] = parent[e.id] or e.id
                    parent[other] = parent[other] or other
                    local a, b = find(e.id), find(other)
                    if a ~= b then parent[b] = a end
                end
            end
        end
    end
    for _, e in ipairs(quests) do
        if parent[e.id] then e.group = find(e.id) end
    end
    index = { quests = quests, byId = byId, factions = factions }
end

local SLICE = 400
-- Builds the index in slices; calls done() when it is ready (immediately if it already is).
function ns.EnsureIndex(done)
    if index then
        if done then done() end
        return
    end
    if building then
        building.waiting[#building.waiting + 1] = done
        return
    end
    building = { waiting = { done } }
    local Q, quests, list, pos = nil, {}, nil, 1
    local function step()
        if not Q then
            local why
            Q, why = Questie_()
            if not Q then
                ns.indexError = why
                Q = nil
                C_Timer.After(1, step)
                if ns.OnChange then ns.OnChange() end
                return
            end
            ns.indexError = nil
            list = {}
            for id in pairs(Q.ids) do list[#list + 1] = id end
            table.sort(list)
        end
        local stop = math.min(pos + SLICE - 1, #list)
        for i = pos, stop do
            local e = BuildEntry(Q, list[i])
            if e then quests[#quests + 1] = e end
        end
        pos = stop + 1
        if pos <= #list then
            C_Timer.After(0, step)
            return
        end
        Finish(Q, quests)
        local waiting = building.waiting
        building = nil
        for _, cb in ipairs(waiting) do
            if cb then cb() end
        end
    end
    step()
end

function ns.IndexReady() return index ~= nil end

-- Forget the index so the next use rebuilds it (after a Questie data change).
function ns.Rescan()
    index = nil
end

-- ---------------------------------------------------------------------------------------------
-- Compute: the whole picture for this character. Requires the index (see EnsureIndex).
-- ---------------------------------------------------------------------------------------------
-- Returns { zones = {...}, factions = {...}, earned, total, left, other }, every zone and faction
-- carrying cells { faction, name, earned, total, left, other, done, pending = {{id,title,value}} }.
function ns.Compute()
    if not index then return nil end
    local Q = Questie_()
    local picked, groups = {}, {}
    for _, e in ipairs(index.quests) do
        if Allowed(Q, e) then
            if not e.group then
                picked[#picked + 1] = e
            else
                local list = groups[e.group]
                if not list then
                    list = {}
                    groups[e.group] = list
                end
                list[#list + 1] = e
            end
        end
    end
    -- Only one quest of an exclusive set can ever be done, so the set counts once: the one already
    -- done, else the most generous.
    local ordered = {}
    for g in pairs(groups) do ordered[#ordered + 1] = g end
    table.sort(ordered)
    for _, g in ipairs(ordered) do
        local list, rep = groups[g], nil
        for _, e in ipairs(list) do
            if IsDone(e.id) then rep = e break end
        end
        if not rep then
            local best = -1
            for _, e in ipairs(list) do
                local s = 0
                for i = 2, #e.rewards, 2 do s = s + e.rewards[i] end
                if s > best then best, rep = s, e end
            end
        end
        picked[#picked + 1] = rep
    end

    local zoneByKey, zoneByName = {}, {}
    local function zoneFor(key, name)
        local z = zoneByKey[key]
        if not z then
            z = {
                key = key, name = name or (Q and ZoneLabel(Q, key)) or tostring(key),
                cells = {}, byFaction = {}, special = key == SPECIAL or key == UNKNOWN,
            }
            zoneByKey[key] = z
            zoneByName[z.name] = z
        end
        return z
    end
    local function cellFor(z, fid)
        local c = z.byFaction[fid]
        if not c then
            c = { faction = fid, zone = z, earned = 0, total = 0, left = 0, other = 0, done = 0, pending = {} }
            z.byFaction[fid] = c
            z.cells[#z.cells + 1] = c
        end
        return c
    end

    for _, e in ipairs(picked) do
        local z = zoneFor(e.zone)
        local done = IsDone(e.id)
        local r = e.rewards
        for i = 1, #r, 2 do
            local c = cellFor(z, r[i])
            local v = r[i + 1]
            c.total = c.total + v
            if done then
                c.earned = c.earned + v
                c.done = c.done + 1
            else
                c.left = c.left + v
                c.pending[#c.pending + 1] = { id = e.id, title = e.name, value = v }
            end
        end
    end

    local otherNames = {}
    for zoneName in pairs(CharData().other) do otherNames[#otherNames + 1] = zoneName end
    table.sort(otherNames)
    for _, zoneName in ipairs(otherNames) do
        local z = zoneByName[zoneName] or zoneFor("name:" .. zoneName, zoneName)
        for fid, amount in pairs(CharData().other[zoneName]) do
            cellFor(z, fid).other = amount
        end
    end

    local result = { zones = {}, factions = {}, earned = 0, total = 0, left = 0, other = 0 }
    local factionById = {}
    for _, z in pairs(zoneByKey) do
        z.earned, z.total, z.left, z.other = 0, 0, 0, 0
        for _, c in ipairs(z.cells) do
            c.name = ns.FactionName(c.faction)
            z.earned, z.total, z.left, z.other = z.earned + c.earned, z.total + c.total, z.left + c.left, z.other + c.other
            local f = factionById[c.faction]
            if not f then
                f = { id = c.faction, name = c.name, cells = {}, earned = 0, total = 0, left = 0, other = 0 }
                factionById[c.faction] = f
                result.factions[#result.factions + 1] = f
            end
            f.cells[#f.cells + 1] = c
            f.earned, f.total, f.left, f.other = f.earned + c.earned, f.total + c.total, f.left + c.left, f.other + c.other
            table.sort(c.pending, function(a, b)
                if a.value ~= b.value then return a.value > b.value end
                return a.id < b.id
            end)
        end
        table.sort(z.cells, function(a, b)
            if a.total ~= b.total then return a.total > b.total end
            return a.name < b.name
        end)
        result.zones[#result.zones + 1] = z
        result.earned, result.total, result.left, result.other = result.earned + z.earned, result.total + z.total, result.left + z.left, result.other + z.other
    end
    table.sort(result.zones, function(a, b)
        if a.special ~= b.special then return not a.special end
        return a.name < b.name
    end)
    table.sort(result.factions, function(a, b) return a.name < b.name end)
    for _, f in ipairs(result.factions) do
        table.sort(f.cells, function(a, b)
            if a.zone.special ~= b.zone.special then return not a.zone.special end
            return a.zone.name < b.zone.name
        end)
    end
    return result
end

-- ---------------------------------------------------------------------------------------------
-- Live tracking of rep that no quest explains.
-- ---------------------------------------------------------------------------------------------
local snapshot, ready = {}, false
local questWindow = {}      -- factionId -> GetTime() until which a gain belongs to a quest turn-in
local scheduled = false

local function ReadAll()
    local out = {}
    for _, fid in ipairs(index and index.factions or {}) do
        local s = Standing(fid)
        if s ~= nil then out[fid] = s end
    end
    return out
end

local function Process()
    scheduled = false
    if not index then return end
    local now = ReadAll()
    if not ready then
        snapshot, ready = now, true
        return
    end
    local zone = GetRealZoneText()
    local usable = type(zone) == "string" and zone ~= "" and not (issecretvalue and issecretvalue(zone))
    local t = GetTime()
    local changed = false
    for fid, cur in pairs(now) do
        local old = snapshot[fid]
        if old ~= nil and cur > old and usable then
            local win = questWindow[fid]
            if not (win and win >= t) then
                local per = CharData().other
                per[zone] = per[zone] or {}
                per[zone][fid] = (per[zone][fid] or 0) + (cur - old)
                changed = true
            end
        end
    end
    snapshot = now
    if changed and ns.OnChange then ns.OnChange() end
end

-- Several UPDATE_FACTION events (and the quest event that explains them) arrive together; look once.
local function Schedule()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.5, Process)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UPDATE_FACTION")
events:RegisterEvent("QUEST_TURNED_IN")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        -- standings can resolve late on this client: take the baseline a moment after entering
        ready = false
        scheduled = true
        C_Timer.After(2, function() ns.EnsureIndex(Process) end)
    elseif event == "UPDATE_FACTION" then
        Schedule()
    elseif event == "QUEST_TURNED_IN" then
        local e = index and index.byId[arg1]
        if e then
            local until_ = GetTime() + 3
            for i = 1, #e.rewards, 2 do questWindow[e.rewards[i]] = until_ end
        end
        if ns.OnChange then C_Timer.After(0.6, ns.OnChange) end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------------------------
local function Say(msg) print("|cffffd200ZoneRep|r " .. msg) end

SLASH_ZONEREP1 = "/zonerep"
SLASH_ZONEREP2 = "/zrep"
SlashCmdList.ZONEREP = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" then
        ns.Toggle()
    elseif msg == "reset" then
        CharData().other = {}
        Say("Cleared the rep tracked from kills and other sources for this character.")
        if ns.OnChange then ns.OnChange() end
    elseif msg == "clearmarks" then
        Say(("Removed %d map marks."):format(ns.ClearMarks()))
        if ns.OnChange then ns.OnChange() end
    elseif msg == "rescan" then
        ns.Rescan()
        ns.EnsureIndex(function()
            Say(#index.quests .. " reputation quests read from Questie.")
            if ns.OnChange then ns.OnChange() end
        end)
    elseif msg == "factions" then
        -- factions nobody can name: list them with the quests that give them, to work out what they are
        ns.EnsureIndex(function()
            local names, shown = {}, 0
            for _, e in ipairs(index.quests) do
                for i = 1, #e.rewards, 2 do
                    local fid = e.rewards[i]
                    if ns.FactionName(fid) == "Faction " .. fid then
                        names[fid] = names[fid] or {}
                        if #names[fid] < 3 then names[fid][#names[fid] + 1] = e.name end
                    end
                end
            end
            local ids = {}
            for fid in pairs(names) do ids[#ids + 1] = fid end
            table.sort(ids)
            for _, fid in ipairs(ids) do
                shown = shown + 1
                Say(("Faction %d: %s"):format(fid, table.concat(names[fid], "; ")))
            end
            if shown == 0 then Say("Every faction has a name.") end
        end)
    elseif msg == "debug" then
        local n, shown = 0, {}
        for fid, v in pairs(ReadAll()) do
            n = n + 1
            if #shown < 4 then shown[#shown + 1] = ns.FactionName(fid) .. " = " .. v end
        end
        local _, _, raceId = UnitRace("player")
        Say(("quest index: %s; tracker ready: %s; factions readable: %d of %d; zone: %s; race id %s"):format(
            index and (#index.quests .. " quests") or ("not built (" .. tostring(ns.indexError) .. ")"),
            tostring(ready), n, index and #index.factions or 0, tostring(GetRealZoneText()), tostring(raceId)))
        if index then
            local Q, mine = Questie_(), 0
            for _, e in ipairs(index.quests) do
                if Allowed(Q, e) then mine = mine + 1 end
            end
            Say(("%d of the %d reputation quests can be taken by this character"):format(mine, #index.quests))
        end
        if #shown > 0 then Say(table.concat(shown, ", ")) end
    else
        Say("/zonerep - open the window;  /zonerep reset - clear the tracked kill rep;  /zonerep clearmarks;  /zonerep rescan;  /zonerep factions;  /zonerep debug")
    end
end
