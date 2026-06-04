-- startup.lua
-- Boot sequence: check for updates, then launch terminal + chatbot in parallel

shell.run("updater.lua")

parallel.waitForAny(
    function() shell.run("terminal.lua") end,
    function() shell.run("chatbot.lua") end
)

print("A program exited. Rebooting in 3 seconds...")
sleep(3)
os.reboot()
