-- updater.lua
-- Checks GitHub for a newer version and downloads the appropriate files.
-- Detects whether this is a node or terminal computer and downloads accordingly.
-- Runs at boot before everything else. Falls back gracefully if HTTP fails.

-- ============================================================
-- CONFIG
-- ============================================================
local GITHUB_BASE  = "https://raw.githubusercontent.com/dryerguy/cc-atm9-inventory/master/"
local VERSION_FILE = "version.txt"

local NODE_FILES     = {"node.lua", "updater.lua", "node_startup.lua"}
local TERMINAL_FILES = {"terminal.lua", "chatbot.lua", "startup.lua", "updater.lua"}

-- ============================================================
-- COMPUTER TYPE DETECTION
-- Terminal has a chatBox (sendMessage method) or a monitor attached.
-- Node has inventory peripherals on its wired network.
-- ============================================================
local function isTerminal()
    for _, name in ipairs(peripheral.getNames()) do
        local methods = peripheral.getMethods(name) or {}
        for _, m in ipairs(methods) do
            if m == "sendMessage" then return true end
        end
        if peripheral.hasType(name, "monitor") then return true end
    end
    return false
end

-- ============================================================
-- HELPERS
-- ============================================================
local function readLocalVersion()
    if not fs.exists(VERSION_FILE) then return "0" end
    local f = fs.open(VERSION_FILE, "r")
    local v = f.readLine()
    f.close()
    return v and v:match("^%s*(.-)%s*$") or "0"
end

local function writeLocalVersion(v)
    local f = fs.open(VERSION_FILE, "w")
    f.write(v)
    f.close()
end

local function httpGet(url)
    local ok, resp = pcall(http.get, url)
    if not ok or not resp then return nil end
    local body = resp.readAll()
    resp.close()
    return body
end

-- ============================================================
-- UPDATE CHECK
-- ============================================================
local function update()
    print("Updater: checking...")

    local remoteBody = httpGet(GITHUB_BASE .. VERSION_FILE)
    if not remoteBody then
        print("Updater: no HTTP connection, skipping.")
        return
    end

    local remoteVersion = remoteBody:match("^%s*(.-)%s*$")
    local localVersion  = readLocalVersion()

    if remoteVersion == localVersion then
        print("Updater: up to date (v" .. localVersion .. ")")
        return
    end

    local FILES = isTerminal() and TERMINAL_FILES or NODE_FILES
    local kind  = isTerminal() and "terminal" or "node"

    print("Updater [" .. kind .. "]: v" .. localVersion .. " -> v" .. remoteVersion)

    local failed = 0
    for _, file in ipairs(FILES) do
        local content = httpGet(GITHUB_BASE .. file)
        if content then
            local f = fs.open(file, "w")
            f.write(content)
            f.close()
            print("  + " .. file)
        else
            print("  FAIL: " .. file)
            failed = failed + 1
        end
    end

    if failed == 0 then
        writeLocalVersion(remoteVersion)
        print("Updater: done. Rebooting...")
        sleep(2)
        os.reboot()
    else
        print("Updater: " .. failed .. " file(s) failed. Skipping reboot.")
    end
end

update()
