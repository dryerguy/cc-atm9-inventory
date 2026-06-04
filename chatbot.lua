-- chatbot.lua
-- Chat command handler — reads from shared inventory populated by terminal.lua

-- ============================================================
-- CONFIG
-- ============================================================
local BOT_NAME    = "StockBot"
local MSG_DELAY   = 0.2   -- seconds between chat messages to avoid spam

-- ============================================================
-- PERIPHERAL SETUP
-- Detect chatBox by method scan — AP type strings are unreliable
-- ============================================================
local chatBox = nil
for _, name in ipairs(peripheral.getNames()) do
    local methods = peripheral.getMethods(name)
    if methods then
        for _, m in ipairs(methods) do
            if m == "sendMessage" then
                chatBox = peripheral.wrap(name)
                break
            end
        end
    end
    if chatBox then break end
end

if not chatBox then
    error("No chatBox peripheral found. Attach a Chat Box (Advanced Peripherals).", 0)
end

print("ChatBot ready. Listening for !stock commands...")

-- ============================================================
-- HELPERS
-- ============================================================
local function send(msg)
    chatBox.sendMessage("[" .. BOT_NAME .. "] " .. msg, BOT_NAME, "<>", 0xAAAAAA)
    sleep(MSG_DELAY)
end

local function getItems()
    local items = _G.sharedInventory
    if not items or #items == 0 then return nil end
    return items
end

-- ============================================================
-- COMMAND HANDLERS
-- ============================================================
local function cmdHelp()
    send("Commands: !stock | !stock <name> | !stock low | !help")
end

local function cmdStock(arg)
    local items = getItems()
    if not items then
        send("No data yet — terminal is still loading.")
        return
    end

    if arg == "" then
        send("Top 10 items:")
        for i = 1, math.min(10, #items) do
            send("  " .. items[i].displayName .. ": " .. items[i].count)
        end

    elseif arg == "low" then
        local low = {}
        for _, item in ipairs(items) do
            if item.count < 64 then low[#low + 1] = item end
        end
        if #low == 0 then
            send("Nothing below 64!")
        else
            send("Low stock (<64): " .. #low .. " items")
            for i = 1, math.min(15, #low) do
                send("  " .. low[i].displayName .. ": " .. low[i].count)
            end
            if #low > 15 then send("  ...and " .. (#low - 15) .. " more") end
        end

    else
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
            send("Matching '" .. arg .. "': " .. #results .. " found")
            for i = 1, math.min(15, #results) do
                send("  " .. results[i].displayName .. ": " .. results[i].count)
            end
            if #results > 15 then send("  ...and " .. (#results - 15) .. " more") end
        end
    end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
while true do
    local ok, err = pcall(function()
        local event, username, message = os.pullEvent("chat")
        if type(message) ~= "string" then return end

        local lower = message:lower():match("^%s*(.-)%s*$")

        if lower == "!help" then
            cmdHelp()
        elseif lower == "!stock" then
            cmdStock("")
        elseif lower:sub(1, 7) == "!stock " then
            cmdStock(message:sub(8):match("^%s*(.-)%s*$"))
        end
    end)

    if not ok then
        print("ChatBot error: " .. tostring(err))
        sleep(1)
    end
end
