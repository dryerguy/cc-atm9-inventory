-- terminal.lua
-- Inventory network terminal for ATM9 modpack
-- Displays merged inventory from all nodes, with live search

-- ============================================================
-- CONFIG  (edit nodeIDs to match your node computer IDs)
-- ============================================================
local nodeIDs  = {2, 3, 4, 5}
local PROTOCOL = "inv_net"
local TIMEOUT  = 3    -- seconds to wait for node responses
local REFRESH  = 15   -- seconds between auto-refreshes

-- ============================================================
-- PERIPHERAL SETUP
-- ============================================================

-- Auto-detect wireless modem
local modemSide = nil
for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
    if peripheral.getType(side) == "modem" then
        modemSide = side
        break
    end
end

if not modemSide then
    error("No modem found! Attach a wireless modem.", 0)
end
rednet.open(modemSide)

-- Auto-detect monitor (optional)
local monitor = nil
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
        monitor = peripheral.wrap(name)
        monitor.setTextScale(0.5)
        break
    end
end

-- ============================================================
-- STATE
-- ============================================================
local sortedItems  = {}   -- {name, displayName, count} sorted by count desc
local nodeStatus   = {}   -- [id] = "online" | "offline"
local searchQuery  = ""
local queryActive  = false
local pendingNodes = 0
local rawCombined  = {}   -- name -> count accumulator during a query
local queryTimer   = nil
local refreshTimer = nil

-- ============================================================
-- HELPERS
-- ============================================================

local function stripNamespace(name)
    -- "minecraft:iron_ingot" -> "iron_ingot"
    return name:match(":(.+)$") or name
end

local function formatName(raw)
    -- Turn underscores to spaces and title-case
    local stripped = stripNamespace(raw)
    return (stripped:gsub("_", " "):gsub("^%l", string.upper))
end

local function getFiltered()
    if searchQuery == "" then
        return sortedItems
    end
    local q = searchQuery:lower()
    local out = {}
    for _, item in ipairs(sortedItems) do
        if item.displayName:lower():find(q, 1, true) then
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
    local w, h = display.getSize()

    display.setBackgroundColor(colors.black)
    display.clear()

    local function setColor(fg)
        if isColor then display.setTextColor(fg) end
    end

    -- Header
    setColor(colors.yellow)
    display.setCursorPos(1, 1)
    local title = " Inventory Network "
    local pad = math.floor((w - #title) / 2)
    display.write(string.rep("=", pad) .. title .. string.rep("=", w - pad - #title))

    -- Node status line
    setColor(colors.white)
    display.setCursorPos(1, 2)
    local onlineCount = 0
    for _, id in ipairs(nodeIDs) do
        if nodeStatus[id] == "online" then onlineCount = onlineCount + 1 end
    end
    local total = #nodeIDs
    local statusLine = "Nodes: " .. onlineCount .. "/" .. total
    if isColor then
        if onlineCount == total then
            display.setTextColor(colors.lime)
        elseif onlineCount > 0 then
            display.setTextColor(colors.orange)
        else
            display.setTextColor(colors.red)
        end
    end
    display.write(statusLine)

    -- Item list (rows 3 to h-2, leaving room for footer and search)
    local listStart = 3
    local listEnd   = h - 2
    local listRows  = listEnd - listStart + 1

    for i = 1, listRows do
        local item = filtered[i]
        display.setCursorPos(1, listStart + i - 1)
        setColor(colors.white)
        if item then
            local countStr = tostring(item.count)
            local nameMax  = w - #countStr - 2
            local name     = item.displayName
            if #name > nameMax then name = name:sub(1, nameMax - 1) .. "~" end
            display.write(name .. string.rep(" ", w - #name - #countStr) .. countStr)
        else
            display.write(string.rep(" ", w))
        end
    end

    -- Footer: item type count
    setColor(isColor and colors.gray or colors.white)
    display.setCursorPos(1, h - 1)
    local footerText = " " .. #filtered .. " types shown (" .. #sortedItems .. " total)"
    display.write(footerText:sub(1, w))

    -- Search bar
    setColor(colors.white)
    display.setCursorPos(1, h)
    local searchDisplay = "Search: " .. searchQuery
    if #searchDisplay < w then
        searchDisplay = searchDisplay .. string.rep(" ", w - #searchDisplay)
    end
    display.write(searchDisplay:sub(1, w))
end

local function render()
    local filtered = getFiltered()
    renderTo(term, filtered)
    if monitor then
        renderTo(monitor, filtered)
    end
    -- Restore cursor to search bar on main terminal
    local _, h = term.getSize()
    term.setCursorPos(9 + #searchQuery, h)
end

-- ============================================================
-- NODE QUERYING
-- ============================================================

local function startQuery()
    rawCombined  = {}
    pendingNodes = 0
    queryActive  = true

    for _, id in ipairs(nodeIDs) do
        nodeStatus[id] = nodeStatus[id] or "offline"
        rednet.send(id, "list", PROTOCOL)
        pendingNodes = pendingNodes + 1
    end

    queryTimer = os.startTimer(TIMEOUT)
end

local function finishQuery()
    queryActive = false

    -- Build sorted list from rawCombined
    sortedItems = {}
    for name, count in pairs(rawCombined) do
        sortedItems[#sortedItems + 1] = {
            name        = name,
            displayName = formatName(name),
            count       = count,
        }
    end
    table.sort(sortedItems, function(a, b) return a.count > b.count end)

    render()
end

local function handleRednetMessage(senderID, message, protocol)
    if not queryActive then return end
    if protocol ~= PROTOCOL then return end

    -- Check if this sender is one of our nodes
    local isNode = false
    for _, id in ipairs(nodeIDs) do
        if id == senderID then isNode = true; break end
    end
    if not isNode then return end

    nodeStatus[senderID] = "online"

    if type(message) == "string" and message:sub(1, 6) ~= "error:" then
        local ok, items = pcall(textutils.unserialize, message)
        if ok and type(items) == "table" then
            for _, item in ipairs(items) do
                local name  = item.name or "unknown"
                local count = item.count or 1
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

-- Mark all nodes offline at start
for _, id in ipairs(nodeIDs) do
    nodeStatus[id] = "offline"
end

render()
startQuery()  -- Immediate first query

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" then
        if p1 == queryTimer and queryActive then
            -- Timeout: mark non-responding nodes offline, finish up
            for _, id in ipairs(nodeIDs) do
                if nodeStatus[id] ~= "online" then
                    nodeStatus[id] = "offline"
                end
            end
            finishQuery()
            refreshTimer = os.startTimer(REFRESH)

        elseif p1 == refreshTimer then
            -- Reset online status before re-querying
            for _, id in ipairs(nodeIDs) do
                nodeStatus[id] = "offline"
            end
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
