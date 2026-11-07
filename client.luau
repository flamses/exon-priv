-- EXON v3 — one shared chat-only chunk. No GUI or cosmetic screen effects.
-- Owners: run the PRIVATE setup once in your executor. Never publish its key.
do
local env=(getgenv and getgenv()) or _G
if env.OwnerRelay and env.OwnerRelay.stop then pcall(env.OwnerRelay.stop) end
local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local Run=game:GetService("RunService")
local Teleport=game:GetService("TeleportService")
local me=Players.LocalPlayer
local httpRequest=request or http_request or (syn and syn.request)
if not httpRequest then warn("[Exon] This executor needs an HTTP request API.") else
local URL="https://exon-priv-relay.onrender.com"
local key=env.EXON_OWNER_KEY or ""
if key=="" and readfile then
    local ok,stored=pcall(readfile,"exon-owner-key.txt")
    if ok and type(stored)=="string" then key=stored:match("^%s*(.-)%s*$") end
end
local state={version=3,role="connecting"}
env.OwnerRelay=state
env.Exon=state
local running,paused,sessionKey,isOwner=true,false,"",false
local connections,cleanups={},{}
local function log(message) print("[Exon] "..tostring(message)) end
local function connect(signal,fn)
    local connection=signal:Connect(fn);table.insert(connections,connection);return connection
end
local function clear(name)
    local fn=cleanups[name];cleanups[name]=nil
    if fn then pcall(fn) end
end
local function clearAll()
    local names={};for name in pairs(cleanups) do table.insert(names,name) end
    for _,name in ipairs(names) do clear(name) end
end
function state.stop()
    running=false
    for _,connection in ipairs(connections) do connection:Disconnect() end
    clearAll()
    state.role="stopped"
    log("Stopped. Re-run the shared chunk to reconnect.")
end
local function api(path,body,method,ownerCall)
    local response=httpRequest({Url=URL..path,Method=method or "POST",
        Headers={["Content-Type"]="application/json",Authorization="Bearer "..(ownerCall and key or sessionKey),["X-Owner-Id"]=tostring(me.UserId)},
        Body=body and Http:JSONEncode(body) or nil})
    local code=tonumber(response.StatusCode or response.Status)
    if not code or code<200 or code>=300 then
        local ok,decoded=pcall(function()return Http:JSONDecode(response.Body)end)
        error("Relay HTTP "..tostring(code)..": "..(ok and type(decoded)=="table" and decoded.error or tostring(response.Body)),0)
    end
    return Http:JSONDecode(response.Body)
end
local function character()
    local char=me.Character
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    local root=char and char:FindFirstChild("HumanoidRootPart")
    assert(char and hum and root,"Character is not ready")
    return char,hum,root
end
local propertyLayers={}
local function save(name,object,property,value)
    clear(name)
    propertyLayers[object]=propertyLayers[object]or{}
    local entry=propertyLayers[object][property]
    if not entry then entry={original=object[property],layers={}};propertyLayers[object][property]=entry end
    local layer={name=name,value=value};table.insert(entry.layers,layer);object[property]=value
    cleanups[name]=function()
        for index,item in ipairs(entry.layers)do if item==layer then table.remove(entry.layers,index);break end end
        if object.Parent then if #entry.layers>0 then object[property]=entry.layers[#entry.layers].value else object[property]=entry.original end end
        if #entry.layers==0 then propertyLayers[object][property]=nil end
    end
end
local function moveTo(cf)
    local char,_,root=character()
    state.previous=root.CFrame
    char:PivotTo(cf)
end
local function externalJson(url)
    -- Roblox server discovery receives NO relay credentials.
    local response=httpRequest({Url=url,Method="GET"})
    local code=tonumber(response.StatusCode or response.Status)
    assert(code and code>=200 and code<300,"Server discovery HTTP "..tostring(code))
    return Http:JSONDecode(response.Body)
end
local function hop(mode)
    local servers,cursor={},nil
    local visited=env.EXON_VISITED or {};env.EXON_VISITED=visited
    for _=1,3 do
        local url="https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?limit=100&excludeFullGames=true&sortOrder="..(mode=="hophigh" and "Desc" or "Asc")
        if cursor then url..="&cursor="..Http:UrlEncode(cursor) end
        local page=externalJson(url)
        for _,server in ipairs(page.data or {}) do
            if server.id~=game.JobId and server.playing<server.maxPlayers then table.insert(servers,server) end
        end
        cursor=page.nextPageCursor
        if not cursor or cursor=="" then break end
    end
    assert(#servers>0,"No other joinable public servers found")
    if mode=="hoplow" or mode=="hophigh" then
        table.sort(servers,function(a,b)return mode=="hoplow" and a.playing<b.playing or mode=="hophigh" and a.playing>b.playing end)
    else
        local fresh={};for _,server in ipairs(servers)do if not visited[server.id] then table.insert(fresh,server) end end
        if #fresh>0 then servers=fresh end
        local chosen=math.random(#servers);servers[1],servers[chosen]=servers[chosen],servers[1]
    end
    visited[game.JobId]=true;visited[servers[1].id]=true
    Teleport:TeleportToPlaceInstance(game.PlaceId,servers[1].id,me)
end
local function referencePlayer(id)
    local player=Players:GetPlayerByUserId(tonumber(id) or 0)
    assert(player and player~=me,"Reference player must be another player in this server")
    return player
end
local function execute(item)
    local cmd,v=item.command,item.value
    if cmd=="kick" then me:Kick(item.text or "Disconnected by the script owner.");return
    elseif cmd=="rejoin" then Teleport:TeleportToPlaceInstance(game.PlaceId,game.JobId,me);return
    elseif cmd=="serverhop" or cmd=="hoplow" or cmd=="hophigh" then hop(cmd);return
    elseif cmd=="joinplace" then Teleport:Teleport(v,me);return end
    local char,hum,root=character()
    if cmd=="bring" or cmd=="tpcoords" then
        local p=item.position;moveTo(CFrame.new(p[1],p[2],p[3])*root.CFrame.Rotation)
    elseif cmd=="kill" or cmd=="reset" then hum.Health=0
    elseif cmd=="heal" then hum.Health=hum.MaxHealth
    elseif cmd=="freeze" then save("freeze",root,"Anchored",true)
    elseif cmd=="unfreeze" then clear("freeze")
    elseif cmd=="sit" then hum.Sit=true
    elseif cmd=="unsit" then hum.Sit=false;hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    elseif cmd=="jump" then hum.Jump=true
    elseif cmd=="walkspeed" then save("speed",hum,"WalkSpeed",v)
    elseif cmd=="jumppower" or cmd=="jumpheight" then
        clear("jumpstats")
        local oldPower,oldHeight,oldUse=hum.JumpPower,hum.JumpHeight,hum.UseJumpPower
        hum.UseJumpPower=cmd=="jumppower"
        if cmd=="jumppower" then hum.JumpPower=v else hum.JumpHeight=v end
        cleanups.jumpstats=function()if hum.Parent then hum.JumpPower=oldPower;hum.JumpHeight=oldHeight;hum.UseJumpPower=oldUse end end
    elseif cmd=="hipheight" then save("hip",hum,"HipHeight",v)
    elseif cmd=="platformstand" then save("platform",hum,"PlatformStand",true)
    elseif cmd=="unplatformstand" then clear("platform");hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    elseif cmd=="autorotate" then save("rotation",hum,"AutoRotate",true)
    elseif cmd=="noautorotate" then save("rotation",hum,"AutoRotate",false)
    elseif cmd=="ragdoll" then hum:ChangeState(Enum.HumanoidStateType.Ragdoll)
    elseif cmd=="unragdoll" then hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    elseif cmd=="stun" then save("stun_speed",hum,"WalkSpeed",0);save("stun_platform",hum,"PlatformStand",true)
    elseif cmd=="unstun" then clear("stun_speed");clear("stun_platform");hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    elseif cmd=="sprint" then save("sprint",hum,"WalkSpeed",32)
    elseif cmd=="unsprint" then clear("sprint")
    elseif cmd=="crouch" then clear("crouch_hip");clear("crouch_speed");save("crouch_hip",hum,"HipHeight",math.max(-2,hum.HipHeight-1.5));save("crouch_speed",hum,"WalkSpeed",8)
    elseif cmd=="uncrouch" then clear("crouch_hip");clear("crouch_speed")
    elseif cmd=="stopvelocity" then root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
    elseif cmd=="fling" then assert(not root.Anchored,"Unfreeze first");root.AssemblyLinearVelocity=Vector3.new(100,150,0);root.AssemblyAngularVelocity=Vector3.new(0,35,0)
    elseif cmd=="launch" then root.AssemblyLinearVelocity=Vector3.new(0,v,0)
    elseif cmd=="drop" then root.AssemblyLinearVelocity=Vector3.new(0,-v,0)
    elseif cmd=="boost" then root.AssemblyLinearVelocity=root.CFrame.LookVector*v+Vector3.new(0,20,0)
    elseif cmd=="velocity" then local p=item.position;root.AssemblyLinearVelocity=Vector3.new(p[1],p[2],p[3])
    elseif cmd=="forward" or cmd=="backward" or cmd=="left" or cmd=="right" or cmd=="up" or cmd=="down" then
        local offsets={forward=Vector3.new(0,0,-v),backward=Vector3.new(0,0,v),left=Vector3.new(-v,0,0),right=Vector3.new(v,0,0),up=Vector3.new(0,v,0),down=Vector3.new(0,-v,0)}
        moveTo(root.CFrame*CFrame.new(offsets[cmd]))
    elseif cmd=="turn" or cmd=="turnleft" or cmd=="turnright" or cmd=="turnaround" then
        local angles={turnleft=90,turnright=-90,turnaround=180}
        moveTo(root.CFrame*CFrame.Angles(0,math.rad(angles[cmd] or v),0))
    elseif cmd=="faceforward" or cmd=="facebackward" or cmd=="faceleft" or cmd=="faceright" then
        local angles={faceforward=0,facebackward=180,faceleft=90,faceright=-90}
        moveTo(CFrame.new(root.Position)*CFrame.Angles(0,math.rad(angles[cmd]),0))
    elseif cmd=="walkto" then local p=item.position;hum:MoveTo(Vector3.new(p[1],p[2],p[3]))
    elseif cmd=="stopwalk" then hum:Move(Vector3.zero,false);hum:MoveTo(root.Position)
    elseif cmd=="spin" then
        clear("spin")
        local a=Instance.new("Attachment");a.Name="ExonSpin";a.Parent=root
        local angular=Instance.new("AngularVelocity");angular.Attachment0=a;angular.RelativeTo=Enum.ActuatorRelativeTo.World;angular.AngularVelocity=Vector3.new(0,v,0);angular.MaxTorque=1000000;angular.Parent=root
        cleanups.spin=function()angular:Destroy();a:Destroy();if root.Parent then root.AssemblyAngularVelocity=Vector3.zero end end
    elseif cmd=="unspin" then clear("spin")
    elseif cmd=="float" then
        clear("float")
        local a=Instance.new("Attachment");a.Parent=root
        local align=Instance.new("AlignPosition");align.Mode=Enum.PositionAlignmentMode.OneAttachment;align.Attachment0=a;align.Position=root.Position+Vector3.new(0,v,0);align.MaxForce=1000000;align.Responsiveness=20;align.Parent=root
        cleanups.float=function()align:Destroy();a:Destroy()end
    elseif cmd=="unfloat" then clear("float")
    elseif cmd=="follow" or cmd=="orbit" then
        clear("tracking")
        local player=referencePlayer(item.reference)
        local elapsed=0
        local c=Run.Heartbeat:Connect(function(dt)
            local other=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if not root.Parent or not hum.Parent or not other then clear("tracking");return end
            elapsed+=dt
            if cmd=="follow" then hum:MoveTo((other.CFrame*CFrame.new(0,0,v)).Position)
            else
                local p=other.Position+Vector3.new(math.cos(elapsed)*v,0,math.sin(elapsed)*v)
                char:PivotTo(CFrame.lookAt(p,Vector3.new(other.Position.X,p.Y,other.Position.Z)))
            end
        end)
        cleanups.tracking=function()c:Disconnect();if hum.Parent then hum:Move(Vector3.zero,false);hum:MoveTo(root.Position)end end
    elseif cmd=="unfollow" or cmd=="unorbit" then clear("tracking")
    elseif cmd=="bunnyhop" then
        clear("bunnyhop")
        local c=Run.Heartbeat:Connect(function()if hum.Parent and hum.FloorMaterial~=Enum.Material.Air then hum.Jump=true end end)
        cleanups.bunnyhop=function()c:Disconnect()end
    elseif cmd=="unbunnyhop" then clear("bunnyhop")
    elseif cmd=="autowalk" then
        clear("autowalk")
        local c=Run.Heartbeat:Connect(function()if hum.Parent and root.Parent then hum:Move(root.CFrame.LookVector,false)end end)
        cleanups.autowalk=function()c:Disconnect();if hum.Parent then hum:Move(Vector3.zero,false)end end
    elseif cmd=="unautowalk" then clear("autowalk")
    elseif cmd=="noclip" then
        clear("noclip");local originals={}
        local c=Run.Stepped:Connect(function()
            for _,p in ipairs(char:GetDescendants())do if p:IsA("BasePart")then if originals[p]==nil then originals[p]=p.CanCollide end;p.CanCollide=false end end
        end)
        cleanups.noclip=function()c:Disconnect();for p,old in pairs(originals)do if p.Parent then p.CanCollide=old end end end
    elseif cmd=="clip" then clear("noclip")
    elseif cmd=="resetstats" then clearAll();hum.Sit=false;hum:ChangeState(Enum.HumanoidStateType.GettingUp)
    elseif cmd=="wave" or cmd=="point" or cmd=="cheer" or cmd=="laugh" or cmd=="dance" or cmd=="dance2" or cmd=="dance3" then
        assert(hum:PlayEmoteAsync(cmd),"This character doesn't have the requested emote")
    elseif cmd=="equip" then
        local backpack=me:FindFirstChildOfClass("Backpack")
        local tool=backpack and backpack:FindFirstChildOfClass("Tool")
        assert(tool,"No backpack tool available");hum:EquipTool(tool)
    elseif cmd=="unequip" then hum:UnequipTools()
    elseif cmd=="equipall" then
        local backpack=me:FindFirstChildOfClass("Backpack")
        assert(backpack,"No backpack")
        for _,tool in ipairs(backpack:GetChildren())do if tool:IsA("Tool")then tool.Parent=char end end
    elseif cmd=="activate" or cmd=="deactivate" then
        local tool=char:FindFirstChildOfClass("Tool");assert(tool,"Equip a tool first")
        if cmd=="activate" then tool:Activate()else tool:Deactivate()end
    elseif cmd=="droptools" then
        for _,tool in ipairs(char:GetChildren())do if tool:IsA("Tool") and tool.CanBeDropped then tool.Parent=workspace end end
    else error("Unknown action: "..tostring(cmd))end
end
connect(me.CharacterRemoving,clearAll)
connect(Teleport.TeleportInitFailed,function(player,_,message)if player==me then warn("[Exon] Teleport failed: "..tostring(message))end end)
local CATALOG = {["bring"]={["kind"]="action",["description"]="bring"},["kill"]={["kind"]="action",["description"]="kill"},["heal"]={["kind"]="action",["description"]="heal"},["reset"]={["kind"]="action",["description"]="reset"},["freeze"]={["kind"]="action",["description"]="freeze"},["unfreeze"]={["kind"]="action",["description"]="unfreeze"},["sit"]={["kind"]="action",["description"]="sit"},["unsit"]={["kind"]="action",["description"]="unsit"},["jump"]={["kind"]="action",["description"]="jump"},["platformstand"]={["kind"]="action",["description"]="platformstand"},["unplatformstand"]={["kind"]="action",["description"]="unplatformstand"},["autorotate"]={["kind"]="action",["description"]="autorotate"},["noautorotate"]={["kind"]="action",["description"]="noautorotate"},["ragdoll"]={["kind"]="action",["description"]="ragdoll"},["unragdoll"]={["kind"]="action",["description"]="unragdoll"},["stun"]={["kind"]="action",["description"]="stun"},["unstun"]={["kind"]="action",["description"]="unstun"},["stopvelocity"]={["kind"]="action",["description"]="stopvelocity"},["stopwalk"]={["kind"]="action",["description"]="stopwalk"},["unfollow"]={["kind"]="action",["description"]="unfollow"},["unorbit"]={["kind"]="action",["description"]="unorbit"},["unfloat"]={["kind"]="action",["description"]="unfloat"},["noclip"]={["kind"]="action",["description"]="noclip"},["clip"]={["kind"]="action",["description"]="clip"},["bunnyhop"]={["kind"]="action",["description"]="bunnyhop"},["unbunnyhop"]={["kind"]="action",["description"]="unbunnyhop"},["autowalk"]={["kind"]="action",["description"]="autowalk"},["unautowalk"]={["kind"]="action",["description"]="unautowalk"},["sprint"]={["kind"]="action",["description"]="sprint"},["unsprint"]={["kind"]="action",["description"]="unsprint"},["crouch"]={["kind"]="action",["description"]="crouch"},["uncrouch"]={["kind"]="action",["description"]="uncrouch"},["resetstats"]={["kind"]="action",["description"]="resetstats"},["walkspeed"]={["kind"]="action",["description"]="walkspeed",["arg"]="number",["default"]=50,["min"]=0,["max"]=200},["jumppower"]={["kind"]="action",["description"]="jumppower",["arg"]="number",["default"]=100,["min"]=0,["max"]=200},["jumpheight"]={["kind"]="action",["description"]="jumpheight",["arg"]="number",["default"]=14,["min"]=0,["max"]=100},["hipheight"]={["kind"]="action",["description"]="hipheight",["arg"]="number",["default"]=3,["min"]=-3,["max"]=20},["spin"]={["kind"]="action",["description"]="spin",["arg"]="number",["default"]=10,["min"]=-50,["max"]=50},["forward"]={["kind"]="action",["description"]="forward",["arg"]="number",["default"]=10,["min"]=0,["max"]=200},["backward"]={["kind"]="action",["description"]="backward",["arg"]="number",["default"]=10,["min"]=0,["max"]=200},["left"]={["kind"]="action",["description"]="left",["arg"]="number",["default"]=10,["min"]=0,["max"]=200},["right"]={["kind"]="action",["description"]="right",["arg"]="number",["default"]=10,["min"]=0,["max"]=200},["up"]={["kind"]="action",["description"]="up",["arg"]="number",["default"]=10,["min"]=0,["max"]=500},["down"]={["kind"]="action",["description"]="down",["arg"]="number",["default"]=10,["min"]=0,["max"]=500},["turn"]={["kind"]="action",["description"]="turn",["arg"]="number",["default"]=90,["min"]=-360,["max"]=360},["launch"]={["kind"]="action",["description"]="launch",["arg"]="number",["default"]=100,["min"]=0,["max"]=250},["drop"]={["kind"]="action",["description"]="drop",["arg"]="number",["default"]=100,["min"]=0,["max"]=250},["boost"]={["kind"]="action",["description"]="boost",["arg"]="number",["default"]=70,["min"]=0,["max"]=200},["float"]={["kind"]="action",["description"]="float",["arg"]="number",["default"]=5,["min"]=0,["max"]=100},["orbit"]={["kind"]="action",["description"]="orbit",["arg"]="number",["default"]=8,["min"]=2,["max"]=40},["follow"]={["kind"]="action",["description"]="follow",["arg"]="number",["default"]=4,["min"]=2,["max"]=30},["unspin"]={["kind"]="action",["description"]="unspin"},["turnleft"]={["kind"]="action",["description"]="turnleft"},["turnright"]={["kind"]="action",["description"]="turnright"},["turnaround"]={["kind"]="action",["description"]="turnaround"},["faceforward"]={["kind"]="action",["description"]="faceforward"},["facebackward"]={["kind"]="action",["description"]="facebackward"},["faceleft"]={["kind"]="action",["description"]="faceleft"},["faceright"]={["kind"]="action",["description"]="faceright"},["tpcoords"]={["kind"]="action",["description"]="tpcoords",["arg"]="vector",["default"]=nil,["min"]=-1000000,["max"]=1000000},["velocity"]={["kind"]="action",["description"]="velocity",["arg"]="vector",["default"]=nil,["min"]=-1000000,["max"]=1000000},["walkto"]={["kind"]="action",["description"]="walkto",["arg"]="vector",["default"]=nil,["min"]=-1000000,["max"]=1000000},["wave"]={["kind"]="action",["description"]="wave"},["point"]={["kind"]="action",["description"]="point"},["cheer"]={["kind"]="action",["description"]="cheer"},["laugh"]={["kind"]="action",["description"]="laugh"},["dance"]={["kind"]="action",["description"]="dance"},["dance2"]={["kind"]="action",["description"]="dance2"},["dance3"]={["kind"]="action",["description"]="dance3"},["equip"]={["kind"]="action",["description"]="equip"},["unequip"]={["kind"]="action",["description"]="unequip"},["equipall"]={["kind"]="action",["description"]="equipall"},["activate"]={["kind"]="action",["description"]="activate"},["deactivate"]={["kind"]="action",["description"]="deactivate"},["droptools"]={["kind"]="action",["description"]="droptools"},["rejoin"]={["kind"]="action",["description"]="rejoin"},["serverhop"]={["kind"]="action",["description"]="serverhop"},["hoplow"]={["kind"]="action",["description"]="hoplow"},["hophigh"]={["kind"]="action",["description"]="hophigh"},["joinplace"]={["kind"]="action",["description"]="joinplace",["arg"]="number",["default"]=nil,["min"]=1,["max"]=10000000000000000},["kick"]={["kind"]="action",["description"]="kick",["arg"]="text",["default"]=nil,["min"]=nil,["max"]=nil},["help"]={["kind"]="info",["description"]="help"},["users"]={["kind"]="info",["description"]="users"},["players"]={["kind"]="info",["description"]="players"},["whoami"]={["kind"]="info",["description"]="whoami"},["ping"]={["kind"]="info",["description"]="ping"},["relaystatus"]={["kind"]="info",["description"]="relaystatus"},["status"]={["kind"]="info",["description"]="status"},["serverinfo"]={["kind"]="info",["description"]="serverinfo"},["gameinfo"]={["kind"]="info",["description"]="gameinfo"},["placeid"]={["kind"]="info",["description"]="placeid"},["jobid"]={["kind"]="info",["description"]="jobid"},["universeid"]={["kind"]="info",["description"]="universeid"},["playercount"]={["kind"]="info",["description"]="playercount"},["ownerids"]={["kind"]="info",["description"]="ownerids"},["version"]={["kind"]="info",["description"]="version"},["goto"]={["kind"]="query",["description"]="goto"},["join"]={["kind"]="query",["description"]="join"},["locate"]={["kind"]="query",["description"]="locate"},["userid"]={["kind"]="query",["description"]="userid"},["username"]={["kind"]="query",["description"]="username"},["displayname"]={["kind"]="query",["description"]="displayname"},["distance"]={["kind"]="query",["description"]="distance"},["position"]={["kind"]="query",["description"]="position"},["health"]={["kind"]="query",["description"]="health"},["speed"]={["kind"]="query",["description"]="speed"},["jumpstats"]={["kind"]="query",["description"]="jumpstats"},["state"]={["kind"]="query",["description"]="state"},["tools"]={["kind"]="query",["description"]="tools"},["rig"]={["kind"]="query",["description"]="rig"},["team"]={["kind"]="query",["description"]="team"},["age"]={["kind"]="query",["description"]="age"},["savepos"]={["kind"]="bookmark",["description"]="savepos"},["loadpos"]={["kind"]="bookmark",["description"]="loadpos"},["delpos"]={["kind"]="bookmark",["description"]="delpos"},["listpos"]={["kind"]="bookmark",["description"]="listpos"},["clearpos"]={["kind"]="bookmark",["description"]="clearpos"},["back"]={["kind"]="bookmark",["description"]="back"},["refresh"]={["kind"]="control",["description"]="refresh"},["reconnect"]={["kind"]="control",["description"]="reconnect"},["stop"]={["kind"]="control",["description"]="stop"},["pause"]={["kind"]="control",["description"]="pause"},["resume"]={["kind"]="control",["description"]="resume"},["fling"]={["kind"]="action",["description"]="fling"}}
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
local aliases={commands="help",me="whoami",ws="walkspeed",speed="walkspeed",jp="jumppower",jh="jumpheight",hh="hipheight",tp="goto",joinuser="join",joinfree="join",hop="serverhop",stand="unsit",unplatform="unplatformstand",unnoclip="clip"}
local cachedUsers,lastFetch={},0
local bookmarks=env.EXON_BOOKMARKS or {};env.EXON_BOOKMARKS=bookmarks
local function fetchUsers(force)
    if force or os.clock()-lastFetch>2 then
        cachedUsers=api("/clients",nil,"GET",true).clients;lastFetch=os.clock()
    end
    return cachedUsers
end
local function localRecord(player)
    return {id=tostring(player.UserId),name=player.Name,display=player.DisplayName,job=game.JobId,place=game.PlaceId,game_name="Current game",player=player}
end
local function resolve(query,relayOnly)
    query=tostring(query or "me")
    if query:lower()=="me" or query:lower()=="self" then return localRecord(me) end
    local candidates,keys={},{}
    for _,u in ipairs(fetchUsers())do
        local k=u.id..":"..u.job
        if not keys[k] then table.insert(candidates,u);keys[k]=true end
    end
    if not relayOnly then
        for _,p in ipairs(Players:GetPlayers())do
            local u=localRecord(p);local k=u.id..":"..u.job
            if not keys[k] then table.insert(candidates,u);keys[k]=true end
        end
    end
    local best,matches=0,{}
    for _,u in ipairs(candidates)do
        local score=matchScore(u,query)
        if score>best then best=score;matches={u}
        elseif score==best and score>0 then table.insert(matches,u)end
    end
    if #matches>1 then
        local id,same=matches[1].id,{}
        local allSame=true
        for _,u in ipairs(matches)do if u.id~=id then allSame=false end;if u.job==game.JobId then table.insert(same,u)end end
        if allSame and #same==1 then matches=same end
    end
    assert(#matches>0,"No player matches '"..query.."'")
    if #matches>1 then
        local names={};for i=1,math.min(#matches,6)do table.insert(names,"@"..matches[i].name)end
        error("Ambiguous name: "..table.concat(names,", ")..". Type more letters or the user ID.",0)
    end
    return matches[1]
end
local function localPlayer(user)
    assert(user.job==game.JobId,"Join that user's server first")
    return assert(Players:GetPlayerByUserId(tonumber(user.id)),"Player is no longer in this server")
end
local function rootFor(player)
    return assert(player.Character and player.Character:FindFirstChild("HumanoidRootPart"),"Target character is not ready")
end
local function humanoidFor(player)
    return assert(player.Character and player.Character:FindFirstChildOfClass("Humanoid"),"Target humanoid is not ready")
end
local function tokenize(text)
    local words={};local i=1
    assert(#text<=1000,"Command is too long")
    while i<=#text do
        local ch=text:sub(i,i)
        if ch:match("%s")then i+=1
        elseif ch=='"' or ch=="'"then
            local finish=text:find(ch,i+1,true);assert(finish,"Close the quoted name")
            table.insert(words,text:sub(i+1,finish-1));i=finish+1
        else
            local finish=text:find("%s",i)or(#text+1);table.insert(words,text:sub(i,finish-1));i=finish
        end
    end
    return words
end
function state.command(text)
    local words=tokenize(text)
    local cmd=(words[1]or""):lower()
    local prefix=env.EXON_PREFIX or "!"
    if cmd:sub(1,#prefix)==prefix then cmd=cmd:sub(#prefix+1)end
    cmd=aliases[cmd]or cmd
    local spec=assert(CATALOG[cmd],"Unknown command. Use !help")
    if cmd=="stop"then state.stop();return
    elseif cmd=="pause"then paused=true;clearAll();log("Receiving paused; use !resume to reconnect.");return
    elseif cmd=="resume"then paused=false;sessionKey="";log("Resuming connection.");return
    elseif cmd=="reconnect"then sessionKey="";log("Reconnecting on next poll.");return
    elseif cmd=="status"then log("v3 · "..state.role.." · "..(paused and "paused" or "running"));return end
    assert(isOwner,"Owner authentication is required for this command")
    if spec.kind=="info"then
        if cmd=="help"then
            local names={};for name in pairs(CATALOG)do table.insert(names,name)end;table.sort(names)
            log(#names.." commands: "..table.concat(names,", "))
            log("Actions: !walkspeed f 50, !rejoin me, !serverhop me, !follow f 4. Travel: !goto f, !join f. Coordinates: !tpcoords me 0 20 0. Names: short prefix, ID, or quoted display name.")
        elseif cmd=="users"then for _,u in ipairs(fetchUsers(true))do log("@"..u.name.." · "..u.id.." · "..u.game_name.." · "..(u.job==game.JobId and "same server"or"another server"))end
        elseif cmd=="players"then for _,p in ipairs(Players:GetPlayers())do log("@"..p.Name.." / "..p.DisplayName.." / "..p.UserId)end
        elseif cmd=="whoami"then log(me.Name.." / "..me.DisplayName.." / "..me.UserId.." / "..state.role)
        elseif cmd=="ping"then local start=os.clock();api("/health",nil,"GET");log("Relay round trip: "..math.floor((os.clock()-start)*1000).." ms")
        elseif cmd=="relaystatus"then log("Relay healthy: "..tostring(api("/health",nil,"GET").ok))
        elseif cmd=="serverinfo"then log("Place "..game.PlaceId.." / job "..game.JobId.." / "..#Players:GetPlayers().." players")
        elseif cmd=="gameinfo"then log("Universe "..game.GameId.." / place "..game.PlaceId.." / "..game.Name)
        elseif cmd=="placeid"then log(game.PlaceId)
        elseif cmd=="jobid"then log(game.JobId)
        elseif cmd=="universeid"then log(game.GameId)
        elseif cmd=="playercount"then log(#Players:GetPlayers())
        elseif cmd=="ownerids"then log(table.concat(api("/ownerids",nil,"GET",true).ids,", "))
        elseif cmd=="version"then log("EXON v3 chat-only; public chunk is identical for every user.")end
        return
    elseif spec.kind=="bookmark"then
        local name=words[2]or"default"
        if cmd=="savepos"then local _,_,root=character();bookmarks[name]={cf=root.CFrame,place=game.PlaceId,job=game.JobId};log("Saved "..name)
        elseif cmd=="loadpos"then local mark=assert(bookmarks[name],"Unknown saved position");assert(mark.job==game.JobId and mark.place==game.PlaceId,"Bookmark belongs to another server");moveTo(mark.cf)
        elseif cmd=="delpos"then assert(bookmarks[name],"Unknown saved position");bookmarks[name]=nil;log("Deleted "..name)
        elseif cmd=="listpos"then for label,mark in pairs(bookmarks)do log(label.." · "..mark.place.." · "..mark.job)end
        elseif cmd=="clearpos"then table.clear(bookmarks);log("Saved positions cleared")
        elseif cmd=="back"then local previous=assert(state.previous,"No previous position");moveTo(previous)end
        return
    elseif spec.kind=="control"then
        if cmd=="refresh"then log(#fetchUsers(true).." connected sessions")end
        return
    end
    local user=resolve(words[2],cmd=="join"or cmd=="locate")
    if spec.kind=="query"then
        if cmd=="join"then
            assert(tonumber(user.place)and user.place>0 and user.job~="","No game information for this user")
            if user.job==game.JobId and user.place==game.PlaceId then log("Already in that server");return end
            log("Joining @"..user.name..". Re-run your hub after teleporting.")
            Teleport:TeleportToPlaceInstance(user.place,user.job,me)
        elseif cmd=="locate"then log("@"..user.name.." · "..user.game_name.." · place "..user.place.." · job "..user.job)
        elseif cmd=="userid"then log(user.id)
        elseif cmd=="username"then log(user.name)
        elseif cmd=="displayname"then log(user.display)
        else
            local player=localPlayer(user)
            if cmd=="goto"then moveTo(rootFor(player).CFrame*CFrame.new(0,0,4))
            elseif cmd=="position"then log(tostring(rootFor(player).Position))
            elseif cmd=="distance"then local _,_,root=character();log(math.floor((root.Position-rootFor(player).Position).Magnitude).." studs")
            elseif cmd=="health"then local hum=humanoidFor(player);log(hum.Health.." / "..hum.MaxHealth)
            elseif cmd=="speed"then log(humanoidFor(player).WalkSpeed)
            elseif cmd=="jumpstats"then local hum=humanoidFor(player);log("Power "..hum.JumpPower.." / height "..hum.JumpHeight.." / UseJumpPower "..tostring(hum.UseJumpPower))
            elseif cmd=="state"then log(tostring(humanoidFor(player):GetState()))
            elseif cmd=="rig"then log(tostring(humanoidFor(player).RigType))
            elseif cmd=="team"then log(player.Team and player.Team.Name or "No team")
            elseif cmd=="age"then log(player.AccountAge.." days")
            elseif cmd=="tools"then
                local items={};local backpack=player:FindFirstChildOfClass("Backpack")
                for _,container in ipairs({player.Character,backpack})do
                    if container then for _,tool in ipairs(container:GetChildren())do if tool:IsA("Tool")then table.insert(items,tool.Name)end end end
                end
                log(#items>0 and table.concat(items,", ")or"No visible tools")
            end
        end
        return
    end
    local item={command=cmd}
    if spec.arg=="number"then
        local n=words[3]and tonumber(words[3])or spec.default
        assert(n and n==n and n>=spec.min and n<=spec.max,"Supply a number from "..spec.min.." to "..spec.max.." after the target")
        if cmd=="joinplace"then assert(n%1==0,"Place ID must be an integer")end
        item.value=n
    elseif spec.arg=="vector"then
        local p={tonumber(words[3]),tonumber(words[4]),tonumber(words[5])}
        assert(type(p[1])=="number" and type(p[2])=="number" and type(p[3])=="number","Supply x y z after the target")
        local bound=cmd=="velocity"and 250 or 1000000
        for _,n in ipairs(p)do assert(n==n and math.abs(n)<=bound,"Coordinates/velocity outside allowed range")end
        item.position=p
    elseif spec.arg=="text"then item.text=table.concat(words," ",3);if item.text==""then item.text="Disconnected by the script owner."end;assert(#item.text<=200,"Reason is too long")end
    if cmd=="bring"then
        local _,_,root=character();local p=(root.CFrame*CFrame.new(0,0,-4)).Position
        item.position={p.X,p.Y,p.Z}
    elseif cmd=="follow"or cmd=="orbit"then item.reference=tostring(me.UserId)end
    if user.id==tostring(me.UserId)then
        execute(item);log("Ran "..cmd.." on your character")
    else
        assert(user.sid,"That player isn't connected to the relay. Run the shared chunk on their account first.")
        assert(not user.owner,"Owners cannot be targeted")
        item.target=user.id;item.session=user.sid;item.job=user.job;item.origin_job=game.JobId;item.origin_place=game.PlaceId
        api("/command",item,"POST",true);log("Queued "..cmd.." for @"..user.name.."; execution depends on their game.")
    end
end
-- The script-hub chunk returns immediately; networking runs independently.
task.spawn(function()
    local initialized=false
    local gameName="Place "..game.PlaceId
    task.spawn(function()
        local ok,info=pcall(function()return game:GetService("MarketplaceService"):GetProductInfoAsync(game.PlaceId,Enum.InfoType.Asset)end)
        if ok and info.Name then gameName=info.Name end
    end)
    local seen,order={},{}
    local backoff=1
    while running do
        local ok,err=pcall(function()
            if not initialized then
                local allowed=api("/role",{id=tostring(me.UserId)}).owner
                isOwner=allowed and key~=""
                if isOwner then
                    -- Verify the secret now; a wrong key never starts an owner session.
                    api("/clients",nil,"GET",true)
                elseif allowed then
                    warn("[Exon] Your ID is whitelisted; run the private owner setup once to enable owner chat commands.")
                end
                state.role=isOwner and "owner"or"free";initialized=true
                log("v3 "..state.role.." connected. No GUI. "..(isOwner and "Use !help. "or"Owner commands can affect this character. ").."Use !stop to disconnect.")
                connect(me.Chatted,function(text)
                    local prefix=env.EXON_PREFIX or "!"
                    if text:sub(1,#prefix)==prefix then
                        task.spawn(function()local worked,reason=pcall(state.command,text);if not worked then warn("[Exon] "..tostring(reason))end end)
                    end
                end)
            end
            if paused then return end
            if sessionKey==""then
                sessionKey=api("/join",{id=tostring(me.UserId),name=me.Name,display=me.DisplayName,job=game.JobId,place=game.PlaceId,game_name=gameName,version=3}).token
            end
            local result=api("/poll",{game_name=gameName})
            if not running then return end
            local ack={}
            for _,item in ipairs(result.commands)do
                if not running then break end
                if not seen[item.id]then
                    seen[item.id]=true;table.insert(order,item.id)
                    if #order>256 then seen[table.remove(order,1)]=nil end
                    local worked,reason=pcall(execute,item)
                    if not worked then warn("[Exon] "..item.command.." failed: "..tostring(reason))end
                end
                table.insert(ack,item.id)
            end
            if #ack>0 and running then api("/ack",{ids=ack})end
        end)
        if ok then backoff=1 else
            warn("[Exon] "..tostring(err))
            if initialized and tostring(err):find("HTTP 403",1,true)then sessionKey=""end
            backoff=math.min(backoff*2,15)
        end
        task.wait(backoff)
    end
end)
end -- HTTP support
end -- isolated script-hub chunk
