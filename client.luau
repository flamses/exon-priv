-- Public copy: everyone connects as free with no setup or key entry.
-- Keep OWNER_KEY empty in the public copy. Only private copies contain it.
local CONFIG = {
    URL = "https://exon-priv-relay.onrender.com",
    OWNER_KEY = "",
}

local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local me = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
local httpRequest = request or http_request or (syn and syn.request)
assert(httpRequest, "This executor needs an HTTP request API")
assert(CONFIG.URL ~= "https://YOUR-RELAY-HOST", "Configure the relay URL first")
local previous = env.OwnerRelay
if previous and previous.stop then previous.stop() end
local running, connection = true, nil
local state = {}
function state.stop()
    running = false
    if connection then connection:Disconnect() end
    local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
    if root and state.frozenRoot == root then root.Anchored = false end
end
env.OwnerRelay = state

local sessionKey = ""
local isOwner = false
local function api(path, body, method)
    local response = httpRequest({
        Url = CONFIG.URL:gsub("/$", "") .. path,
        Method = method or "POST",
        Headers = { ["Content-Type"] = "application/json", Authorization = "Bearer " .. (isOwner and CONFIG.OWNER_KEY or sessionKey), ["X-Owner-Id"] = tostring(me.UserId) },
        Body = body and Http:JSONEncode(body) or nil,
    })
    local code = response.StatusCode or response.Status
    assert(code and code >= 200 and code < 300,
        "Relay HTTP " .. tostring(code) .. ": " .. tostring(response.Body))
    return Http:JSONDecode(response.Body)
end

local function execute(item)
    if item.command == "kick" then
        me:Kick("Disconnected by the script owner.")
        return
    end
    local char = me.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    assert(char and hum and root, "Character is not ready")
    if item.command == "kill" then
        hum.Health = 0
    elseif item.command == "bring" then
        local p = item.position
        char:PivotTo(CFrame.new(p[1], p[2], p[3]))
    elseif item.command == "freeze" then
        root.Anchored = true
        state.frozenRoot = root
    elseif item.command == "unfreeze" then
        root.Anchored = false
        state.frozenRoot = nil
    elseif item.command == "walkspeed" then
        hum.WalkSpeed = item.value
    elseif item.command == "jumppower" then
        hum.UseJumpPower = true
        hum.JumpPower = item.value
    elseif item.command == "fling" then
        assert(not root.Anchored, "Unfreeze before fling")
        root.AssemblyLinearVelocity = Vector3.new(100, 150, 0)
        root.AssemblyAngularVelocity = Vector3.new(0, 35, 0)
    end
end

-- A public ID whitelist is an authorization rule, not proof of identity.
-- Owner commands require BOTH the whitelist entry and the private credential.
local allowed = api("/role", {id = tostring(me.UserId)}).owner
isOwner = allowed and CONFIG.OWNER_KEY ~= ""
if CONFIG.OWNER_KEY ~= "" and not allowed then
    error("Your user ID is not listed in owners.txt")
end
local function join()
    sessionKey = api("/join", {id = tostring(me.UserId), name = me.Name, job = game.JobId}).token
end

if isOwner then
    function state.command(text)
        local words = {}
        for word in text:gmatch("%S+") do table.insert(words, word) end
        local cmd = (words[1] or ""):lower():gsub("^!", "")
        if cmd == "stop" then state.stop(); return end
        if cmd == "users" then
            for _, user in ipairs(api("/clients", nil, "GET").clients) do
                print(user.name, user.id, user.job == game.JobId and "same server" or "other/offline")
            end
            return
        end
        assert(words[2], "Supply a username or user ID")
        local query, matches = words[2]:lower(), {}
        for _, player in ipairs(Players:GetPlayers()) do
            if tostring(player.UserId) == query or player.Name:lower() == query then
                matches = {player}; break
            elseif player.Name:lower():sub(1, #query) == query then
                table.insert(matches, player)
            end
        end
        assert(#matches == 1, "Use an unambiguous username or user ID")
        local body = {target = tostring(matches[1].UserId), command = cmd, job = game.JobId}
        if cmd == "walkspeed" or cmd == "jumppower" then
            body.value = tonumber(words[3])
            assert(body.value, "Supply a number from 0 to 200")
        elseif cmd == "bring" then
            local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
            assert(root, "Your character is not ready")
            local p = (root.CFrame * CFrame.new(0, 0, -4)).Position
            body.position = {p.X, p.Y, p.Z}
        end
        api("/command", body)
        print("Queued", cmd, matches[1].Name)
    end
    connection = me.Chatted:Connect(function(text)
        if text:sub(1, 1) ~= "!" then return end
        local ok, err = pcall(state.command, text)
        if not ok then warn(err) end
    end)
    print('Owner ready. Use !users or !bring username. Console fallback: getgenv().OwnerRelay.command("bring username")')
else
    if allowed then warn("You are whitelisted. Run your private owner copy to enable commands.") end
    local seen, order = {}, {}
    task.spawn(function()
        local backoff = 1
        while running do
            local ok, err = pcall(function()
                if sessionKey == "" then join() end
                local result = api("/poll", {})
                if not running then return end
                local ack = {}
                for _, item in ipairs(result.commands) do
                    if not running then break end
                    if not seen[item.id] then
                        seen[item.id] = true
                        table.insert(order, item.id)
                        if #order > 256 then seen[table.remove(order, 1)] = nil end
                        local worked, reason = pcall(execute, item)
                        if not worked then warn("Command failed:", item.command, reason) end
                    end
                    table.insert(ack, item.id)
                end
                if #ack > 0 then api("/ack", {ids = ack}) end
            end)
            if ok then backoff = 1 else
                warn("Relay:", err)
                if tostring(err):find("HTTP 403", 1, true) then sessionKey = "" end
                backoff = math.min(backoff * 2, 15)
            end
            task.wait(backoff)
        end
    end)
    print("Free-user relay active. The owner can control this character while this script runs.")
    print("Stop with getgenv().OwnerRelay.stop()")
end
