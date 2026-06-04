-- terminal.lua
-- Inventory network terminal — aggregates and displays all node data

-- ============================================================
-- CONFIG
-- ============================================================
local NODE_IDS = {5}
local PROTOCOL = "inv_net"
local TIMEOUT  = 3
local REFRESH  = 15

-- ============================================================
-- PERIPHERAL SETUP
-- ============================================================

-- Find wireless (ender) modem
local modemSide = nil
for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == "modem" then
        local m = peripheral.wrap(side)
        if m and m.isWireless() then
            modemSide = side
            break
        end
    end
end

if not modemSide then
    error("No wireless modem found. Attach an Ender Modem.", 0)
end
rednet.open(modemSide)

-- Find monitor (optional)
local monitor = nil
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "monitor") then
        monitor = peripheral.wrap(name)
        monitor.setTextScale(0.5)
        break
    end
end

-- ============================================================
-- STATE
-- ============================================================
local sortedItems  = {}   -- [{name, displayName, count}] sorted by count desc
local nodeStatus   = {}   -- [id] = "online" | "offline"
local searchQuery  = ""

local queryActive  = false
local pendingNodes = 0
local rawCombined  = {}
local queryTimer   = nil
local refreshTimer = nil

for _, id in ipairs(NODE_IDS) do
    nodeStatus[id] = "offline"
end

-- ============================================================
-- HELPERS
-- ============================================================
local function formatName(raw)
    local stripped = raw:match(":(.+)$") or raw
    return (stripped:gsub("_", " "):gsub("^%l", string.upper))
end

local function getFiltered()
    if searchQuery == "" then return sortedItems end
    local q = searchQuery:lower()
    local out = {}
    for _, item in ipairs(sortedItems) do
        if item.displayName:lower():find(q, 1, true) or
           item.name:lower():find(q, 1, true) then
            out[#out + 1] = item
        end
    end
    return out
end

-- ============================================================
-- RENDERING
-- ============================================================
local function renderTo(display, filtered)
    local isColor = display.isColor()
    local w, h    = display.getSize()

    display.setBackgroundColor(colors.black)
    display.clear()

    local function fg(c)
        if isColor then display.setTextColor(c) end
    end

    -- Header
    fg(colors.yellow)
    display.setCursorPos(1, 1)
    local title = " Inventory Network "
    local pad   = math.floor((w - #title) / 2)
    display.write(string.rep("=", pad) .. title .. string.rep("=", w - pad - #title))

    -- Node status
    local onlineCount = 0
    for _, id in ipairs(NODE_IDS) do
        if nodeStatus[id] == "online" then onlineCount = onlineCount + 1 end
    end
    display.setCursorPos(1, 2)
    if isColor then
        if onlineCount == #NODE_IDS then fg(colors.lime)
        elseif onlineCount > 0       then fg(colors.orange)
        else                              fg(colors.red) end
    end
    local statusStr = "Nodes: " .. onlineCount .. "/" .. #NODE_IDS
    display.write(statusStr .. string.rep(" ", w - #statusStr))

    -- Item list (rows 3 to h-2)
    local listStart = 3
    local listEnd   = h - 2
    local listRows  = listEnd - listStart + 1

    for i = 1, listRows do
        local item = filtered[i]
        display.setCursorPos(1, listStart + i - 1)
        fg(colors.white)
        if item then
            local countStr = tostring(item.count)
            local nameMax  = w - #countStr - 1
            local name     = item.displayName
            if #name > nameMax then name = name:sub(1, nameMax - 1) .. "~" end
            local spaces   = w - #name - #countStr
            display.write(name .. string.rep(" ", math.max(1, spaces)) .. countStr)
        else
            display.write(string.rep(" ", w))
        end
    end

    -- Footer
    fg(isColor and colors.gray or colors.white)
    display.setCursorPos(1, h - 1)
    local footer = " " .. #filtered .. " types (" .. #sortedItems .. " total)"
    display.write(footer .. string.rep(" ", math.max(0, w - #footer)))

    -- Search bar
    fg(colors.white)
    display.setCursorPos(1, h)
    local searchLine = "Search: " .. searchQuery
    display.write(searchLine .. string.rep(" ", math.max(0, w - #searchLine)))
end

local function render()
    local filtered = getFiltered()
    renderTo(term, filtered)
    if monitor then renderTo(monitor, filtered) end
    -- Park cursor at end of search input
    local _, h = term.getSize()
    term.setCursorPos(9 + #searchQuery, h)
end

-- ============================================================
-- NODE QUERYING (event-driven, non-blocking)
-- ============================================================
local function startQuery()
    rawCombined  = {}
    pendingNodes = 0
    queryActive  = true
    for _, id in ipairs(NODE_IDS) do
        nodeStatus[id] = "offline"
        rednet.send(id, "list", PROTOCOL)
        pendingNodes = pendingNodes + 1
    end
    queryTimer = os.startTimer(TIMEOUT)
end

local function finishQuery()
    queryActive = false
    sortedItems = {}
    for name, count in pairs(rawCombined) do
        sortedItems[#sortedItems + 1] = {
            name        = name,
            displayName = formatName(name),
            count       = count,
        }
    end
    table.sort(sortedItems, function(a, b) return a.count > b.count end)
    -- Share latest data with chatbot running in parallel
    _G.sharedInventory = sortedItems
    render()
end

local function handleRednetMessage(senderID, message, protocol)
    if not queryActive or protocol ~= PROTOCOL then return end
    local isNode = false
    for _, id in ipairs(NODE_IDS) do
        if id == senderID then isNode = true; break end
    end
    if not isNode then return end

    nodeStatus[senderID] = "online"
    local ok, inv = pcall(textutils.unserialize, message)
    if ok and type(inv) == "table" then
        for name, count in pairs(inv) do
            if type(name) == "string" and type(count) == "number" then
                rawCombined[name] = (rawCombined[name] or 0) + count
            end
        end
    end

    pendingNodes = pendingNodes - 1
    if pendingNodes <= 0 then
        finishQuery()
        refreshTimer = os.startTimer(REFRESH)
    end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
_G.sharedInventory = {}
render()
startQuery()

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" then
        if p1 == queryTimer and queryActive then
            finishQuery()
            refreshTimer = os.startTimer(REFRESH)
        elseif p1 == refreshTimer then
            startQuery()
        end

    elseif event == "rednet_message" then
        handleRednetMessage(p1, p2, p3)

    elseif event == "char" then
        searchQuery = searchQuery .. p1
        render()

    elseif event == "key" then
        if p1 == keys.backspace then
            searchQuery = searchQuery:sub(1, -2)
            render()
        elseif p1 == keys.delete then
            searchQuery = ""
            render()
        end

    elseif event == "term_resize" or event == "monitor_resize" then
        render()
    end
end
