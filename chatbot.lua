-- chatbot.lua
-- Chat command handler for ATM9 inventory network
-- Responds to !stock commands in Minecraft chat

-- ============================================================
-- CONFIG  (must match terminal.lua)
-- ============================================================
local nodeIDs  = {2, 3, 4, 5}
local PROTOCOL = "inv_net"
local TIMEOUT  = 3    -- seconds to wait for node responses
local BOT_NAME = "StockBot"   -- name shown in chat responses

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

-- Auto-detect chatBox peripheral (Advanced Peripherals)
local chatBox = nil
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "chatBox" then
        chatBox = peripheral.wrap(name)
        break
    end
end

if not chatBox then
    error("No chatBox found! Attach a Chat Box peripheral (Advanced Peripherals).", 0)
end

print("ChatBot online. Listening for !stock commands...")

-- ============================================================
-- HELPERS
-- ============================================================

local function stripNamespace(name)
    return name:match(":(.+)$") or name
end

local function formatName(raw)
    local stripped = stripNamespace(raw)
    return (stripped:gsub("_", " "):gsub("^%l", string.upper))
end

-- ============================================================
-- NODE QUERYING
-- ============================================================
-- Queries all nodes and returns a sorted list of items.
-- This runs synchronously (blocks until timeout or all respond).

local function queryNodes()
    local combined  = {}
    local status    = {}

    -- Send list request to all nodes
    for _, id in ipairs(nodeIDs) do
        rednet.send(id, "list", PROTOCOL)
        status[id] = "offline"
    end

    local remaining = #nodeIDs
    local timer     = os.startTimer(TIMEOUT)

    while remaining > 0 do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "rednet_message" then
            local senderID, message, protocol = p1, p2, p3
            if protocol == PROTOCOL and status[senderID] ~= nil then
                status[senderID] = "online"
                remaining = remaining - 1

                if type(message) == "string" and message:sub(1, 6) ~= "error:" then
                    local ok, items = pcall(textutils.unserialize, message)
                    if ok and type(items) == "table" then
                        for _, item in ipairs(items) do
                            local name  = item.name or "unknown"
                            local count = item.count or 1
                            combined[name] = (combined[name] or 0) + count
                        end
                    end
                end
            end

        elseif event == "timer" and p1 == timer then
            break
        end
    end

    -- Build sorted array
    local sorted = {}
    for name, count in pairs(combined) do
        sorted[#sorted + 1] = {name = name, displayName = formatName(name), count = count}
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)

    return sorted
end

-- ============================================================
-- COMMAND HANDLERS
-- ============================================================

local function handleStock(player, arg)
    print("!stock from " .. player .. (arg ~= "" and (" [" .. arg .. "]") or ""))

    local items = queryNodes()

    if #items == 0 then
        chatBox.sendMessage("[" .. BOT_NAME .. "] No inventory data available.", BOT_NAME)
        return
    end

    if arg == "" then
        -- Top 10 items by count
        chatBox.sendMessage("[" .. BOT_NAME .. "] Top 10 items:", BOT_NAME)
        for i = 1, math.min(10, #items) do
            local item = items[i]
            chatBox.sendMessage("  " .. item.displayName .. ": " .. item.count, BOT_NAME)
        end

    elseif arg == "low" then
        -- Items below 64
        chatBox.sendMessage("[" .. BOT_NAME .. "] Low stock (< 64):", BOT_NAME)
        local found = 0
        for _, item in ipairs(items) do
            if item.count < 64 then
                chatBox.sendMessage("  " .. item.displayName .. ": " .. item.count, BOT_NAME)
                found = found + 1
                if found >= 20 then
                    chatBox.sendMessage("  ... (showing first 20)", BOT_NAME)
                    break
                end
            end
        end
        if found == 0 then
            chatBox.sendMessage("  Nothing below 64!", BOT_NAME)
        end

    else
        -- Search by name
        local query   = arg:lower()
        local results = {}
        for _, item in ipairs(items) do
            if item.displayName:lower():find(query, 1, true) or
               item.name:lower():find(query, 1, true) then
                results[#results + 1] = item
            end
        end

        if #results == 0 then
            chatBox.sendMessage("[" .. BOT_NAME .. "] No items matching '" .. arg .. "'.", BOT_NAME)
        else
            chatBox.sendMessage("[" .. BOT_NAME .. "] Items matching '" .. arg .. "':", BOT_NAME)
            for i = 1, math.min(15, #results) do
                local item = results[i]
                chatBox.sendMessage("  " .. item.displayName .. ": " .. item.count, BOT_NAME)
            end
            if #results > 15 then
                chatBox.sendMessage("  ... and " .. (#results - 15) .. " more", BOT_NAME)
            end
        end
    end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
while true do
    local ok, err = pcall(function()
        -- "chat" event from Advanced Peripherals chatBox
        -- params: username, message, uuid, isHidden
        local event, username, message = os.pullEvent("chat")

        if type(message) == "string" then
            local lower = message:lower()

            if lower == "!stock" then
                handleStock(username, "")

            elseif lower:sub(1, 7) == "!stock " then
                local arg = message:sub(8):match("^%s*(.-)%s*$")  -- trim whitespace
                handleStock(username, arg)
            end
        end
    end)

    if not ok then
        print("ChatBot error: " .. tostring(err))
        sleep(1)
    end
end
