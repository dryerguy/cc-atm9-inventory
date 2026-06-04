-- chatbot.lua
-- Chat command handler — reads from shared inventory populated by terminal.lua

-- ============================================================
-- CONFIG
-- ============================================================
local BOT_NAME = "StockBot"

-- ============================================================
-- PERIPHERAL SETUP
-- ============================================================

-- Find chatBox (Advanced Peripherals)
local chatBox = nil
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "chatBox" then
        chatBox = peripheral.wrap(name)
        break
    end
end

if not chatBox then
    error("No chatBox peripheral found. Attach a Chat Box.", 0)
end

print("ChatBot ready. Listening for !stock commands...")

-- ============================================================
-- HELPERS
-- ============================================================
local function send(msg)
    chatBox.sendMessage("[" .. BOT_NAME .. "] " .. msg, BOT_NAME)
end

-- Reads from the shared inventory table that terminal.lua keeps updated.
-- Returns an empty table with a notice if terminal hasn't loaded yet.
local function getItems()
    local items = _G.sharedInventory
    if not items or #items == 0 then
        return nil
    end
    return items
end

-- ============================================================
-- COMMAND HANDLERS
-- ============================================================
local function handleStock(player, arg)
    local items = getItems()
    if not items then
        send("No inventory data yet — terminal is still loading.")
        return
    end

    if arg == "" then
        -- Top 10 items by count
        send("Top 10 items:")
        for i = 1, math.min(10, #items) do
            send("  " .. items[i].displayName .. ": " .. items[i].count)
        end

    elseif arg == "low" then
        -- Items below 64
        local found = 0
        local lines = {}
        for _, item in ipairs(items) do
            if item.count < 64 then
                lines[#lines + 1] = item
                found = found + 1
            end
        end
        if found == 0 then
            send("Nothing below 64!")
        else
            send("Low stock (< 64):")
            for i = 1, math.min(20, #lines) do
                send("  " .. lines[i].displayName .. ": " .. lines[i].count)
            end
            if found > 20 then
                send("  ...and " .. (found - 20) .. " more")
            end
        end

    else
        -- Search by name
        local q       = arg:lower()
        local results = {}
        for _, item in ipairs(items) do
            if item.displayName:lower():find(q, 1, true) or
               item.name:lower():find(q, 1, true) then
                results[#results + 1] = item
            end
        end
        if #results == 0 then
            send("No items matching '" .. arg .. "'.")
        else
            send("Matching '" .. arg .. "':")
            for i = 1, math.min(15, #results) do
                send("  " .. results[i].displayName .. ": " .. results[i].count)
            end
            if #results > 15 then
                send("  ...and " .. (#results - 15) .. " more")
            end
        end
    end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
while true do
    local ok, err = pcall(function()
        -- Advanced Peripherals chatBox fires: username, message, uuid, isHidden
        local event, username, message = os.pullEvent("chat")

        if type(message) ~= "string" then return end

        local lower = message:lower()

        if lower == "!stock" then
            handleStock(username, "")
        elseif lower:sub(1, 7) == "!stock " then
            local arg = message:sub(8):match("^%s*(.-)%s*$")
            handleStock(username, arg)
        end
    end)

    if not ok then
        print("ChatBot error: " .. tostring(err))
        sleep(1)
    end
end
