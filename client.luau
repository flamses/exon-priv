-- EXON v2 | Public copy: no key entry. Keep private owner copies private.
local CONFIG = { URL = "https://exon-priv-relay.onrender.com", OWNER_KEY = "" }
local Players = game:GetService("Players")
local Http = game:GetService("HttpService")
local Run = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Input = game:GetService("UserInputService")
local Teleport = game:GetService("TeleportService")
local me = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
local httpRequest = request or http_request or (syn and syn.request)
assert(httpRequest, "Executor needs request, http_request, or syn.request")
if env.OwnerRelay and env.OwnerRelay.stop then env.OwnerRelay.stop() end
local running, sessionKey, isOwner = true, "", false
local connections, cleanups = {}, {}
local state = {version = 2}
env.OwnerRelay = state
local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end
local function clearEffect(name)
    if cleanups[name] then
        local cleanup = cleanups[name]
        cleanups[name] = nil
        pcall(cleanup)
    end
end
function state.stop()
    running = false
    for _, c in ipairs(connections) do c:Disconnect() end
    local names = {}
    for name in pairs(cleanups) do table.insert(names, name) end
    for _, name in ipairs(names) do clearEffect(name) end
    if state.gui then state.gui:Destroy() end
end
local function api(path, body, method)
    local response = httpRequest({Url = CONFIG.URL .. path, Method = method or "POST",
        Headers = {["Content-Type"] = "application/json", Authorization = "Bearer " .. (isOwner and CONFIG.OWNER_KEY or sessionKey), ["X-Owner-Id"] = tostring(me.UserId)},
        Body = body and Http:JSONEncode(body) or nil})
    local code = tonumber(response.StatusCode or response.Status)
    if not code or code < 200 or code >= 300 then
        local ok, decoded = pcall(function() return Http:JSONDecode(response.Body) end)
        error("Relay HTTP " .. tostring(code) .. ": " .. (ok and decoded.error or tostring(response.Body)), 0)
    end
    return Http:JSONDecode(response.Body)
end
local function character()
    local char = me.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    assert(char and hum and root, "Character is not ready")
    return char, hum, root
end
local function instance(class, props, parent)
    local object = Instance.new(class)
    for k, v in pairs(props or {}) do object[k] = v end
    object.Parent = parent
    return object
end
local function camera() return assert(workspace.CurrentCamera, "Camera isn't ready") end
local function saveProperty(effect, object, property, value)
    clearEffect(effect)
    local original = object[property]
    object[property] = value
    cleanups[effect] = function() if object.Parent then object[property] = original end end
end
local function characterVisual(kind, enabled)
    local key = "visual_" .. kind
    clearEffect(key)
    if not enabled then return end
    local _, _, root = character()
    local effect = instance(kind, {}, root)
    cleanups[key] = function() effect:Destroy() end
end
local function execute(item)
    local cmd, value = item.command, item.value
    if cmd == "kick" then me:Kick("Disconnected by the script owner."); return end
    if cmd == "disco" then
        clearEffect("disco")
        local effect = instance("ColorCorrectionEffect", {Name = "ExonDisco", Saturation = 0.3}, Lighting)
        local elapsed = 0
        local c = Run.RenderStepped:Connect(function(dt)
            elapsed += dt
            effect.TintColor = Color3.fromHSV((elapsed * 0.12) % 1, 0.65, 1)
        end)
        cleanups.disco = function() c:Disconnect(); effect:Destroy() end
        return
    elseif cmd == "undisco" then clearEffect("disco"); return
    elseif cmd == "blur" then
        clearEffect("blur")
        local effect = instance("BlurEffect", {Name = "ExonBlur", Size = value}, Lighting)
        cleanups.blur = function() effect:Destroy() end
        return
    elseif cmd == "unblur" then clearEffect("blur"); return
    elseif cmd == "blind" then
        clearEffect("blind")
        local screen = instance("ScreenGui", {Name = "ExonBlind", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 900}, me:WaitForChild("PlayerGui"))
        instance("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(), BorderSizePixel = 0}, screen)
        cleanups.blind = function() screen:Destroy() end
        return
    elseif cmd == "unblind" then clearEffect("blind"); return
    elseif cmd == "fov" then saveProperty("fov", camera(), "FieldOfView", value); return
    elseif cmd == "unfov" then clearEffect("fov"); return
    elseif cmd == "gravity" then saveProperty("gravity", workspace, "Gravity", value); return
    elseif cmd == "ungravity" then clearEffect("gravity"); return
    elseif cmd == "day" or cmd == "night" then saveProperty("clock", Lighting, "ClockTime", cmd == "day" and 14 or 0); return
    elseif cmd == "fullbright" then
        clearEffect("fullbright")
        local original = {Brightness = Lighting.Brightness, Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, GlobalShadows = Lighting.GlobalShadows}
        Lighting.Brightness = 3; Lighting.Ambient = Color3.new(1, 1, 1); Lighting.OutdoorAmbient = Color3.new(1, 1, 1); Lighting.GlobalShadows = false
        cleanups.fullbright = function() for k, v in pairs(original) do Lighting[k] = v end end
        return
    elseif cmd == "unfullbright" then clearEffect("fullbright"); clearEffect("clock"); return
    elseif cmd == "smoke" or cmd == "unsmoke" then characterVisual("Smoke", cmd == "smoke"); return
    elseif cmd == "sparkles" or cmd == "unsparkles" then characterVisual("Sparkles", cmd == "sparkles"); return
    elseif cmd == "fire" or cmd == "unfire" then characterVisual("Fire", cmd == "fire"); return
    end
    local char, hum, root = character()
    if cmd == "kill" then hum.Health = 0
    elseif cmd == "bring" then local p = item.position; char:PivotTo(CFrame.new(p[1], p[2], p[3]))
    elseif cmd == "freeze" then saveProperty("freeze", root, "Anchored", true)
    elseif cmd == "unfreeze" then clearEffect("freeze")
    elseif cmd == "walkspeed" then saveProperty("speed", hum, "WalkSpeed", value)
    elseif cmd == "jumppower" then
        clearEffect("jumpstats")
        local power, use = hum.JumpPower, hum.UseJumpPower
        hum.UseJumpPower = true; hum.JumpPower = value
        cleanups.jumpstats = function() if hum.Parent then hum.JumpPower = power; hum.UseJumpPower = use end end
    elseif cmd == "fling" then
        assert(not root.Anchored, "Unfreeze first")
        root.AssemblyLinearVelocity = Vector3.new(100, 150, 0); root.AssemblyAngularVelocity = Vector3.new(0, 35, 0)
    elseif cmd == "spin" then
        clearEffect("spin")
        local attachment = instance("Attachment", {Name = "ExonSpin"}, root)
        local angular = instance("AngularVelocity", {Attachment0 = attachment, RelativeTo = Enum.ActuatorRelativeTo.World, AngularVelocity = Vector3.new(0, value, 0), MaxTorque = 1000000}, root)
        cleanups.spin = function() angular:Destroy(); attachment:Destroy(); if root.Parent then root.AssemblyAngularVelocity = Vector3.zero end end
    elseif cmd == "unspin" then clearEffect("spin")
    elseif cmd == "sit" then hum.Sit = true
    elseif cmd == "unsit" then hum.Sit = false
    elseif cmd == "jump" then hum.Jump = true
    elseif cmd == "heal" then hum.Health = hum.MaxHealth
    elseif cmd == "invisible" then
        clearEffect("invisible")
        local originals = {}
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then originals[part] = part.LocalTransparencyModifier; part.LocalTransparencyModifier = 1 end
        end
        cleanups.invisible = function() for part, old in pairs(originals) do if part.Parent then part.LocalTransparencyModifier = old end end end
    elseif cmd == "visible" then clearEffect("invisible")
    elseif cmd == "noclip" then
        clearEffect("noclip")
        local originals = {}
        local c = Run.Stepped:Connect(function()
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    if originals[part] == nil then originals[part] = part.CanCollide end
                    part.CanCollide = false
                end
            end
        end)
        cleanups.noclip = function() c:Disconnect(); for part, old in pairs(originals) do if part.Parent then part.CanCollide = old end end end
    elseif cmd == "clip" then clearEffect("noclip")
    elseif cmd == "resetstats" then
        for _, name in ipairs({"speed", "jumpstats", "freeze", "spin", "noclip", "invisible", "gravity", "fov"}) do clearEffect(name) end
        hum.Sit = false
    else error("Unknown command: " .. tostring(cmd)) end
end
-- Character-bound effects never carry stale references across respawns.
connect(me.CharacterRemoving, function()
    for _, name in ipairs({"freeze", "speed", "jumpstats", "spin", "noclip", "invisible", "visual_Smoke", "visual_Fire", "visual_Sparkles"}) do clearEffect(name) end
end)
local allowed = api("/role", {id = tostring(me.UserId)}).owner
isOwner = allowed and CONFIG.OWNER_KEY ~= ""
if CONFIG.OWNER_KEY ~= "" and not allowed then state.stop(); error("Your ID isn't in owners.txt") end
local gameName = "Place " .. tostring(game.PlaceId)
task.spawn(function()
    local ok, info = pcall(function() return game:GetService("MarketplaceService"):GetProductInfoAsync(game.PlaceId, Enum.InfoType.Asset) end)
    if ok and info.Name then gameName = info.Name end
end)
local function normalize(text)
    return (tostring(text or ""):lower():gsub("[^%w]", ""))
end
local function editDistance(a, b)
    if math.abs(#a - #b) > 1 then return 2 end
    local last = {}
    for j = 0, #b do last[j] = j end
    for i = 1, #a do
        local row = {[0] = i}
        for j = 1, #b do
            row[j] = math.min(row[j-1] + 1, last[j] + 1, last[j-1] + (a:sub(i,i) == b:sub(j,j) and 0 or 1))
        end
        last = row
    end
    return last[#b]
end
local function matchScore(user, query)
    local q = tostring(query or ""):lower():gsub("^@", "")
    if q == "" then return 1 end
    if #q > 64 then return 0 end
    local name = tostring(user.name or ""):lower()
    local display = tostring(user.display or ""):lower()
    if tostring(user.id) == q then return 1100 end
    if name == q then return 1000 end
    if display == q then return 950 end
    local nq, nn, nd = normalize(q), normalize(name), normalize(display)
    if nq == "" then return 0 end
    if nn == nq then return 900 end
    if nd == nq then return 850 end
    if name:sub(1, #q) == q then return 800 end
    if display:sub(1, #q) == q then return 750 end
    if nn:sub(1, #nq) == nq then return 700 end
    if nd:sub(1, #nq) == nq then return 650 end
    if #nq >= 2 and nn:find(nq, 1, true) then return 600 end
    if #nq >= 2 and nd:find(nq, 1, true) then return 550 end
    if #nq >= 4 and editDistance(nq, nn) <= 1 then return 400 end
    return 0
end
if isOwner then
    local specs = {
        {name="bring", label="Bring", group="Character"}, {name="kill", label="Kill", group="Character"},
        {name="heal", label="Heal", group="Character"}, {name="sit", label="Sit", group="Character"},
        {name="unsit", label="Stand", group="Character"}, {name="jump", label="Jump", group="Character"},
        {name="freeze", label="Freeze", group="Character"}, {name="unfreeze", label="Unfreeze", group="Character"},
        {name="fling", label="Fling", group="Character"}, {name="kick", label="Kick", group="Character"},
        {name="walkspeed", label="Walk speed", group="Movement", default=50, min=0, max=200},
        {name="jumppower", label="Jump power", group="Movement", default=100, min=0, max=200},
        {name="spin", label="Spin", group="Movement", default=10, min=0, max=50}, {name="unspin", label="Stop spin", group="Movement"},
        {name="noclip", label="Noclip", group="Movement"}, {name="clip", label="Restore collision", group="Movement"},
        {name="gravity", label="Gravity", group="Movement", default=60, min=0, max=500}, {name="ungravity", label="Restore gravity", group="Movement"},
        {name="resetstats", label="Reset stats", group="Movement"},
        {name="disco", label="Disco", group="Effects"}, {name="undisco", label="Stop disco", group="Effects"},
        {name="blind", label="Black screen", group="Effects"}, {name="unblind", label="Clear screen", group="Effects"},
        {name="blur", label="Blur", group="Effects", default=24, min=0, max=56}, {name="unblur", label="Clear blur", group="Effects"},
        {name="fov", label="Field of view", group="Effects", default=100, min=20, max=120}, {name="unfov", label="Restore FOV", group="Effects"},
        {name="invisible", label="Invisible (local)", group="Effects"}, {name="visible", label="Visible", group="Effects"},
        {name="smoke", label="Smoke", group="Effects"}, {name="unsmoke", label="Remove smoke", group="Effects"},
        {name="sparkles", label="Sparkles", group="Effects"}, {name="unsparkles", label="Remove sparkles", group="Effects"},
        {name="fire", label="Fire effect", group="Effects"}, {name="unfire", label="Remove fire", group="Effects"},
        {name="day", label="Day", group="Lighting"}, {name="night", label="Night", group="Lighting"},
        {name="fullbright", label="Fullbright", group="Lighting"}, {name="unfullbright", label="Restore lighting", group="Lighting"},
    }
    local aliases = {ws="walkspeed", speed="walkspeed", jp="jumppower", jumpheight="jumppower", tp="bring", stopdisco="undisco", stand="unsit", unfreeze="unfreeze", reset="resetstats", unnoclip="clip"}
    local byName = {}
    for _, spec in ipairs(specs) do byName[spec.name] = spec end
    local users, selected, refreshing = {}, nil, false
    local renderUsers, renderSelection
    local statusLabel
    local function status(message, bad)
        if not running then return end
        print("[Exon] " .. tostring(message))
        if statusLabel then
            statusLabel.Text = tostring(message)
            statusLabel.TextColor3 = bad and Color3.fromRGB(255, 139, 147) or Color3.fromRGB(167, 211, 196)
        end
    end
    local function sameServer(user)
        return user.job == game.JobId and (tonumber(user.place) == game.PlaceId or tonumber(user.place) == 0)
    end
    local function refresh()
        if refreshing then return end
        refreshing = true
        local ok, result = pcall(function() return api("/clients", nil, "GET") end)
        refreshing = false
        if not running then return end
        if not ok then status(result, true); return end
        users = result.clients
        -- Keep an exact connection selected; never silently switch targets.
        if selected then
            local found
            for _, u in ipairs(users) do if u.sid == selected.sid then found = u; break end end
            selected = found
        end
        if renderUsers then renderUsers() end
        if renderSelection then renderSelection() end
        return users
    end
    local function resolve(query)
        refresh()
        local best, matches = 0, {}
        for _, user in ipairs(users) do
            local score = matchScore(user, query)
            if score > best then best = score; matches = {user}
            elseif score == best and score > 0 then table.insert(matches, user) end
        end
        if #matches > 1 then
            -- Duplicate connections of one account can prefer its current server.
            local sameID, localMatches = true, {}
            for _, u in ipairs(matches) do
                if u.id ~= matches[1].id then sameID = false end
                if sameServer(u) then table.insert(localMatches, u) end
            end
            if sameID and #localMatches == 1 then matches = localMatches end
        end
        if #matches == 0 then error("No connected free user matches '" .. query .. "'. Run the free script on that account.", 0) end
        if #matches > 1 then
            local labels = {}
            for i = 1, math.min(#matches, 6) do table.insert(labels, "@" .. matches[i].name) end
            error("Multiple matches: " .. table.concat(labels, ", ") .. ". Type more letters or choose a GUI row.", 0)
        end
        return matches[1]
    end
    local function send(command, user, rawValue)
        local spec = assert(byName[command], "Unknown command: " .. tostring(command))
        assert(user, "Select a connected user first")
        assert(not user.owner, "Owners cannot be targeted")
        local body = {target = tostring(user.id), session = user.sid, job = user.job, command = command, origin_job = game.JobId, origin_place = game.PlaceId}
        if spec.default then
            local value = rawValue ~= nil and tonumber(rawValue) or nil
            -- Explicit branch keeps omitted values numeric in both chat and GUI.
            if rawValue == nil or tostring(rawValue):match("^%s*$") then value = spec.default end
            assert(value and value == value and value >= spec.min and value <= spec.max, "Use a value from " .. spec.min .. " to " .. spec.max)
            body.value = value
        end
        if command == "bring" then
            assert(sameServer(user), "Join this user's server before using Bring")
            local _, _, root = character()
            local p = (root.CFrame * CFrame.new(0, 0, -4)).Position
            body.position = {p.X, p.Y, p.Z}
        end
        api("/command", body)
        status("Queued " .. spec.label .. " for @" .. user.name .. ".")
    end
    local function joinUser(user)
        assert(user and tonumber(user.place) and tonumber(user.place) > 0 and user.job ~= "", "This user needs the updated free script for game details")
        if sameServer(user) then status("You are already in this user's server."); return end
        status("Joining @" .. user.name .. " — run the owner script again after teleporting.")
        Teleport:TeleportToPlaceInstance(tonumber(user.place), user.job, me)
    end
    connect(Teleport.TeleportInitFailed, function(player, _, message)
        if player == me then status("Join failed: " .. tostring(message), true) end
    end)
    function state.command(text)
        local words = {}
        -- Quoted display names work too: !disco "Display Name".
        local i = 1
        while i <= #text do
            local char = text:sub(i,i)
            if char:match("%s") then i += 1
            elseif char == '"' or char == "'" then
                local close = text:find(char, i+1, true)
                assert(close, "Close the quoted player name")
                table.insert(words, text:sub(i+1,close-1)); i = close+1
            else
                local finish = text:find("%s",i) or (#text+1)
                table.insert(words,text:sub(i,finish-1)); i=finish
            end
        end
        local cmd = (words[1] or ""):lower():gsub("^!", "")
        cmd = aliases[cmd] or cmd
        if cmd == "stop" then state.stop(); return end
        if cmd == "gui" then if state.gui then state.gui.Enabled = not state.gui.Enabled end; return end
        if cmd == "users" then
            refresh()
            for _, user in ipairs(users) do print("@" .. user.name, user.id, user.game_name, sameServer(user) and "same server" or "another server") end
            status(tostring(#users) .. " connected sessions"); return
        end
        if cmd == "help" or cmd == "commands" then
            local names = {"users", "gui", "join", "stop"}
            for _, spec in ipairs(specs) do table.insert(names, spec.name) end
            print(table.concat(names, ", ")); return
        end
        assert(words[2] and words[2] ~= "", "Supply a username, short name, display name, or user ID")
        local user = resolve(words[2])
        if cmd == "join" then joinUser(user); return end
        send(cmd, user, words[3])
    end
    connect(me.Chatted, function(text)
        if text:sub(1,1) == "!" then
            task.spawn(function() local ok, err = pcall(state.command, text); if not ok then status(err, true) end end)
        end
    end)
    -- Owner panel: responsive, draggable, keyboard toggle, no external UI loader.
    local palette = {bg=Color3.fromRGB(14,17,23), panel=Color3.fromRGB(22,27,35), card=Color3.fromRGB(31,38,49), text=Color3.fromRGB(236,240,246), muted=Color3.fromRGB(143,155,175), accent=Color3.fromRGB(112,225,190)}
    local gui = instance("ScreenGui", {Name="ExonOwner", ResetOnSpawn=false, DisplayOrder=1000, ZIndexBehavior=Enum.ZIndexBehavior.Sibling}, me:WaitForChild("PlayerGui"))
    state.gui = gui
    local window = instance("Frame", {Size=UDim2.fromOffset(920,580), Position=UDim2.fromScale(0.5,0.5), AnchorPoint=Vector2.new(0.5,0.5), BackgroundColor3=palette.bg, BorderSizePixel=0}, gui)
    instance("UICorner", {CornerRadius=UDim.new(0,14)}, window)
    instance("UIStroke", {Color=Color3.fromRGB(53,65,80), Thickness=1}, window)
    local scale = instance("UIScale", {}, window)
    local function fit()
        local c = workspace.CurrentCamera
        if c then scale.Scale = math.min(1, math.max(0.25, math.min((c.ViewportSize.X-24)/920,(c.ViewportSize.Y-70)/580))) end
    end
    fit()
    connect(workspace:GetPropertyChangedSignal("CurrentCamera"), fit)
    local viewportConnection
    local function bindViewport()
        if viewportConnection then viewportConnection:Disconnect() end
        if workspace.CurrentCamera then viewportConnection = connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), fit) end
        fit()
    end
    bindViewport(); connect(workspace:GetPropertyChangedSignal("CurrentCamera"), bindViewport)
    local function label(parent, text, x, y, w, h, size, color)
        return instance("TextLabel", {Text=text, Position=UDim2.fromOffset(x,y), Size=UDim2.fromOffset(w,h), BackgroundTransparency=1, TextColor3=color or palette.text, TextSize=size or 14, Font=Enum.Font.Gotham, TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd}, parent)
    end
    local function button(parent, text, x, y, w, h, callback, accent)
        local b = instance("TextButton", {Text=text, Position=UDim2.fromOffset(x,y), Size=UDim2.fromOffset(w,h), BackgroundColor3=accent and palette.accent or palette.card, TextColor3=accent and palette.bg or palette.text, TextSize=13, Font=Enum.Font.GothamMedium, BorderSizePixel=0, AutoButtonColor=true}, parent)
        instance("UICorner", {CornerRadius=UDim.new(0,7)}, b)
        b.Activated:Connect(function()
            task.spawn(function()
                if not running then return end
                local ok, err = pcall(callback)
                if not ok then status(err, true) end
            end)
        end)
        return b
    end
    local function textBox(parent, placeholder, x, y, w, h)
        local box = instance("TextBox", {Text="", PlaceholderText=placeholder, Position=UDim2.fromOffset(x,y), Size=UDim2.fromOffset(w,h), BackgroundColor3=palette.card, TextColor3=palette.text, PlaceholderColor3=palette.muted, TextSize=13, Font=Enum.Font.Gotham, BorderSizePixel=0, ClearTextOnFocus=false, TextXAlignment=Enum.TextXAlignment.Left}, parent)
        instance("UICorner", {CornerRadius=UDim.new(0,7)}, box)
        instance("UIPadding", {PaddingLeft=UDim.new(0,12), PaddingRight=UDim.new(0,10)}, box)
        return box
    end
    local titlebar = instance("Frame", {Size=UDim2.new(1,-120,0,66), BackgroundTransparency=1, Active=true}, window)
    label(titlebar,"EXON",24,12,90,28,23,palette.accent).Font=Enum.Font.GothamBold
    label(titlebar,"OWNER PANEL",112,17,190,22,12,palette.muted)
    label(titlebar,"Connected free users · live controls",24,41,500,18,12,palette.muted)
    button(window,"Hide",800,20,96,32,function() gui.Enabled=false end)
    local dragging, dragInput, dragStart, startPos
    connect(titlebar.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=true; dragStart=input.Position; startPos=window.Position
        end
    end)
    connect(titlebar.InputChanged,function(input)
        if input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch then dragInput=input end
    end)
    connect(Input.InputChanged,function(input)
        if dragging and input==dragInput then
            local delta=input.Position-dragStart
            window.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
        end
    end)
    connect(Input.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)
    connect(Input.InputBegan,function(input,processed)
        if not processed and input.KeyCode==Enum.KeyCode.RightShift then gui.Enabled=not gui.Enabled end
    end)
    local left=instance("Frame",{Position=UDim2.fromOffset(16,78),Size=UDim2.fromOffset(282,442),BackgroundColor3=palette.panel,BorderSizePixel=0},window)
    instance("UICorner",{CornerRadius=UDim.new(0,10)},left)
    local countLabel=label(left,"USERS · 0",14,10,160,24,12,palette.muted)
    button(left,"Refresh",192,8,76,28,function() refresh() end)
    local search=textBox(left,"Search name, display name, or ID",12,46,258,36)
    local list=instance("ScrollingFrame",{Position=UDim2.fromOffset(10,94),Size=UDim2.fromOffset(262,336),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=palette.muted,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},left)
    instance("UIListLayout",{Padding=UDim.new(0,8),SortOrder=Enum.SortOrder.LayoutOrder},list)
    local right=instance("Frame",{Position=UDim2.fromOffset(312,78),Size=UDim2.fromOffset(592,442),BackgroundColor3=palette.panel,BorderSizePixel=0},window)
    instance("UICorner",{CornerRadius=UDim.new(0,10)},right)
    local targetLabel=label(right,"Select a user",16,12,408,28,18)
    targetLabel.Font=Enum.Font.GothamMedium
    local gameLabel=label(right,"Their game and commands will appear here.",16,42,408,22,12,palette.muted)
    local serverLabel=label(right,"",16,65,408,20,11,palette.muted)
    local joinButton=button(right,"Join server",448,18,128,36,function() joinUser(selected) end,true)
    local valueBox=textBox(right,"Optional number · blank uses button default",16,100,560,34)
    local commandScroll=instance("ScrollingFrame",{Position=UDim2.fromOffset(12,148),Size=UDim2.fromOffset(568,280),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=palette.muted,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y},right)
    instance("UIListLayout",{Padding=UDim.new(0,10),SortOrder=Enum.SortOrder.LayoutOrder},commandScroll)
    local commandButtons={}
    for order, category in ipairs({"Character","Movement","Effects","Lighting"}) do
        local group={}
        for _,spec in ipairs(specs) do if spec.group==category then table.insert(group,spec) end end
        local holder=instance("Frame",{Size=UDim2.new(1,-6,0,30+math.ceil(#group/3)*42),BackgroundTransparency=1,LayoutOrder=order},commandScroll)
        label(holder,category:upper(),4,0,400,22,11,palette.muted)
        for index,spec in ipairs(group) do
            local row,col=math.floor((index-1)/3),(index-1)%3
            local text=spec.label..(spec.default and " · "..tostring(spec.default) or "")
            local b=button(holder,text,col*186+2,28+row*42,178,34,function()
                send(spec.name,selected,valueBox.Text)
            end)
            table.insert(commandButtons,{button=b,spec=spec})
        end
    end
    statusLabel=label(window,"Connecting to the relay…",22,532,872,24,12,palette.muted)
    label(window,"Right Shift hides/shows · Actions run on the selected user's client · Queued does not mean completed",22,559,872,16,10,palette.muted)
    renderSelection=function()
        if not running then return end
        if selected then
            targetLabel.Text=(selected.display~="" and selected.display or selected.name).."  @"..selected.name
            gameLabel.Text=selected.game_name~="" and selected.game_name or "Game details unavailable · update free script"
            serverLabel.Text=(sameServer(selected) and "YOUR SERVER" or "ANOTHER SERVER").."  ·  ID "..selected.id.."  ·  "..tostring(selected.place or 0)
        else
            targetLabel.Text="Select a user"; gameLabel.Text="Choose a connected free user on the left."; serverLabel.Text=""
        end
        local enabled=selected~=nil and not selected.owner
        for _,entry in ipairs(commandButtons) do
            local active=enabled and (entry.spec.name~="bring" or sameServer(selected))
            entry.button.Active=active
            entry.button.AutoButtonColor=active
            entry.button.TextTransparency=active and 0 or 0.6
        end
        joinButton.Text=selected and sameServer(selected) and "Already here" or "Join server"
    end
    renderUsers=function()
        if not running then return end
        for _,child in ipairs(list:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
        local filtered={}
        for _,user in ipairs(users) do
            local score=matchScore(user,search.Text)
            if score>0 then table.insert(filtered,{user=user,score=score}) end
        end
        table.sort(filtered,function(a,b)
            if a.score~=b.score then return a.score>b.score end
            if a.user.name~=b.user.name then return a.user.name:lower()<b.user.name:lower() end
            return a.user.sid<b.user.sid
        end)
        countLabel.Text="USERS · "..#users
        if #filtered==0 then
            local empty=label(list,#users==0 and "No free scripts connected yet." or "No matching users.",8,10,242,40,12,palette.muted)
            empty.TextWrapped=true
        end
        for index,entry in ipairs(filtered) do
            local user=entry.user
            local row=button(list,"",0,0,252,82,function()
                selected=user; renderSelection(); renderUsers()
            end)
            row.LayoutOrder=index
            row.BackgroundColor3=selected and selected.sid==user.sid and Color3.fromRGB(36,64,60) or palette.card
            label(row,"@"..user.name..(user.owner and " · OWNER" or ""),10,7,232,21,13)
            label(row,user.display or user.name,10,29,232,18,11,palette.muted)
            label(row,(sameServer(user) and "● HERE  " or "● REMOTE  ")..(user.game_name~="" and user.game_name or "Game unknown"),10,52,232,20,11,palette.accent)
        end
    end
    connect(search:GetPropertyChangedSignal("Text"),function() renderUsers() end)
    renderSelection(); renderUsers()
    task.spawn(function()
        while running do refresh(); task.wait(5) end
    end)
    status("Owner panel ready · "..#specs.." commands · choose a user.")
    print('Chat: !disco f, !ws flames 60, !join username. !help lists commands. Right Shift toggles the GUI.')
else
    if allowed then warn("Whitelisted ID detected. Use your private owner copy for the owner panel.") end
    local seen, order, announced={}, {}, false
    local function join()
        sessionKey=api("/join",{id=tostring(me.UserId),name=me.Name,display=me.DisplayName,job=game.JobId,place=game.PlaceId,game_name=gameName,version=2}).token
    end
    -- Small visible indicator makes participation and the Stop control clear.
    local badge=instance("ScreenGui",{Name="ExonFreeStatus",ResetOnSpawn=false,DisplayOrder=2000},me:WaitForChild("PlayerGui"))
    state.gui=badge
    local stop=instance("TextButton",{Size=UDim2.fromOffset(310,32),Position=UDim2.new(0.5,-155,0,8),BackgroundColor3=Color3.fromRGB(22,27,35),TextColor3=Color3.fromRGB(166,231,209),TextSize=12,Font=Enum.Font.Gotham,Text="EXON · Connecting… · click to stop",BorderSizePixel=0},badge)
    instance("UICorner",{CornerRadius=UDim.new(0,8)},stop)
    connect(stop.Activated,function() state.stop() end)
    task.spawn(function()
        local backoff=1
        while running do
            local ok,err=pcall(function()
                if sessionKey=="" then join() end
                local result=api("/poll",{game_name=gameName})
                if not running then return end
                stop.Text="EXON · Owner controls active · click to stop"
                if not announced then print("[Exon] Free client connected. Owner commands are active. Click the badge or call getgenv().OwnerRelay.stop() to leave."); announced=true end
                local ack={}
                for _,item in ipairs(result.commands) do
                    if not running then break end
                    if not seen[item.id] then
                        seen[item.id]=true; table.insert(order,item.id)
                        if #order>256 then seen[table.remove(order,1)]=nil end
                        local worked,reason=pcall(execute,item)
                        if not worked then warn("[Exon] Command failed:",item.command,reason) end
                    end
                    table.insert(ack,item.id)
                end
                if #ack>0 and running then api("/ack",{ids=ack}) end
            end)
            if ok then backoff=1 else
                warn("[Exon] Relay:",err)
                if running then stop.Text="EXON · Reconnecting… · click to stop" end
                if tostring(err):find("HTTP 403",1,true) then sessionKey="" end
                backoff=math.min(backoff*2,15)
            end
            task.wait(backoff)
        end
    end)
end
