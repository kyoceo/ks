--========================================================--
--                  T21 SYSTEM (FLOATING)
--   Smooth chase    No teleport    Noclip    Auto repeat
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

--========================================================--
-- USERNAME CHECK (Guard Clause)
--========================================================--
local allowedUsers = {
    ["craken696"] = true,
    ["MKU48U"] = true,
    ["MCT48T"] = true,
    ["miso_matchapuri"] = true,
    ["queenrosee172"] = true,
    ["treezeekk"] = true,
    ["roblox_user_4058510147"] = true,
    ["aly_jxhn"] = true,
}

if not allowedUsers[player.Name] then
    -- Stops execution entirely if the username is not authorized
    return
end

--========================================================--
-- CHAT SYSTEM SETUP (Safe Execution)
--========================================================--
local TextChatService = game:GetService("TextChatService")
local isLegacyChat = TextChatService.ChatVersion == Enum.ChatVersion.LegacyChatService

local function chat(msg)
    pcall(function()
        if isLegacyChat then
            local replicatedChat = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
            if replicatedChat then
                local sayMessageRequest = replicatedChat:FindFirstChild("SayMessageRequest")
                if sayMessageRequest then
                    sayMessageRequest:FireServer(msg, "All")
                end
            end
        else
            local channels = TextChatService:FindFirstChild("TextChannels")
            if channels then
                local general = channels:FindFirstChild("RBXGeneral")
                if general then
                    general:SendAsync(msg)
                end
            end
        end
    end)
end

-- Send startup message through chat system
chat("T21 Script Loaded...")

-- Added messages with delays
task.wait(1)
chat("Made By Kyoshi")
task.wait(1)
chat("Script abuser hunter")
task.wait(1)
chat("T21 Cmd: m1/m2 on/off, predict on/off, block on/off, attack/destroy")

local parentPlayer = player
local followConnection = nil

-- States
local mode = "idle"
local attackTarget = nil
local panicMode = false

-- Settings
local FLOAT_HEIGHT = 0
local MOVE_STEP = 0.3
local HITBOX_SIZE = 100
local BLOCK_ENABLED = false
local PREDICT_ENABLED = false
local PREDICT_FACTOR = 0.1
local loopKillTargetName = nil

-- Auto Combat Settings
local m1Active = false
local m2Active = false
local COMBAT_COOLDOWN = 0

-- Destroy Settings
local destroyTarget = nil
local DESTROY_RADIUS = 20
local DESTROY_SPEED = 0.1
local destroyMode = false

-- Orbit settings for destroy mode
local ORBIT_RADIUS = 14
local ORBIT_SPEED = 6
local orbitAngle = 0
local savedOrbitSpeed = ORBIT_SPEED

-- Internal
local lastCommand = nil
local immunePlayers = {}
local resetUsed = false

-- Recovery & Monitoring State
local isRecovering = false
local attackActiveState = false

-- Assigners
local assigners = {
    ["jhxnna_rxse"] = true,
}
assigners[player.Name] = true

--========================================================--
-- PLAYER FIND
--========================================================--

local function findPlayerByFuzzy(str)
    str = str:lower()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.DisplayName:lower():find(str) or plr.Name:lower():find(str) then
            return plr
        end
    end
    return nil
end

--========================================================--
-- NOCLIP
--========================================================--

RunService.Stepped:Connect(function()
    local char = player.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end
end)

--========================================================--
-- HITBOX CONTROL
--========================================================--

local function updateHitboxes()
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            if plr ~= parentPlayer and not immunePlayers[plr] and not assigners[plr.Name] then
                char.HumanoidRootPart.Size = Vector3.new(HITBOX_SIZE, HITBOX_SIZE, HITBOX_SIZE)
            else
                char.HumanoidRootPart.Size = Vector3.new(1, 4, 1)
            end
        end
    end
end

--========================================================--
-- SMOOTH MOVE
--========================================================--

local function smoothMove(hrp, targetPos)
    local dir = targetPos - hrp.Position
    local mag = dir.Magnitude
    if mag < 0.001 then return end
    dir = dir.Unit
    local step = math.min(MOVE_STEP, mag)
    local newPos = hrp.Position + dir * step
    newPos = Vector3.new(newPos.X, targetPos.Y, newPos.Z)
    hrp.CFrame = CFrame.new(newPos)
end

--========================================================--
-- PREDICTION
--========================================================--

local function getPredictedPosition(targetHRP)
    if not PREDICT_ENABLED then
        return targetHRP.Position
    end
    local velocity = targetHRP.Velocity
    return targetHRP.Position + (velocity * PREDICT_FACTOR)
end

--========================================================--
-- DESTROY FUNCTION
--========================================================--

local function getTargetPosition(target)
    if target and target.Character then
        local hrp = target.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            return hrp.Position
        end
    end
    return nil
end

local function destroyTargetPlayer(dt)
    if not destroyTarget then return end
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local pos = getTargetPosition(destroyTarget)
    if not hrp or not pos then return end

    -- Orbit around target
    orbitAngle = orbitAngle + (ORBIT_SPEED * dt)
    local offset = Vector3.new(math.cos(orbitAngle) * ORBIT_RADIUS, FLOAT_HEIGHT, math.sin(orbitAngle) * ORBIT_RADIUS)
    smoothMove(hrp, pos + offset)
end

--========================================================--
-- AUTO M1 / M2 / BLOCK LOOPS
--========================================================--

task.spawn(function()
    while true do
        if m1Active then
            pcall(function()
                ReplicatedStorage.CombatRemote:FireServer("M1")
            end)
        end
        task.wait(COMBAT_COOLDOWN)
    end
end)

task.spawn(function()
    while true do
        if m2Active then
            pcall(function()
                ReplicatedStorage.CombatRemote:FireServer("M2")
            end)
        end
        task.wait(COMBAT_COOLDOWN)
    end
end)

task.spawn(function()
    while true do
        if BLOCK_ENABLED then
            ReplicatedStorage.CombatRemote:FireServer("Block")
            task.wait(0)
            ReplicatedStorage.CombatRemote:FireServer("Block")
        end
        task.wait(0)
    end
end)

--========================================================--
-- VOID DROP EXECUTION SEQUENCE
--========================================================--

local function executeSingleVoidDrop()
    local localChar = player.Character or player.CharacterAdded:Wait()
    local rootPart = localChar:WaitForChild("HumanoidRootPart", 5)
    if not rootPart then return end

    if localChar:FindFirstChild("VoidRunning") then
        localChar.VoidRunning:Destroy()
    end

    local marker = Instance.new("BoolValue")
    marker.Name = "VoidRunning"
    marker.Parent = localChar

    for _, part in ipairs(localChar:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = false
        end
    end

    local fallSpeed = 1000
    local connection

    connection = RunService.RenderStepped:Connect(function(deltaTime)
        if not localChar or not localChar.Parent or not rootPart.Parent or not marker.Parent then
            if connection then connection:Disconnect() end
            return
        end

        localChar:PivotTo(localChar:GetPivot() - Vector3.new(0, fallSpeed * deltaTime, 0))
        rootPart.AssemblyLinearVelocity = Vector3.new(0, -fallSpeed, 0)

        if rootPart.Position.Y < -500 then
            if connection then connection:Disconnect() end
            marker:Destroy()
        end
    end)

    task.wait(0.8)
end

local function runVoidDropSequence()
    for i = 1, 5 do
        executeSingleVoidDrop()
    end
end

-- Unified Recovery / Initiation Sequence Handler with 5s Timer for 100000 Move Step
local function performRecoverySequence(onCompleteCallback)
    if isRecovering then return end
    isRecovering = true

    -- 1. Reset avatar ONE TIME ONLY
    local char = player.Character
    if char and char:FindFirstChild("Humanoid") then
        char.Humanoid.Health = 0
    end

    -- Wait for respawn after reset
    player.CharacterAdded:Wait()

    -- 2. Wait exactly 2.8 seconds
    task.wait(0.7)

    -- 3. Run 5 Void Drop moves with 1 second wait after each
    runVoidDropSequence()

    -- 4. Set MOVE_STEP = 100000 for 5 seconds on resume/start, then revert to 0.33
    MOVE_STEP = 100000
    task.spawn(function()
        task.wait(5)
        MOVE_STEP = 0.3
    end)

    isRecovering = false
    if onCompleteCallback then
        onCompleteCallback()
    end
end

--========================================================--
-- TARGET MONITORING REFERENCES
--========================================================--
local targetDiedConnection = nil
local targetLeavingConnection = nil

local function stopFollowing()
    if followConnection then followConnection:Disconnect() end
    if targetDiedConnection then targetDiedConnection:Disconnect() end
    if targetLeavingConnection then targetLeavingConnection:Disconnect() end
    
    followConnection = nil
    targetDiedConnection = nil
    targetLeavingConnection = nil
    
    attackActiveState = false
    mode = "stop"
    attackTarget = nil
    destroyTarget = nil
    loopKillTargetName = nil
    ORBIT_SPEED = savedOrbitSpeed
end

--========================================================--
-- FOLLOW LOOP
--========================================================--

local lastTick = tick()
local function startFollowing()
    if followConnection then followConnection:Disconnect() end
    attackActiveState = true
    followConnection = RunService.Heartbeat:Connect(function()
        local now = tick()
        local dt = now - lastTick
        lastTick = now

        if panicMode or isRecovering or not attackActiveState then return end
        local char = player.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        updateHitboxes()

        -- DESTROY MODE
        if mode == "destroy" and destroyTarget then
            destroyTargetPlayer(dt)
            task.wait(DESTROY_SPEED)
            return
        end

        -- ATTACK MODE
        if mode == "attack" and attackTarget then
            local tChar = attackTarget.Character
            if tChar and tChar:FindFirstChild("HumanoidRootPart") then
                local predicted = getPredictedPosition(tChar.HumanoidRootPart)
                local pos = predicted + Vector3.new(0, FLOAT_HEIGHT, 0)
                smoothMove(hrp, pos)
            end
            return
        end

        -- IDLE MODE
        if mode == "idle" and parentPlayer.Character then
            local pHRP = parentPlayer.Character:FindFirstChild("HumanoidRootPart")
            if pHRP then
                smoothMove(hrp, pHRP.Position + Vector3.new(0, FLOAT_HEIGHT, 8))
            end
        end
    end)
end

--========================================================--
-- MONITORING HEALTH & ENEMY STATUS DURING ATTACK
--========================================================--

-- Monitor Local Player Health (1-5 HP trigger)
RunService.Heartbeat:Connect(function()
    if not attackActiveState or isRecovering then return end
    local char = player.Character
    if char then
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 and humanoid.Health <= 5 then
            attackActiveState = false -- temporarily pause T21 attack
            performRecoverySequence(function()
                attackActiveState = true -- resume T21 attack
            end)
        end
    end
end)

local function monitorTarget(targetPlr)
    if targetDiedConnection then targetDiedConnection:Disconnect() end
    if targetLeavingConnection then targetLeavingConnection:Disconnect() end

    if not targetPlr then return end

    local function setupCharMon(tChar)
        local humanoid = tChar:FindFirstChildOfClass("Humanoid")
        if humanoid then
            targetDiedConnection = humanoid.Died:Connect(function()
                if attackActiveState and not isRecovering and attackTarget == targetPlr then
                    attackActiveState = false -- temporarily pause T21 attack
                    performRecoverySequence(function()
                        attackActiveState = true -- resume T21 attack
                    end)
                end
            end)
        end
    end

    if targetPlr.Character then
        setupCharMon(targetPlr.Character)
    end
    targetPlr.CharacterAdded:Connect(function(tChar)
        setupCharMon(tChar)
        -- If enemy resets/respawns
        if attackActiveState and not isRecovering and attackTarget == targetPlr then
            attackActiveState = false
            performRecoverySequence(function()
                attackActiveState = true
            end)
        end
    end)

    -- Enemy leaves server behavior
    targetLeavingConnection = Players.PlayerRemoving:Connect(function(leavingPlr)
        if leavingPlr == targetPlr then
            task.delay(0.5, function()
                if not leavingPlr:IsDescendantOf(game) then
                    if attackActiveState and not isRecovering and loopKillTargetName == targetPlr.Name then
                        attackActiveState = false
                        local connectionRejoin
                        connectionRejoin = Players.PlayerAdded:Connect(function(rejoiningPlr)
                            -- Strict check: if stop was called, loopKillTargetName will be nil or mismatch
                            if not loopKillTargetName or loopKillTargetName ~= targetPlr.Name then
                                if connectionRejoin then connectionRejoin:Disconnect() end
                                return
                            end
                            if rejoiningPlr.Name == targetPlr.Name then
                                connectionRejoin:Disconnect()
                                attackTarget = rejoiningPlr
                                performRecoverySequence(function()
                                    attackActiveState = true
                                    monitorTarget(rejoiningPlr)
                                end)
                            end
                        end)
                    end
                end
            end)
        end
    end)
end

--========================================================--
-- COMMAND HANDLER
--========================================================--

local function runCommand(cmd)
    lastCommand = cmd

    if cmd.type == "idle" then
        mode = "idle"
        startFollowing()

    elseif cmd.type == "attack" or cmd.type == "destroy" then
        local target = cmd.target
        if cmd.type == "destroy" then
            savedOrbitSpeed = ORBIT_SPEED
            ORBIT_SPEED = 16
            mode = "destroy"
            destroyTarget = target
        else
            mode = "attack"
            attackTarget = target
            loopKillTargetName = target.Name
        end

        performRecoverySequence(function()
            monitorTarget(target)
            startFollowing()
        end)

    elseif cmd.type == "stop" then
        stopFollowing()

    elseif cmd.type == "height" then
        FLOAT_HEIGHT = cmd.val -- Supports negative numbers (e.g. -5)

    elseif cmd.type == "immune" then
        immunePlayers[cmd.target] = true

    elseif cmd.type == "unimmune" then
        immunePlayers[cmd.target] = nil

    elseif cmd.type == "block" then
        BLOCK_ENABLED = cmd.val

    elseif cmd.type == "reset" then
        if not resetUsed then
            resetUsed = true
            local char = player.Character
            if char and char:FindFirstChild("Humanoid") then
                char.Humanoid.Health = 0
            end
        end

    elseif cmd.type == "predict" then
        PREDICT_ENABLED = cmd.val

    elseif cmd.type == "loopkill" then
        local target = cmd.target
        if target then
            mode = "attack"
            attackTarget = target
            loopKillTargetName = target.Name
            performRecoverySequence(function()
                monitorTarget(target)
                startFollowing()
            end)
        end

    elseif cmd.type == "unloopkill" then
        stopFollowing()
    end
end

--========================================================--
-- CHAT LISTENER
--========================================================--

local function onChat(plr, msg)
    local m = msg:lower()

    if assigners[plr.Name] then
        local t = m:match("^t21%s+(.-)%s+controll$")
        if t then
            local found = findPlayerByFuzzy(t)
            if found then
                parentPlayer = found
            end
            return
        end
    end

    if plr ~= parentPlayer then return end

    if m == "t21 idle" then runCommand({type = "idle"}) end
    if m == "t21 stop" then runCommand({type = "stop"}) end

    local a = m:match("^t21 attack%s+(.+)$")
    if a then
        local found = findPlayerByFuzzy(a)
        if found then 
            task.spawn(function()
                runCommand({type = "attack", target = found})
            end)
        end
    end

    -- Adjusted pattern to allow negative numbers (e.g., t21 height -5)
    local h = m:match("^t21 height%s+([%-%d]+)$")
    if h then runCommand({type = "height", val = tonumber(h)}) end

    local im = m:match("^t21 immune%s+(.+)$")
    if im then
        local found = findPlayerByFuzzy(im)
        if found then runCommand({type = "immune", target = found}) end
    end

    local uim = m:match("^t21 unimmune%s+(.+)$")
    if uim then
        local found = findPlayerByFuzzy(uim)
        if found then runCommand({type = "unimmune", target = found}) end
    end

    if m == "t21 block on" then runCommand({type = "block", val = true}) end
    if m == "t21 block off" then runCommand({type = "block", val = false}) end

    -- M1 / M2 Commands
    if m == "t21 m1 on" then m1Active = true end
    if m == "t21 m1 off" then m1Active = false end
    if m == "t21 m2 on" then m2Active = true end
    if m == "t21 m2 off" then m2Active = false end

    if m == "t21 reset" then
        resetUsed = false
        runCommand({type = "reset"})
    end

    if m == "t21 predict on" then runCommand({type = "predict", val = true}) end
    if m == "t21 predict off" then runCommand({type = "predict", val = false}) end

    local lk = m:match("^t21 loopkill%s+(.+)$")
    if lk then
        local found = findPlayerByFuzzy(lk)
        if found then runCommand({type = "loopkill", target = found}) end
    end
    if m == "t21 unloopkill" then runCommand({type = "unloopkill"}) end

    local d = m:match("^t21 destroy%s+(.+)$")
    if d then
        local found = findPlayerByFuzzy(d)
        if found then 
            task.spawn(function()
                runCommand({type = "destroy", val = true, target = found})
            end)
        end
    end

    local dr = m:match("^t21 destroyradius%s+(%d+)$")
    if dr then
        DESTROY_RADIUS = tonumber(dr)
    end

    local ds = m:match("^t21 destroyspeed%s+(%d+)$")
    if ds then
        DESTROY_SPEED = tonumber(ds) / 100
    end

    if m == "t21 destroy off" then
        stopFollowing()
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    p.Chatted:Connect(function(msg) onChat(p, msg) end)
end
Players.PlayerAdded:Connect(function(p)
    p.Chatted:Connect(function(msg) onChat(p, msg) end)
end)

--========================================================--
-- LOOPKILL AUTO-RETARGET ON JOIN
--========================================================--

Players.PlayerAdded:Connect(function(p)
    if loopKillTargetName and p.Name == loopKillTargetName then
        attackTarget = p
        mode = "attack"
        performRecoverySequence(function()
            monitorTarget(p)
            startFollowing()
        end)
    end
end)

--========================================================--
-- RESPAWN HANDLER
--========================================================--

player.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    if lastCommand and lastCommand.type ~= "attack" and lastCommand.type ~= "destroy" and lastCommand.type ~= "stop" then 
        runCommand(lastCommand) 
    end
    if loopKillTargetName and not attackActiveState then
        local target = findPlayerByFuzzy(loopKillTargetName)
        if target then
            mode = "attack"
            attackTarget = target
            performRecoverySequence(function()
                monitorTarget(target)
                startFollowing()
            end)
        end
    end
end)
