-- node.lua
-- Inventory node — reads connected chests via wired modem network
-- Responds to rednet requests from the terminal computer

-- ============================================================
-- CONFIG
-- ============================================================
local PROTOCOL = "inv_net"

-- ============================================================
-- MODEM SETUP
-- Find the wireless (ender) modem for rednet
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

if not modemSide then
    error("No wireless modem found. Attach an Ender Modem.", 0)
end

rednet.open(modemSide)

-- ============================================================
-- INVENTORY AGGREGATION
-- Scans all peripherals on the wired network for inventory types.
-- chest.list() returns {[slot] = {name, count}} — must use pairs()
-- ============================================================
local function getInventory()
    local combined = {}

    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.hasType(name, "inventory") then
            local wrapOk, inv = pcall(peripheral.wrap, name)
            if wrapOk and inv then
                local listOk, slots = pcall(inv.list)
                if listOk and slots then
                    for _, item in pairs(slots) do
                        if item and item.name then
                            combined[item.name] = (combined[item.name] or 0) + (item.count or 1)
                        end
                    end
                end
            end
        end
    end

    return combined
end

-- ============================================================
-- STARTUP
-- ============================================================
local nodeID = os.getComputerID()
term.clear()
term.setCursorPos(1, 1)
print("================================")
print("  Node " .. nodeID .. " Online")
print("  Protocol : " .. PROTOCOL)
print("  Modem    : " .. modemSide)
print("================================")

-- Count visible inventories at boot for sanity check
local invCount = 0
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "inventory") then
        invCount = invCount + 1
    end
end
print("Inventories found: " .. invCount)
print("Listening for requests...")

-- ============================================================
-- MAIN LOOP
-- ============================================================
while true do
    local ok, err = pcall(function()
        local senderID, message = rednet.receive(PROTOCOL)

        if message == "ping" then
            print("[ping] from #" .. senderID)
            rednet.send(senderID, "pong:" .. nodeID, PROTOCOL)

        elseif message == "list" then
            print("[list] from #" .. senderID)
            local inventory = getInventory()
            local itemCount = 0
            for _ in pairs(inventory) do itemCount = itemCount + 1 end
            rednet.send(senderID, textutils.serialize(inventory), PROTOCOL)
            print("  Sent " .. itemCount .. " item types")
        end
    end)

    if not ok then
        print("ERROR: " .. tostring(err))
        sleep(1)
    end
end
