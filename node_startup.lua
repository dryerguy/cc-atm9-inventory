-- node_startup.lua
-- Boot script for node computers.
-- Rename to startup.lua on each node computer.

shell.run("updater.lua")

while true do
    shell.run("node.lua")
    print("node.lua exited. Restarting in 3 seconds...")
    sleep(3)
end
