-- startup.lua
-- Boot sequence for terminal computer: update, then run terminal + chatbot

shell.run("updater.lua")

parallel.waitForAny(
    function() shell.run("terminal.lua") end,
    function()
        -- Chatbot failure must not kill the terminal
        local ok, err = pcall(shell.run, "chatbot.lua")
        if not ok then
            print("ChatBot failed: " .. tostring(err))
            print("Terminal will continue without chat commands.")
        end
    end
)

print("Terminal exited. Rebooting in 3 seconds...")
sleep(3)
os.reboot()
