-- node.lua
-- ComputerCraft inventory node for ATM9 modpack
-- Place next to chests with an Inventory Manager peripheral attached

-- ============================================================
-- CONFIG
-- ============================================================
local PROTOCOL = "inv_net"

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
    error("No modem found! Attach a wireless modem to this computer.", 0)
end

rednet.open(modemSide)

-- Auto-detect inventoryManager peripheral
local inv = nil
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "inventoryManager" then
        inv = peripheral.wrap(name)
        break
    end
end

if not inv then
    error("No inventoryManager found! Attach an Inventory Manager peripheral.", 0)
end

-- ============================================================
-- STARTUP
-- ============================================================
local nodeID = os.getComputerID()
term.clear()
term.setCursorPos(1, 1)
print("================================")
print("  Node " .. nodeID .. " Online")
print("  Protocol: " .. PROTOCOL)
print("  Modem: " .. modemSide)
print("================================")
print("Waiting for requests...")

-- ============================================================
-- MAIN LOOP
-- ============================================================
while true do
    local ok, err = pcall(function()
        local senderID, message = rednet.receive(PROTOCOL)

        if message == "ping" then
            print("[" .. os.time() .. "] Ping from #" .. senderID)
            rednet.send(senderID, "pong:" .. nodeID, PROTOCOL)

        elseif message == "list" then
            print("[" .. os.time() .. "] List request from #" .. senderID)
            local getOk, items = pcall(function() return inv.getItems() end)
            if getOk and items then
                rednet.send(senderID, textutils.serialize(items), PROTOCOL)
                print("  Sent " .. #items .. " item stacks")
            else
                rednet.send(senderID, "error:inv_read_failed", PROTOCOL)
                print("  ERROR: Could not read inventory")
            end

        elseif message == "identify" then
            print("[" .. os.time() .. "] Identify from #" .. senderID)
            rednet.send(senderID, "node:" .. nodeID, PROTOCOL)
        end
    end)

    if not ok then
        print("ERROR: " .. tostring(err))
        sleep(1)
    end
end
