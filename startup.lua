-- startup.lua
-- Launches terminal and chatbot simultaneously on the terminal computer

parallel.waitForAny(
    function() shell.run("terminal.lua") end,
    function() shell.run("chatbot.lua") end
)

print("A program exited. Restarting in 3 seconds...")
sleep(3)
shell.run("startup.lua")
