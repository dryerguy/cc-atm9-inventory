-- terminal.lua
-- Inventory network terminal — aggregates and displays all node data

-- ============================================================
-- CONFIG  (edit NODE_IDS to match your node computer IDs)
-- ============================================================
local NODE_IDS = {5}
local PROTOCOL = "inv_net"
local TIMEOUT  = 3    -- seconds to wait for node responses
local REFRESH  = 15   -- seconds between auto-refreshes

-- ============================================================
-- PERIPHERAL SETUP
-- ============================================================

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
if not modemSide then error("No wireless modem found. Attach an Ender Modem.", 0) end
rednet.open(modemSide)

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
local sortedItems  = {}     -- [{name, displayName, count}] sorted by count desc
local nodeStatus   = {}     -- [id] = "online" | "offline"
local searchQuery  = ""
local scrollOffset = 0      -- rows scrolled down in item list
local lastRefresh  = nil    -- os.clock() value at last finishQuery
local queryActive  = false  -- true while waiting for node responses
local pendingNodes = 0
local rawCombined  = {}
local queryTimer   = nil
local refreshTimer = nil

for _, id in ipairs(NODE_IDS) do nodeStatus[id] = "offline" end

_G.sharedInventory = {}

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

local function countColor(isColor, count)
    if not isColor then return end
    if count < 64 then
        term.setTextColor(colors.red)
    elseif count <= 256 then
        term.setTextColor(colors.yellow)
    else
        term.setTextColor(colors.lime)
    end
end

local function countColorOn(display, isColor, count)
    if not isColor then return end
    if count < 64 then
        display.setTextColor(colors.red)
    elseif count <= 256 then
        display.setTextColor(colors.yellow)
    else
        display.setTextColor(colors.lime)
    end
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
    local function resetFg()
        if isColor then display.setTextColor(colors.white) end
    end

    -- Line 1: Header
    fg(colors.yellow)
    display.setCursorPos(1, 1)
    local title = " Inventory Network "
    local pad   = math.floor((w - #title) / 2)
    display.write(string.rep("=", pad) .. title .. string.rep("=", w - pad - #title))

    -- Line 2: Node status + refresh info
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
    local nodeStr = "Nodes: " .. onlineCount .. "/" .. #NODE_IDS
    display.write(nodeStr)

    -- Refresh status (right-aligned on line 2)
    resetFg()
    local refreshStr
    if queryActive then
        if isColor then fg(colors.cyan) end
        refreshStr = "[ QUERYING... ]"
    elseif lastRefresh then
        local age = math.floor(os.clock() - lastRefresh)
        refreshStr = "[ +" .. age .. "s ]"
    else
        refreshStr = "[ -- ]"
    end
    local rpos = w - #refreshStr + 1
    if rpos > #nodeStr + 2 then
        display.setCursorPos(rpos, 2)
        display.write(refreshStr)
    end

    -- Lines 3 to h-2: Item list
    local listStart = 3
    local listEnd   = h - 2
    local listRows  = listEnd - listStart + 1
    local canScrollUp   = scrollOffset > 0
    local canScrollDown = #filtered > scrollOffset + listRows

    for i = 1, listRows do
        local item = filtered[i + scrollOffset]
        display.setCursorPos(1, listStart + i - 1)
        if item then
            local countStr = tostring(item.count)
            local nameMax  = w - #countStr - 1
            local name     = item.displayName
            if #name > nameMax then name = name:sub(1, nameMax - 1) .. "~" end
            local spaces   = w - #name - #countStr
            resetFg()
            display.write(name .. string.rep(" ", math.max(1, spaces)))
            countColorOn(display, isColor, item.count)
            display.write(countStr)
        else
            resetFg()
            display.write(string.rep(" ", w))
        end
    end

    -- Line h-1: Footer
    fg(isColor and colors.gray or colors.white)
    display.setCursorPos(1, h - 1)
    local scrollHint = ""
    if canScrollUp and canScrollDown then scrollHint = " [↑↓]"
    elseif canScrollUp   then scrollHint = " [↑]"
    elseif canScrollDown then scrollHint = " [↓]"
    end
    local footer = " " .. #filtered .. " types (" .. #sortedItems .. " total)" .. scrollHint
    display.write(footer .. string.rep(" ", math.max(0, w - #footer)))

    -- Line h: Search bar
    resetFg()
    display.setCursorPos(1, h)
    local prompt = "Search: " .. searchQuery
    local hint   = "  [R]=refresh [Esc]=clear"
    local searchLine = prompt
    if #prompt + #hint <= w then
        fg(isColor and colors.gray or colors.white)
        searchLine = prompt .. string.rep(" ", w - #prompt - #hint) .. hint
    else
        searchLine = prompt .. string.rep(" ", math.max(0, w - #prompt))
    end
    resetFg()
    display.setCursorPos(1, h)
    display.write(searchLine:sub(1, w))
end

local function render()
    local filtered = getFiltered()
    -- Clamp scroll to valid range
    local _, h  = term.getSize()
    local rows  = h - 4
    local maxScroll = math.max(0, #filtered - rows)
    if scrollOffset > maxScroll then scrollOffset = maxScroll end

    renderTo(term, filtered)
    if monitor then renderTo(monitor, filtered) end
    -- Park cursor at end of search input
    local _, th = term.getSize()
    term.setCursorPos(9 + #searchQuery, th)
end

-- ============================================================
-- NODE QUERYING (event-driven, non-blocking)
-- ============================================================
local function startQuery()
    rawCombined  = {}
    pendingNodes = #NODE_IDS
    queryActive  = true
    -- Don't reset nodeStatus here — keep previous status visible until
    -- timeout or response. Only mark offline on timeout.
    for _, id in ipairs(NODE_IDS) do
        rednet.send(id, "list", PROTOCOL)
    end
    queryTimer = os.startTimer(TIMEOUT)
    render()
end

local function finishQuery()
    queryActive  = false
    lastRefresh  = os.clock()
    sortedItems  = {}
    for name, count in pairs(rawCombined) do
        sortedItems[#sortedItems + 1] = {
            name        = name,
            displayName = formatName(name),
            count       = count,
        }
    end
    table.sort(sortedItems, function(a, b) return a.count > b.count end)
    _G.sharedInventory = sortedItems
    scrollOffset = 0
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
render()
startQuery()

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" then
        if p1 == queryTimer and queryActive then
            -- Timeout: mark non-responding nodes offline
            for _, id in ipairs(NODE_IDS) do
                if nodeStatus[id] ~= "online" then
                    nodeStatus[id] = "offline"
                end
            end
            finishQuery()
            refreshTimer = os.startTimer(REFRESH)

        elseif p1 == refreshTimer and not queryActive then
            startQuery()
        end

    elseif event == "rednet_message" then
        handleRednetMessage(p1, p2, p3)

    elseif event == "char" then
        local ch = p1
        if ch:lower() == "r" and searchQuery == "" then
            -- Force refresh
            if refreshTimer then refreshTimer = nil end
            if not queryActive then startQuery() end
        else
            searchQuery = searchQuery .. ch
            scrollOffset = 0
            render()
        end

    elseif event == "key" then
        if p1 == keys.backspace then
            searchQuery = searchQuery:sub(1, -2)
            scrollOffset = 0
            render()
        elseif p1 == keys.delete or p1 == keys.escape then
            searchQuery = ""
            scrollOffset = 0
            render()
        elseif p1 == keys.up then
            if scrollOffset > 0 then
                scrollOffset = scrollOffset - 1
                render()
            end
        elseif p1 == keys.down then
            local filtered = getFiltered()
            local _, h = term.getSize()
            local rows = h - 4
            if scrollOffset < #filtered - rows then
                scrollOffset = scrollOffset + 1
                render()
            end
        end

    elseif event == "term_resize" or event == "monitor_resize" then
        scrollOffset = 0
        render()
    end
end
