-- Main services

local Players         = game:GetService("Players")

local RunService      = game:GetService("RunService")

local TweenService    = game:GetService("TweenService")

local UserInputService = game:GetService("UserInputService")

local Workspace       = game:GetService("Workspace")



local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then return end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")



-- ============================================================

-- CLEANUP OLD COPIES

-- ============================================================

local possibleParents = { playerGui }

pcall(function() table.insert(possibleParents, game:GetService("CoreGui")) end)

pcall(function()

    if type(gethui) == "function" then

        local h = gethui()

        if h then table.insert(possibleParents, h) end

    end

end)

local oldNames = {

    "BlehHubFlowerSnowOnly","BlehHubGamesMenuFlowerSnow","BlehHubGUIOnly",

    "BlehHubAppearanceOnly","BlehHubAppearanceOnlyFixed","ACECodeSniperUI","BlehHubAimbot",

}

for _, root in ipairs(possibleParents) do

    pcall(function()

        for _, name in ipairs(oldNames) do

            local old = root:FindFirstChild(name)

            if old then old:Destroy() end

        end

    end)

end



-- ============================================================

-- CONFIG

-- ============================================================

local Config = {

    aimLockEnabled     = false,

    aimLockTargetType  = "Zombie",

    aimLockMaxDistance = 700,

    aimLockSmoothness  = 1,

    aimLockMode        = "Always Lock",

    aimLockPart        = "Torso",

}



-- ============================================================

-- STATE

-- ============================================================

local State = {

    playerRoles         = {},

    connection15        = nil,

    stateField52        = nil,

    stateField13        = nil,

    stateField108       = 0,

    stateField15        = false,

    _zombieCacheReady   = false,

    _hookedMobButtons   = {},

    _hookedSlasherButtons = {},

    scpEspObjects       = {},

}



-- ============================================================

-- UPDATE TASK RUNNER (lightweight port)

-- ============================================================

local UpdateTasks = {}

local function RegisterUpdateTask(name, interval, fn)

    UpdateTasks[#UpdateTasks + 1] = { name = name, interval = interval, timer = 0, fn = fn }

end

RunService.Heartbeat:Connect(function(dt)

    for i = 1, #UpdateTasks do

        local t = UpdateTasks[i]

        t.timer = t.timer + dt

        if t.timer >= t.interval then

            t.timer = 0

            pcall(t.fn, dt)

        end

    end

end)



-- ============================================================

-- PLAYER ROLE

-- ============================================================

local function GetPlayerRole(player)

    return State.playerRoles[player] or "survivor"

end

local function UpdatePlayerRole(player)

    local ok, teamName = pcall(function()

        return player.Team and player.Team.Name:lower() or ""

    end)

    State.playerRoles[player] = (ok and teamName:find("killer")) and "killer" or "survivor"

end

for _, p in ipairs(Players:GetPlayers()) do UpdatePlayerRole(p) end

Players.PlayerAdded:Connect(UpdatePlayerRole)

Players.PlayerRemoving:Connect(function(p) State.playerRoles[p] = nil end)



-- ============================================================

-- ZOMBIE / SCP CACHE

-- ============================================================

local recoveredValue189 = {}

local zombieCacheTime   = 0



local function IsZombieName(name)

    if type(name) ~= "string" or name == "" then return false end

    local low = name:lower()

    if low:find("zombie") then return true end

    if low == "scp" then return true end

    for i = 1, 9 do

        if low == ("scp" .. i) or low:find("^scp%-" .. i) then return true end

    end

    return false

end



function GetScpModelRoot(model)

    local root = model.PrimaryPart

    if not root then root = model:FindFirstChild("HumanoidRootPart") end

    if not root then

        for _, c in ipairs(model:GetChildren()) do

            if c:IsA("BasePart") then root = c; break end

        end

    end

    return root

end



local zombieCache = {}

local function InitZombieCache()

    if State._zombieCacheReady then return end

    State._zombieCacheReady = true



    local function addModel(m)

        if not m:IsA("Model") then return end

        if LocalPlayer.Character and m == LocalPlayer.Character then return end

        for _, p in ipairs(Players:GetPlayers()) do

            if p.Character and m == p.Character then return end

        end

        if not IsZombieName(m.Name) then return end

        if zombieCache[m] then return end

        zombieCache[m] = true

        table.insert(recoveredValue189, m)

    end



    local function removeModel(m)

        if not zombieCache[m] then return end

        zombieCache[m] = nil

        for i, v in ipairs(recoveredValue189) do

            if v == m then table.remove(recoveredValue189, i); break end

        end

    end



    Workspace.DescendantAdded:Connect(addModel)

    Workspace.DescendantRemoving:Connect(removeModel)



    local charSet = {}

    for _, p in ipairs(Players:GetPlayers()) do

        if p.Character then charSet[p.Character] = true end

    end

    for _, d in ipairs(Workspace:GetDescendants()) do

        if d:IsA("Model") and not charSet[d] and IsZombieName(d.Name) then

            zombieCache[d] = true

            table.insert(recoveredValue189, d)

        end

    end

    zombieCacheTime = tick()

end



function RefreshZombieCache()

    InitZombieCache()

    zombieCacheTime = tick()

end



pcall(InitZombieCache)



-- ============================================================

-- HOLD-TO-LOCK INPUT WIRING  (RMB / Touch / Gamepad L2)

-- ============================================================

do

    local function hitTestCircle(frame, pos)

        if not frame or not frame.Parent then return false end

        local ap = frame.AbsolutePosition

        local as = frame.AbsoluteSize

        local cx = ap.X + as.X / 2

        local cy = ap.Y + as.Y / 2

        local r  = math.min(as.X, as.Y) / 2 * 0.8

        local dx = pos.X - cx

        local dy = pos.Y - cy

        return (dx*dx + dy*dy) <= (r*r)

    end



    local mobButtonNames = {

        ["Slasher-mob"]=true,["Masked-mob"]=true,["Hidden-mob"]=true,["Killer-mob"]=true,

    }



    local function hookMobButton(btn)

        if State._hookedMobButtons[btn] then return end

        State._hookedMobButtons[btn] = true

        UserInputService.InputBegan:Connect(function(input)

            if input.UserInputType ~= Enum.UserInputType.Touch then return end

            if not hitTestCircle(btn, input.Position) then return end

            State.stateField15 = true

            local conn

            conn = UserInputService.InputEnded:Connect(function(ended)

                if ended == input then

                    State.stateField15 = false

                    conn:Disconnect()

                end

            end)

        end)

    end



    local function isAttackButton(obj)

        if not (obj and obj:IsA("GuiButton")) then return false end

        if obj.Name ~= "attack" then return false end

        local hasMob, hasCtrl = false, false

        local cur = obj.Parent

        while cur do

            if mobButtonNames[cur.Name] then hasMob = true end

            if cur.Name == "Controls" or cur.Name == "Control" then hasCtrl = true end

            cur = cur.Parent

        end

        return hasMob and hasCtrl

    end



    local function hookSlasherButton(btn)

        if State._hookedSlasherButtons[btn] then return end

        State._hookedSlasherButtons[btn] = true

        btn.InputBegan:Connect(function(input)

            if input.UserInputType == Enum.UserInputType.Touch

            or input.UserInputType == Enum.UserInputType.MouseButton1 then

                State.stateField15 = true

            end

        end)

        btn.InputEnded:Connect(function(input)

            if input.UserInputType == Enum.UserInputType.Touch

            or input.UserInputType == Enum.UserInputType.MouseButton1 then

                State.stateField15 = false

            end

        end)

    end



    local function scanGui(parent)

        local function recurse(p)

            local mobGui = p:FindFirstChild("Gui-mob", true)

            if mobGui and mobGui:IsA("ImageButton") then hookMobButton(mobGui) end

            local ctrl = p:FindFirstChild("Control") or p:FindFirstChild("Controls")

            if ctrl then

                local function scanCtrl(c)

                    for _, ch in ipairs(c:GetChildren()) do

                        if isAttackButton(ch) then hookSlasherButton(ch) end

                        scanCtrl(ch)

                    end

                end

                scanCtrl(ctrl)

            end

        end

        for name in pairs(mobButtonNames) do

            local child = parent:FindFirstChild(name)

            if child then recurse(child) end

        end

        parent.DescendantAdded:Connect(function(d)

            if d:IsA("ImageButton") and d.Name == "Gui-mob" then hookMobButton(d) end

            if isAttackButton(d) then hookSlasherButton(d) end

        end)

    end



    task.spawn(function()

        local pg = LocalPlayer:WaitForChild("PlayerGui")

        scanGui(pg)

    end)



    UserInputService.InputBegan:Connect(function(input, gpe)

        local isKiller = GetPlayerRole(LocalPlayer) == "killer"

        if isKiller then

            if input.UserInputType == Enum.UserInputType.MouseButton1 then State.stateField15 = true end

        else

            if not gpe and input.UserInputType == Enum.UserInputType.MouseButton2 then State.stateField15 = true end

        end

        if not gpe and input.UserInputType == Enum.UserInputType.Gamepad1

        and input.KeyCode == Enum.KeyCode.ButtonL2 then State.stateField15 = true end

    end)



    UserInputService.InputEnded:Connect(function(input)

        if input.UserInputType == Enum.UserInputType.MouseButton1

        or input.UserInputType == Enum.UserInputType.MouseButton2 then

            State.stateField15 = false

        end

        if input.UserInputType == Enum.UserInputType.Gamepad1

        and input.KeyCode == Enum.KeyCode.ButtonL2 then State.stateField15 = false end

    end)



    RegisterUpdateTask("HoldLock", 0.2, function()

        if not Config.aimLockEnabled then return end

        if State.stateField15 then return end

        local char = LocalPlayer.Character

        if char and char:GetAttribute("Aiming") == true then

            State.stateField15 = true

        end

    end)

end



-- ============================================================

-- AIM LOCK ENGINE (full port from VD)

-- ============================================================

local StartCameraLock, StopCameralock

do

    local function GetAimPos(char)

        if not char then return nil end

        if Config.aimLockPart == "Head" then

            local head = char:FindFirstChild("Head")

            if head then return head.Position end

        end

        local ut = char:FindFirstChild("UpperTorso")

        if ut then return ut.Position end

        local t  = char:FindFirstChild("Torso")

        if t then return t.Position end

        local hrp = char:FindFirstChild("HumanoidRootPart")

        if hrp then

            return hrp.Position + (Config.aimLockPart == "Head" and Vector3.new(0,2.5,0) or Vector3.new(0,1.2,0))

        end

        return nil

    end



    local function IsValidTarget(player, char, humanoid)

        if not char or not humanoid or humanoid.Health <= 0 then return false end

        if humanoid.Health < 50 then return false end

        if char:GetAttribute("IsHooked")    then return false end

        if char:GetAttribute("IsCarried")   then return false end

        if player:GetAttribute("IsHooked")  then return false end

        if player:GetAttribute("IsCarried") then return false end

        local st = humanoid:GetState()

        if st == Enum.HumanoidStateType.PlatformStanding then return false end

        if st == Enum.HumanoidStateType.Physics and humanoid.PlatformStand then return false end

        local hrp = char:FindFirstChild("HumanoidRootPart")

        if hrp and hrp.Anchored then return false end

        return true

    end



    local function FindTarget(currentTarget)

        local myChar = LocalPlayer.Character

        local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")

        if not myHRP then return nil end

        local myPos  = myHRP.Position

        local best   = nil

        local bestD  = Config.aimLockMaxDistance



        -- Zombie mode

        if Config.aimLockTargetType == "Zombie" then

            if currentTarget and typeof(currentTarget) == "Instance" and not currentTarget:IsA("Player") then

                local root = GetScpModelRoot(currentTarget)

                if root and root:IsA("BasePart") and currentTarget.Parent then

                    local d = (root.Position - myPos).Magnitude

                    if d <= Config.aimLockMaxDistance then best = currentTarget; bestD = d - 0.1 end

                end

            end

            if tick() - zombieCacheTime > 0.5 then RefreshZombieCache() end

            for _, m in ipairs(recoveredValue189) do

                if m and m.Parent then

                    local root = GetScpModelRoot(m)

                    if root and root:IsA("BasePart") then

                        local d = (root.Position - myPos).Magnitude

                        if d < bestD then bestD = d; best = m end

                    end

                end

            end

            return best

        end



        -- Player modes (Survivor / Killer)

        if currentTarget and currentTarget.Character then

            local char = currentTarget.Character

            local hum  = char:FindFirstChildOfClass("Humanoid")

            local pos  = GetAimPos(char)

            local validRole = true

            if Config.aimLockTargetType == "Killer"   and GetPlayerRole(currentTarget) ~= "killer"   then validRole = false end

            if Config.aimLockTargetType == "Survivor" and GetPlayerRole(currentTarget) ~= "survivor" then validRole = false end

            if validRole and IsValidTarget(currentTarget, char, hum) and pos then

                local d = (pos - myPos).Magnitude

                if d <= Config.aimLockMaxDistance then best = currentTarget; bestD = d - 0.1 end

            end

        end



        for _, p in ipairs(Players:GetPlayers()) do

            if p == LocalPlayer then continue end

            local char = p.Character

            if not char then continue end

            local hum  = char:FindFirstChildOfClass("Humanoid")

            if not IsValidTarget(p, char, hum) then continue end

            local pos  = GetAimPos(char)

            if not pos then continue end

            local role = GetPlayerRole(p)

            if Config.aimLockTargetType == "Killer"   and role ~= "killer"   then continue end

            if Config.aimLockTargetType == "Survivor" and role ~= "survivor" then continue end

            local d = (pos - myPos).Magnitude

            if d < bestD then bestD = d; best = p end

        end

        return best

    end



    function StartCameraLock()

        if State.connection15 then State.connection15:Disconnect() end

        State.stateField52  = nil

        State.stateField108 = 0

        State.stateField13  = nil



        State.connection15 = RunService.RenderStepped:Connect(function(dt)

            if not Config.aimLockEnabled then return end

            if Config.aimLockMode == "Hold to Lock" and not State.stateField15 then

                State.stateField52 = nil; State.stateField13 = nil; return

            end



            local myChar = LocalPlayer.Character

            if not myChar then return end

            local myHRP = myChar:FindFirstChild("HumanoidRootPart")

            if not myHRP then return end



            State.stateField108 = State.stateField108 + dt

            if State.stateField108 >= 0.15 then

                State.stateField108 = 0

                State.stateField52  = FindTarget(State.stateField52)

            end



            local target = State.stateField52

            if not target then State.stateField13 = nil; return end



            local targetPos

            if typeof(target) == "Instance" and not target:IsA("Player") then

                local root = GetScpModelRoot(target)

                if not root or not root:IsA("BasePart") or not target.Parent then

                    State.stateField52 = nil; State.stateField13 = nil; return

                end

                targetPos = root.Position

            else

                local char = target.Character

                if not char then State.stateField52 = nil; State.stateField13 = nil; return end

                local hum = char:FindFirstChildOfClass("Humanoid")

                if not IsValidTarget(target, char, hum) then

                    State.stateField52 = nil; State.stateField13 = nil; return

                end

                targetPos = GetAimPos(char)

            end

            if not targetPos then State.stateField52 = nil; State.stateField13 = nil; return end



            local cam     = Workspace.CurrentCamera

            if not cam then return end

            local camCF   = cam.CFrame

            local camPos  = camCF.Position

            local lookVec = camCF.LookVector

            local smooth  = Config.aimLockSmoothness

            local toTarget = targetPos - camPos

            local dist     = toTarget.Magnitude

            local toMe     = (targetPos - myHRP.Position).Magnitude

            local MIN_DIST = 4.0



            local aimDir

            if dist >= MIN_DIST and toMe >= 1.5 then

                aimDir = toTarget.Unit

                State.stateField13 = aimDir

            elseif State.stateField13 then

                aimDir = State.stateField13

            else

                aimDir = lookVec

            end



            local lerped = lookVec:Lerp(aimDir, smooth)

            if lerped.Magnitude < 0.001 then return end

            cam.CFrame = CFrame.new(camPos, camPos + lerped)



            -- body rotation when not auto-rotating

            local hum = myChar:FindFirstChildOfClass("Humanoid")

            if hum and not hum.AutoRotate then

                local fwd   = cam.CFrame.LookVector

                local flat  = Vector3.new(fwd.X, 0, fwd.Z)

                if flat.Magnitude > 0.001 then

                    local curA = math.atan2(myHRP.CFrame.LookVector.X, myHRP.CFrame.LookVector.Z)

                    local newA = math.atan2(flat.X, flat.Z)

                    local dA   = ((newA - curA + math.pi) % (2 * math.pi)) - math.pi

                    local blendA = curA + dA * 0.15

                    local sx, sz = math.sin(blendA), math.cos(blendA)

                    local target2 = myHRP.Position + Vector3.new(sx, 0, sz) * 900

                    myHRP.CFrame = CFrame.new(myHRP.Position, Vector3.new(target2.X, myHRP.Position.Y, target2.Z))

                end

            end

        end)

    end



    function StopCameralock()

        if State.connection15 then State.connection15:Disconnect(); State.connection15 = nil end

        State.stateField52 = nil; State.stateField13 = nil

    end

end



-- ============================================================

-- CROSSHAIR ENGINE

-- ============================================================

local CROSSHAIR_STYLES = { "Dot", "Circle", "Circle + Dot", "Plus", "Cross (X)", "T-Shape", "Square" }

local CrosshairState   = {

    enabled=false, style="Dot", size=20, opacity=1, offsetX=0, offsetY=0, drawings={},

}



local function ClearCrosshair()

    for _, d in ipairs(CrosshairState.drawings) do pcall(function() d:Remove() end) end

    CrosshairState.drawings = {}

end



local function DrawCrosshair()

    ClearCrosshair()

    if not CrosshairState.enabled then return end

    local cam = Workspace.CurrentCamera

    if not cam then return end

    local vp  = cam.ViewportSize

    local cx  = vp.X / 2 + CrosshairState.offsetX

    local cy  = vp.Y / 2 + CrosshairState.offsetY

    local s   = CrosshairState.size

    local t   = 1 - CrosshairState.opacity

    local col = Color3.new(1,1,1)

    local sty = CrosshairState.style

    local half = s / 2

    local gap  = math.max(2, s * 0.15)



    local function dot(x, y, r)

        local c = Drawing.new("Circle")

        c.Position=Vector2.new(x,y); c.Radius=r; c.Color=col

        c.Filled=true; c.Thickness=1; c.Transparency=t; c.Visible=true

        table.insert(CrosshairState.drawings, c)

    end

    local function line(x1,y1,x2,y2,th)

        local l = Drawing.new("Line")

        l.From=Vector2.new(x1,y1); l.To=Vector2.new(x2,y2)

        l.Color=col; l.Thickness=th or 1.5; l.Transparency=t; l.Visible=true

        table.insert(CrosshairState.drawings, l)

    end



    if     sty == "Dot"          then dot(cx,cy,math.max(2,s*0.12))

    elseif sty == "Circle"       then

        local c=Drawing.new("Circle"); c.Position=Vector2.new(cx,cy); c.Radius=half

        c.Color=col; c.Filled=false; c.Thickness=1.5; c.Transparency=t; c.Visible=true

        table.insert(CrosshairState.drawings,c)

    elseif sty == "Circle + Dot" then

        dot(cx,cy,math.max(2,s*0.1))

        local c=Drawing.new("Circle"); c.Position=Vector2.new(cx,cy); c.Radius=half

        c.Color=col; c.Filled=false; c.Thickness=1.5; c.Transparency=t; c.Visible=true

        table.insert(CrosshairState.drawings,c)

    elseif sty == "Plus"         then

        line(cx,cy-half,cx,cy-gap); line(cx,cy+gap,cx,cy+half)

        line(cx-half,cy,cx-gap,cy); line(cx+gap,cy,cx+half,cy)

    elseif sty == "Cross (X)"    then

        line(cx-half,cy-half,cx-gap,cy-gap); line(cx+gap,cy+gap,cx+half,cy+half)

        line(cx+half,cy-half,cx+gap,cy-gap); line(cx-gap,cy+gap,cx-half,cy+half)

    elseif sty == "T-Shape"      then

        line(cx-half,cy,cx+half,cy); line(cx,cy,cx,cy+half)

    elseif sty == "Square"       then

        local sq=Drawing.new("Square"); sq.Position=Vector2.new(cx-half,cy-half)

        sq.Size=Vector2.new(s,s); sq.Color=col; sq.Filled=false

        sq.Thickness=1.5; sq.Transparency=t; sq.Visible=true

        table.insert(CrosshairState.drawings,sq)

    end

end



Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(DrawCrosshair)



local Crosshair = {}

function Crosshair:SetEnabled(v) CrosshairState.enabled=v; DrawCrosshair() end

function Crosshair:SetStyle(v)   CrosshairState.style=v;   DrawCrosshair() end

function Crosshair:SetSize(v)    CrosshairState.size=v;    DrawCrosshair() end

function Crosshair:SetOpacity(v) CrosshairState.opacity=v; DrawCrosshair() end

function Crosshair:SetOffsetX(v) CrosshairState.offsetX=v; DrawCrosshair() end

function Crosshair:SetOffsetY(v) CrosshairState.offsetY=v; DrawCrosshair() end


-- ============================================================
-- KILLER BACKEND PORTED FROM Bleh Hub
-- Kept in its own scope so the main Bleh Hub aimbot's locals/UI
-- are not overwritten by the source script's Config/State tables.
-- ============================================================
local function CreateKillerRuntime()
local __BlehHubBootProbe = { last = "BOOT" }
function __BlehHubBootProbe:Set(stage)
    self.last = tostring(stage or "BOOT")
end
function __BlehHubBootProbe:Finish()
    self.last = "FULL UI LOADED"
end
__BlehHubBootProbe:Set("RUNTIME ENTERED")

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser       = game:GetService("VirtualUser")
local GuiService          = game:GetService("GuiService")
local Lighting             = game:GetService("Lighting")
local Stats                = game:GetService("Stats")
local Workspace             = game:GetService("Workspace")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local function FindRemoteEvent(root, remoteName)
    if not root then return nil end
    local candidate = root:FindFirstChild(remoteName, true)
    if candidate and candidate:IsA("RemoteEvent") then
        return candidate
    end
    return nil
end
local HttpService        = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local DEFAULT_AIM_ANGLE  = math.rad(30)
local MAX_LOCK_ANGLE  = math.rad(45)
local PITCH_COMPENSATION_ANGLE  = math.rad(42)
local MIN_PITCH_ANGLE  = math.rad(28)
local PITCH_BIAS_ANGLE  = math.rad(18)
local MAX_PITCH_ANGLE  = math.rad(72)
local MIN_VERTICAL_DOT = -0.95
local MAX_VERTICAL_DOT =  0.95
local DEFAULT_GRAVITY = Workspace.Gravity

local TOF_BULLET_SPEED  = 200    -- Configurable projectile-speed estimate.
local TOF_BASE_LAG      = 0.065  -- Additional latency compensation.
local TOF_VEL_LERP      = 0.20   -- Target-velocity smoothing factor.

local TARGET_SNAP_DISTANCE        = (2.0)
local TARGET_STABILITY_DISTANCE   = 1.5
local DEFAULT_PREDICTION_STEP         = 0.15
local LOCK_GRACE_FRAMES      = (3.0)

local VERSION = "V1"
local NotifyColor = Color3.fromRGB(150, 88, 255)
local function Notify(labelOrTitle, content, delay)
    local title = tostring(labelOrTitle or "Bleh Hub")
    local text = tostring(content or "")
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = tonumber(delay) or 2,
        })
    end)
end


__BlehHubBootProbe:Set("KEY SYSTEM REMOVED")

local Config = {
    killerEspShowName=false, killerEspShowOutline=true, killerEspOutlineOnly=true,
    killerEspColor=Color3.fromRGB(255,93,108),
    survivorEspShowName=false, survivorEspShowOutline=true, survivorEspOutlineOnly=true,
    survivorEspColor=Color3.fromRGB(64,224,255),
    maxDistance=500, killerEspDistance=500, survivorEspDistance=500, fillTransparency=0.6,
    scpEspEnabled=false, scpEspShowName=true, scpEspDistance=500,
    scpEspColor=Color3.fromRGB(200,60,255),
    maxCameraZoomEnabled=false, cameraZoomValue=1000,
    smoothCameraEnabled=false, cameraStiffness=5.0,
    stretchedResolutionEnabled=false, stretchedResolutionRatio=((16.0)/9),
    killerWarningEnabled=false, warnDist1=60, warnDist2=40, warnDist3=20,
    fovValue=(70.0), lockFovEnabled=false,
    autoGeneratorEnabled=true, autoGeneratorMode="Instant",
    showGenBoostButton=false,
    aimLockEnabled=false, aimLockTargetType="Zombie",
    aimLockMaxDistance=700, aimLockSmoothness=1, aimLockMode="Always Lock",
    aimLockPart="Torso",
    hitboxModifierEnabled=false, survivorHitboxPercent=100, killerHitboxPercent=100,
    hitboxEspEnabled=false, hitboxSurvivorColor=Color3.fromRGB((0.0),(255.0),120),
    hitboxKillerColor=Color3.fromRGB((255.0),60,60), hitboxFillTransparency=0.5, hitboxEspOutlineOnly=false,
    generatorEspEnabled=false, generatorProgressEnabled=false, generatorEspColor=Color3.fromRGB(150,0,200),
    windowEspEnabled = false, windowEspColor = Color3.fromRGB(74,255,181),
    palletEspEnabled=false, palletEspColor=Color3.fromRGB(74,255,181),
    hookEspEnabled=false, hookEspColor=Color3.fromRGB(132,255,169),
    gateEspEnabled=false, gateEspColor=Color3.fromRGB(255,255,255),
    cameraAssistEnabled=false, cameraAssistSnaplineEnabled=false, cameraAssistMaxDistance=175,
    cameraAssistSmoothness=1, cameraAssistSpearSpeed=220, cameraAssistGravityMult=0.5,
    cameraAssistTargetType="Survivor",
    skipEndScreen=false,
    skipLoadingAndEndScreen=false,
    silentAimFovRadius = 150,
    silentAimTargetType = "Killer",
    silentAimAutoPrediction = true,
    silentAimAdaptiveDamping = true,
    spearFovRadius = (150.0),
    spearAutoPrediction = true,
    spearAntiStrafing = true,

    spearPingLead = 1.0,
    spearSnaplineMaxDistance = 400,
    spearShowNameAndDistance = true,
    autoCrouchEnabled=false, autoCrouchRadius=18,
    antiFlashlightBlind = false,
    showEquippedItem=false,
    forceMouseCursor = false,
    moonwalkEnabled = false,
    moonwalkMode = "Classic",
    moonwalkSwayWidth = 0.55,
    moonwalkSwaySpeed = 6,
    infiniteLungeEnabled = false,
    alwaysFastVault = false,
    forceFlowstatePerk = false,
    flowstateCooldown = 15,
    hideFlowstateUi = false,
    killerPerksInfoEnabled = false,
    showHookCounter = false,
    stateField58 = false,
}

local State = {
    espObjects     = {},
    outlineObjects = {},
    playerRoles    = {},
    playerTeamConns = {},
    playerCharConns = {},
    worldEspObjects = { Generators={}, Pallets={}, Hooks={}, Gates={} },
    palletMetadata = {},
    hookParts = {},
    completedGenerators = {},
    worldEspConnections = {},
    stateField106 = 1,
    cachedCharacter=nil, cachedHumanoid=nil,
    worldEspReady = false,
    movementConnections = {},
    noSlowdownEnabled=false, SpeedBoost=false, speedBoostMultiplier=0.3, countSpeedPerks=true, antiFallSlowEnabled=false, safeModeSpeed=true, safeNoSlowdownEnabled=true, pauseSpeedWhenCrouching=false,
    movementSlowUntil=0, scpEspObjects={},
    autoParryEnabled    = false,
    parryRadiusEspEnabled  = false,
    parryRadius     = 13,
    stateField107       = 0,
    stateField4     = {},
    parryAimStrictness       = -0.2,
    stateField46  = (0.0),
    stateField21      = {},
    stateField93 = {},
    killerCharacters = {},
    stateField15=false,
    stateField12=false, humanoid4=nil,
    hitboxOriginalSizes = {},
    hitboxEspObjects = {},
    stateField69 = false,
    stateField48 = (0.0),
    stateField7 = (0.0),
    stateField75 = false,
    distanceValue4 = nil,
    stateField101 = nil,
    cursorBackupIcon = nil,
    cursorBackupBehavior = nil,
    connection2 = nil,
    connection14 = nil,
    stateField50 = nil,
    stateField114 = nil,
    stateField8 = nil,
    stateField110 = false,
    stateField63 = {},
    pnameNameConns = {},
    pnameSlotConns = {},
    connection7 = nil,
    connection11 = nil,
    stateField = nil,
    stateField80 = nil,
    stateField65 = nil,
    stateField23 = false,
    avatarUiSlotConns = {},
    stateField2 = nil,
    stateField62 = nil,
    stateField26 = false,
    stateField91 = nil, stateField64 = false, stateField83 = false, stateField33 = false,
    stateField25 = nil, stateField28 = nil, cameraValue6 = nil, cameraValue5 = nil,
    stateField78 = nil, stateField17 = nil,
    cameraAssistFrameCounter = 0, stateField55 = (-99.0), stateField19 = false, stateField6 = (-99.0),
    stateField96 = nil, stateField18 = -99, stateField51 = nil, stateField94 = nil,
    stateField77 = nil, stateField72 = nil,
    cameraAssistConnections = {}, cameraAssistInputBegan = nil, cameraAssistInputEnded = nil, connection16 = nil,
    stateField99 = nil, cameraAssistAttackButtons = {}, CV_RenderStepName = "BlehHub_CameraAssist",
    skipEndScreenConns = {},
    fullbrightEnabled = false,
    removeVisualEffectsEnabled = false,
    silentAimEnabled     = false,
    stateField79      = nil,
    vectorValue44  = nil,
    vectorValue65   = Vector3.new(0,0,0),
    vectorValue52 = Vector3.new(0,(0.0),(0.0)),
    stateField74     = {},
    stateField87   = nil,
    stateField30 = nil,
    stateField43    = nil,
    silentAimLaserEspEnabled      = true,
    stateField88         = false,
    stateField9     = nil,
    stateField112     = nil,
    frame6            = nil,
    silentAimFovCircleEnabled  = false,
    silentSpearEnabled = false,
    stateField42 = nil,
    vectorValue64 = Vector3.new(0,0,0),
    stateField109 = nil,
    spearAimIndicatorEnabled = false,
    silentSpearFovCircleEnabled = false,
    timeValue18 = false,
    timeValue17 = nil,
    spearSpeedEstimate = 142.5,
    spearGravityMultiplier = 0.5,
    distanceValue57 = 1.0,
    SPEAR_SNAPLINE = {
        enabled = false, stateField34 = false, stateField57 = nil, distanceValue48 = "",
        distanceValue46 = math.huge, lockPulse = 0,
    },
    frame11 = nil,
    stateField39 = nil, textLabel5 = nil, textLabel6 = nil, frame3 = nil, frame5 = nil,
    screenGui2 = nil, frame2 = nil, frame7 = nil, textLabel2 = nil,
    crouchingForced=false,
    autoCrouchActiveSlashers={},
    autoCrouchAnimConns={},
    _hookedMobButtons = {},
    _hookedSlasherButtons = {},
    stateField100 = 0,
    stateField89 = 0,
    stateField41 = false,
    ghostGateLegitMode = false,
    movConns = { antiFall = nil, noSlow = nil },
    originalLungeBoost = nil,
    infiniteLungeRespawnConnection = nil,
    disabledLungeConnections = nil,
    connection15 = nil,
    stateField52 = nil,
    stateField108 = 0,
    stateField13 = nil,
    ghostGateOriginals = {},
    antiLoopWindowEnabled = false,
    stateField60 = nil,
    stateField36 = nil,
    stateField10 = false,
    stateField97 = "Unknown",
    stateField14 = nil,
    connection18 = nil,
    autoDropNearbyPallet = false,
    nearbyPallets = nil,
    timeValue7 = 0,
    stateField31 = false,
    moonwalkSwayPhase = 0,
    moonwalkForwardLocked = false,
    moonwalkBackwardLocked = false,
    moonwalkGui = nil,

    stateField24 = 0,
    stateField111 = 1,
    timeValue2 = 0,
    fastVaultPoints = {},
    fastVaultLastScan = 0,
    stateField49 = 0,
    stateField3 = 0,

    stateField98 = true,
    stateField35 = {},
    hookCounterAttrConns = {},
    connection24 = nil,
    connection23 = nil,
    connection9 = nil,

    stunTimerEnabled=false,
    warningMaxDistance=(250.0),
    stunTimerBoards={},
    stunTimerForced={},
    stunTimerAnim={},
    stunTimerConns={},
    stateField53=false,
    stunTimerLens={},

    flashlightAimlockEnabled=false,
    flashlightActive=false,
    flashlightAimSmoothness=0.35,

    invisibleEnabled=false,
    invisibleRemoteArgs=nil,
    stateField38=false,
    invisibleCharacterConnection=nil,
    stateField102=0,
    stateField59=0,
    stateField27=0,

    mayersAimlockM2Enabled=false,
    mayersAimlockSmoothness=1.0,
    timeValue8=0,
    connection17=nil,

    mayersNoCooldownEnabled=false,
    mayersAutoStalkEnabled=false,
    stateField16=false,
    mayersMobileConnections={},
    mayersDescendantConnection=nil,
    mayersCharacterAddedConnection=nil,
    hookedMayersButtons={},
    stateField61=nil,


    potatoModeEnabled = false,
    potatoProcessed = {},
    potatoPallets = {},
    stateField81 = {},
    stateField90 = nil,
    stateField56 = (1.0),
    stateField84 = {},
    stateField11 = 1,
    stateField68 = 0,
    stateField37 = {},
    stateField44 = {},
    stateField73 = {},
    stateField86 = {},
    stateField40 = nil,
    stateField67 = nil,
    stateField82 = nil,
    stateField76 = {},

    noclipEnabled=false,
}

__BlehHubBootProbe:Set("STATE READY")

local ItemIconAssets = {
    ["Adrenaline Shot"] = "rbxassetid://135388781922226",
    Bandage = "rbxassetid://97791520639443",
    Flashlight = "rbxassetid://103299939715311",
    Gate = "rbxassetid://131249244284700",
    ["Holy Water"] = "rbxassetid://86130208614143",
    ["Motion Tracker"] = "rbxassetid://92303584765773",
    ["Parrying Dagger"] = "rbxassetid://76822757630703",
    ["Riot Shield"] = "rbxassetid://95718705901699",
    ["Shadow Clone"] = "rbxassetid://134088840518889",
    ["Twist of Fate"] = "rbxassetid://98397448432071",
    ["WaxBound Candle"] = "rbxassetid://110413686590821",
}

local function GetItemIconAssetId(recoveredValue148)
    if not recoveredValue148 or type(recoveredValue148) ~= "string" then return nil end

    recoveredValue148 = recoveredValue148:match("^%s*(.-)%s*$")

    local recoveredValue81 = ItemIconAssets[recoveredValue148]
    if recoveredValue81 then return recoveredValue81 end


    for name, id in pairs(ItemIconAssets) do
        if name:lower() == recoveredValue148:lower() then
            return id
        end
    end
    return nil
end

local BASE_WALK_SPEED = (17.0)
local ProtectedDisplayNames = { "BlehHub" }

__BlehHubBootProbe:Set("CORE HELPERS READY")

local EspFolder = Instance.new("Folder")
EspFolder.Name = "__BlehHubESP__"
EspFolder.Parent = workspace

local function GetEspFolder()
    if EspFolder and EspFolder.Parent then return EspFolder end
    EspFolder = Instance.new("Folder")
    EspFolder.Name = "__BlehHubESP__"
    EspFolder.Parent = workspace
    return EspFolder
end

local UpdateTasks = {}

local function RegisterUpdateTask(name, interval, fn)
    UpdateTasks[#UpdateTasks + (1.0)] = { name=name, interval=interval, timer=0, fn=fn }
end

local NoCooldownEnabled = false
local OriginalTaskDelay

local NoCooldownDelayValues = { [25] = true, [17] = true, [(30.0)] = true, [67.8] = true, [2] = true, [4] = true, [0.25] = true, [70] = true, [0.65] = true }

local MayersCooldownDelayValues = { [(1.0)] = true, [10] = true }

local CachedKillerType, _activeKillerT = nil, 0
local function GetActiveKillerType()
    local timeValue12 = tick()
    if timeValue12 - _activeKillerT < (2.0) and CachedKillerType ~= nil then
        return CachedKillerType
    end
    local recoveredValue222 = nil
    pcall(function()
        local attributeValue17 = LocalPlayer:GetAttribute("SelectedKiller")
        local name = tostring(attributeValue17 or ""):lower()
        if name:find("hidden") then
            recoveredValue222 = "hidden"
        elseif name:find("mayers") or name:find("stalker") or name:find("michael") then
            recoveredValue222 = "mayers"
        end
        if not recoveredValue222 then
            local remote10 = game:GetService("ReplicatedStorage")
            local recoveredValue141 = remote10:FindFirstChild("Remotes") and remote10.Remotes:FindFirstChild("Killers")
            if recoveredValue141 then
                if recoveredValue141:FindFirstChild("Stalker") then recoveredValue222 = "mayers"
                elseif recoveredValue141:FindFirstChild("Hidden") then recoveredValue222 = "hidden"
                end
            end
        end
    end)
    CachedKillerType, _activeKillerT = recoveredValue222, timeValue12
    return recoveredValue222
end

local function InstallNoCooldownHook()
    if OriginalTaskDelay then return end
    if not hookfunction then
        Notify("No Cooldown", "Your executor does not support hookfunction.", 2)
        return
    end
    local success, err = pcall(function()
        local recoveredValue138 = newcclosure or function(frame) return frame end
        OriginalTaskDelay = hookfunction(task.delay, recoveredValue138(function(delayTime, callback)

            if not OriginalTaskDelay then
                return task.delay and task.delay(0, callback) or task.spawn(callback)
            end
            if not NoCooldownEnabled then
                return OriginalTaskDelay(delayTime, callback)
            end
            if NoCooldownDelayValues[delayTime] then
                return OriginalTaskDelay((0.0), callback)
            end


            if MayersCooldownDelayValues[delayTime] and GetActiveKillerType() == "mayers" then
                return OriginalTaskDelay(0, callback)
            end
            return OriginalTaskDelay(delayTime, callback)
        end))
    end)
    if not success then
        Notify("No Cooldown", "Failed to hook task.delay: " .. tostring(err), 2)
        OriginalTaskDelay = nil
    end
end

local function RemoveNoCooldownHook()
    if OriginalTaskDelay then
        if restorefunction then
            pcall(restorefunction, task.delay)
        end
        OriginalTaskDelay = nil
    end
end

local function GetPlayerRole(player)
    return State.playerRoles[player] or "survivor"
end

local function UpdatePlayerRole(player)
    local success, teamName = pcall(function() return player.Team and player.Team.Name:lower() or "" end)
    State.playerRoles[player] = (success and teamName:find("killer")) and "killer" or "survivor"
end

local TriggerMayersGrabAttack, GetNearestSurvivorForMayers, StartMayersMobileHook, StopMayersMobileHook
do
        function GetNearestSurvivorForMayers(maxDist)
            maxDist = maxDist or 5
            local char = LocalPlayer.Character
            local rootPart16 = char and char:FindFirstChild("HumanoidRootPart")
            if not rootPart16 then return nil, math.huge end
            local distanceValue60, distanceValue52 = nil, maxDist + 0.01
            for _, targetPlayer in ipairs(Players:GetPlayers()) do
                if targetPlayer ~= LocalPlayer and targetPlayer.Character then
                    local rootPart7 = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                    local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
                    if rootPart7 and humanoid and humanoid.Health > 0 then
                        local distance = (rootPart7.Position - rootPart16.Position).Magnitude
                        if distance < distanceValue52 then distanceValue60, distanceValue52 = targetPlayer.Character, distance end
                    end
                end
            end
            return distanceValue60, distanceValue52
        end

        function TriggerMayersGrabAttack()
            if not (State.mayersNoCooldownEnabled or NoCooldownEnabled) then return end
            if GetActiveKillerType() ~= "mayers" then return end
            if State.stateField16 then return end
            local char = LocalPlayer.Character
            if not char then return end
            local rootPart16 = char:FindFirstChild("HumanoidRootPart")
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if not (rootPart16 and humanoid and humanoid.Health > (0.0)) then return end
            State.stateField16 = true
            task.delay(0.35, function() State.stateField16 = false end)
            local recoveredValue197 = nil
            pcall(function()
                local animation2 = Instance.new("Animation")
                animation2.AnimationId = "rbxassetid://77477445889320"
                local recoveredValue31 = humanoid:FindFirstChildOfClass("Animator") or humanoid
                recoveredValue197 = recoveredValue31:LoadAnimation(animation2)
                recoveredValue197.Priority = Enum.AnimationPriority.Action
                recoveredValue197:Play()
            end)
            local remote10 = game:GetService("ReplicatedStorage")
            pcall(function() remote10.Remotes.SoundPlayer:FireServer("132736711620405", rootPart16, 0.3, 70) end)
            pcall(function() remote10.Remotes.Attacks.BasicAttack:FireServer(true) end)
            pcall(function()
                local remote2 = remote10:FindFirstChild("Remotes") and remote10.Remotes:FindFirstChild("Killers") and remote10.Remotes.Killers:FindFirstChild("Stalker") and remote10.Remotes.Killers.Stalker:FindFirstChild("ConsumeReady")
                if remote2 then remote2:FireServer() end
            end)
            task.spawn(function()
                local timeValue21 = tick()
                local rootPart9 = false
                while tick() - timeValue21 < 2 and not rootPart9 do
                    RunService.Heartbeat:Wait()
                    local target, dist = GetNearestSurvivorForMayers(5)
                    if target and dist <= (5.0) then
                        pcall(function()
                            local remote29 = remote10.Remotes.Killers.Stalker:FindFirstChild("grab")
                            if remote29 then remote29:FireServer(target) end
                        end)
                        if recoveredValue197 then pcall(function() recoveredValue197:Stop(0.1) end) end
                        rootPart9 = true
                        break
                    end
                end
                if recoveredValue197 then pcall(function() recoveredValue197:Stop(0.1) end) end
            end)
        end

        RegisterUpdateTask("MayersStalkWhileMoving", 0.2, function()
            if not State.mayersAutoStalkEnabled then return end
            pcall(function()
                local remote10 = game:GetService("ReplicatedStorage")
                local recoveredValue264 = remote10:FindFirstChild("Remotes") and remote10.Remotes:FindFirstChild("Killers") and remote10.Remotes.Killers:FindFirstChild("Stalker")
                local remote2 = recoveredValue264 and recoveredValue264:FindFirstChild("StartStalking")
                if not remote2 then return end
                for _, targetPlayer in ipairs(Players:GetPlayers()) do
                    if targetPlayer ~= LocalPlayer and targetPlayer.Character then
                        local humanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
                        if humanoid and humanoid.Health > 0 then
                            pcall(function() remote2:FireServer(targetPlayer) end)
                        end
                    end
                end
            end)
        end)

            State.stateField61 = UserInputService.InputBegan:Connect(function(input, recoveredValue58)
                if recoveredValue58 then return end
                if input.KeyCode ~= Enum.KeyCode.Q then return end
                if not (State.mayersNoCooldownEnabled or NoCooldownEnabled) then return end
                pcall(TriggerMayersGrabAttack)
            end)


        local function HelperFunction218(currentValue)
            if not (currentValue and currentValue:IsA("GuiButton")) then return false end
            if currentValue.Name ~= "move2" then return false end
            local parentObject = currentValue.Parent
            if not (parentObject and parentObject.Name == "Controls") then return false end
            local recoveredValue58 = parentObject.Parent
            if not (recoveredValue58 and recoveredValue58.Name == "Slasher-mob") then return false end
            return true
        end

        local function HelperFunction145(recoveredValue274)
            if not State.mayersNoCooldownEnabled then return end
            if GetActiveKillerType() ~= "mayers" then return end
            if not HelperFunction218(recoveredValue274) then return end
            if State.hookedMayersButtons[recoveredValue274] then return end
            State.hookedMayersButtons[recoveredValue274] = true
            pcall(function() recoveredValue274.Active = true end)
            local function HelperFunction148()
                if not State.mayersNoCooldownEnabled then return end
                pcall(TriggerMayersGrabAttack)
            end


            local connection3 = recoveredValue274.Activated:Connect(HelperFunction148)
            table.insert(State.mayersMobileConnections, connection3)
        end

        local function HelperFunction20()
            if not State.mayersNoCooldownEnabled then return end
            if GetActiveKillerType() ~= "mayers" then return end
            local recoveredValue40 = LocalPlayer:FindFirstChildOfClass("PlayerGui") or PlayerGui
            if not recoveredValue40 then return end
            pcall(function()
                local recoveredValue283 = recoveredValue40:FindFirstChild("Slasher-mob")
                if recoveredValue283 then
                    local recoveredValue118 = recoveredValue283:FindFirstChild("Controls")
                    if recoveredValue118 then
                        local recoveredValue64 = recoveredValue118:FindFirstChild("move2")
                        if recoveredValue64 then HelperFunction145(recoveredValue64) end

                        for _, child in ipairs(recoveredValue118:GetDescendants()) do
                            if child.Name == "move2" then HelperFunction145(child) end
                        end
                    end
                end
            end)

            if State.mayersCharacterAddedConnection then pcall(function() State.mayersCharacterAddedConnection:Disconnect() end) end
            State.mayersCharacterAddedConnection = recoveredValue40.ChildAdded:Connect(function(child)
                if child.Name == "Slasher-mob" then
                    task.wait(0.5)
                    HelperFunction20()

                    if State.mayersDescendantConnection then pcall(function() State.mayersDescendantConnection:Disconnect() end) end
                    State.mayersDescendantConnection = child.DescendantAdded:Connect(function(descendant)
                        if descendant.Name == "move2" then HelperFunction145(descendant) end
                    end)
                    table.insert(State.mayersMobileConnections, State.mayersDescendantConnection)
                end
            end)
            table.insert(State.mayersMobileConnections, State.mayersCharacterAddedConnection)

            pcall(function()
                local recoveredValue283 = recoveredValue40:FindFirstChild("Slasher-mob")
                if recoveredValue283 and not State.mayersDescendantConnection then
                    State.mayersDescendantConnection = recoveredValue283.DescendantAdded:Connect(function(descendant)
                        if descendant.Name == "move2" then HelperFunction145(descendant) end
                    end)
                    table.insert(State.mayersMobileConnections, State.mayersDescendantConnection)
                end
            end)
        end

        function StartMayersMobileHook()
            HelperFunction20()
        end

        function StopMayersMobileHook()
            for _, connection in ipairs(State.mayersMobileConnections) do pcall(function() connection:Disconnect() end) end
            State.mayersMobileConnections = {}
            State.hookedMayersButtons = {}
            if State.mayersCharacterAddedConnection then pcall(function() State.mayersCharacterAddedConnection:Disconnect() end) State.mayersCharacterAddedConnection = nil end
            if State.mayersDescendantConnection then pcall(function() State.mayersDescendantConnection:Disconnect() end) State.mayersDescendantConnection = nil end
        end
end

local function StopInfiniteLunge()
    if State.infiniteLungeRespawnConnection then
        State.infiniteLungeRespawnConnection:Disconnect()
        State.infiniteLungeRespawnConnection = nil
    end


    if State.originalLungeBoost ~= nil then
        local char = LocalPlayer.Character
        if char then
            pcall(function() char:SetAttribute("lungeboost", State.originalLungeBoost) end)
        end
        State.originalLungeBoost = nil
    end


    if State.disabledLungeConnections then
        for index = (1.0), #State.disabledLungeConnections do
            local connection = State.disabledLungeConnections[index]
            if connection then
                pcall(function() connection:Enable() end)
            end
        end
        State.disabledLungeConnections = nil
    end
end

local function StartInfiniteLunge()
    if GetPlayerRole(LocalPlayer) ~= "killer" then return end
    if State.infiniteLungeRespawnConnection then return end

    local char = LocalPlayer.Character


    if char then
        pcall(function()
            State.originalLungeBoost = char:GetAttribute("lungeboost")
            char:SetAttribute("lungeboost", 999999)
        end)
    end


    pcall(function()
        local recoveredValue409 = ReplicatedStorage:FindFirstChild("Remotes")
        local recoveredValue19 = recoveredValue409 and recoveredValue409:FindFirstChild("Attacks")
        local remote19 = recoveredValue19 and recoveredValue19:FindFirstChild("LungeDetect")
        if remote19 and remote19:IsA("RemoteEvent") then
            local connection13 = getconnections(remote19.OnClientEvent)
            local cache16 = {}
            for index = 1, #connection13 do
                local connection = connection13[index]
                pcall(function()
                    connection:Disable()
                    cache16[#cache16 + (1.0)] = connection
                end)
            end
            State.disabledLungeConnections = cache16
        end
    end)


    State.infiniteLungeRespawnConnection = LocalPlayer.CharacterAdded:Connect(function(newChar)
        if not Config.infiniteLungeEnabled then return end
        pcall(function()
            State.originalLungeBoost = newChar:GetAttribute("lungeboost")
            newChar:SetAttribute("lungeboost", 999999)
        end)
    end)
end

local SetAntiAfkEnabled
do
    local cache11 = {}
    local function HelperFunction161(gui)
        if gui.Name == "Blind" then
            cache11[gui] = true
            if gui:IsA("ScreenGui") then
                gui.Enabled = false
            elseif gui:IsA("GuiObject") then
                gui.Visible = false
                gui.BackgroundTransparency = 1
            end
        end
    end

    local recoveredValue297 = false
    local function HelperFunction185()
        if recoveredValue297 then return end
        local success = pcall(function()
            assert(typeof(hookmetamethod) == "function", "hookmetamethod missing")
            assert(typeof(getnamecallmethod) == "function", "getnamecallmethod missing")
            assert(typeof(checkcaller) == "function", "checkcaller missing")
            local recoveredValue262  = ReplicatedStorage:FindFirstChild("Remotes")
            local index  = recoveredValue262 and recoveredValue262:FindFirstChild("Items")
            local recoveredValue347 = index and index:FindFirstChild("Flashlight")
            local remote15 = recoveredValue347 and recoveredValue347:FindFirstChild("GotBlinded")
            if not (remote15 and remote15:IsA("RemoteEvent")) then return end

            local recoveredValue277
            recoveredValue277 = hookmetamethod(game, "__namecall", function(self, ...)
                if not checkcaller()
                    and Config.antiFlashlightBlind
                    and rawequal(self, remote15)
                    and getnamecallmethod() == "FireServer"
                    and GetPlayerRole(LocalPlayer) == "killer"
                then
                    return
                end
                return recoveredValue277(self, ...)
            end)
            recoveredValue297 = true
        end)
        return success
    end
    ((getgenv and getgenv()) or _G).SetupAntiBlindHook = HelperFunction185

    PlayerGui.DescendantAdded:Connect(function(descendant)
        if Config.antiFlashlightBlind then HelperFunction161(descendant) end
    end)


    RegisterUpdateTask("AntiBlindForce", 1.0, function()
        if not Config.antiFlashlightBlind then return end
        HelperFunction185()
        for gui, _ in pairs(cache11) do
            if not gui.Parent then
                cache11[gui] = nil
            else
                HelperFunction161(gui)
            end
        end
    end)


    local antiAfkConnection
    function SetAntiAfkEnabled(attributeValue4)
        if attributeValue4 then
            if not antiAfkConnection then
                antiAfkConnection = LocalPlayer.Idled:Connect(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new())
                end)
            end
        else
            if antiAfkConnection then
                antiAfkConnection:Disconnect()
                antiAfkConnection = nil
            end
        end
    end
end

local UpdateTargetVelocityHistory, Spear_PingSec
do


    local recoveredValue425 = nil
    function Spear_PingSec()
        if recoveredValue425 == nil then
            pcall(function()
                recoveredValue425 = game:GetService("Stats").Network.ServerStatsItem["Data Ping"]
            end)
        end
        local value2 = (0.0)
        if recoveredValue425 ~= nil then
            pcall(function() value2 = recoveredValue425:GetValue() end)
        end
        value2 = tonumber(value2) or 0
        return math.clamp(value2 / 1000, 0, (1.0))
    end
    function UpdateTargetVelocityHistory(vectorValue6, char, posNow)
        local timeValue12 = tick()
        if vectorValue6.char ~= char then
            vectorValue6.char = char
            vectorValue6.hist = {}
            vectorValue6.vectorValue46 = Vector3.new(0, 0, 0)
            vectorValue6.turn = (0.0)
        end
        if vectorValue6.turn == nil then vectorValue6.turn = 0 end
        local hist = vectorValue6.hist
        table.insert(hist, { pos = posNow, t = timeValue12 })
        while #hist > 1 and hist[1].t < timeValue12 - 0.4 do table.remove(hist, 1) end
        if #hist >= 2 then
            local attributeValue12 = hist[#hist - (1.0)]
            local attributeValue22 = hist[#hist]
            local recoveredValue206 = attributeValue22.t - attributeValue12.t
            if recoveredValue206 > 0.001 then
                local vectorValue23 = (attributeValue22.pos - attributeValue12.pos) / recoveredValue206
                local currentValue = Vector3.new(vectorValue23.X, 0, vectorValue23.Z)
                local rootPart2 = char and char:FindFirstChild("HumanoidRootPart")
                if rootPart2 and rootPart2:IsA("BasePart") then
                    local success, av = pcall(function() return rootPart2.AssemblyLinearVelocity end)
                    if success and typeof(av) == "Vector3" then
                        local vectorValue51 = Vector3.new(av.X, 0, av.Z)
                        if vectorValue51.Magnitude > 0.5 and vectorValue51.Magnitude < 100 then
                            currentValue = currentValue:Lerp(vectorValue51, 0.5)
                        end
                    end
                end


                if currentValue.Magnitude > (24.0) then currentValue = currentValue.Unit * 24 end


                local recoveredValue403 = 0
                if vectorValue6.vectorValue46.Magnitude > 2 and currentValue.Magnitude > 2 then
                    local distance = vectorValue6.vectorValue46:Dot(currentValue) / (vectorValue6.vectorValue46.Magnitude * currentValue.Magnitude)
                    if Config.spearAntiStrafing and distance < 0 then currentValue = currentValue * 0.7 end
                    recoveredValue403 = math.clamp((1.0) - distance, 0, (1.0))
                end
                vectorValue6.turn = vectorValue6.turn * 0.7 + recoveredValue403 * 0.3
                vectorValue6.vectorValue46 = vectorValue6.vectorValue46:Lerp(currentValue, 0.45)
            end
        end
        local vectorValue54 = Vector3.new(vectorValue6.vectorValue46.X, 0, vectorValue6.vectorValue46.Z)
        if vectorValue54.Magnitude > 24 then vectorValue54 = vectorValue54.Unit * 24 end
        vectorValue6.vectorValue46 = vectorValue54
        local stab = 1 - math.clamp(vectorValue6.turn, (0.0), (1.0))
        return vectorValue54, stab
    end
end

__BlehHubBootProbe:Set("PRE CAMERA/Assist")

local StartCameraAssist, StopCameraAssist, CV_ScanAttackButtons, CV_ClearLock
do
    local vectorValue5 = { hist = {}, char = nil, vectorValue46 = Vector3.new((0.0), 0, (0.0)) }
    local function HelperFunction131()
        local success, parentObject = pcall(function() if gethui then return gethui() end return game:GetService("CoreGui") end)
        return (success and parentObject) or PlayerGui
    end
    local function HelperFunction22(char)
        if not char then return nil end
        local rootPart19 = char:FindFirstChild("Head")
        if rootPart19 then return rootPart19.Position end
        local rootPart2 = char:FindFirstChild("HumanoidRootPart")
        if rootPart2 then return rootPart2.Position end
        local recoveredValue155 = char:FindFirstChild("UpperTorso")
        if recoveredValue155 then return recoveredValue155.Position end
        local t = char:FindFirstChild("Torso")
        if t then return t.Position end
        return char.PrimaryPart and char.PrimaryPart.Position or nil
    end
    local function HelperFunction6(rootPart)
        if not rootPart then return Vector3.new((0.0), 0, 0) end
        local vel = rootPart.AssemblyLinearVelocity
        local vectorValue20 = Vector3.new(vel.X, (0.0), vel.Z)
        if vectorValue20.Magnitude > (65.0) then vectorValue20 = vectorValue20.Unit * (65.0) end
        return vectorValue20
    end
    local function HelperFunction25()
        local char = LocalPlayer.Character
        local rootPart2 = char and char:FindFirstChild("HumanoidRootPart")
        if not rootPart2 then return nil end
        local camera = Workspace.CurrentCamera
        local vectorValue26 = (camera and camera.CFrame.LookVector) or rootPart2.CFrame.LookVector
        return rootPart2.Position + vectorValue26 * 3 + Vector3.new(0, 1.5, 0)
    end
    local function HelperFunction172(distanceValue6)
        local speed = tonumber(State.stateField78) or tonumber(Config.cameraAssistSpearSpeed) or 220
        return math.clamp(speed, (35.0), 800)
    end
    local function HelperFunction52(distanceValue31, recoveredValue168, speed, distanceValue9)
        local recoveredValue126 = math.cos(recoveredValue168)
        if recoveredValue126 <= 0.015 then return nil, nil end
        local travelTime = distanceValue31 / (speed * recoveredValue126)
        if travelTime ~= travelTime or travelTime <= 0 then return nil, nil end
        local recoveredValue219 = 1 / (60.0)
        local recoveredValue265 = 0.5 * distanceValue9 * recoveredValue219 * travelTime
        local recoveredValue43 = speed * math.sin(recoveredValue168) * travelTime - (0.5 * distanceValue9 * travelTime * travelTime) - recoveredValue265
        return recoveredValue43, travelTime
    end
    local function HelperFunction164(distanceValue31, recoveredValue263, recoveredValue168, speed, distanceValue9)
        local recoveredValue241, travelTime = HelperFunction52(distanceValue31, recoveredValue168, speed, distanceValue9)
        if not recoveredValue241 or not travelTime then return nil end
        if travelTime < 0.025 or travelTime > (4.0) then return nil end
        local recoveredValue82 = math.abs(recoveredValue241 - recoveredValue263)
        local recoveredValue324 = math.max(recoveredValue168 - PITCH_COMPENSATION_ANGLE, (0.0)) * 0.35
        local recoveredValue161 = math.max(travelTime - 1.3, 0) * 0.25
        return recoveredValue82 + recoveredValue324 + recoveredValue161, recoveredValue82, travelTime
    end
    local function HelperFunction42(recoveredValue379, vectorValue9, speed, distanceValue9)
        local vectorValue40 = vectorValue9 - recoveredValue379
        local vectorValue20 = Vector3.new(vectorValue40.X, 0, vectorValue40.Z)
        local distanceValue31 = vectorValue20.Magnitude
        local recoveredValue263 = vectorValue40.Y
        if vectorValue40.Magnitude <= 0.001 then return nil end
        if distanceValue31 <= 0.35 or distanceValue9 <= 0.001 then return vectorValue40.Unit, math.clamp(vectorValue40.Magnitude / speed, 0.025, (4.0)) end
        local vectorValue35 = vectorValue20.Unit
        local recoveredValue176 = math.atan2(recoveredValue263, distanceValue31)
        local recoveredValue98 = math.max(-MIN_PITCH_ANGLE, recoveredValue176 - PITCH_BIAS_ANGLE)
        local recoveredValue397 = MAX_PITCH_ANGLE
        local vectorValue29, bestScore, bestError, bestTime = nil, math.huge, math.huge, nil

        local recoveredValue240 = distanceValue31 > 80
        local recoveredValue359 = recoveredValue240 and 40 or (24.0)
        local recoveredValue140 = recoveredValue240 and 0.08 or DEFAULT_PREDICTION_STEP
        for index = (0.0), recoveredValue359 do
            local recoveredValue168 = recoveredValue98 + (recoveredValue397 - recoveredValue98) * (index / recoveredValue359)
            local recoveredValue151, recoveredValue82, travelTime = HelperFunction164(distanceValue31, recoveredValue263, recoveredValue168, speed, distanceValue9)
            if recoveredValue151 and recoveredValue151 < bestScore then
                bestScore, bestError, vectorValue29, bestTime = recoveredValue151, recoveredValue82, recoveredValue168, travelTime
                if bestError < recoveredValue140 then break end
            end
        end
        if vectorValue29 then
            local recoveredValue46 = (recoveredValue397 - recoveredValue98) / recoveredValue359 * 2.5
            local recoveredValue10 = (bestError < recoveredValue140) and (1.0) or (recoveredValue240 and (5.0) or 3)
            for _ = (1.0), recoveredValue10 do
                local recoveredValue244, localBestScore, localBestError, localBestTime = vectorValue29, bestScore, bestError, bestTime
                for index2 = (-3.0), 3 do
                    local recoveredValue168 = math.clamp(vectorValue29 + recoveredValue46 * (index2 / 3), recoveredValue98, recoveredValue397)
                    local recoveredValue151, recoveredValue82, travelTime = HelperFunction164(distanceValue31, recoveredValue263, recoveredValue168, speed, distanceValue9)
                    if recoveredValue151 and recoveredValue151 < localBestScore then
                        localBestScore, localBestError, recoveredValue244, localBestTime = recoveredValue151, recoveredValue82, recoveredValue168, travelTime
                    end
                end
                vectorValue29, bestScore, bestError, bestTime = recoveredValue244, localBestScore, localBestError, localBestTime
                if bestError < recoveredValue140 then break end
                recoveredValue46 = recoveredValue46 * 0.38
            end
        end
        if not vectorValue29 then
            local recoveredValue50 = math.clamp(distanceValue31 / speed, 0.025, 4)


            local vectorValue68 = math.min(0.5 * distanceValue9 * recoveredValue50 * recoveredValue50, 15)
            local vectorValue37 = vectorValue9 + Vector3.new((0.0), vectorValue68, (0.0))
            local distanceValue44 = vectorValue37 - recoveredValue379
            if distanceValue44.Magnitude <= 0.001 then return nil end
            return distanceValue44.Unit, recoveredValue50
        end
        local vectorValue61 = vectorValue35 * math.cos(vectorValue29) + Vector3.new((0.0), math.sin(vectorValue29), 0)
        if vectorValue61.Magnitude <= 0.001 then return nil end
        return vectorValue61.Unit, bestTime
    end
    local function HelperFunction64(vectorValue9)
        local recoveredValue379 = HelperFunction25()
        if not recoveredValue379 or not vectorValue9 then return nil end
        local speed = HelperFunction172((vectorValue9 - recoveredValue379).Magnitude)
        local recoveredValue193 = math.max(tonumber(State.stateField17) or tonumber(Config.cameraAssistGravityMult) or (1.0), 0)
        local distanceValue9 = DEFAULT_GRAVITY * recoveredValue193
        return HelperFunction42(recoveredValue379, vectorValue9, speed, distanceValue9)
    end
    local function HelperFunction214(recoveredValue305, rootPart3, recoveredValue437)
        if not recoveredValue305 then return nil end
        local recoveredValue379 = HelperFunction25()
        if recoveredValue379 then
            local distanceValue23 = recoveredValue305 - recoveredValue379
            local distanceValue = distanceValue23.Magnitude
            if distanceValue < 6 then
                if distanceValue < 0.001 then return nil end
                local recoveredValue416 = tonumber(State.stateField78) or tonumber(Config.cameraAssistSpearSpeed) or (220.0)
                return distanceValue23.Unit, recoveredValue305, math.clamp(distanceValue / math.max(recoveredValue416, 1), 0.01, 1)
            end
        end
        local recoveredValue281 = State.cameraAssistFrameCounter
        local recoveredValue427 = recoveredValue281 - State.stateField18
        local recoveredValue225 = State.stateField51 and (recoveredValue305 - State.stateField51).Magnitude < TARGET_STABILITY_DISTANCE
        if recoveredValue427 < TARGET_SNAP_DISTANCE and recoveredValue225 and State.stateField94 then
            return State.stateField94, State.stateField77, State.stateField72
        end
        local predictedPos = recoveredValue305
        local distanceValue63, travelTime = HelperFunction64(predictedPos)
        if distanceValue63 and travelTime and rootPart3 and rootPart3.Magnitude > 1.25 then

            local recoveredValue149 = 0.68 + 0.32 * math.clamp(travelTime / 0.6, 0, 1)

            local recoveredValue80 = (recoveredValue379 and recoveredValue305) and (recoveredValue305 - recoveredValue379).Magnitude or 0
            local distanceValue18 = math.max(recoveredValue80 * 0.4, 4)

            local distanceValue62 = Spear_PingSec() * (tonumber(Config.spearPingLead) or 1.0)
            local recoveredValue423 = math.clamp(travelTime * recoveredValue149, 0, 1.1)
            local lead = rootPart3 * ((recoveredValue423 + distanceValue62) * recoveredValue437)
            if lead.Magnitude > 32 then lead = lead.Unit * 32 end
            if lead.Magnitude > distanceValue18 then lead = lead.Unit * distanceValue18 end
            local recoveredValue275 = recoveredValue305 + lead
            local cframeValue18, newTime = HelperFunction64(recoveredValue275)
            if cframeValue18 and newTime then distanceValue63, travelTime, predictedPos = cframeValue18, newTime, recoveredValue275 end

            if cframeValue18 and newTime and newTime > 0.35 then
                local recoveredValue435 = math.clamp(newTime * recoveredValue149, 0, 1.1)
                local distanceValue51 = rootPart3 * ((recoveredValue435 + distanceValue62) * recoveredValue437)
                if distanceValue51.Magnitude > (32.0) then distanceValue51 = distanceValue51.Unit * (32.0) end
                if distanceValue51.Magnitude > distanceValue18 then distanceValue51 = distanceValue51.Unit * distanceValue18 end
                local recoveredValue235 = recoveredValue305 + distanceValue51
                local recoveredValue247, newTime2 = HelperFunction64(recoveredValue235)
                if recoveredValue247 and newTime2 then distanceValue63, travelTime, predictedPos = recoveredValue247, newTime2, recoveredValue235 end
            end
        end
        State.stateField18 = recoveredValue281
        State.stateField51 = recoveredValue305
        State.stateField94 = distanceValue63
        State.stateField77 = predictedPos
        State.stateField72 = travelTime
        return distanceValue63, predictedPos, travelTime
    end
    local HelperFunction177
    local function HelperFunction30()
        local camera = Workspace.CurrentCamera
        if not camera then return nil end
        local cframeValue16, camDir = camera.CFrame.Position, camera.CFrame.LookVector
        local distanceValue17, vectorValue29 = nil, DEFAULT_AIM_ANGLE
        local rootPart22 = LocalPlayer.Character
        local rootPart13 = rootPart22 and rootPart22:FindFirstChild("HumanoidRootPart")
        if not rootPart13 then return nil end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local distanceValue19 = GetPlayerRole(player)
                if distanceValue19 == "survivor" then
                    local char = player.Character
                    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
                    if char and humanoid and humanoid.Health > 0 then
                        local recoveredValue305 = HelperFunction22(char)
                        if recoveredValue305 then
                            local dist = (recoveredValue305 - rootPart13.Position).Magnitude
                            if dist <= Config.cameraAssistMaxDistance then
                                local distanceValue14 = recoveredValue305 - cframeValue16
                                if distanceValue14.Magnitude > 0.001 then
                                    local recoveredValue168 = math.acos(math.clamp(camDir:Dot(distanceValue14.Unit), -1, (1.0)))
                                    if recoveredValue168 < vectorValue29 then vectorValue29 = recoveredValue168; distanceValue17 = player end
                                end
                            end
                        end
                    end
                end
            end
        end
        return distanceValue17
    end
    local function HelperFunction200()
        if State.stateField28 and State.stateField28.Parent and State.cameraValue6 and State.cameraValue6.Parent and State.cameraValue5 and State.cameraValue5.Parent then return end
        local gui = Instance.new("ScreenGui")
        gui.Name = "CameraAssist_SnapLine"
        gui.IgnoreGuiInset = true; gui.ResetOnSpawn = false; gui.Parent = HelperFunction131()
        local frame13 = Instance.new("Frame")
        frame13.Name = "Line"; frame13.AnchorPoint = Vector2.new(0.5, 0.5); frame13.BorderSizePixel = 0
        frame13.BackgroundColor3 = Color3.fromRGB(0, (255.0), 120); frame13.BackgroundTransparency = 0.08
        frame13.Visible = false; frame13.Parent = gui
        local dot = Instance.new("Frame")
        dot.Name = "Dot"; dot.AnchorPoint = Vector2.new(0.5, 0.5); dot.BorderSizePixel = (0.0)
        dot.BackgroundColor3 = Color3.fromRGB(0, 255, 120); dot.BackgroundTransparency = (0.0)
        dot.Size = UDim2.fromOffset(7, 7); dot.Visible = false; dot.Parent = gui
        local recoveredValue115 = Instance.new("UICorner"); recoveredValue115.CornerRadius = UDim.new((1.0), (0.0)); recoveredValue115.Parent = dot
        State.stateField28 = gui; State.cameraValue6 = frame13; State.cameraValue5 = dot
    end
    local function HelperFunction186(vectorValue9)
        if not Config.cameraAssistSnaplineEnabled or not State.stateField26 then
            if State.cameraValue6 then State.cameraValue6.Visible = false end
            if State.cameraValue5 then State.cameraValue5.Visible = false end
            return
        end
        if not HelperFunction177() then
            if State.cameraValue6 then State.cameraValue6.Visible = false end
            if State.cameraValue5 then State.cameraValue5.Visible = false end
            return
        end
        local recoveredValue281 = State.cameraAssistFrameCounter
        if vectorValue9 and (recoveredValue281 - State.stateField55) < (2.0) then return end
        State.stateField55 = recoveredValue281
        local success = pcall(function()
            HelperFunction200()
            local frame13 = State.cameraValue6; local dot = State.cameraValue5; local camera = Workspace.CurrentCamera
            if not frame13 or not camera then if frame13 then frame13.Visible = false end if dot then dot.Visible = false end return end
            local recoveredValue315 = vectorValue9
            local colorValue9 = (State.stateField91 ~= nil and State.stateField64)
            if not colorValue9 then
                local recoveredValue295 = HelperFunction30()
                if recoveredValue295 then
                    local char = recoveredValue295.Character
                    if char then recoveredValue315 = HelperFunction22(char) end
                else recoveredValue315 = nil end
            end
            if not recoveredValue315 then frame13.Visible = false; if dot then dot.Visible = false end return end
            local recoveredValue254, onScreen = camera:WorldToViewportPoint(recoveredValue315)
            if not onScreen or recoveredValue254.Z <= 0 then frame13.Visible = false; if dot then dot.Visible = false end return end
            local cameraValue8 = camera.ViewportSize
            local distanceValue3 = Vector2.new(cameraValue8.X * 0.5, cameraValue8.Y * 0.5)
            local distanceValue34 = Vector2.new(recoveredValue254.X, recoveredValue254.Y)
            local vectorValue40 = distanceValue34 - distanceValue3; local length = vectorValue40.Magnitude
            if length < (2.0) then frame13.Visible = false; if dot then dot.Visible = false end return end
            local colorValue3 = colorValue9 and Color3.fromRGB(0, 255, (120.0)) or Color3.fromRGB(255, 220, (0.0))
            local recoveredValue239 = colorValue9 and 0.08 or 0.35
            frame13.BackgroundColor3 = colorValue3; frame13.BackgroundTransparency = recoveredValue239
            frame13.Size = UDim2.fromOffset(length, colorValue9 and (2.0) or (1.0))
            frame13.Position = UDim2.fromOffset((distanceValue3.X + distanceValue34.X) * 0.5, (distanceValue3.Y + distanceValue34.Y) * 0.5)
            frame13.Rotation = math.deg(math.atan2(vectorValue40.Y, vectorValue40.X)); frame13.Visible = true
            if dot then
                dot.BackgroundColor3 = colorValue3; dot.Position = UDim2.fromOffset(distanceValue34.X, distanceValue34.Y); dot.Visible = true
            end
        end)
        if not success then
            if State.cameraValue6 then State.cameraValue6.Visible = false end
            if State.cameraValue5 then State.cameraValue5.Visible = false end
        end
    end
    function CV_ClearLock()
        State.stateField91 = nil; State.stateField64 = false
        State.stateField25 = nil; State.stateField96 = nil
        HelperFunction186(nil)
    end
    HelperFunction177 = function()
        local recoveredValue281 = State.cameraAssistFrameCounter
        if recoveredValue281 == State.stateField6 then return State.stateField19 end
        State.stateField6 = recoveredValue281
        local char = LocalPlayer.Character
        local recoveredValue248 = false
        if char then
            local success, value2 = pcall(char.GetAttribute, char, "spearmode")
            recoveredValue248 = success and value2 == true
        end
        State.stateField19 = recoveredValue248
        return recoveredValue248
    end
    local function HelperFunction138()
        if not HelperFunction177() then return false end
        return State.stateField83 or State.stateField33
    end
    local function HelperFunction207()
        State.cameraAssistFrameCounter = State.cameraAssistFrameCounter + 1
        if not State.stateField26 then return end
        local recoveredValue284 = HelperFunction138()
        if not recoveredValue284 then
            if State.stateField64 then CV_ClearLock() else HelperFunction186(nil) end
            return
        end
        if not State.stateField64 then
            State.stateField25 = nil
            State.stateField91 = HelperFunction30()
            State.stateField64 = true
            State.stateField96 = State.cameraAssistFrameCounter
        end
        if State.stateField96 and (State.cameraAssistFrameCounter - State.stateField96) < LOCK_GRACE_FRAMES then
            local recoveredValue399 = HelperFunction30()
            if recoveredValue399 then State.stateField91 = recoveredValue399 end
        end
        local target = State.stateField91
        if not target then State.stateField64 = false; return end
        local char = target.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        local distanceValue19 = GetPlayerRole(target)
        if not char or not humanoid or humanoid.Health <= 0 or distanceValue19 ~= "survivor" then
            State.stateField64 = false; State.stateField91 = nil; return
        end
        local recoveredValue305 = HelperFunction22(char)
        if not recoveredValue305 then State.stateField64 = false; State.stateField91 = nil; return end
        local camera = Workspace.CurrentCamera
        local rootPart22 = LocalPlayer.Character
        local rootPart6 = rootPart22 and rootPart22:FindFirstChild("HumanoidRootPart")
        if not camera or not rootPart6 then return end
        if (recoveredValue305 - rootPart6.Position).Magnitude > Config.cameraAssistMaxDistance then
            State.stateField64 = false; State.stateField91 = nil; return
        end
        local rootPart3, stabNow = nil, 1
        if Config.spearAutoPrediction then
            rootPart3, stabNow = UpdateTargetVelocityHistory(vectorValue5, char, recoveredValue305)
        else
            vectorValue5.char, vectorValue5.hist, vectorValue5.vectorValue46 = nil, {}, Vector3.new(0, (0.0), 0)
            vectorValue5.turn = 0
            rootPart3 = HelperFunction6(char:FindFirstChild("HumanoidRootPart"))
        end


        local recoveredValue437 = 1
        if Config.spearAntiStrafing then recoveredValue437 = 0.55 + 0.45 * math.clamp(stabNow or 1, 0, 1) end
        local cframeValue3 = HelperFunction214(recoveredValue305, rootPart3, recoveredValue437)
        local distanceValue45 = cframeValue3 and cframeValue3.Magnitude > 0.001 and cframeValue3.Y < MAX_VERTICAL_DOT and cframeValue3.Y > MIN_VERTICAL_DOT
        if distanceValue45 then
            if State.stateField25 then
                local recoveredValue373 = math.acos(math.clamp(State.stateField25:Dot(cframeValue3.Unit), -1, 1))
                if recoveredValue373 < MAX_LOCK_ANGLE then State.stateField25 = cframeValue3.Unit end
            else
                State.stateField25 = cframeValue3.Unit
            end
            cframeValue3 = State.stateField25
        elseif State.stateField25 then
            cframeValue3 = State.stateField25
        else
            cframeValue3 = camera.CFrame.LookVector
        end
        local cframeValue6 = camera.CFrame.Position
        local cframeValue14 = math.clamp(Config.cameraAssistSmoothness or (1.0), 0.05, 1)
        local cframeValue18 = camera.CFrame.LookVector:Lerp(cframeValue3, cframeValue14)
        if cframeValue18.Magnitude > 0.001 then
            camera.CFrame = CFrame.new(cframeValue6, cframeValue6 + cframeValue18.Unit)
            HelperFunction186(recoveredValue305)
        end
    end
    local function HelperFunction95(currentValue, name)
        local recoveredValue59 = currentValue and currentValue.Parent
        while recoveredValue59 do
            if recoveredValue59.Name == name then return true end
            recoveredValue59 = recoveredValue59.Parent
        end
        return false
    end
    local function HelperFunction13(currentValue)
        if not (currentValue and currentValue:IsA("GuiButton")) then return false end
        if currentValue.Name ~= "attack" then return false end
        if not HelperFunction95(currentValue, "Slasher-mob") then return false end
        if not HelperFunction95(currentValue, "Control") and not HelperFunction95(currentValue, "Controls") then return false end
        return true
    end
    local function HelperFunction202(recoveredValue274)
        if not HelperFunction13(recoveredValue274) then return end
        if State.cameraAssistAttackButtons[recoveredValue274] then return end
        State.cameraAssistAttackButtons[recoveredValue274] = true
        local function HelperFunction83()
            if not State.stateField26 or not HelperFunction177() then return end
            State.stateField33 = true
        end
        local function HelperFunction69() State.stateField33 = false end
        local connection5 = recoveredValue274.InputBegan:Connect(function(input)
            local t = input.UserInputType
            if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
            HelperFunction83()
            local connection12
            connection12 = UserInputService.InputEnded:Connect(function(ended)
                if ended == input then HelperFunction69(); if connection12 then connection12:Disconnect() end end
            end)
        end)
        table.insert(State.cameraAssistConnections, connection5)
        local connection4 = recoveredValue274.InputEnded:Connect(function(input)
            local t = input.UserInputType
            if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
            HelperFunction69()
        end)
        table.insert(State.cameraAssistConnections, connection4)
    end
    function CV_ScanAttackButtons()
        local recoveredValue40 = LocalPlayer:FindFirstChildOfClass("PlayerGui") or PlayerGui
        if not recoveredValue40 then return end
        pcall(function()
            local recoveredValue283 = recoveredValue40:FindFirstChild("Slasher-mob", true)
            if recoveredValue283 then
                local recoveredValue73 = recoveredValue283:FindFirstChild("Control") or recoveredValue283:FindFirstChild("Controls")
                if recoveredValue73 then
                    local function HelperFunction213(parentObject)
                        for _, child in ipairs(parentObject:GetChildren()) do
                            HelperFunction202(child)
                            HelperFunction213(child)
                        end
                    end
                    HelperFunction213(recoveredValue73)
                end
            end
        end)
        if State.connection16 then State.connection16:Disconnect() end
        State.connection16 = recoveredValue40.DescendantAdded:Connect(HelperFunction202)
        table.insert(State.cameraAssistConnections, State.connection16)
    end
    local function HelperFunction55()
        if State.stateField99 then return end
        local success, remote = pcall(function()
            local remote10 = game:GetService("ReplicatedStorage")
            local recoveredValue409 = remote10:FindFirstChild("Remotes")
            local mechanics = recoveredValue409 and recoveredValue409:FindFirstChild("Mechanics")
            return mechanics and mechanics:FindFirstChild("visualize")
        end)
        if success and remote and remote:IsA("RemoteEvent") then
            State.stateField99 = remote.OnClientEvent:Connect(function(ownerChar, spearDir, spearSpeed, gravityMult)
                if ownerChar ~= LocalPlayer.Character then return end

                if type(spearSpeed) == "number" and spearSpeed >= 15 and spearSpeed <= 800 then State.stateField78 = spearSpeed end
                if type(gravityMult) == "number" and gravityMult > 0.2 and gravityMult <= 5 then State.stateField17 = gravityMult end
            end)
            table.insert(State.cameraAssistConnections, State.stateField99)
        end
    end
    function StartCameraAssist()
        if State.stateField26 then return end
        State.stateField26 = true
        State.stateField83 = false; State.stateField33 = false
        CV_ClearLock(); HelperFunction55(); CV_ScanAttackButtons()
        State.cameraAssistInputBegan = UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton2 and HelperFunction177() then State.stateField83 = true end
        end)
        table.insert(State.cameraAssistConnections, State.cameraAssistInputBegan)
        State.cameraAssistInputEnded = UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton2 then State.stateField83 = false end
        end)
        table.insert(State.cameraAssistConnections, State.cameraAssistInputEnded)
        pcall(function() RunService:UnbindFromRenderStep(State.CV_RenderStepName) end)
        pcall(function() RunService:BindToRenderStep(State.CV_RenderStepName, Enum.RenderPriority.Camera.Value + (2.0), HelperFunction207) end)
    end
    function StopCameraAssist()

        State.stateField78 = nil; State.stateField17 = nil
        State.stateField26 = false
        State.stateField83 = false; State.stateField33 = false
        CV_ClearLock()
        State.cameraAssistFrameCounter = 0; State.stateField55 = -99; State.stateField6 = (-99.0); State.stateField19 = false
        State.stateField18 = -99; State.stateField51 = nil; State.stateField94 = nil
        State.stateField77 = nil; State.stateField72 = nil
        pcall(function() RunService:UnbindFromRenderStep(State.CV_RenderStepName) end)
        for _, connection in ipairs(State.cameraAssistConnections) do pcall(function() connection:Disconnect() end) end
        State.cameraAssistConnections = {}; State.cameraAssistAttackButtons = {}
        State.cameraAssistInputBegan = nil; State.cameraAssistInputEnded = nil; State.connection16 = nil; State.stateField99 = nil
    end
end

local HelperFunction191
local HelperFunction2
local HelperFunction125
local RefreshPlayerESP, ForceRefreshAllESP, GetCamPosition, AttachESPToChar, RemovePlayerESP, AttachOutlineToChar, ValidateAndReattachESP, CreateBillboardTag
do
    function CreateBillboardTag(text, color, size, colorValue13)
        local billboardGui = Instance.new("BillboardGui")
        billboardGui.AlwaysOnTop = true; billboardGui.Size = size or UDim2.new(0, (40.0), 0, (40.0)); billboardGui.StudsOffset = Vector3.new(0, 3.5, 0)
        local textLabel = Instance.new("TextLabel")
        textLabel.Name = "Label"; textLabel.Size = UDim2.new(1, 0, 1, 0); textLabel.BackgroundTransparency = 1
        textLabel.Text = text; textLabel.TextColor3 = color; textLabel.TextStrokeTransparency = 0
        textLabel.TextStrokeColor3 = Color3.new(0, (0.0), 0); textLabel.TextSize = colorValue13 or 22
        textLabel.Font = Enum.Font.GothamBold; textLabel.RichText = true; textLabel.Parent = billboardGui
        return billboardGui
    end

    local function GetEspMaxDistance(isKiller)
        return isKiller and Config.killerEspDistance or Config.survivorEspDistance
    end

    local PLAYER_ESP_COLORS = {
        Killer = Color3.fromRGB(255,93,108),
        Survivor = Color3.fromRGB(64,224,255),
        Injured = Color3.fromRGB(200,200,0),
        Knocked = Color3.fromRGB(200,100,0),
        Hooked = Color3.fromRGB(255,182,193),
    }

    local function ReadPlayerEspState(char, name)
        if not char then return nil end
        local ok, attr = pcall(char.GetAttribute, char, name)
        if ok and attr ~= nil then return attr end
        local child = char:FindFirstChild(name)
        if child and child:IsA("ValueBase") then
            local okValue, value = pcall(function() return child.Value end)
            if okValue then return value end
        end
        return nil
    end

    local function GetLegacyPlayerEspVisual(player)
        local role = GetPlayerRole(player)
        local isKiller = role == "killer"
        local char = player and player.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        local color = isKiller and PLAYER_ESP_COLORS.Killer or PLAYER_ESP_COLORS.Survivor

        if char then
            local isHooked = ReadPlayerEspState(char, "IsHooked") == true
                or ReadPlayerEspState(char, "Hooked") == true
            local isKnocked = ReadPlayerEspState(char, "Knocked") == true

            if isHooked then
                color = PLAYER_ESP_COLORS.Hooked
            elseif humanoid and humanoid.MaxHealth > 0 and humanoid.Health < humanoid.MaxHealth then
                color = isKnocked and PLAYER_ESP_COLORS.Knocked or PLAYER_ESP_COLORS.Injured
            end
        end

        return color, isKiller
    end

    local function GetLegacyPlayerEspText(player, rootPart, isKiller)
        local displayName = State.stateField110 and (State.stateField63[player] or player.Name) or player.Name
        if isKiller then
            local selected = player:GetAttribute("SelectedKiller")
            if selected ~= nil and tostring(selected) ~= "" then
                displayName = tostring(selected)
            end
        end

        local distance = 0
        local myChar = LocalPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if myRoot and rootPart then
            distance = math.floor((rootPart.Position - myRoot.Position).Magnitude + 0.5)
        end
        return tostring(displayName) .. "\n[" .. tostring(distance) .. " studs]"
    end

    local function ApplyLegacyPlayerEspVisual(player)
        if not player or player == LocalPlayer then return end
        local char = player.Character
        if not char then return end
        local rootPart = char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Head")
        if not rootPart then return end

        local color, isKiller = GetLegacyPlayerEspVisual(player)
        local espEntry = State.espObjects[player]
        local outline = State.outlineObjects[player]
        local maxDistance = GetEspMaxDistance(isKiller)
        local withinDistance = true
        local camera = workspace.CurrentCamera
        if camera then
            withinDistance = (rootPart.Position - camera.CFrame.Position).Magnitude <= maxDistance
        end

        local showName = withinDistance and ((isKiller and Config.killerEspShowName)
            or ((not isKiller) and Config.survivorEspShowName))
        local showOutline = withinDistance and ((isKiller and Config.killerEspShowOutline)
            or ((not isKiller) and Config.survivorEspShowOutline))

        if espEntry and espEntry.nameLabel then
            espEntry.nameLabel.Text = GetLegacyPlayerEspText(player, rootPart, isKiller)
            espEntry.nameLabel.TextColor3 = color
            espEntry.nameLabel.Visible = showName
            if espEntry.billboard then
                espEntry.billboard.Enabled = showName
                espEntry.billboard.MaxDistance = maxDistance
            end
        end

        if outline then
            outline.Adornee = char
            outline.FillColor = color
            outline.OutlineColor = color
            outline.FillTransparency = 0.8
            outline.OutlineTransparency = 0.3
            outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            outline.Enabled = showOutline
        end
    end

    function RefreshPlayerESP()
        for player, _ in pairs(State.espObjects) do
            ApplyLegacyPlayerEspVisual(player)
            local espEntry = State.espObjects[player]
            if espEntry and espEntry.billboard then
                local _, isKiller = GetLegacyPlayerEspVisual(player)
                espEntry.billboard.MaxDistance = GetEspMaxDistance(isKiller)
                if espEntry.itemBillboard then
                    espEntry.itemBillboard.MaxDistance = GetEspMaxDistance(isKiller)
                end
            end
        end
        for player, _ in pairs(State.outlineObjects) do
            if not State.espObjects[player] then
                ApplyLegacyPlayerEspVisual(player)
            end
        end
        HelperFunction125()
    end

    local function RemoveAllEspForPlayer(player)
        if player == LocalPlayer or not player or not player.Parent then return end
        local recoveredValue385 = State.espObjects[player]
        if recoveredValue385 then
            if recoveredValue385.billboard and recoveredValue385.billboard.Parent then recoveredValue385.billboard:Destroy() end
            if recoveredValue385.itemBillboard and recoveredValue385.itemBillboard.Parent then recoveredValue385.itemBillboard:Destroy() end
        end
        local recoveredValue104 = State.outlineObjects[player]
        if recoveredValue104 and recoveredValue104.Parent then recoveredValue104:Destroy() end
        State.espObjects[player] = nil
        State.outlineObjects[player] = nil
        HelperFunction191(player)
        HelperFunction2(player)
    end

    function ForceRefreshAllESP()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then RemoveAllEspForPlayer(player) end
        end
    end

    function GetCamPosition()
        local camera = workspace.CurrentCamera
        if camera then return camera.CFrame.Position end
        return nil
    end

    HelperFunction125 = function()
        local cframeValue16 = GetCamPosition()
        if not cframeValue16 then return end
        for player, espEntry in pairs(State.espObjects) do
            if player and player.Parent then
                local char = player.Character
                local rootPart2 = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso") or char:FindFirstChild("Head"))
                if rootPart2 then
                    ApplyLegacyPlayerEspVisual(player)
                    local dist = (rootPart2.Position - cframeValue16).Magnitude
                    local isKiller = GetPlayerRole(player) == "killer"
                    local distanceValue27 = GetEspMaxDistance(isKiller)
                    local distanceValue36 = dist <= distanceValue27

                    local outline = State.outlineObjects[player]
                    if outline then
                        local recoveredValue269 = (isKiller and Config.killerEspShowOutline) or (not isKiller and Config.survivorEspShowOutline)
                        local recoveredValue387 = recoveredValue269 and distanceValue36
                        if outline.Enabled ~= recoveredValue387 then outline.Enabled = recoveredValue387 end
                    end
                    if espEntry then
                        if espEntry.billboard then
                            local recoveredValue268 = (isKiller and Config.killerEspShowName) or (not isKiller and Config.survivorEspShowName)
                            local recoveredValue431 = distanceValue36 and recoveredValue268
                            if espEntry.billboard.Enabled ~= recoveredValue431 then espEntry.billboard.Enabled = recoveredValue431 end
                            espEntry.billboard.MaxDistance = distanceValue27
                        end
                        if espEntry.itemBillboard and Config.showEquippedItem then
                            if espEntry.itemBillboard.Enabled ~= distanceValue36 then espEntry.itemBillboard.Enabled = distanceValue36 end
                        end
                    end
                end
            end
        end
    end

    function AttachESPToChar(player, char)
        local espEntry = State.espObjects[player]
        if not espEntry then return end
        if not char or not char.Parent or player.Character ~= char then return end

        local rootPart2 = char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Head")

        if not rootPart2 then
            task.spawn(function()
                local success, waitedRoot = pcall(function() return char:WaitForChild("HumanoidRootPart", 3) end)
                if success and waitedRoot and waitedRoot["	7rent"] and char.Parent and player.Character == char then
                    if espEntry.billboard then
                        espEntry.billboard.Adornee = waitedRoot
                        espEntry.billboard.Enabled = true
                    end
                    if espEntry.itemBillboard then
                        espEntry.itemBillboard.Adornee = waitedRoot
                        espEntry.itemBillboard.Enabled = true
                    end
                end
            end)
            return
        end

        if espEntry.billboard then
            espEntry.billboard.Adornee = rootPart2
            espEntry.billboard.Enabled = true
        end
        if espEntry.itemBillboard then
            espEntry.itemBillboard.Adornee = rootPart2
            espEntry.itemBillboard.Enabled = true
        end

        ApplyLegacyPlayerEspVisual(player)
    end

    function RemovePlayerESP(player)
        if State.espObjects[player] then

            if State.espObjects[player].billboard then
                State.espObjects[player].billboard.Destroy(State.espObjects[player].billboard)
            end

            if State.espObjects[player].itemBillboard then
                State.espObjects[player].itemBillboard.Destroy(State.espObjects[player].itemBillboard)
            end
            State.espObjects[player] = nil
        end
        if State.outlineObjects[player] then
            State.outlineObjects[player].Destroy(State.outlineObjects[player]); State.outlineObjects[player] = nil
        end
        State.playerRoles[player] = nil
        if State.playerTeamConns[player] then
            State.playerTeamConns[player].Disconnect(State.playerTeamConns[player]); State.playerTeamConns[player] = nil
        end
    end

    function AttachOutlineToChar(player, char)
        local outline = State.outlineObjects[player]
        if not outline then return end
        if not char or not char.Parent or player.Character ~= char then return end

        outline.Adornee = char
        outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        ApplyLegacyPlayerEspVisual(player)
    end

    function ValidateAndReattachESP(player)
        if player == LocalPlayer then return end
        if not player or not player.Parent then return end

        local espEntry = State.espObjects[player]
        local outline = State.outlineObjects[player]
        if not espEntry and not outline then return end


        if (espEntry and espEntry.billboard and not espEntry.billboard.Parent) or (outline and not outline.Parent) then
            RemoveAllEspForPlayer(player)
            return
        end

        local char = player.Character
        if not char or not char.Parent then
            if espEntry and espEntry.billboard then espEntry.billboard.Adornee = nil end
            if espEntry and espEntry.itemBillboard then espEntry.itemBillboard.Adornee = nil end
            if outline then outline.Adornee = nil; outline.Enabled = false end
            return
        end

        local rootPart2 = char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Head")
        if not rootPart2 then return end


        local cframeValue16 = GetCamPosition()
        local distanceValue36 = true
        if cframeValue16 then
            local dist = (rootPart2.Position - cframeValue16).Magnitude
            local distanceValue21 = GetPlayerRole(player) == "killer"
            distanceValue36 = dist <= GetEspMaxDistance(distanceValue21)
        end
        local recoveredValue129 = GetPlayerRole(player) == "killer"
        local recoveredValue253 = (recoveredValue129 and Config.killerEspShowName) or (not recoveredValue129 and Config.survivorEspShowName)
        local recoveredValue432 = (recoveredValue129 and Config.killerEspShowOutline) or (not recoveredValue129 and Config.survivorEspShowOutline)


        if espEntry and espEntry.billboard then
            if espEntry.billboard.Adornee ~= rootPart2 then espEntry.billboard.Adornee = rootPart2 end
            local recoveredValue431 = distanceValue36 and recoveredValue253
            if espEntry.billboard.Enabled ~= recoveredValue431 then espEntry.billboard.Enabled = recoveredValue431 end
        end
        if espEntry and espEntry.itemBillboard then
            if espEntry.itemBillboard.Adornee ~= rootPart2 then espEntry.itemBillboard.Adornee = rootPart2 end
            if espEntry.itemBillboard.Enabled ~= distanceValue36 then espEntry.itemBillboard.Enabled = distanceValue36 end
        end

        if outline then
            if outline.Adornee ~= char then
                AttachOutlineToChar(player, char)
            else
                local recoveredValue259 = distanceValue36 and recoveredValue432
                if outline.Enabled ~= recoveredValue259 then outline.Enabled = recoveredValue259 end
            end
        end
        ApplyLegacyPlayerEspVisual(player)
    end

    HelperFunction191 = function(player)
        if player == LocalPlayer then return end
        UpdatePlayerRole(player)
        local distanceValue19 = GetPlayerRole(player)


        local billboard = Instance.new("BillboardGui")
        billboard.Name = "ESP_BB_" .. player.Name; billboard.AlwaysOnTop = true
        billboard.Size = UDim2.new(0, 150, 0, 36)
        billboard.StudsOffset = Vector3.new((0.0), 3.5, 0)
        billboard.MaxDistance = GetEspMaxDistance(distanceValue19 == "killer"); billboard.Parent = GetEspFolder()

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "NameLabel"; nameLabel.Size = UDim2.new((1.0), 0, (1.0), 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Color3.fromRGB((255.0), 255, 255); nameLabel.TextStrokeTransparency = (0.0)
        nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0); nameLabel.TextSize = (12.0)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = State.stateField110 and (State.stateField63[player] or player.Name) or player.Name
        nameLabel.Visible = (distanceValue19 == "killer" and Config.killerEspShowName) or (distanceValue19 ~= "killer" and Config.survivorEspShowName)
        nameLabel.Parent = billboard


        local itemBillboard = Instance.new("BillboardGui")
        itemBillboard.Name = "ESP_Item_" .. player.Name
        itemBillboard.AlwaysOnTop = true


        itemBillboard.Size = UDim2.new(1.5, 0, 1.5, 0)

        itemBillboard.StudsOffset = Vector3.new(0, (-5.0), 0)
        itemBillboard.MaxDistance = GetEspMaxDistance(distanceValue19 == "killer")
        itemBillboard.Parent = GetEspFolder()

        local itemImage = Instance.new("ImageLabel")
        itemImage.Name = "ItemImage"
        itemImage.Size = UDim2.new(1, 0, 1, (0.0))
        itemImage.BackgroundTransparency = 1
        itemImage.Visible = false
        itemImage.Parent = itemBillboard


        State.espObjects[player] = {
            billboard = billboard,
            nameLabel = nameLabel,
            itemBillboard = itemBillboard,
            itemImage = itemImage
        }

        if player.Character then AttachESPToChar(player, player.Character) end
        if not State.playerTeamConns[player] then
            State.playerTeamConns[player] = player:GetPropertyChangedSignal("Team"):Connect(function()
                UpdatePlayerRole(player)
                RefreshPlayerESP()

                task.delay(0.5, function() ValidateAndReattachESP(player) end)
                task.delay(2, function() ValidateAndReattachESP(player) end)
            end)
        end
    end

    HelperFunction2 = function(player)
        if player == LocalPlayer then return end
        local outline = Instance.new("Highlight"); outline.Parent = GetEspFolder()
        State.outlineObjects[player] = outline
        if player.Character then AttachOutlineToChar(player, player.Character) end
    end
end

local RefreshWorldESP, ApplyAntiLoopWindow, DisableAntiLoopWindow, DropAllPallets, ApplyGhostGateToObj
do
    local function GetInstanceNumericValue(instance, name)
        if typeof(instance) ~= "Instance" then return nil end
        local attributeValue17 = instance:GetAttribute(name)
        if attributeValue17 ~= nil then return attributeValue17 end
        local child = instance:FindFirstChild(name)
        if child and child:IsA("ValueBase") then return child.Value end
        return nil
    end

    local function ApplyHighlight(object, color)
        if not object or not object.Parent then return end
        local highlight2 = object:FindFirstChild("__BlehHubHL__")
        if not highlight2 then
            highlight2 = Instance.new("Highlight"); highlight2.Name = "__BlehHubHL__"; highlight2.Adornee = object
            highlight2.FillTransparency = 1; highlight2.OutlineTransparency = (0.0); highlight2.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight2.FillColor = color; highlight2.OutlineColor = color; highlight2.Parent = object; return
        end
        if highlight2.FillColor ~= color then highlight2.FillColor = color; highlight2.OutlineColor = color end
        if not highlight2.Enabled then highlight2.Enabled = true end
    end

    local function RemoveHighlight(object)
        if not object then return end
        local highlight2 = object:FindFirstChild("__BlehHubHL__")
        if highlight2 then highlight2:Destroy() end
    end

    local function IsGeneratorComplete(generator)
        if not generator or not generator.Parent then return true end
        if State.completedGenerators[generator] then return true end

        local attributeValue = generator:GetAttribute("RepairProgress") or generator:GetAttribute("Progress") or 0
        local attributeValue26 = (attributeValue >= 100)
            or (generator:GetAttribute("Completed") == true)
            or (generator:GetAttribute("IsCompleted") == true)
            or (generator:GetAttribute("Done") == true)

        local billboard = generator:FindFirstChild("__BlehHubGenProgress__")

        if attributeValue26 then
            if billboard then billboard:Destroy() end
            RemoveHighlight(generator)
            generator:SetAttribute("__BlehHubGenLastPct__", nil)
            State.completedGenerators[generator] = true
            State.worldEspConnections[generator] = nil
            return true
        end

        if Config.generatorEspEnabled then
            ApplyHighlight(generator, Color3.fromRGB(150, 0, 200))
        else
            RemoveHighlight(generator)
        end

        if Config.generatorProgressEnabled then
            local attributeValue30 = math.clamp(math.floor(attributeValue + 0.5), 0, 100)
            local attributeValue29 = generator:GetAttribute("__BlehHubGenLastPct__")
            local recoveredValue190 = State.worldEspConnections[generator] or 1

            local recoveredValue299 = generator:FindFirstChild("GeneratorBody", true)
                or generator:FindFirstChild("defaultMaterial", true)
                or (generator:IsA("Model") and generator.PrimaryPart)
                or generator:FindFirstChildWhichIsA("BasePart", true)

            if not recoveredValue299 then return false end

            if not billboard then
                billboard = Instance.new("BillboardGui")
                billboard.Name = "__BlehHubGenProgress__"
                billboard.Adornee = recoveredValue299
                billboard.AlwaysOnTop = true
                billboard.LightInfluence = 0
                billboard.ResetOnSpawn = false
                billboard.MaxDistance = 260
                billboard.Size = UDim2.fromOffset(122, 36)

                local vectorValue15 = (recoveredValue299.Size.Y / 2) + 3.8
                billboard.StudsOffset = Vector3.new(0, vectorValue15, 0)
                billboard.Parent = generator

                local title = Instance.new("TextLabel")
                title.Name = "Title"
                title.BackgroundTransparency = 1
                title.Size = UDim2.new(1, 0, 0, 16)
                title.Position = UDim2.fromOffset(0, 0)
                title.Font = Enum.Font.GothamBlack
                title.TextSize = 11
                title.TextColor3 = Color3.fromRGB(245, 245, 245)
                title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                title.TextStrokeTransparency = 0.15
                title.TextXAlignment = Enum.TextXAlignment.Center
                title.Parent = billboard

                local bar = Instance.new("Frame")
                bar.Name = "Bar"
                bar.Size = UDim2.new(1, -10, 0, 13)
                bar.Position = UDim2.new(0, 5, 0, 19)
                bar.BackgroundColor3 = Color3.fromRGB(20, 25, 28)
                bar.BackgroundTransparency = 0.08
                bar.BorderSizePixel = 0
                bar.ClipsDescendants = true
                bar.Parent = billboard

                local barCorner = Instance.new("UICorner")
                barCorner.CornerRadius = UDim.new(0, 3)
                barCorner.Parent = bar

                local barStroke = Instance.new("UIStroke")
                barStroke.Name = "Border"
                barStroke.Thickness = 1
                barStroke.Transparency = 0.15
                barStroke.Color = Color3.fromRGB(112, 128, 118)
                barStroke.Parent = bar

                local fill = Instance.new("Frame")
                fill.Name = "Fill"
                fill.Size = UDim2.new(0, 0, 1, 0)
                fill.BackgroundColor3 = Color3.fromRGB(55, 220, 105)
                fill.BorderSizePixel = 0
                fill.Parent = bar

                local fillCorner = Instance.new("UICorner")
                fillCorner.CornerRadius = UDim.new(0, 3)
                fillCorner.Parent = fill

                local percent = Instance.new("TextLabel")
                percent.Name = "Percent"
                percent.BackgroundTransparency = 1
                percent.Size = UDim2.new(1, 0, 1, 0)
                percent.Position = UDim2.fromOffset(0, 0)
                percent.Font = Enum.Font.GothamBold
                percent.TextSize = 9
                percent.TextColor3 = Color3.fromRGB(255, 255, 255)
                percent.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                percent.TextStrokeTransparency = 0.25
                percent.TextXAlignment = Enum.TextXAlignment.Center
                percent.ZIndex = 3
                percent.Parent = bar
            else
                if billboard.Adornee ~= recoveredValue299 then
                    billboard.Adornee = recoveredValue299
                end
                local vectorValue15 = (recoveredValue299.Size.Y / 2) + 3.8
                billboard.StudsOffset = Vector3.new(0, vectorValue15, 0)
            end

            local title = billboard:FindFirstChild("Title")
            local bar = billboard:FindFirstChild("Bar")
            local fill = bar and bar:FindFirstChild("Fill")
            local percent = bar and bar:FindFirstChild("Percent")
            if not (title and bar and fill and percent) then
                billboard:Destroy()
                generator:SetAttribute("__BlehHubGenLastPct__", nil)
                return IsGeneratorComplete(generator)
            end

            if attributeValue29 ~= attributeValue30 then
                generator:SetAttribute("__BlehHubGenLastPct__", attributeValue30)
            end

            title.Text = string.format("GEN %d", recoveredValue190)
            percent.Text = string.format("%d%%", attributeValue30)
            fill.Size = UDim2.new(attributeValue30 / 100, 0, 1, 0)
        else
            if billboard then
                billboard:Destroy()
                generator:SetAttribute("__BlehHubGenLastPct__", nil)
            end
        end
        return false
    end

    local function HelperFunction217(generator)
        local function HelperFunction105()

            if not Config.generatorEspEnabled and not Config.generatorProgressEnabled then return end
            IsGeneratorComplete(generator)
        end

        pcall(function()
            generator:GetAttributeChangedSignal("RepairProgress"):Connect(HelperFunction105)
            generator:GetAttributeChangedSignal("Progress"):Connect(HelperFunction105)
            generator:GetAttributeChangedSignal("Completed"):Connect(HelperFunction105)
            generator:GetAttributeChangedSignal("IsCompleted"):Connect(HelperFunction105)
        end)
    end

    local function HelperFunction92(attributeValue2, cache48)
        local function HelperFunction38()
            local recoveredValue411 = GetInstanceNumericValue(attributeValue2, "Dropped") or GetInstanceNumericValue(attributeValue2, "IsDropped")
            local recoveredValue147 = GetInstanceNumericValue(attributeValue2, "Broken") or GetInstanceNumericValue(attributeValue2, "IsBroken") or GetInstanceNumericValue(attributeValue2, "Destroyed")
            if recoveredValue411 or recoveredValue147 or cache48.isFake then
                RemoveHighlight(attributeValue2)
                for index, targetPlayer in ipairs(State.worldEspObjects.Pallets) do
                    if targetPlayer == attributeValue2 then table.remove(State.worldEspObjects.Pallets, index); break end
                end
                State.palletMetadata[attributeValue2] = nil
            end
        end
        for _, attributeValue17 in ipairs({"Dropped","IsDropped","Broken","IsBroken","Destroyed"}) do
            attributeValue2:GetAttributeChangedSignal(attributeValue17):Connect(HelperFunction38)
        end
        attributeValue2.ChildAdded:Connect(function(child)
            if child:IsA("ValueBase") and (child.Name=="Dropped" or child.Name=="IsDropped" or child.Name=="Broken" or child.Name=="IsBroken" or child.Name=="Destroyed") then
                child.Changed:Connect(HelperFunction38)
            end
        end)
    end

    function ApplyGhostGateToObj(part6, enabled)
        if not part6 or not part6.Parent then return end
        local parts2 = part6:IsA("BasePart") and {part6} or {}
        if not part6:IsA("BasePart") then
            local function HelperFunction109(parentObject)
                for _, child in ipairs(parentObject:GetChildren()) do
                    if child:IsA("BasePart") then table.insert(parts2, child) end
                    HelperFunction109(child)
                end
            end
            HelperFunction109(part6)
        end
        for _, part in ipairs(parts2) do
            if part:IsA("BasePart") then
                if enabled then
                    if not State.ghostGateOriginals[part] then
                        State.ghostGateOriginals[part] = { CanCollide = part.CanCollide, Transparency = part.Transparency }
                    end
                    part.CanCollide = false
                    part.Transparency = 0.6
                else
                    if State.ghostGateOriginals[part] then
                        part.CanCollide = State.ghostGateOriginals[part].CanCollide
                        part.Transparency = State.ghostGateOriginals[part].Transparency
                    end
                end
            end
        end
    end

    local function HelperFunction183(descendant)
        local n = descendant.Name
        if n == "Generator" then
            table.insert(State.worldEspObjects.Generators, descendant)
            if not State.worldEspConnections[descendant] then

                if next(State.worldEspConnections) == nil then
                    State.stateField106 = 1
                end
                State.worldEspConnections[descendant] = State.stateField106
                State.stateField106 = State.stateField106 + 1
            end
            if Config.generatorEspEnabled then IsGeneratorComplete(descendant); HelperFunction217(descendant) end
        elseif n == "Hook" then
            table.insert(State.worldEspObjects.Hooks, descendant)
            local parts2 = {}
            local m = descendant:FindFirstChild("Model")
            if m then
                local function HelperFunction124(parentObject)
                    for _, child in ipairs(parentObject:GetChildren()) do
                        if child:IsA("MeshPart") then table.insert(parts2, child) end
                        HelperFunction124(child)
                    end
                end
                HelperFunction124(m)
            end
            State.hookParts[descendant] = parts2
            if Config.hookEspEnabled then
                if #parts2 > 0 then for _, targetPlayer in ipairs(parts2) do ApplyHighlight(targetPlayer, Config.hookEspColor) end
                else ApplyHighlight(descendant, Config.hookEspColor) end
            end
        elseif n == "Gate" then
            table.insert(State.worldEspObjects.Gates, descendant)
            if Config.gateEspEnabled then ApplyHighlight(descendant, Config.gateEspColor) end
            if State.ghostGateLegitMode then ApplyGhostGateToObj(descendant, true) end
        elseif n == "Pallet" or n == "Palletwrong" then
            table.insert(State.worldEspObjects.Pallets, descendant)
            local recoveredValue311 = n:lower()
            local part = (descendant:IsA("Model") and descendant.PrimaryPart) or descendant:FindFirstChildWhichIsA("BasePart", true) or (descendant:IsA("BasePart") and descendant)
            local fake = recoveredValue311:find("fake") or recoveredValue311:find("broken") or recoveredValue311:find("destroyed")
            local cache48 = { part = part, isFake = fake and true or false }
            State.palletMetadata[descendant] = cache48
            if Config.palletEspEnabled and not cache48.isFake then ApplyHighlight(descendant, Config.palletEspColor) end
            HelperFunction92(descendant, cache48)
        end
    end

    local function HelperFunction212(descendant)
        local n = descendant.Name
        if n == "Generator" then
            for index, value2 in ipairs(State.worldEspObjects.Generators) do
                if value2 == descendant then table.remove(State.worldEspObjects.Generators, index); break end
            end
            State.worldEspConnections[descendant] = nil
            State.completedGenerators[descendant] = nil
            RemoveHighlight(descendant)
            local attributeValue22 = descendant:FindFirstChild("__BlehHubGenProgress__")
            if attributeValue22 then attributeValue22:Destroy() end

            if next(State.worldEspConnections) == nil then
                State.stateField106 = 1
            end
        elseif n == "Hook" then
            for index, value2 in ipairs(State.worldEspObjects.Hooks) do
                if value2 == descendant then table.remove(State.worldEspObjects.Hooks, index); break end
            end
            local parts2 = State.hookParts[descendant]
            if parts2 then for _, targetPlayer in ipairs(parts2) do RemoveHighlight(targetPlayer) end else RemoveHighlight(descendant) end
            State.hookParts[descendant] = nil
        elseif n == "Gate" then
            for index, value2 in ipairs(State.worldEspObjects.Gates) do
                if value2 == descendant then table.remove(State.worldEspObjects.Gates, index); break end
            end
            RemoveHighlight(descendant)
        elseif n == "Pallet" or n == "Palletwrong" then
            for index, value2 in ipairs(State.worldEspObjects.Pallets) do
                if value2 == descendant then table.remove(State.worldEspObjects.Pallets, index); break end
            end
            RemoveHighlight(descendant)
            State.palletMetadata[descendant] = nil
        end
    end

    local function HelperFunction34(recoveredValue363)
        if not recoveredValue363 then return end
        State.worldEspObjects = { Generators={}, Pallets={}, Hooks={}, Gates={} }
        State.palletMetadata = {}; State.hookParts = {}; State.completedGenerators = {}
        State.worldEspConnections = {}; State.stateField106 = 1
        for _, instance in ipairs(recoveredValue363:GetDescendants()) do HelperFunction183(instance) end
    end

    local function HelperFunction132(recoveredValue363)
        if not recoveredValue363 then return end
        HelperFunction34(recoveredValue363)
        recoveredValue363.DescendantAdded:Connect(HelperFunction183)
        recoveredValue363.DescendantRemoving:Connect(HelperFunction212)
        State.worldEspReady = true
    end


    State.movementConnections = {}
    State._windowParts = {}
    State._windowPartMap = {}

    local function HelperFunction84(part)
        if not part or not part.Parent or State.movementConnections[part] then return end

        local color = Config.windowEspColor


        local recoveredValue132 = Instance.new("BoxHandleAdornment")
        recoveredValue132.Name = "WindowESP_Box"
        recoveredValue132.Adornee = part
        recoveredValue132.Color3 = color
        recoveredValue132.Transparency = 0.3
        recoveredValue132.Size = part.Size
        recoveredValue132.AlwaysOnTop = true
        recoveredValue132.ZIndex = 10
        recoveredValue132.Parent = GetEspFolder()

        State.movementConnections[part] = recoveredValue132
    end

    local function HelperFunction175(part)
        local recoveredValue132 = State.movementConnections[part]
        if recoveredValue132 then
            pcall(function() recoveredValue132:Destroy() end)
            State.movementConnections[part] = nil
        end
    end


    local function HelperFunction61(descendant)
        if typeof(descendant) ~= "Instance" then return nil end
        local n = string.lower(descendant.Name)


        if n == "window" and descendant:IsA("Model") then
            local part3 = descendant:FindFirstChild("Bottom", true)
            if part3 and part3:IsA("BasePart") then
                return part3
            end
            return descendant.PrimaryPart
        end


        if n == "bottom" and descendant:IsA("BasePart") then
            if descendant.Parent and string.lower(descendant.Parent.Name) == "window" then
                return descendant
            end
        end


        return nil
    end

    local function HelperFunction104(descendant)
        local recoveredValue299 = HelperFunction61(descendant)
        if recoveredValue299 then
            if not State._windowPartMap[recoveredValue299] then
                State._windowPartMap[recoveredValue299] = true
                table.insert(State._windowParts, recoveredValue299)
            end
            if Config.windowEspEnabled and not State.movementConnections[recoveredValue299] then
                HelperFunction84(recoveredValue299)
            end
        end
    end

    Workspace.DescendantAdded:Connect(function(descendant)
        HelperFunction104(descendant)
    end)

    Workspace.DescendantRemoving:Connect(function(descendant)
        local recoveredValue299 = HelperFunction61(descendant) or descendant
        if State._windowPartMap[recoveredValue299] then
            State._windowPartMap[recoveredValue299] = nil
            for index, e in ipairs(State._windowParts) do
                if e == recoveredValue299 then table.remove(State._windowParts, index) break end
            end
        end
        if State.movementConnections[recoveredValue299] then
            HelperFunction175(recoveredValue299)
        end
    end)

    local function HelperFunction171()

        for part, recoveredValue132 in pairs(State.movementConnections) do
            if not part or not part.Parent then
                HelperFunction175(part)
            end
        end


        if Config.windowEspEnabled then
            for _, target in ipairs(State._windowParts) do
                if target and target.Parent and not State.movementConnections[target] then
                    HelperFunction84(target)
                end
            end
        end
    end


    task.spawn(function()
        task.wait(3)

        for _, instance in ipairs(Workspace:GetDescendants()) do
            local target = HelperFunction61(instance)
            if target and not State._windowPartMap[target] then
                State._windowPartMap[target] = true
                table.insert(State._windowParts, target)
            end
        end
        HelperFunction171()
    end)

    function RefreshWorldESP()
        if not State.worldEspReady then return end


        local recoveredValue413 = Config.generatorEspEnabled or Config.generatorProgressEnabled
        if recoveredValue413 then
            local cache15 = {}
            for _, instance in ipairs(State.worldEspObjects.Generators) do
                if instance and instance.Parent then
                    local recoveredValue266 = IsGeneratorComplete(instance)
                    if not recoveredValue266 then table.insert(cache15, instance) end
                end
            end
            State.worldEspObjects.Generators = cache15
        else

            for _, instance in ipairs(State.worldEspObjects.Generators) do
                if instance and instance.Parent then
                    RemoveHighlight(instance)
                    local attributeValue22 = instance:FindFirstChild("__BlehHubGenProgress__")
                    if attributeValue22 then attributeValue22:Destroy() end
                    instance:SetAttribute("__BlehHubGenLastPct__", nil)
                end
            end
        end


        if Config.palletEspEnabled then
            for _, attributeValue2 in ipairs(State.worldEspObjects.Pallets) do
                if attributeValue2 and attributeValue2.Parent then
                    local cache48 = State.palletMetadata[attributeValue2]
                    if cache48 and not cache48.isFake then ApplyHighlight(attributeValue2, Config.palletEspColor) end
                end
            end
        else
            for _, attributeValue2 in ipairs(State.worldEspObjects.Pallets) do
                if attributeValue2 then RemoveHighlight(attributeValue2) end
            end
        end


        if Config.hookEspEnabled then
            for _, recoveredValue201 in ipairs(State.worldEspObjects.Hooks) do
                if recoveredValue201 and recoveredValue201.Parent then
                    local parts2 = State.hookParts[recoveredValue201]
                    if parts2 then for _, targetPlayer in ipairs(parts2) do ApplyHighlight(targetPlayer, Config.hookEspColor) end
                    else ApplyHighlight(recoveredValue201, Config.hookEspColor) end
                end
            end
        else
            for _, recoveredValue201 in ipairs(State.worldEspObjects.Hooks) do
                if recoveredValue201 and recoveredValue201.Parent then
                    local parts2 = State.hookParts[recoveredValue201]
                    if parts2 then for _, targetPlayer in ipairs(parts2) do RemoveHighlight(targetPlayer) end
                    else RemoveHighlight(recoveredValue201) end
                end
            end
        end


        if Config.gateEspEnabled then
            for _, part6 in ipairs(State.worldEspObjects.Gates) do
                if part6 and part6.Parent then ApplyHighlight(part6, Config.gateEspColor) end
            end
        else
            for _, part6 in ipairs(State.worldEspObjects.Gates) do
                if part6 and part6.Parent then RemoveHighlight(part6) end
            end
        end


        if Config.windowEspEnabled then
            HelperFunction171()
            for part, recoveredValue132 in pairs(State.movementConnections) do
                if part and part.Parent and recoveredValue132 and recoveredValue132.Parent then
                    pcall(function()
                        local color = Config.windowEspColor
                        recoveredValue132.Color3 = color
                        recoveredValue132.Size = part.Size
                    end)
                else
                    HelperFunction175(part)
                end
            end
        else
            for part, recoveredValue132 in pairs(State.movementConnections) do
                HelperFunction175(part)
            end
        end
    end


    State._antiLoopWindowCache = {}
    State._antiLoopWindowMap = {}
    Workspace.DescendantAdded:Connect(function(descendant)
        if typeof(descendant) ~= "Instance" then return end
        if not (descendant:IsA("BasePart") or descendant:IsA("Model")) then return end
        local n = descendant.Name
        if n ~= "Window" and n ~= "VaultPoint" and not string.find(n, "Window") then return end
        if State._antiLoopWindowMap[descendant] then return end
        State._antiLoopWindowMap[descendant] = true
        table.insert(State._antiLoopWindowCache, descendant)
    end)
    Workspace.DescendantRemoving:Connect(function(descendant)
        if not State._antiLoopWindowMap[descendant] then return end
        State._antiLoopWindowMap[descendant] = nil
        for index, e in ipairs(State._antiLoopWindowCache) do
            if e == descendant then table.remove(State._antiLoopWindowCache, index) break end
        end
    end)
    task.spawn(function()
        local recoveredValue363 = workspace:FindFirstChild("Map")
        if recoveredValue363 then
            for _, descendant in ipairs(recoveredValue363:GetDescendants()) do
                if typeof(descendant) == "Instance" and (descendant:IsA("BasePart") or descendant:IsA("Model")) then
                    local n = descendant.Name
                    if n == "Window" or n == "VaultPoint" or string.find(n, "Window") then
                        if not State._antiLoopWindowMap[descendant] then
                            State._antiLoopWindowMap[descendant] = true
                            table.insert(State._antiLoopWindowCache, descendant)
                        end
                    end
                end
            end
        end
    end)

    local function HelperFunction12()
        local cache51 = {}
        for _, recoveredValue96 in ipairs(State._antiLoopWindowCache) do
            if recoveredValue96 and recoveredValue96.Parent then table.insert(cache51, recoveredValue96) end
        end

        for _, recoveredValue267 in ipairs(CollectionService:GetTagged("VaultPoint")) do
            local recoveredValue185 = false
            for _, recoveredValue96 in ipairs(cache51) do
                if recoveredValue96 == recoveredValue267 then recoveredValue185 = true break end
            end
            if not recoveredValue185 then table.insert(cache51, recoveredValue267) end
        end
        return cache51
    end

    function ApplyAntiLoopWindow()
        if not State.antiLoopWindowEnabled then return end

        local recoveredValue409 = ReplicatedStorage:FindFirstChild("Remotes")
        if not recoveredValue409 then return end
        local recoveredValue207 = recoveredValue409:FindFirstChild("Window")
        if not recoveredValue207 then return end
        local remote30 = recoveredValue207:FindFirstChild("VaultEvent")
        if not remote30 then return end

        task.spawn(function()
            task.wait(1)

            local cache51 = HelperFunction12()

            for _, remote26 in ipairs(cache51) do
                task.spawn(function()
                    pcall(function()

                        remote30:FireServer(remote26, true)
                    end)
                end)
                task.wait(0.05)
            end
        end)
    end


    function DisableAntiLoopWindow()
        local recoveredValue409 = ReplicatedStorage:FindFirstChild("Remotes")
        if not recoveredValue409 then return end
        local recoveredValue207 = recoveredValue409:FindFirstChild("Window")
        if not recoveredValue207 then return end

        local remote11 = recoveredValue207:FindFirstChild("VaultCompleteEvent")
        local remote21 = recoveredValue207:FindFirstChild("VaultCompleteEventpart1")

        task.spawn(function()
            local cache51 = HelperFunction12()

            for _, remote26 in ipairs(cache51) do
                task.spawn(function()
                    pcall(function()

                        if remote11 then
                            remote11:FireServer(remote26, false)
                        end

                        if remote21 then
                            remote21:FireServer()
                        end
                    end)
                end)
                task.wait(0.05)
            end
        end)
    end


    do
        local recoveredValue84 = workspace:FindFirstChild("Map")
        if recoveredValue84 then
            pcall(HelperFunction132, recoveredValue84)
            pcall(ApplyAntiLoopWindow)
        end
        workspace.ChildAdded:Connect(function(child)
            if child.Name == "Map" then
                task.wait(2)
                HelperFunction132(child)
                ApplyAntiLoopWindow()
            end
        end)
        workspace.ChildRemoved:Connect(function(child)
            if child.Name == "Map" then
                State.worldEspObjects = { Generators={}, Pallets={}, Hooks={}, Gates={} }
                State.palletMetadata = {}; State.hookParts = {}
                State.completedGenerators = {}; State.worldEspReady = false
                State.worldEspConnections = {}; State.stateField106 = 1
            end
        end)
    end

    RegisterUpdateTask("GenESPUpdater", 0.2, function()
        if not Config.generatorEspEnabled and not Config.generatorProgressEnabled then return end
        for _, instance in ipairs(State.worldEspObjects.Generators) do
            if instance and instance.Parent and not State.completedGenerators[instance] then IsGeneratorComplete(instance) end
        end
    end)

    function DropAllPallets()
        if not getnilinstances then
            Notify("Error", "Your executor does not support getnilinstances().", 2)
            return
        end

        task.spawn(function()
            local recoveredValue409 = ReplicatedStorage:FindFirstChild("Remotes")
            if not recoveredValue409 then return end
            local remote4 = recoveredValue409:FindFirstChild("Pallet")
            remote4 = remote4 and remote4:FindFirstChild("PalletDropEvent")
            if not remote4 then return end

            local cache47 = {}
            local cache36 = {}

            local success, nilInstances = pcall(getnilinstances)
            if success and type(nilInstances) == "table" then
                for _, instance in ipairs(nilInstances) do
                    if typeof(instance) == "Instance" then
                        local name = instance.Name
                        if name == "PalletPointSlide" or name == "palletDropPoint" or name == "PalletDropPoint" or name == "PalletPoint" then
                            if not cache36[instance] then
                                table.insert(cache47, instance)
                                cache36[instance] = true
                            end
                        end
                    end
                end
            end


            if State.nearbyPallets then
                for _, instance in ipairs(State.nearbyPallets) do
                    if instance and instance.Parent and not cache36[instance] then
                        table.insert(cache47, instance)
                        cache36[instance] = true
                    end
                end
            end

            if #cache47 == 0 then
                return
            end
            for _, remote18 in ipairs(cache47) do
                pcall(function()
                    remote4:FireServer(remote18)
                end)
            end
        end)
    end

    local function HelperFunction62(instance)
        if typeof(instance) ~= "Instance" then return end
        local name = instance.Name
        if name ~= "PalletPointSlide" and name ~= "palletDropPoint" and name ~= "PalletDropPoint" and name ~= "PalletPoint" then return end
        if not State.nearbyPallets then State.nearbyPallets = {} end
        if State._palletPointMap[instance] then return end
        State._palletPointMap[instance] = true
        table.insert(State.nearbyPallets, instance)
    end
    State._palletPointMap = {}
    Workspace.DescendantAdded:Connect(HelperFunction62)
    Workspace.DescendantRemoving:Connect(function(instance)
        if not State._palletPointMap[instance] then return end
        State._palletPointMap[instance] = nil
        if State.nearbyPallets then
            for index, e in ipairs(State.nearbyPallets) do
                if e == instance then table.remove(State.nearbyPallets, index) break end
            end
        end
    end)
    if getnilinstances then
        local success, nilInstances = pcall(getnilinstances)
        if success and type(nilInstances) == "table" then
            for _, instance in ipairs(nilInstances) do HelperFunction62(instance) end
        end
    end
    for _, instance in ipairs(workspace:GetDescendants()) do HelperFunction62(instance) end

    RegisterUpdateTask("AutoDropNearbyPallets", 0.2, function()
        if not State.autoDropNearbyPallet then return end
        if State.stateField31 then return end

        local char = LocalPlayer.Character
        if not char then return end
        local rootPart2 = char:FindFirstChild("HumanoidRootPart")
        if not rootPart2 then return end

        local recoveredValue409 = ReplicatedStorage:FindFirstChild("Remotes")
        if not recoveredValue409 then return end
        local remote4 = recoveredValue409:FindFirstChild("Pallet")
        remote4 = remote4 and remote4:FindFirstChild("PalletDropEvent")
        if not remote4 then return end

        local distanceValue39 = rootPart2.Position

        if not State.nearbyPallets then
            State.nearbyPallets = {}
            State._palletPointMap = {}
            if getnilinstances then
                local success, nilInstances = pcall(getnilinstances)
                if success and type(nilInstances) == "table" then
                    for _, instance in ipairs(nilInstances) do HelperFunction62(instance) end
                end
            end
            for _, instance in ipairs(workspace:GetDescendants()) do HelperFunction62(instance) end
        end


        if tick() - (State.timeValue7 or (0.0)) > 5 then
            State.timeValue7 = tick()
            if getnilinstances then
                local success, nilInstances = pcall(getnilinstances)
                if success and type(nilInstances) == "table" then
                    for _, instance in ipairs(nilInstances) do HelperFunction62(instance) end
                end
            end
        end

        local remote13 = nil
        local distanceValue15 = math.huge


        for index = #State.nearbyPallets, (1.0), -1 do
            local instance = State.nearbyPallets[index]
            if not instance or not instance.Parent then
                State._palletPointMap[instance] = nil
                table.remove(State.nearbyPallets, index)
            else
                local pos = nil

                pcall(function()
                    if instance:IsA("BasePart") then
                        pos = instance.Position
                    elseif instance:IsA("Model") then
                        pos = instance:GetPivot().Position
                    elseif instance:IsA("Attachment") then
                        pos = instance.WorldPosition
                    end
                end)


                if not pos then
                    local part = instance:FindFirstChildWhichIsA("BasePart", true)
                    if part then pos = part.Position end
                end

                if pos then
                    local dist = (pos - distanceValue39).Magnitude
                    if dist < distanceValue15 then
                        distanceValue15 = dist
                        remote13 = instance
                    end
                end
            end
        end


        if remote13 and distanceValue15 <= (4.0) then
            pcall(function()
                remote4:FireServer(remote13)
            end)
            for index, instance in ipairs(State.nearbyPallets) do
                if instance == remote13 then
                    State._palletPointMap[instance] = nil
                    table.remove(State.nearbyPallets, index)
                    break
                end
            end

            State.stateField31 = true
            task.delay(2, function()
                State.stateField31 = false
            end)
        end
    end)
end

local function ApplyHitboxModifier(player, char)
    if not Config.hitboxModifierEnabled then return end
    if not char then return end

    local distanceValue19 = GetPlayerRole(player)
    local recoveredValue35 = (distanceValue19 == "killer") and Config.killerHitboxPercent or Config.survivorHitboxPercent
    local vectorValue = recoveredValue35 / 100


    local rootPart2 = char:FindFirstChild("HumanoidRootPart")
    if rootPart2 and rootPart2:IsA("BasePart") then
        if not State.hitboxOriginalSizes[rootPart2] then
            State.hitboxOriginalSizes[rootPart2] = rootPart2.Size
        end


        local vectorValue25 = 2
        local vectorValue55 = Vector3.new(vectorValue25 * vectorValue, vectorValue25 * vectorValue, vectorValue25 * vectorValue)

        pcall(function()
            rootPart2.Size = vectorValue55
            rootPart2.Transparency = 1
            rootPart2.CanCollide = false
        end)
    end
end

local function RestoreHitboxModifier(player, char)
    if not char then return end
    local rootPart2 = char:FindFirstChild("HumanoidRootPart")
    if rootPart2 and rootPart2:IsA("BasePart") then
        local recoveredValue166 = State.hitboxOriginalSizes[rootPart2]
        if recoveredValue166 then
            pcall(function()
                rootPart2.Size = recoveredValue166
                rootPart2.Transparency = 1
            end)
            State.hitboxOriginalSizes[rootPart2] = nil
        end
    end
end

local function RefreshAllHitboxes()
    if not Config.hitboxModifierEnabled then return end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then ApplyHitboxModifier(player, player.Character) end
    end
end

local function RestoreAllHitboxes()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then RestoreHitboxModifier(player, player.Character) end
    end
end

local function AttachHitboxEsp(player, char)
    if player == LocalPlayer then return end
    local rootPart2 = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart2 then return end
    local recoveredValue121 = State.hitboxEspObjects[player]

    if recoveredValue121 and recoveredValue121.Parent then
        if recoveredValue121.Adornee == rootPart2 then return end
        recoveredValue121:Destroy()
    end

    local distanceValue19 = GetPlayerRole(player)
    local color = (distanceValue19 == "killer") and Config.hitboxKillerColor or Config.hitboxSurvivorColor
    local selectionBox = Instance.new("SelectionBox")
    selectionBox.Adornee = rootPart2; selectionBox.Color3 = color; selectionBox.LineThickness = 0.10
    selectionBox.SurfaceTransparency = Config.hitboxEspOutlineOnly and (1.0) or Config.hitboxFillTransparency
    selectionBox.SurfaceColor3 = color; selectionBox.Parent = GetEspFolder()
    State.hitboxEspObjects[player] = selectionBox
end

local function RemoveHitboxEsp(player)
    local selectionBox = State.hitboxEspObjects[player]
    if selectionBox then pcall(function() selectionBox:Destroy() end); State.hitboxEspObjects[player] = nil end
end

local function RefreshHitboxEsp()
    for player, selectionBox in pairs(State.hitboxEspObjects) do
        if selectionBox and selectionBox.Parent then
            local distanceValue19 = GetPlayerRole(player)
            local color = (distanceValue19 == "killer") and Config.hitboxKillerColor or Config.hitboxSurvivorColor
            selectionBox.Color3 = color; selectionBox.SurfaceColor3 = color
            selectionBox.SurfaceTransparency = Config.hitboxEspOutlineOnly and (1.0) or Config.hitboxFillTransparency
        end
    end
end

local function StartHitboxSystem()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then AttachHitboxEsp(player, player.Character) end
    end
end

local function StopHitboxSystem()
    for player, _ in pairs(State.hitboxEspObjects) do RemoveHitboxEsp(player) end
end

local IsMovementSlowActive, IsPlayerDoingAction
do
    local function HelperFunction194()
        task.spawn(function()
            local success, mechanics = pcall(function()
                return game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 10):WaitForChild("Mechanics", 10)
            end)
            if not success or not mechanics then return end

            local recoveredValue18 = mechanics:FindFirstChild("Slow")
            if recoveredValue18 and recoveredValue18:IsA("BindableEvent") then
                recoveredValue18.Event:Connect(function(_, dur, extra)
                    local timeValue5 = (tonumber(dur) or 0) + (tonumber(extra) or 0)
                    if timeValue5 > 0 then State.movementSlowUntil = tick() + timeValue5 + 0.1 end
                end)
            end

            local remote7 = mechanics:FindFirstChild("Slowserver")
            if remote7 and remote7:IsA("RemoteEvent") then
                remote7.OnClientEvent:Connect(function(_, dur)
                    local timeValue5 = tonumber(dur) or 0
                    if timeValue5 > 0 then State.movementSlowUntil = tick() + timeValue5 + 0.1 end
                end)
            end
        end)
    end

    function IsMovementSlowActive()
        return tick() < State.movementSlowUntil
    end

    function IsPlayerDoingAction()
        local char = LocalPlayer.Character
        if not char then return false end
        local rootPart2 = char:FindFirstChild("HumanoidRootPart")
        if rootPart2 and CollectionService:HasTag(rootPart2, "doing action") then return true end
        return false
    end

    pcall(HelperFunction194)
end

do
    local function HelperFunction111(player)
        if not player then return 0 end
        local success, val = pcall(function() return player:GetAttribute("HookCount") end)
        if success and typeof(val) == "number" then return val end

        local value2 = player:FindFirstChild("HookCount")
        if value2 and value2:IsA("ValueBase") then return tonumber(value2.Value) or 0 end
        local char = player.Character
        if char then
            local successFlag6, cval = pcall(function() return char:GetAttribute("HookCount") end)
            if successFlag6 and typeof(cval) == "number" then return cval end
            local recoveredValue406 = char:FindFirstChild("HookCount")
            if recoveredValue406 and recoveredValue406:IsA("ValueBase") then return tonumber(recoveredValue406.Value) or 0 end
        end
        return (0.0)
    end

    local function HelperFunction180(enabled)
        local recoveredValue105 = LocalPlayer:FindFirstChild("PlayerGui")
        if not recoveredValue105 then return end
        for _, gui in ipairs(recoveredValue105:GetChildren()) do
            if gui:IsA("ScreenGui") and gui.Name:match("%-mob$") then
                local frame4 = gui:FindFirstChild("Frame")
                if frame4 then
                    for index = (1.0), 5 do
                        local recoveredValue131 = frame4:FindFirstChild("Survivor" .. index)
                        local recoveredValue290 = recoveredValue131 and recoveredValue131:FindFirstChild("ImageLabel")
                        local recoveredValue51 = recoveredValue131 and recoveredValue131:FindFirstChild("TextLabel")
                        if recoveredValue290 and recoveredValue51 then
                            local recoveredValue380 = "BlehHub_CustomHookCounter"
                            local textLabel3 = recoveredValue290:FindFirstChild(recoveredValue380)
                            local recoveredValue86 = recoveredValue290:FindFirstChild("Counter")

                            local function HelperFunction45(cacheKey)
                                if recoveredValue86 then pcall(function() recoveredValue86.Visible = false end) end
                                if textLabel3 then textLabel3.Visible = false end
                                if cacheKey then State.stateField35[cacheKey] = nil end
                            end

                            if not enabled then
                                HelperFunction45(nil)
                                continue
                            end


                            local recoveredValue355 = recoveredValue51.Text and recoveredValue51.Text:match("^%s*(.-)%s*$") or ""
                            local NormalizeName = recoveredValue355:lower()
                            local recoveredValue440 = (recoveredValue355 == "" or NormalizeName == "waiting" or NormalizeName:find("waiting") or NormalizeName == "empty" or recoveredValue355:match("^Survivor%d+$"))

                            local recoveredValue231 = true
                            pcall(function()
                                if recoveredValue131.Visible == false then recoveredValue231 = false end
                                if recoveredValue290.Image == "" or recoveredValue290.Image == "rbxasset://textures/ui/GuiImagePlaceholder.png" then

                                end
                            end)
                            if not recoveredValue231 then
                                HelperFunction45(nil)
                                continue
                            end

                            local player = nil
                            if not recoveredValue440 then
                                for _, targetPlayer in ipairs(Players:GetPlayers()) do
                                    if targetPlayer.Name == recoveredValue355 or targetPlayer.DisplayName == recoveredValue355 then
                                        player = targetPlayer
                                        break
                                    end
                                end
                            end
                            if not player then
                                HelperFunction45(nil)
                                continue
                            end

                            local recoveredValue289 = HelperFunction111(player)
                            State.stateField35[player.Name] = recoveredValue289


                            if recoveredValue289 <= 0 then
                                if recoveredValue86 then pcall(function() recoveredValue86.Visible = false end) end
                                if not textLabel3 then
                                    textLabel3 = Instance.new("TextLabel")
                                    textLabel3.Name = recoveredValue380
                                    textLabel3.Size = UDim2.new(1, (0.0), 0.35, 0)
                                    textLabel3.Position = UDim2.new(0, 0, 0.65, 0)
                                    textLabel3.BackgroundColor3 = Color3.fromRGB((0.0), 0, 0)
                                    textLabel3.BackgroundTransparency = 0.5
                                    textLabel3.TextColor3 = Color3.fromRGB(255, (255.0), 255)
                                    textLabel3.TextStrokeColor3 = Color3.fromRGB(0, (0.0), 0)
                                    textLabel3.TextStrokeTransparency = 0
                                    textLabel3.TextScaled = true
                                    textLabel3.Font = Enum.Font.SourceSansBold
                                    textLabel3.BorderSizePixel = 0
                                    textLabel3.Parent = recoveredValue290
                                end
                                textLabel3.Visible = true
                                textLabel3.Text = "Hooks: 0"
                                textLabel3.TextColor3 = Color3.fromRGB(255, (255.0), 255)
                                continue
                            end


                            if recoveredValue86 then pcall(function() recoveredValue86.Visible = true end) end
                            if not textLabel3 then
                                textLabel3 = Instance.new("TextLabel")
                                textLabel3.Name = recoveredValue380
                                textLabel3.Size = UDim2.new((1.0), 0, 0.35, 0)
                                textLabel3.Position = UDim2.new(0, 0, 0.65, 0)
                                textLabel3.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                                textLabel3.BackgroundTransparency = 0.5
                                textLabel3.TextColor3 = Color3.fromRGB(255, 255, (255.0))
                                textLabel3.TextStrokeColor3 = Color3.fromRGB((0.0), 0, (0.0))
                                textLabel3.TextStrokeTransparency = 0
                                textLabel3.TextScaled = true
                                textLabel3.Font = Enum.Font.SourceSansBold
                                textLabel3.BorderSizePixel = 0
                                textLabel3.Parent = recoveredValue290
                            end
                            textLabel3.Visible = true
                            if recoveredValue289 >= 3 then
                                textLabel3.Text = "DEAD"
                                textLabel3.TextColor3 = Color3.fromRGB(255, 75, 75)
                            elseif recoveredValue289 == 2 then
                                textLabel3.Text = "Hooks: 2"
                                textLabel3.TextColor3 = Color3.fromRGB(255, 140, 0)
                            else
                                textLabel3.Text = "Hooks: 1"
                                textLabel3.TextColor3 = Color3.fromRGB(210, 130, 255)
                            end
                        end
                    end
                end
            end
        end
    end

    local function HelperFunction139(player)
        if not player or State.hookCounterAttrConns[player] then return end
        pcall(function()
            local connection = player:GetAttributeChangedSignal("HookCount"):Connect(function()
                State.stateField98 = true
            end)
            State.hookCounterAttrConns[player] = connection
        end)

        pcall(function()
            local value2 = player:FindFirstChild("HookCount")
            if value2 and value2:IsA("ValueBase") then
                local connection8 = value2.Changed:Connect(function() State.stateField98 = true end)

                State.hookCounterAttrConns[player.Name .. "_val"] = connection8
            end
        end)
        if player.Character then
            pcall(function()
                local attributeValue8 = player.Character:GetAttributeChangedSignal("HookCount"):Connect(function()
                    State.stateField98 = true
                end)
                State.hookCounterAttrConns[player.Name .. "_char"] = attributeValue8
            end)
        end

        pcall(function()
            player.CharacterAdded:Connect(function(char)
                if not Config.showHookCounter then return end
                task.wait(0.5)
                pcall(function()
                    local attributeValue8 = char:GetAttributeChangedSignal("HookCount"):Connect(function()
                        State.stateField98 = true
                    end)
                    State.hookCounterAttrConns[player.Name .. "_char"] = attributeValue8
                end)
                State.stateField98 = true
            end)
        end)
    end

    local function HelperFunction197()
        for distanceValue7, connection in pairs(State.hookCounterAttrConns) do
            pcall(function() connection:Disconnect() end)
            State.hookCounterAttrConns[distanceValue7] = nil
        end
        if State.connection24 then
            pcall(function() State.connection24:Disconnect() end)
            State.connection24 = nil
        end
        if State.connection23 then
            pcall(function() State.connection23:Disconnect() end)
            State.connection23 = nil
        end
        if State.connection9 then
            pcall(function() State.connection9:Disconnect() end)
            State.connection9 = nil
        end
    end

    local function HelperFunction10()
        if State.connection24 then return end
        State.stateField98 = true

        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            HelperFunction139(targetPlayer)
        end
        State.connection23 = Players.PlayerAdded:Connect(function(targetPlayer)
            task.wait(0.5)
            HelperFunction139(targetPlayer)
            State.stateField98 = true
        end)
        State.connection9 = Players.PlayerRemoving:Connect(function(targetPlayer)
            State.stateField35[targetPlayer.Name] = nil
            local contextValue = State.hookCounterAttrConns[targetPlayer]
            if contextValue then pcall(function() contextValue:Disconnect() end); State.hookCounterAttrConns[targetPlayer]=nil end
            local connection8 = State.hookCounterAttrConns[targetPlayer.Name .. "_val"]
            if connection8 then pcall(function() connection8:Disconnect() end); State.hookCounterAttrConns[targetPlayer.Name .. "_val"]=nil end
            local connection6 = State.hookCounterAttrConns[targetPlayer.Name .. "_char"]
            if connection6 then pcall(function() connection6:Disconnect() end); State.hookCounterAttrConns[targetPlayer.Name .. "_char"]=nil end
            State.stateField98 = true
        end)

        local recoveredValue40 = LocalPlayer:FindFirstChild("PlayerGui")
        if recoveredValue40 then
            State.connection24 = recoveredValue40.ChildAdded:Connect(function(child)
                if child:IsA("ScreenGui") and child.Name:match("%-mob$") then
                    State.stateField98 = true
                end

                if child.Name == "Frame" and child.Parent and child.Parent.Name:match("%-mob$") then
                    State.stateField98 = true
                end
            end)

            local connection21 = recoveredValue40.DescendantAdded:Connect(function(descendant)
                if descendant.Name == "Survivor1" or descendant.Name == "ImageLabel" then
                    local recoveredValue238 = descendant:FindFirstAncestorOfClass("ScreenGui")
                    if recoveredValue238 and recoveredValue238.Name:match("%-mob$") then
                        State.stateField98 = true
                    end
                end
            end)

            State.hookCounterAttrConns._guiDesc = connection21
        end
        HelperFunction180(true)
    end

    local function HelperFunction170()
        HelperFunction197()
        State.stateField35 = {}
        State.stateField98 = true
        HelperFunction180(false)

        local recoveredValue105 = LocalPlayer:FindFirstChild("PlayerGui")
        if recoveredValue105 then
            for _, gui in ipairs(recoveredValue105:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Name:match("%-mob$") then
                    local frame4 = gui:FindFirstChild("Frame")
                    if frame4 then
                        for index = 1, (5.0) do
                            local recoveredValue131 = frame4:FindFirstChild("Survivor" .. index)
                            local recoveredValue290 = recoveredValue131 and recoveredValue131:FindFirstChild("ImageLabel")
                            local textLabel3 = recoveredValue290 and recoveredValue290:FindFirstChild("BlehHub_CustomHookCounter")
                            if textLabel3 then pcall(function() textLabel3:Destroy() end) end
                        end
                    end
                end
            end
        end
    end

    RegisterUpdateTask("HookCounter", 0.5, function()
        if not Config.showHookCounter then return end
        if not State.stateField98 then

            local recoveredValue114 = false
            for _, targetPlayer in ipairs(Players:GetPlayers()) do
                local cur = HelperFunction111(targetPlayer)
                if State.stateField35[targetPlayer.Name] ~= cur then recoveredValue114 = true break end
            end
            if not recoveredValue114 then return end
            State.stateField98 = true
        end
        State.stateField98 = false
        HelperFunction180(true)
    end)


    _G.BlehHub_SetShowHookCounter = function(enabled)
        Config.showHookCounter = enabled and true or false
        if Config.showHookCounter then
            HelperFunction10()
        else
            HelperFunction170()
        end
    end
    getgenv().BlehHub_SetShowHookCounter = _G.BlehHub_SetShowHookCounter

    State._HookCounter_Enable = HelperFunction10
    State._HookCounter_Disable = HelperFunction170
    State._HookCounter_Update = HelperFunction180
end

local GetDesiredWalkSpeed, _ApplySpeed, _StartAntiFallSlow, _StopAntiFallSlow, _StartNoSlowdown, _StopNoSlowdown, SetupMovementForChar
do


    function GetDesiredWalkSpeed()
        if State.SpeedBoost then
            return BASE_WALK_SPEED * (1 + math.clamp(tonumber(State.speedBoostMultiplier) or 0.3, 0, (2.0)))
        end
        return BASE_WALK_SPEED
    end

    function _ApplySpeed(humanoid, humanoid14)
        if not humanoid or not humanoid.Parent then return end
        if math.abs(humanoid.WalkSpeed - humanoid14) > 0.05 then
            pcall(function() humanoid.WalkSpeed = humanoid14 end)
        end
    end

    local function HelperFunction9()
        task.spawn(function()
            local success, remote = pcall(function()
                return game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 10):WaitForChild("Mechanics", (10.0)):WaitForChild("Fall", 10)
            end)
            if not success or not remote then return end
            local recoveredValue277
            recoveredValue277 = hookmetamethod(game, "__namecall", function(self, ...)
                local remote27 = getnamecallmethod()
                if State.antiFallSlowEnabled and remote27 == "FireServer" and rawequal(self, remote) then return end
                return recoveredValue277(self, ...)
            end)
        end)
    end

    function _StartAntiFallSlow(humanoid)
        if State.movConns.antiFall then State.movConns.antiFall:Disconnect() end
        HelperFunction9()
        if not humanoid then return end
        pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
        State.movConns.antiFall = humanoid.StateChanged:Connect(function(_, recoveredValue130)
            if not State.antiFallSlowEnabled then return end
            if recoveredValue130 == Enum.HumanoidStateType.Landed or recoveredValue130 == Enum.HumanoidStateType.GettingUp or recoveredValue130 == Enum.HumanoidStateType.FallingDown then
                pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Running) end)
                _ApplySpeed(humanoid, GetDesiredWalkSpeed())
            end
        end)
    end

    function _StopAntiFallSlow(humanoid)
        if State.movConns.antiFall then State.movConns.antiFall:Disconnect(); State.movConns.antiFall = nil end
        if humanoid and humanoid.Parent then pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true) end) end
    end

    function _StartNoSlowdown(humanoid)
        if State.movConns.noSlow then State.movConns.noSlow:Disconnect(); State.movConns.noSlow = nil end
        if not humanoid then return end
        if GetPlayerRole(LocalPlayer) == "killer" then return end
        State.movConns.noSlow = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if not State.noSlowdownEnabled then return end
            if GetPlayerRole(LocalPlayer) == "killer" then return end

            local char = LocalPlayer.Character

            if State.safeModeSpeed and char and (char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried") or humanoid.Health <= 50) then
                return
            end

            if State.safeNoSlowdownEnabled and (IsMovementSlowActive() or IsPlayerDoingAction()) then
                return
            end

            local humanoid14 = GetDesiredWalkSpeed()
            if humanoid.WalkSpeed < humanoid14 - 0.05 then pcall(function() humanoid.WalkSpeed = humanoid14 end) end
        end)
    end

    function _StopNoSlowdown()
        if State.movConns.noSlow then State.movConns.noSlow:Disconnect(); State.movConns.noSlow = nil end
    end

    function SetupMovementForChar(char)
        if not char then return end
        local humanoid = char:WaitForChild("Humanoid", (5.0))
        if not humanoid then return end
        if State.antiFallSlowEnabled then _StartAntiFallSlow(humanoid) end
        if State.noSlowdownEnabled and GetPlayerRole(LocalPlayer) ~= "killer" then _StartNoSlowdown(humanoid) end
        if State.SpeedBoost then
            local humanoid14 = GetDesiredWalkSpeed()
            task.wait(0.15)
            if not (State.safeModeSpeed and (IsMovementSlowActive() or IsPlayerDoingAction())) then
                _ApplySpeed(humanoid, humanoid14)
            end
        end
    end

    LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
        UpdatePlayerRole(LocalPlayer)
        if GetPlayerRole(LocalPlayer) == "killer" and State.movConns.noSlow then
            State.movConns.noSlow:Disconnect(); State.movConns.noSlow = nil
        end
        if GetPlayerRole(LocalPlayer) ~= "killer" then
            StopInfiniteLunge()
        end
    end)
end

local EnsureMoonwalkGui
do
    function EnsureMoonwalkGui()
        if State.moonwalkGui then
            if State.moonwalkGui.Parent then return end
            State.moonwalkGui = nil
        end

        local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
        local screenGui3 = Instance.new("ScreenGui")
        screenGui3.Name = "BlehHubMoonwalk"
        screenGui3.ResetOnSpawn = false
        screenGui3.Enabled = false
        screenGui3.Parent = PlayerGui

        local frame9 = Instance.new("Frame")
        frame9.Name = "MoonwalkBtns"
        frame9.AnchorPoint = Vector2.new(1,1)
        frame9.Position = UDim2.new((1.0),(-18.0),1,-170)
        frame9.Size = UDim2.fromOffset((46.0),96)
        frame9.BackgroundTransparency = 1
        frame9.Parent = screenGui3

        local function HelperFunction182(rotation, recoveredValue173)
            local colorValue12 = Instance.new("TextButton")
            colorValue12.BackgroundColor3 = Color3.fromRGB(24, 20, 48)
            colorValue12.BackgroundTransparency = 0.15
            colorValue12.BorderSizePixel = 0
            colorValue12.AutoButtonColor = false
            colorValue12.AnchorPoint = Vector2.new(0.5,0)
            colorValue12.Position = UDim2.new(0.5,0,0,recoveredValue173)
            colorValue12.Size = UDim2.fromOffset(42,42)
            colorValue12.Text = rotation < 0 and "<" or ">"
            colorValue12.TextColor3 = Color3.fromRGB(205, 190, 255)
            colorValue12.Font = Enum.Font.GothamBold
            colorValue12.TextSize = 19
            colorValue12.Parent = frame9
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = colorValue12
            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(78, 57, 135)
            stroke.Thickness = 1
            stroke.Parent = colorValue12
            return colorValue12
        end

        local recoveredValue292 = HelperFunction182((-90.0),0)
        local recoveredValue396 = HelperFunction182(90,(50.0))


        local function HelperFunction73(recoveredValue274, vectorValue61)
            recoveredValue274.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                    State.moonwalkSwayPhase = vectorValue61
                    recoveredValue274.TextColor3 = Color3.fromRGB(255,255,255)
                    recoveredValue274.BackgroundColor3 = Color3.fromRGB(78,57,135)
                end
            end)
            recoveredValue274.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                    State.moonwalkSwayPhase = (0.0)
                    recoveredValue274.TextColor3 = Color3.fromRGB(205,190,255)
                    recoveredValue274.BackgroundColor3 = Color3.fromRGB(24,20,48)
                end
            end)
        end

        HelperFunction73(recoveredValue292, (1.0))
        HelperFunction73(recoveredValue396, (-1.0))

        State.moonwalkGui = screenGui3
    end

    RegisterUpdateTask("MoonwalkGuiGuard", 0.5, function()
        if not Config.moonwalkEnabled then return end
        if not State.moonwalkGui or not State.moonwalkGui.Parent then
            EnsureMoonwalkGui()
            if State.moonwalkGui then State.moonwalkGui.Enabled = true end
        elseif not State.moonwalkGui.Enabled then
            State.moonwalkGui.Enabled = true
        end
    end)


    local function HelperFunction102(rootPart2)
        if rootPart2:FindFirstChild("BlehHubMoonwalkAlign") then return rootPart2:FindFirstChild("BlehHubMoonwalkAlign") end

        local attachment = Instance.new("Attachment")
        attachment.Name = "BlehHubMoonwalkAtt"
        attachment.Parent = rootPart2

        local alignOrientation = Instance.new("AlignOrientation")
        alignOrientation.Name = "BlehHubMoonwalkAlign"
        alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
        alignOrientation.Attachment0 = attachment
        alignOrientation.MaxTorque = 6000000
        alignOrientation.Responsiveness = (65.0)
        alignOrientation.Parent = rootPart2

        return alignOrientation
    end

    local function HelperFunction71(rootPart2)
        local alignOrientation = rootPart2:FindFirstChild("BlehHubMoonwalkAlign")
        local attachment = rootPart2:FindFirstChild("BlehHubMoonwalkAtt")
        if alignOrientation then alignOrientation:Destroy() end
        if attachment then attachment:Destroy() end
    end

    RegisterUpdateTask("MoonwalkLock", 0, function(recoveredValue206)
        if not Config.moonwalkEnabled then return end

        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        local rootPart2 = char and char:FindFirstChild("HumanoidRootPart")
        local camera = Workspace.CurrentCamera

        if not humanoid or not rootPart2 or not camera then return end


        local recoveredValue125 = 0
        if State.moonwalkForwardLocked then recoveredValue125 = (1.0) end
        if State.moonwalkBackwardLocked then recoveredValue125 = (-1.0) end
        if State.moonwalkSwayPhase ~= (0.0) then recoveredValue125 = State.moonwalkSwayPhase end


        if recoveredValue125 == 0 then
            if not humanoid.AutoRotate then humanoid.AutoRotate = true end
            HelperFunction71(rootPart2)
            State.stateField24 = (0.0)
            return
        end


        humanoid.AutoRotate = false
        local alignOrientation = HelperFunction102(rootPart2)


        local vectorValue50 = camera.CFrame.LookVector
        local vectorValue59 = Vector3.new(vectorValue50.X, 0, vectorValue50.Z)

        if vectorValue59.Magnitude > 0.001 then
            vectorValue59 = vectorValue59.Unit
            local vectorValue12 = (recoveredValue125 == 1) and vectorValue59 or -vectorValue59


            if (Config.moonwalkMode or "Classic") == "Classic" then
                alignOrientation.Responsiveness = 15
                State.stateField24 = 0

                local vectorValue67 = CFrame.lookAt(Vector3.new(0, 0, (0.0)), vectorValue12)


                alignOrientation.CFrame = vectorValue67
            else
                alignOrientation.Responsiveness = (65.0)
                local recoveredValue354 = math.atan2(vectorValue12.X, vectorValue12.Z)

                local recoveredValue102 = (0.0)
                if humanoid.MoveDirection.Magnitude > 0.01 then
                    local recoveredValue260 = Config.moonwalkSwaySpeed or (6.0)
                    local recoveredValue52 = Config.moonwalkSwayWidth or 0.55
                    local recoveredValue383 = 0.06
                    local interval = 1.2 / recoveredValue260
                    if tick() - State.timeValue2 >= interval then
                        State.timeValue2 = tick()
                        State.stateField111 = -State.stateField111
                    end
                    local recoveredValue393 = State.stateField111 * recoveredValue52
                    local recoveredValue71 = math.clamp(recoveredValue206 * 14, 0, 1)
                    State.stateField24 = State.stateField24 + (recoveredValue393 - State.stateField24) * recoveredValue71
                    local recoveredValue25 = (math.random() - 0.5) * recoveredValue383
                    recoveredValue102 = State.stateField24 + recoveredValue25
                else
                    State.stateField24 = 0
                    recoveredValue102 = 0
                end

                local cframeValue11 = recoveredValue354 + recoveredValue102
                local vectorValue67 = CFrame.Angles(0, cframeValue11, 0)
                alignOrientation.CFrame = vectorValue67
            end
        end
    end)
end

local function StartGodMode()
    State.stateField12 = true; State.humanoid4 = nil

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)

        pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false) end)
        pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
    end
end

local function StopGodMode()
    State.stateField12 = false; State.humanoid4 = nil

    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true) end)
        pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true) end)
        pcall(function() humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true) end)
    end
end

RegisterUpdateTask("GodMode", 0.2, function()
    if not State.stateField12 then return end
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local humanoid11 = humanoid.MaxHealth
    local recoveredValue415 = humanoid.Health
    if State.humanoid4 ~= nil and recoveredValue415 < State.humanoid4 and recoveredValue415 > 0 then
        pcall(function() humanoid.Health = humanoid11 end)
    end
    State.humanoid4 = humanoid.Health
    pcall(function()
        local vectorValue6 = humanoid:GetState()
        if vectorValue6 == Enum.HumanoidStateType.Dead then
            humanoid.Health = humanoid11; humanoid:ChangeState(Enum.HumanoidStateType.Running); State.humanoid4 = humanoid11
        elseif vectorValue6 == Enum.HumanoidStateType.Ragdoll or vectorValue6 == Enum.HumanoidStateType.FallingDown then
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
end)

local HelperFunction187
do
        local cache5 = { active = false, target = nil, generator = nil }
    local recoveredValue257
    local recoveredValue237
    do
        local remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage

        local function resolveKingScourgeRemote(remoteName)
            local killerPerks = remotes:FindFirstChild("KillerPerks", true)
            local kingScourge = killerPerks and killerPerks:FindFirstChild("kingscourge", true)
            return (kingScourge and FindRemoteEvent(kingScourge, remoteName))
                or FindRemoteEvent(remotes, remoteName)
        end

        local function bindStart(candidate)
            if recoveredValue257 or not (candidate and candidate:IsA("RemoteEvent")) then return end
            recoveredValue257 = candidate
            recoveredValue257.OnClientEvent:Connect(function(recoveredValue343, remote18, hitCount)
                cache5.active = true; cache5.target = remote18; cache5.generator = recoveredValue343
            end)
        end

        local function bindEnd(candidate)
            if recoveredValue237 or not (candidate and candidate:IsA("RemoteEvent")) then return end
            recoveredValue237 = candidate
            recoveredValue237.OnClientEvent:Connect(function()
                cache5.active = false; cache5.target = nil; cache5.generator = nil
            end)
        end

        bindStart(resolveKingScourgeRemote("KingScourgeStart"))
        bindEnd(resolveKingScourgeRemote("KingScourgeEnd"))
        ReplicatedStorage.DescendantAdded:Connect(function(instance)
            if instance.Name == "KingScourgeStart" then bindStart(instance) end
            if instance.Name == "KingScourgeEnd" then bindEnd(instance) end
        end)
    end

    local function HelperFunction196()
        for _, name in ipairs({"SkillCheckPromptGui", "SkillCheckPromptGui-con"}) do
            local gui = PlayerGui:FindFirstChild(name, true)
            if gui then
                local recoveredValue154 = gui:FindFirstChild("Check", true)
                if recoveredValue154 and recoveredValue154.Visible then
                    return recoveredValue154:FindFirstChild("Line", true), recoveredValue154:FindFirstChild("Goal", true)
                end
            end
        end
    end

    local button4 = nil
    local function HelperFunction137()
        if button4 and button4.Parent then return button4 end
        local recoveredValue242 = PlayerGui:FindFirstChild("Survivor-mob", true)
        if not recoveredValue242 then return nil end
        local recoveredValue118 = recoveredValue242:FindFirstChild("Controls", true)
        if not recoveredValue118 then return nil end
        local button3 = recoveredValue118:FindFirstChild("action")
        if button3 and button3:IsA("GuiButton") then button4 = button3; return button3 end
        button3 = recoveredValue118:FindFirstChild("Gui-mob")
        if button3 and button3:IsA("GuiButton") then button4 = button3; return button3 end
        return nil
    end

    function HelperFunction187()
        local recoveredValue314 = HelperFunction137()
        if recoveredValue314 and type(firesignal) == "function" then
            firesignal(recoveredValue314.MouseButton1Down)
            task.delay(0.05, function()
                if recoveredValue314 and recoveredValue314.Parent then
                    firesignal(recoveredValue314.MouseButton1Up)
                    firesignal(recoveredValue314.MouseButton1Click)
                end
            end)
            return
        end
        local recoveredValue274 = PlayerGui:FindFirstChild("check", true)
        if recoveredValue274 and recoveredValue274:IsA("GuiObject") and recoveredValue274.Visible then
            local targetPlayer = recoveredValue274.AbsolutePosition; local recoveredValue236 = recoveredValue274.AbsoluteSize
            local recoveredValue374 = GuiService:GetGuiInset()
            local recoveredValue286 = targetPlayer.X + (recoveredValue236.X / 2) + recoveredValue374.X; local recoveredValue173 = targetPlayer.Y + (recoveredValue236.Y / (2.0)) + recoveredValue374.Y
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(recoveredValue286, recoveredValue173, 0, true, game, 1)
                task.wait(0.01)
                VirtualInputManager:SendMouseButtonEvent(recoveredValue286, recoveredValue173, 0, false, game, 1)
            end)
        else
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            task.wait()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        end
    end

    RegisterUpdateTask("Generator", 0, function()
        if not Config.autoGeneratorEnabled then return end
        local frame13, goal = HelperFunction196()
        if not (frame13 and goal) then
            State.stateField69 = false
            State.lastGoalRot = nil
            State.prevLr = nil
            return
        end

        local recoveredValue97 = goal.Rotation
        local recoveredValue53 = frame13.Rotation
        local timeValue12 = tick()


        local recoveredValue186 = cache5.active and 0.05 or 0.1
        if timeValue12 - State.stateField48 < recoveredValue186 then
            State.prevLr = recoveredValue53
            return
        end

        if Config.autoGeneratorMode == "Instant" then

            if not State.stateField69 or recoveredValue97 ~= State.lastGoalRot then
                frame13.Rotation = recoveredValue97 + 109
                State.lastGoalRot = recoveredValue97
                State.stateField69 = true
                State.stateField48 = timeValue12
                State.stateField7 = timeValue12
                HelperFunction187()
            end

        else

            local distanceValue20 = (recoveredValue53 - recoveredValue97) % (360.0)


            local recoveredValue371 = -1
            if State.prevLr and State.lastGoalRot == recoveredValue97 then
                recoveredValue371 = (State.prevLr - recoveredValue97) % 360
            end
            State.lastGoalRot = recoveredValue97

            local recoveredValue419, zoneEnd
            if Config.autoGeneratorMode == "Perfect" then

                recoveredValue419 = 102
                zoneEnd = 116
            elseif Config.autoGeneratorMode == "Normal" then

                recoveredValue419 = (116.0)
                zoneEnd = 159
            elseif Config.autoGeneratorMode == "Random" then
                if not State.stateField75 then
                    recoveredValue419 = (102.0); zoneEnd = (116.0)
                else
                    recoveredValue419 = 116; zoneEnd = (159.0)
                end
            else
                return
            end


            local recoveredValue191 = distanceValue20 >= recoveredValue419 and distanceValue20 <= zoneEnd


            local recoveredValue229 = recoveredValue371 >= (0.0) and recoveredValue371 < recoveredValue419 and distanceValue20 > zoneEnd

            if recoveredValue191 or recoveredValue229 then
                if recoveredValue229 then

                    frame13.Rotation = recoveredValue97 + (recoveredValue419 + zoneEnd) / 2
                end

                State.stateField48 = timeValue12
                State.stateField7 = timeValue12
                HelperFunction187()


                if Config.autoGeneratorMode == "Random" then
                    State.stateField75 = not State.stateField75
                end
            end
        end

        State.prevLr = recoveredValue53
    end)

    RegisterUpdateTask("GenBtnRefresh", 2.0, function()
        if not Config.autoGeneratorEnabled then return end
        if not button4 or not button4.Parent then HelperFunction137() end
    end)
end

function IsGeneratorPoint(instance)
    if not instance then return false end
    local attributeValue31 = instance:GetAttribute("OriginalName")
    if attributeValue31 and string.find(tostring(attributeValue31):lower(), "generatorpoint") then return true end
    if string.find(instance.Name, "^GeneratorPoint%d+$") then return true end
    return false
end

function CollectGeneratorPoints(recoveredValue343)
    local cache20 = {}
    if not recoveredValue343 then return cache20 end
    local cache43 = {}
    local function HelperFunction169(instance)
        if cache43[instance] then return end
        if IsGeneratorPoint(instance) then
            cache43[instance] = true
            table.insert(cache20, instance)
        end
    end
    local function HelperFunction101(parentObject)
        for _, child in ipairs(parentObject:GetChildren()) do
            HelperFunction169(child)
            HelperFunction101(child)
        end
    end
    HelperFunction101(recoveredValue343)
    table.sort(cache20, function(attributeValue12, attributeValue22)
        local attributeValue7 = attributeValue12:GetAttribute("OriginalName") or attributeValue12.Name
        local attributeValue14 = attributeValue22:GetAttribute("OriginalName") or attributeValue22.Name
        return tostring(attributeValue7) < tostring(attributeValue14)
    end)
    return cache20
end

function FindGenForPoint(remote18)
    if not remote18 then return nil end
    local recoveredValue59 = remote18
    for _ = 1, 6 do
        local parentObject = recoveredValue59.Parent
        if not parentObject then break end
        if parentObject:IsA("Model") or parentObject:IsA("Folder") then
            local name = parentObject.Name:lower()
            if string.find(name, "generator") or string.find(name, "gens") then
                return parentObject
            end
            for _, child in ipairs(parentObject:GetChildren()) do
                if IsGeneratorPoint(child) then return parentObject end
            end
        end
        recoveredValue59 = parentObject
    end
    for _, recoveredValue343 in ipairs(State.worldEspObjects.Generators) do
        if recoveredValue343 and recoveredValue343.Parent and remote18:IsDescendantOf(recoveredValue343) then return recoveredValue343 end
    end
    return nil
end

function GetAllGenerators()
    local cache39 = {}
    local cache43 = {}
    local function HelperFunction126(recoveredValue343)
        if recoveredValue343 and recoveredValue343.Parent and not cache43[recoveredValue343] then
            cache43[recoveredValue343] = true
            table.insert(cache39, recoveredValue343)
        end
    end
    for _, recoveredValue343 in ipairs(State.worldEspObjects.Generators) do HelperFunction126(recoveredValue343) end
    local recoveredValue363 = workspace:FindFirstChild("Map")
    if recoveredValue363 then
        for _, recoveredValue100 in ipairs({"Generators", "Generator", "Gens"}) do
            local recoveredValue122 = recoveredValue363:FindFirstChild(recoveredValue100)
            if recoveredValue122 then
                for _, recoveredValue343 in ipairs(recoveredValue122:GetChildren()) do HelperFunction126(recoveredValue343) end
            end
        end
    end
    return cache39
end

function GetPointPosition(remote18)
    if remote18:IsA("BasePart") then return remote18.Position end
    local part = remote18:FindFirstChildWhichIsA("BasePart")
    if part then return part.Position end
    return nil
end

function PerformGenBoost()
    task.spawn(function()
        local success, err = pcall(function()
            local char = LocalPlayer.Character
            if not char then
                Notify("GenBoost", "Character not found!", 2)
                return
            end
            local rootPart16 = char:FindFirstChild("HumanoidRootPart")
            if not rootPart16 then
                Notify("GenBoost", "Character HumanoidRootPart not found!", 2)
                return
            end

            local attributeValue19 = char:FindFirstChild("CheckInterractable")
            local attributeValue27 = attributeValue19 and attributeValue19:GetAttribute("isRepairing") or false
            if not attributeValue27 then
                Notify("GenBoost", "Repair a generator first!", 2)
                return
            end

            local cache39 = GetAllGenerators()
            local recoveredValue276 = nil
            local closestDistance = math.huge
            for _, recoveredValue343 in ipairs(cache39) do
                for _, remote18 in ipairs(CollectGeneratorPoints(recoveredValue343)) do
                    local pos = GetPointPosition(remote18)
                    local dist = pos and (pos - rootPart16.Position).Magnitude or math.huge
                    if dist < closestDistance then
                        closestDistance = dist
                        recoveredValue276 = remote18
                    end
                end
            end

            local recoveredValue343 = recoveredValue276 and FindGenForPoint(recoveredValue276)
            if not recoveredValue343 then
                local recoveredValue407 = nil
                local distanceValue56 = math.huge
                for _, textLabel4 in ipairs(cache39) do
                    for _, remote18 in ipairs(CollectGeneratorPoints(textLabel4)) do
                        local pos = GetPointPosition(remote18)
                        local dist = pos and (pos - rootPart16.Position).Magnitude or math.huge
                        if dist < distanceValue56 then
                            distanceValue56 = dist
                            recoveredValue407 = remote18
                        end
                    end
                end
                if recoveredValue407 then
                    recoveredValue276 = recoveredValue407
                    recoveredValue343 = FindGenForPoint(recoveredValue407)
                end
            end

            if not recoveredValue343 then
                Notify("GenBoost", "Could not find current generator!", 2)
                return
            end

            local cache20 = CollectGeneratorPoints(recoveredValue343)
            if #cache20 == 0 then
                Notify("GenBoost", "No generator points resolved!", 2)
                return
            end

            local remotesRoot = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage
            local generatorFolder = remotesRoot:FindFirstChild("Generator", true)
            local remote5 = (generatorFolder and FindRemoteEvent(generatorFolder, "RepairEvent"))
                or FindRemoteEvent(remotesRoot, "RepairEvent")
            if not remote5 then
                Notify("GenBoost", "RepairEvent remote not found!", 2)
                return
            end

            local remote28 = recoveredValue276
            local rootPart9 = false
            for _, targetPlayer in ipairs(cache20) do
                if targetPlayer == remote28 then rootPart9 = true break end
            end
            if not remote28 or not rootPart9 then remote28 = cache20[1] end

            for _, targetPlayer in ipairs(cache20) do
                if targetPlayer ~= remote28 then
                    remote5:FireServer(targetPlayer, true)
                    task.wait(0.4)
                    remote5:FireServer(remote28, true)
                    task.wait(0.15)
                    remote5:FireServer(remote28, false)
                    task.wait(0.15)
                end
            end
            for _, targetPlayer in ipairs(cache20) do
                if targetPlayer ~= remote28 then
                    remote5:FireServer(targetPlayer, true)
                    task.wait(0.3)
                end
            end
            remote5:FireServer(remote28, false)
            task.wait(0.2)
            local vectorValue60 = GetPointPosition(remote28)
            if vectorValue60 and rootPart16 then
                pcall(function() rootPart16.Anchored = false end)
                pcall(function() rootPart16.CFrame = CFrame.new(vectorValue60 + Vector3.new(0, 1.5, 0)) end)
            end
            task.wait(0.3)
            pcall(HelperFunction187)

            Notify("GenBoost", "Successfully applied generator Boost!", 2)
        end)
        if not success then
            Notify("GenBoost", "Critical Error: " .. tostring(err), 2)
        end
    end)
end

function DestroyGenBoostButton()
    if State.cachedHumanoid then
        pcall(function() State.cachedHumanoid:Disconnect() end)
        State.cachedHumanoid = nil
    end
    if State.genBoostHoverConnections then
        for _, connection in ipairs(State.genBoostHoverConnections) do
            pcall(function() connection:Disconnect() end)
        end
        State.genBoostHoverConnections = {}
    end
    if State.cachedCharacter then
        pcall(function() State.cachedCharacter:Destroy() end)
        State.cachedCharacter = nil
    end
end

function BuildGenBoostGui()
    if State.cachedCharacter and State.cachedCharacter.Parent then return end
    DestroyGenBoostButton()

    local uiRoot = nil
    local mainGui = nil
    local candidates = {}
    pcall(function()
        if type(gethui) == "function" then
            local h = gethui()
            if typeof(h) == "Instance" then table.insert(candidates, h) end
        end
    end)
    pcall(function() table.insert(candidates, game:GetService("CoreGui")) end)
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui")
    if pg then table.insert(candidates, pg) end
    for _, candidate in ipairs(candidates) do
        if candidate and candidate.Parent then
            local found = candidate:FindFirstChild("BlehHub_ViolenceDistrict_UI")
            if found then
                uiRoot = candidate
                mainGui = found
                break
            end
        end
    end
    uiRoot = uiRoot or pg
    if not uiRoot then return end

    local old = uiRoot:FindFirstChild("BlehHub_VD_HoverGenBoost")
    if old then pcall(function() old:Destroy() end) end

    local C = {
        SURFACE = Color3.fromRGB(17, 20, 42),
        ELEVATED = Color3.fromRGB(27, 29, 58),
        BORDER = Color3.fromRGB(51, 54, 93),
        TEXT_1 = Color3.fromRGB(240, 241, 255),
        ACCENT = Color3.fromRGB(150, 88, 255),
    }

    local gui = Instance.new("ScreenGui")
    gui.Name = "BlehHub_VD_HoverGenBoost"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 2147482999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = uiRoot
    State.cachedCharacter = gui
    State.genBoostHoverConnections = {}

    local hoverFrame = Instance.new("Frame")
    hoverFrame.Name = "HoverGenBoost"
    hoverFrame.Size = UDim2.fromOffset(148, 44)
    hoverFrame.BackgroundColor3 = C.SURFACE
    hoverFrame.BorderSizePixel = 0
    hoverFrame.Parent = gui
    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 9)
    frameCorner.Parent = hoverFrame
    local frameStroke = Instance.new("UIStroke")
    frameStroke.Color = C.BORDER
    frameStroke.Thickness = 1
    frameStroke.Parent = hoverFrame

    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 3, 0, 24)
    accent.Position = UDim2.new(0, 0, 0.5, -12)
    accent.BackgroundColor3 = C.ACCENT
    accent.BorderSizePixel = 0
    accent.Parent = hoverFrame
    local accentCorner = Instance.new("UICorner")
    accentCorner.CornerRadius = UDim.new(0, 2)
    accentCorner.Parent = accent

    local button = Instance.new("TextButton")
    button.Name = "GenBoostButton"
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundTransparency = 1
    button.BorderSizePixel = 0
    button.Text = "GenBoost"
    button.TextColor3 = C.TEXT_1
    button.Font = Enum.Font.GothamBold
    button.TextSize = 11
    button.AutoButtonColor = false
    button.Parent = hoverFrame

    local function clampToViewport(x, y)
        local camera = Workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
        local w, h = 148, 44
        return math.clamp(x, 6, math.max(6, viewport.X - w - 6)),
               math.clamp(y, 6, math.max(6, viewport.Y - h - 6))
    end

    local function placeBesideMainMenu()
        local x, y = 0, 0
        local rootFrame = mainGui and mainGui:FindFirstChildWhichIsA("Frame")
        if rootFrame and rootFrame.Parent then
            local pos = rootFrame.AbsolutePosition
            local size = rootFrame.AbsoluteSize
            x = pos.X + size.X + 12
            y = pos.Y + 60

            local hoverUnhookGui = uiRoot:FindFirstChild("BlehHub_VD_HoverUnhook")
            local hoverUnhookFrame = hoverUnhookGui and hoverUnhookGui:FindFirstChild("HoverUnhook")
            if hoverUnhookFrame and hoverUnhookFrame.Parent then
                local hp = hoverUnhookFrame.AbsolutePosition
                x = hp.X
                y = hp.Y + hoverUnhookFrame.AbsoluteSize.Y + 8
            end

            local camera = Workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
            if x + 148 > viewport.X - 6 then
                x = pos.X - 160
            end
        else
            local camera = Workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
            x = (viewport.X * 0.5) + 242
            y = (viewport.Y * 0.5) - 134
        end
        x, y = clampToViewport(x, y)
        hoverFrame.Position = UDim2.fromOffset(x, y)
    end

    task.defer(function()
        pcall(function() RunService.RenderStepped:Wait() end)
        if hoverFrame.Parent then placeBesideMainMenu() end
    end)

    local dragging = false
    local moved = false
    local dragStart = Vector2.new()
    local startPosition = UDim2.new()

    table.insert(State.genBoostHoverConnections, button.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = input.Position
            startPosition = hoverFrame.Position
        end
    end))

    table.insert(State.genBoostHoverConnections, UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - dragStart
        if delta.Magnitude >= 5 then moved = true end
        local x = startPosition.X.Offset + delta.X
        local y = startPosition.Y.Offset + delta.Y
        x, y = clampToViewport(x, y)
        hoverFrame.Position = UDim2.fromOffset(x, y)
    end))

    table.insert(State.genBoostHoverConnections, UserInputService.InputEnded:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging = false
        if not moved then
            pcall(PerformGenBoost)
            hoverFrame.BackgroundColor3 = C.ACCENT
            task.delay(0.22, function()
                if hoverFrame and hoverFrame.Parent then hoverFrame.BackgroundColor3 = C.SURFACE end
            end)
        end
    end))

    table.insert(State.genBoostHoverConnections, button.MouseEnter:Connect(function()
        if hoverFrame.Parent then hoverFrame.BackgroundColor3 = C.ELEVATED end
    end))
    table.insert(State.genBoostHoverConnections, button.MouseLeave:Connect(function()
        if hoverFrame.Parent and not dragging then hoverFrame.BackgroundColor3 = C.SURFACE end
    end))
end

function CreateGenBoostButton()
    if State.cachedCharacter and State.cachedCharacter.Parent then return end
    BuildGenBoostGui()
end

RegisterUpdateTask("KillerWarn", 0.1, function()
    if not Config.killerWarningEnabled then
        local rootPart4 = LocalPlayer.Character
        local rootPart13 = rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")
        if rootPart13 then
            local recoveredValue103 = rootPart13:FindFirstChild("KillerWarn")
            if recoveredValue103 then recoveredValue103:Destroy() end
        end
        return
    end
    local rootPart4 = LocalPlayer.Character
    local rootPart13 = rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")
    if not rootPart13 then return end
    local colorValue5 = math.huge
    for player, espEntry in pairs(State.espObjects) do
        if player and player.Parent then
            local distanceValue19 = GetPlayerRole(player)
            if distanceValue19 == "killer" then
                local char = player.Character
                local rootPart2 = char and char:FindFirstChild("HumanoidRootPart")
                if rootPart2 then
                    local dist = (rootPart2.Position - rootPart13.Position).Magnitude
                    if dist < colorValue5 then colorValue5 = dist end
                end
            end
        end
    end
    local recoveredValue103 = rootPart13:FindFirstChild("KillerWarn")
    if colorValue5 <= Config.warnDist1 then
        local colorValue10, col
        if colorValue5 <= Config.warnDist3 then colorValue10 = "!!!"; col = Color3.fromRGB(255, 0, (0.0))
        elseif colorValue5 <= Config.warnDist2 then colorValue10 = "!!"; col = Color3.fromRGB(255, 80, 0)
        else colorValue10 = "!"; col = Color3.fromRGB(255, 160, 0) end
        if not recoveredValue103 then
            recoveredValue103 = CreateBillboardTag(colorValue10, col, UDim2.new(0, (40.0), 0, 40), 22)
            recoveredValue103.Name = "KillerWarn"; recoveredValue103.Parent = rootPart13
        else
            recoveredValue103.Label.Text = colorValue10; recoveredValue103.Label.TextColor3 = col
        end
    elseif recoveredValue103 then
        recoveredValue103:Destroy()
    end
end)

local StartStunTimer, StopStunTimer
do
    local cache = { StunAnimation=true, WallHitStun=true, WallHitStun2=true, WipeMachete=true, Parried=true }

    local cache2 = {
        stunnedvm = "rbxassetid://108650759135855",
        parriedvm = "rbxassetid://87457855797515",
        wallhitvm = "rbxassetid://109632692854327",
        wipevm = "rbxassetid://71906161598748",
    }
    local colorValue8 = Color3.fromRGB(255, 220, 60)
    State.stunTimerPulse = 0


    local function HelperFunction75()
        if State.stunTimerLens.stunnedvm then return true end
        local recoveredValue400 = nil
        pcall(function()
            local char = LocalPlayer.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            if humanoid then recoveredValue400 = humanoid:FindFirstChildOfClass("Animator") end
        end)
        if not recoveredValue400 then return false end
        for recoveredValue222, recoveredValue72 in pairs(cache2) do
            if not State.stunTimerLens[recoveredValue222] then
                pcall(function()
                    local animation2 = Instance.new("Animation")
                    animation2.AnimationId = recoveredValue72
                    local recoveredValue360 = recoveredValue400:LoadAnimation(animation2)
                    if recoveredValue360 and recoveredValue360.Length and recoveredValue360.Length > 0 then
                        State.stunTimerLens[recoveredValue222] = recoveredValue360.Length
                    end
                    pcall(function() animation2:Destroy() end)
                end)
            end
        end
        return State.stunTimerLens.stunnedvm ~= nil
    end

    local function RetryStunTimerSetup()
        task.spawn(function()
            for _ = 1, (5.0) do
                if not State.stunTimerEnabled then return end
                local success = false
                pcall(function() success = HelperFunction75() end)
                if success then return end
                task.wait(2)
            end
        end)
    end


    local function HelperFunction163(dur)
        if not dur or dur <= 0 then return end
        local timeValue6 = tick() + dur
        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            if targetPlayer ~= LocalPlayer and targetPlayer.Parent and GetPlayerRole(targetPlayer) == "killer" then
                local cur = State.stunTimerForced[targetPlayer]
                if not cur or cur < timeValue6 then
                    State.stunTimerForced[targetPlayer] = timeValue6
                end
            end
        end
    end

    local function HelperFunction110(player)
        local billboardGui = State.stunTimerBoards[player]
        if billboardGui then pcall(function() billboardGui:Destroy() end) end
        State.stunTimerBoards[player] = nil
        State.stunTimerForced[player] = nil
        State.stunTimerAnim[player] = nil
    end

    local function ClearStunTimerBoards()
        local cache38 = {}
        for player, _ in pairs(State.stunTimerBoards) do cache38[#cache38 + (1.0)] = player end
        for index = 1, #cache38 do HelperFunction110(cache38[index]) end
        for player, _ in pairs(State.stunTimerForced) do State.stunTimerForced[player] = nil end
        State.stunTimerPulse = 0
    end

    local function HelperFunction17(player, char)
        local attributeValue7 = State.stunTimerAnim[player]
        if attributeValue7 and attributeValue7.Parent then return attributeValue7 end
        attributeValue7 = nil
        pcall(function()
            local humanoid = char:FindFirstChildOfClass("Humanoid")
            if humanoid then attributeValue7 = humanoid:FindFirstChildOfClass("Animator") end
        end)
        State.stunTimerAnim[player] = attributeValue7
        return attributeValue7
    end

    local function HelperFunction40(player, char)
        local recoveredValue400 = HelperFunction17(player, char)
        if not recoveredValue400 then return 0 end
        local success, tracks = pcall(function() return recoveredValue400:GetPlayingAnimationTracks() end)
        if not success or type(tracks) ~= "table" then return 0 end
        local distanceValue60 = (0.0)
        for index = (1.0), #tracks do
            local recoveredValue360 = tracks[index]
            local nm = nil
            local recoveredValue416 = 1
            local recoveredValue221, recoveredValue177, pos = false, 0, 0
            pcall(function()
                nm = recoveredValue360.Name
                local attributeValue12 = recoveredValue360.Animation
                if attributeValue12 then
                    if not cache[nm] and attributeValue12.Name and cache[attributeValue12.Name] then
                        nm = attributeValue12.Name
                    end

                    if not cache[nm] and attributeValue12.AnimationId then
                        local id = tostring(attributeValue12.AnimationId)
                        for _, recoveredValue72 in pairs(cache2) do
                            if id == recoveredValue72 or id:find(recoveredValue72:match("%d+"), 1, true) then
                                nm = "__vmid__"
                                break
                            end
                        end
                    end
                end
                recoveredValue221 = recoveredValue360.IsPlaying
                recoveredValue177 = recoveredValue360.Length or 0
                pos = recoveredValue360.TimePosition or 0
                recoveredValue416 = recoveredValue360.Speed or 1
            end)
            if nm and (cache[nm] or nm == "__vmid__") and recoveredValue221 then
                if recoveredValue416 == 0 then recoveredValue416 = 1 end
                local recoveredValue143 = (recoveredValue177 - pos) / math.abs(recoveredValue416)
                if recoveredValue143 > distanceValue60 then distanceValue60 = recoveredValue143 end
            end
        end


        return distanceValue60
    end

    local function HelperFunction51(player, rootPart19)
        local billboardGui = State.stunTimerBoards[player]
        if billboardGui and billboardGui.Parent and billboardGui.Adornee and billboardGui.Adornee.Parent then
            if billboardGui.Adornee ~= rootPart19 then
                pcall(function() billboardGui.Adornee = rootPart19 end)
            end
            return billboardGui
        end
        if billboardGui then pcall(function() billboardGui:Destroy() end) end
        billboardGui = CreateBillboardTag("Stun 0.0s", colorValue8, UDim2.new(0, 110, 0, 30), 18)
        billboardGui.Name = "StunTimer"
        pcall(function() billboardGui.MaxDistance = State.warningMaxDistance end)
        pcall(function()
            billboardGui.Adornee = rootPart19
            billboardGui.Parent = rootPart19
            billboardGui:SetAttribute("__t", "")
        end)
        State.stunTimerBoards[player] = billboardGui
        return billboardGui
    end

    local function SetupStunTimerRemotes()
        if State.stateField53 then return end
        State.stateField53 = true
        pcall(function()
            local remote10 = ReplicatedStorage:FindFirstChild("Remotes")
            if not remote10 then return end
            local attributeValue2 = remote10:FindFirstChild("Pallet")
            local recoveredValue434 = attributeValue2 and attributeValue2:FindFirstChild("Jason")
            local remote20 = recoveredValue434 and recoveredValue434:FindFirstChild("Stun")
            if remote20 and remote20:IsA("RemoteEvent") then
                table.insert(State.stunTimerConns, remote20.OnClientEvent:Connect(function()
                    if State.stunTimerEnabled then
                        State.stunTimerPulse = tick()

                        if not State.stunTimerLens.stunnedvm then RetryStunTimerSetup() end
                        HelperFunction163(State.stunTimerLens.stunnedvm or 2.5)
                    end
                end))
            end
            local remote31 = recoveredValue434 and recoveredValue434:FindFirstChild("Stunover")
            if remote31 and remote31:IsA("RemoteEvent") then
                table.insert(State.stunTimerConns, remote31.OnClientEvent:Connect(function()
                    if State.stunTimerEnabled then
                        for player, _ in pairs(State.stunTimerForced) do State.stunTimerForced[player] = nil end
                        ClearStunTimerBoards()
                    end
                end))
            end
            local recoveredValue19 = remote10:FindFirstChild("Attacks")
            local remote24 = recoveredValue19 and recoveredValue19:FindFirstChild("AfterAttack")
            if remote24 and remote24:IsA("RemoteEvent") then
                table.insert(State.stunTimerConns, remote24.OnClientEvent:Connect(function(atkType)
                    if not State.stunTimerEnabled then return end
                    if atkType == "Parried" then
                        for _, targetPlayer in ipairs(Players:GetPlayers()) do
                            if targetPlayer ~= LocalPlayer and targetPlayer.Parent and GetPlayerRole(targetPlayer) == "killer" then
                                State.stunTimerForced[targetPlayer] = tick() + 4
                            end
                        end
                    elseif atkType == "WallHitStun" or atkType == "WallHitStun2" then
                        State.stunTimerPulse = tick()
                        if not State.stunTimerLens.wallhitvm then RetryStunTimerSetup() end
                        HelperFunction163(State.stunTimerLens.wallhitvm or 2.5)
                    elseif atkType == "WipeMachete" then
                        State.stunTimerPulse = tick()
                        if not State.stunTimerLens.wipevm then RetryStunTimerSetup() end
                        HelperFunction163(State.stunTimerLens.wipevm or 2.5)
                    end
                end))
            end
            local recoveredValue402 = remote10:FindFirstChild("Killers")
            local recoveredValue157 = recoveredValue402 and recoveredValue402:FindFirstChild("Hidden")
            local recoveredValue356 = recoveredValue157 and recoveredValue157:FindFirstChild("endlag")
            if recoveredValue356 and recoveredValue356:IsA("BindableEvent") then
                table.insert(State.stunTimerConns, recoveredValue356.Event:Connect(function()
                    if State.stunTimerEnabled then
                        State.stunTimerPulse = tick()
                        if not State.stunTimerLens.wipevm then RetryStunTimerSetup() end
                        HelperFunction163(State.stunTimerLens.wipevm or 2.5)
                    end
                end))
            end


            local recoveredValue119 = remote10:FindFirstChild("Game")
            local remote6 = recoveredValue119 and recoveredValue119:FindFirstChild("PlayerActionEvent")
            if remote6 and remote6:IsA("RemoteEvent") then
                table.insert(State.stunTimerConns, remote6.OnClientEvent:Connect(function(message)
                    if State.stunTimerEnabled and message == "Stunned the Killer" then
                        State.stunTimerPulse = tick()
                        if not State.stunTimerLens.stunnedvm then RetryStunTimerSetup() end
                        HelperFunction163(State.stunTimerLens.stunnedvm or 2.5)
                    end
                end))
            end
        end)
    end

    function StartStunTimer()
        State.stunTimerEnabled = true
        SetupStunTimerRemotes()
        RetryStunTimerSetup()
    end

    function StopStunTimer()
        State.stunTimerEnabled = false
        ClearStunTimerBoards()
    end

    RegisterUpdateTask("StunTimer", 0.1, function()
        if not State.stunTimerEnabled then
            if next(State.stunTimerBoards) ~= nil then ClearStunTimerBoards() end
            return
        end
        local rootPart4 = LocalPlayer.Character
        local rootPart13 = rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")
        local vectorValue24 = nil
        if rootPart13 then
            vectorValue24 = rootPart13.Position
        else
            local camera = workspace.CurrentCamera
            if camera then vectorValue24 = camera.CFrame.Position end
        end
        if not vectorValue24 then return end
        local timeValue12 = tick()
        local distanceValue27 = State.warningMaxDistance
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Parent and GetPlayerRole(player) == "killer" then
                local char = player.Character
                local rootPart19 = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
                if char and char.Parent and rootPart19 and rootPart19.Parent then
                    local dist = (rootPart19.Position - vectorValue24).Magnitude
                    if dist <= distanceValue27 then
                        local recoveredValue300 = 0
                        local recoveredValue145 = State.stunTimerForced[player]
                        if recoveredValue145 and recoveredValue145 > timeValue12 then recoveredValue300 = recoveredValue145 - timeValue12 end
                        local recoveredValue298 = HelperFunction40(player, char)
                        if recoveredValue298 > recoveredValue300 then recoveredValue300 = recoveredValue298 end
                        if recoveredValue300 > 0.05 then
                            local billboardGui = HelperFunction51(player, rootPart19)
                            if billboardGui then
                                if not billboardGui.Enabled then billboardGui.Enabled = true end
                                local colorValue10 = string.format("Stun %.1fs", recoveredValue300)
                                local attributeValue5 = billboardGui:GetAttribute("__t")
                                if attributeValue5 ~= colorValue10 then
                                    billboardGui:SetAttribute("__t", colorValue10)
                                    local textLabel = billboardGui:FindFirstChild("Label")
                                    if textLabel then textLabel.Text = colorValue10 end
                                end
                            end
                        else
                            if timeValue12 - (State.stunTimerPulse or 0) > 0.35 then
                                HelperFunction110(player)
                            end
                        end
                    else
                        local billboardGui = State.stunTimerBoards[player]
                        if billboardGui and billboardGui.Enabled then billboardGui.Enabled = false end
                    end
                else
                    HelperFunction110(player)
                end
            end
        end
        local recoveredValue353 = nil
        for player, _ in pairs(State.stunTimerBoards) do
            if not player.Parent then
                recoveredValue353 = recoveredValue353 or {}
                recoveredValue353[#recoveredValue353 + 1] = player
            end
        end
        if recoveredValue353 then
            for index = (1.0), #recoveredValue353 do HelperFunction110(recoveredValue353[index]) end
        end
    end)
end

RegisterUpdateTask("ESPValidator", 1, function()
    if not EspFolder or not EspFolder.Parent then
        ForceRefreshAllESP()
        return
    end
    for player, _ in pairs(State.espObjects) do
        ValidateAndReattachESP(player)
    end
    for player, _ in pairs(State.outlineObjects) do
        if not State.espObjects[player] then
            ValidateAndReattachESP(player)
        end
    end
end)

RegisterUpdateTask("EspDistCull", 0.25, function()
    if State.espObjects then HelperFunction125() end
end)

RegisterUpdateTask("ItemESP", 0.2, function()
    if not Config.showEquippedItem then
        for _, espEntry in pairs(State.espObjects) do
            if espEntry and espEntry.itemImage and espEntry.itemImage.Visible then
                espEntry.itemImage.Visible = false
            end
        end
        return
    end

    local rootPart4 = LocalPlayer.Character
    local rootPart6 = rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")

    for player, espEntry in pairs(State.espObjects) do
        if espEntry and espEntry.billboard and espEntry.billboard.Parent and espEntry.itemBillboard then


            if GetPlayerRole(player) == "killer" then
                if espEntry.itemImage.Visible then espEntry.itemImage.Visible = false end
                continue
            end

            local char = player.Character
            local recoveredValue148 = nil

            if char then
                local attributeValue11 = char:GetAttribute("EquippedItem") or char:GetAttribute("Equippedltem")
                if type(attributeValue11) == "string" then recoveredValue148 = attributeValue11
                elseif typeof(attributeValue11) == "Instance" then recoveredValue148 = attributeValue11.Name end
            end

            if not recoveredValue148 then
                local attributeValue10 = player:GetAttribute("EquippedItem") or player:GetAttribute("Equippedltem")
                if type(attributeValue10) == "string" then recoveredValue148 = attributeValue10
                elseif typeof(attributeValue10) == "Instance" then recoveredValue148 = attributeValue10.Name end
            end

            local recoveredValue81 = GetItemIconAssetId(recoveredValue148)

            if recoveredValue81 then
                if espEntry.itemImage.Image ~= recoveredValue81 then
                    espEntry.itemImage.Image = recoveredValue81
                end


                if rootPart6 and char then
                    local rootPart21 = char:FindFirstChild("HumanoidRootPart")
                    if rootPart21 then
                        local dist = (rootPart6.Position - rootPart21.Position).Magnitude


                        local size = 1.5 + ((dist / (200.0)) * 2)


                        size = math.clamp(size, 1.5, 3.5)

                        espEntry.itemBillboard.Size = UDim2.new(size, 0, size, 0)
                    end
                end


                espEntry.itemImage.Visible = true
            else
                if espEntry.itemImage.Visible then
                    espEntry.itemImage.Visible = false
                end
            end
        elseif espEntry and espEntry.itemImage then
            if espEntry.itemImage.Visible then espEntry.itemImage.Visible = false end
        end
    end
end)

local RemoveScpESP, GetScpModelRoot, RefreshZombieCache, RefreshScpEsp
local recoveredValue189, zombieCacheTime
do
    local function HelperFunction114(name)
        if type(name) ~= "string" or name == "" then return false end
        local recoveredValue120 = name:lower()
        if recoveredValue120:find("zombie") then return true end
        if recoveredValue120 == "scp" then return true end
        for index = (1.0), 9 do
            if recoveredValue120 == ("scp" .. index) or recoveredValue120:find("^scp%-" .. index) then return true end
        end
        return false
    end

    function RemoveScpESP(rootPart15)
        local distanceValue53 = State.scpEspObjects[rootPart15]
        if distanceValue53 then
            if distanceValue53.highlight and distanceValue53.highlight.Parent then distanceValue53.highlight:Destroy() end
            if distanceValue53.billboard and distanceValue53.billboard.Parent then distanceValue53.billboard:Destroy() end
            State.scpEspObjects[rootPart15] = nil
        end
    end

    local function HelperFunction58(rootPart15)
        local outline = Instance.new("Highlight")
        outline.Name = "__BlehHubScpHl__"; outline.Adornee = rootPart15
        outline.FillColor = Config.scpEspColor; outline.OutlineColor = Config.scpEspColor
        outline.FillTransparency = (1.0); outline.OutlineTransparency = 0
        outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        outline.Enabled = true; outline.Parent = GetEspFolder()

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "__BlehHubScpBb__"; billboard.AlwaysOnTop = true
        billboard.Size = UDim2.new(0, 140, 0, 18)
        billboard.StudsOffset = Vector3.new((0.0), (4.0), (0.0))
        billboard.MaxDistance = Config.scpEspDistance
        billboard.Parent = GetEspFolder()

        local textLabel = Instance.new("TextLabel")
        textLabel.Size = UDim2.new(1, (0.0), 1, 0)
        textLabel.BackgroundTransparency = 1
        textLabel.TextColor3 = Color3.fromRGB(255, 255, (255.0))
        textLabel.TextStrokeTransparency = 0; textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
        textLabel.TextSize = 12; textLabel.Font = Enum.Font.GothamBold
        textLabel.Text = Config.scpEspShowName and "zombie" or ""
        textLabel.Parent = billboard

        State.scpEspObjects[rootPart15] = { highlight = outline, billboard = billboard, label = textLabel }
    end

    function GetScpModelRoot(rootPart15)
        local rootPart2 = rootPart15.PrimaryPart
        if not rootPart2 then
            local rootPart9 = rootPart15:FindFirstChild("HumanoidRootPart")
            if rootPart9 and rootPart9:IsA("BasePart") then rootPart2 = rootPart9 end
        end
        if not rootPart2 then
            for _, child in ipairs(rootPart15:GetChildren()) do
                if child:IsA("BasePart") then rootPart2 = child break end
            end
        end
        return rootPart2
    end

    recoveredValue189 = {}
    zombieCacheTime = 0

    local function HelperFunction129()
        if State._zombieCacheReady then return end
        State._zombieCacheReady = true
        local cache27 = {}
        local function HelperFunction193(rootPart15)
            if not rootPart15:IsA("Model") then return end
            if LocalPlayer.Character and rootPart15 == LocalPlayer.Character then return end
            for _, player2 in ipairs(Players:GetPlayers()) do
                if player2.Character and rootPart15 == player2.Character then return end
            end
            if not HelperFunction114(rootPart15.Name) then return end
            if cache27[rootPart15] then return end
            cache27[rootPart15] = true
            table.insert(recoveredValue189, rootPart15)
            if Config.scpEspEnabled and not State.scpEspObjects[rootPart15] then
                HelperFunction58(rootPart15)
            end
        end
        local function HelperFunction142(rootPart15)
            if not cache27[rootPart15] then return end
            cache27[rootPart15] = nil
            for index, recoveredValue121 in ipairs(recoveredValue189) do
                if recoveredValue121 == rootPart15 then
                    table.remove(recoveredValue189, index)
                    break
                end
            end
            RemoveScpESP(rootPart15)
        end
        Workspace.DescendantAdded:Connect(HelperFunction193)
        Workspace.DescendantRemoving:Connect(HelperFunction142)
        local cache12 = {}
        for _, player2 in ipairs(Players:GetPlayers()) do
            if player2.Character then cache12[player2.Character] = true end
        end
        for _, rootPart15 in ipairs(workspace:GetDescendants()) do
            if rootPart15:IsA("Model") and not cache12[rootPart15] and HelperFunction114(rootPart15.Name) then
                cache27[rootPart15] = true
                table.insert(recoveredValue189, rootPart15)
            end
        end
        zombieCacheTime = tick()
    end
    function RefreshZombieCache()
        HelperFunction129()
        zombieCacheTime = tick()
    end
    pcall(HelperFunction129)

    function RefreshScpEsp()
        if not State.scpEspObjects then return end
        local cframeValue16 = GetCamPosition()
        local cache29 = {}
        for rootPart15, distanceValue53 in pairs(State.scpEspObjects) do
            if not rootPart15 or not rootPart15.Parent then
                cache29[#cache29 + (1.0)] = rootPart15
            else
                local distanceValue36 = true
                if cframeValue16 then
                    local rootPart2 = GetScpModelRoot(rootPart15)
                    if rootPart2 then
                        distanceValue36 = (rootPart2.Position - cframeValue16).Magnitude <= Config.scpEspDistance
                    end
                end
                if distanceValue53.highlight and distanceValue53.highlight.Parent then
                    if distanceValue53.highlight.FillColor ~= Config.scpEspColor then
                        distanceValue53.highlight.FillColor = Config.scpEspColor
                        distanceValue53.highlight.OutlineColor = Config.scpEspColor
                    end
                    if distanceValue53.highlight.Enabled ~= distanceValue36 then distanceValue53.highlight.Enabled = distanceValue36 end
                end
                if distanceValue53.billboard then
                    distanceValue53.billboard.MaxDistance = Config.scpEspDistance
                    if distanceValue53.billboard.Enabled ~= distanceValue36 then distanceValue53.billboard.Enabled = distanceValue36 end
                    if distanceValue53.label then
                        local recoveredValue123 = Config.scpEspShowName and "zombie" or ""
                        if distanceValue53.label.Text ~= recoveredValue123 then distanceValue53.label.Text = recoveredValue123 end
                    end
                end
            end
        end
        for index = 1, #cache29 do RemoveScpESP(cache29[index]) end
    end

    RegisterUpdateTask("ScpESP", 0.5, function()
        if not Config.scpEspEnabled then
            for rootPart15, _ in pairs(State.scpEspObjects) do RemoveScpESP(rootPart15) end
            return
        end


        local cache29 = {}
        for rootPart15, _ in pairs(State.scpEspObjects) do
            if not rootPart15 or not rootPart15.Parent then cache29[#cache29 + 1] = rootPart15 end
        end
        for index = 1, #cache29 do RemoveScpESP(cache29[index]) end


        for index = 1, #recoveredValue189 do
            local rootPart15 = recoveredValue189[index]
            if rootPart15 and rootPart15.Parent and not State.scpEspObjects[rootPart15] then
                HelperFunction58(rootPart15)
            end
        end

        RefreshScpEsp()
    end)
end

local SetSpeedBoostEnabled
do

    local function RefreshSpeedBoost()
        if not State.SpeedBoost then return end
        local char = LocalPlayer.Character
        if not char then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end


        if State.safeModeSpeed and (char:GetAttribute("IsHooked") or char:GetAttribute("IsCarried") or humanoid.Health <= 50) then
            return
        end

        if State.safeModeSpeed and (IsMovementSlowActive() or IsPlayerDoingAction()) then
            return
        end


        if State.pauseSpeedWhenCrouching and char:GetAttribute("Crouching") then
            return
        end

        local humanoid14 = GetDesiredWalkSpeed()
        if humanoid14 <= (0.0) then return end
        local recoveredValue390 = math.clamp(tonumber(State.speedBoostMultiplier) or 0.3, 0, 2)
        local recoveredValue3 = BASE_WALK_SPEED * recoveredValue390
        State._jitterFlip = not State._jitterFlip
        local target = State._jitterFlip and (humanoid14 + recoveredValue3) or humanoid14
        if math.abs(humanoid.WalkSpeed - target) > 0.1 then
            pcall(function() humanoid.WalkSpeed = target end)
        end
    end


    RegisterUpdateTask("SpeedBoost", (0.0), function()
        RefreshSpeedBoost()
    end)

    function SetSpeedBoostEnabled(recoveredValue62)
        State.SpeedBoost = recoveredValue62 and true or false
        local char = LocalPlayer.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if not recoveredValue62 then

            if humanoid then _ApplySpeed(humanoid, BASE_WALK_SPEED) end
            return
        end

        if humanoid then RefreshSpeedBoost() end
    end


    State.SB_Retarget = function()
        RefreshSpeedBoost()
    end
    State.SB_RefreshAll = function()
        RefreshSpeedBoost()
    end
end

do
    local function HelperFunction147(recoveredValue274, pos)
        if not recoveredValue274 or not recoveredValue274.Parent then return false end
        local recoveredValue441 = recoveredValue274.AbsolutePosition; local recoveredValue330 = recoveredValue274.AbsoluteSize
        local cx = recoveredValue441.X + recoveredValue330.X / 2; local recoveredValue56 = recoveredValue441.Y + recoveredValue330.Y / 2
        local recoveredValue262 = math.min(recoveredValue330.X, recoveredValue330.Y) / 2 * 0.8
        local dx = pos.X - cx; local dy = pos.Y - recoveredValue56
        return (dx*dx + dy*dy) <= (recoveredValue262*recoveredValue262)
    end

    local function HelperFunction211(recoveredValue274)
        if not recoveredValue274:IsA("ImageButton") then return end
        if recoveredValue274.Name ~= "Gui-mob" then return end
        if State._hookedMobButtons[recoveredValue274] then return end
        State._hookedMobButtons[recoveredValue274] = true
        UserInputService.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.Touch then return end
            if not HelperFunction147(recoveredValue274, input.Position) then return end
            State.stateField15 = true
            local connection
            connection = UserInputService.InputEnded:Connect(function(ended)
                if ended == input then
                    State.stateField15 = false
                    connection:Disconnect()
                end
            end)
        end)
    end


    local cache50 = {
        ["Slasher-mob"] = true,
        ["Masked-mob"]  = true,
        ["Hidden-mob"]  = true,
        ["Killer-mob"]  = true,

    }

    local function HelperFunction74(recoveredValue274)
        if not (recoveredValue274 and recoveredValue274:IsA("GuiButton")) then return false end
        if recoveredValue274.Name ~= "attack" then return false end
        local recoveredValue381, hasControl = false, false
        local targetPlayer = recoveredValue274.Parent
        while targetPlayer do

            if cache50[targetPlayer.Name] then recoveredValue381 = true end
            if targetPlayer.Name == "Controls" or targetPlayer.Name == "Control" then hasControl = true end
            targetPlayer = targetPlayer.Parent
        end
        return recoveredValue381 and hasControl
    end

    local function HelperFunction117(recoveredValue274)
        if State._hookedSlasherButtons[recoveredValue274] then return end
        State._hookedSlasherButtons[recoveredValue274] = true
        recoveredValue274.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                State.stateField15 = true
            end
        end)
        recoveredValue274.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                State.stateField15 = false
            end
        end)
    end

    local function HelperFunction158(parentObject)
        local function HelperFunction31(recoveredValue209)
            if not recoveredValue209 then return end
            local recoveredValue351 = recoveredValue209:FindFirstChild("Gui-mob", true)
            if recoveredValue351 and recoveredValue351:IsA("ImageButton") then HelperFunction211(recoveredValue351) end
            local recoveredValue73 = recoveredValue209:FindFirstChild("Control") or recoveredValue209:FindFirstChild("Controls")
            if recoveredValue73 then
                local function HelperFunction213(parentObject)
                    for _, child in ipairs(parentObject:GetChildren()) do
                        if HelperFunction74(child) then HelperFunction117(child) end
                        HelperFunction213(child)
                    end
                end
                HelperFunction213(recoveredValue73)
            end
        end
        for recoveredValue329, _ in pairs(cache50) do
            HelperFunction31(parentObject:FindFirstChild(recoveredValue329))
        end
        parentObject.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("ImageButton") and descendant.Name == "Gui-mob" then HelperFunction211(descendant) end
            if HelperFunction74(descendant) then HelperFunction117(descendant) end
        end)
    end

    task.spawn(function()
        local recoveredValue40 = LocalPlayer:WaitForChild("PlayerGui")
        HelperFunction158(recoveredValue40)
    end)

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        local isKiller = GetPlayerRole(LocalPlayer) == "killer"

        if isKiller then
            if input.UserInputType == Enum.UserInputType.MouseButton1 then State.stateField15 = true end
        else
            if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton2 then State.stateField15 = true end
        end
        if not gameProcessed and input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonL2 then State.stateField15 = true end
    end)

    UserInputService.InputEnded:Connect(function(input)

        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 then
            State.stateField15 = false
        end
        if input.UserInputType == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonL2 then State.stateField15 = false end
    end)

    RegisterUpdateTask("HoldLock", 0.2, function()
        if not Config.aimLockEnabled then return end
        if State.stateField15 then return end
        local char = LocalPlayer.Character
        if char and char:GetAttribute("Aiming") == true then
            State.stateField15 = true
        end
    end)
end

local StartCameraLock, StopCameralock
do
    local function HelperFunction66(char)
        if not char then return nil end

        if Config.aimLockPart == "Head" then
            local rootPart19 = char:FindFirstChild("Head")
            if rootPart19 then return rootPart19.Position end
        end
        local part4 = char:FindFirstChild("UpperTorso")
        if part4 then return part4.Position end
        local part2 = char:FindFirstChild("Torso")
        if part2 then return part2.Position end
        local rootPart2 = char:FindFirstChild("HumanoidRootPart")
        if rootPart2 then
            return rootPart2.Position + (Config.aimLockPart == "Head" and Vector3.new(0, 2.5, (0.0)) or Vector3.new(0, 1.2, (0.0)))
        end
        return nil
    end


    local function HelperFunction21(player, char, humanoid)
        if not char or not humanoid or humanoid.Health <= 0 then return false end


        if humanoid.Health < (50.0) then return false end


        if char:GetAttribute("IsHooked") then return false end
        if char:GetAttribute("IsCarried") then return false end
        if player:GetAttribute("IsHooked") then return false end
        if player:GetAttribute("IsCarried") then return false end


        local attributeValue4 = humanoid:GetState()
        if attributeValue4 == Enum.HumanoidStateType.PlatformStanding then return false end
        if attributeValue4 == Enum.HumanoidStateType.Physics and humanoid.PlatformStand then return false end


        local rootPart2 = char:FindFirstChild("HumanoidRootPart")
        if rootPart2 and rootPart2.Anchored then return false end

        return true
    end

    local function HelperFunction165(currentTarget)
        local rootPart22 = LocalPlayer.Character
        local rootPart13 = rootPart22 and rootPart22:FindFirstChild("HumanoidRootPart")
        if not rootPart13 then return nil end
        local vectorValue24 = rootPart13.Position
        local distanceValue29 = 0.1
        local distanceValue13 = nil
        local closestDistance = Config.aimLockMaxDistance

        if Config.aimLockTargetType == "Zombie" then
            if currentTarget and typeof(currentTarget) == "Instance" and not currentTarget:IsA("Player") then
                local rootPart2 = GetScpModelRoot(currentTarget)
                if rootPart2 and rootPart2:IsA("BasePart") and currentTarget.Parent then
                    local dist = (rootPart2.Position - vectorValue24).Magnitude
                    if dist <= Config.aimLockMaxDistance then
                        distanceValue13 = currentTarget
                        closestDistance = dist - distanceValue29
                    end
                end
            end
            if tick() - zombieCacheTime > 0.5 then RefreshZombieCache() end
            for index = 1, #recoveredValue189 do
                local rootPart15 = recoveredValue189[index]
                if rootPart15 and rootPart15.Parent then
                    local rootPart2 = GetScpModelRoot(rootPart15)
                    if rootPart2 and rootPart2:IsA("BasePart") then
                        local dist = (rootPart2.Position - vectorValue24).Magnitude
                        if dist < closestDistance then closestDistance = dist; distanceValue13 = rootPart15 end
                    end
                end
            end
            return distanceValue13
        end


        if currentTarget and currentTarget.Character then
            local humanoid3 = currentTarget.Character
            local humanoid6 = humanoid3:FindFirstChildOfClass("Humanoid")
            local recoveredValue433 = HelperFunction66(humanoid3)
            local recoveredValue345 = true
            if Config.aimLockTargetType == "Killer" and GetPlayerRole(currentTarget) ~= "killer" then
                recoveredValue345 = false
            elseif Config.aimLockTargetType == "Survivor" and GetPlayerRole(currentTarget) ~= "survivor" then
                recoveredValue345 = false
            end

            if recoveredValue345 and HelperFunction21(currentTarget, humanoid3, humanoid6) and recoveredValue433 then
                local recoveredValue346 = (recoveredValue433 - vectorValue24).Magnitude
                if recoveredValue346 <= Config.aimLockMaxDistance then
                    distanceValue13 = currentTarget
                    closestDistance = recoveredValue346 - distanceValue29
                end
            end
        end


        for _, player in ipairs(Players:GetPlayers()) do
            if player == LocalPlayer then continue end
            local char = player.Character
            if not char then continue end
            local humanoid = char:FindFirstChildOfClass("Humanoid")

            if not HelperFunction21(player, char, humanoid) then continue end

            local distanceValue28 = HelperFunction66(char)
            if not distanceValue28 then continue end
            local distanceValue19 = GetPlayerRole(player)
            if Config.aimLockTargetType == "Killer" and distanceValue19 ~= "killer" then continue end
            if Config.aimLockTargetType == "Survivor" and distanceValue19 ~= "survivor" then continue end
            local dist = (distanceValue28 - vectorValue24).Magnitude
            if dist < closestDistance then closestDistance = dist; distanceValue13 = player end
        end
        return distanceValue13
    end

    function StartCameraLock()
        if State.connection15 then State.connection15:Disconnect() end
        State.stateField52 = nil; State.stateField108 = 0; State.stateField13 = nil
        State.connection15 = RunService.RenderStepped:Connect(function(recoveredValue206)
            if not Config.aimLockEnabled then return end
            if Config.aimLockMode == "Hold to Lock" and not State.stateField15 then
                State.stateField52 = nil; State.stateField13 = nil; return
            end
            local rootPart22 = LocalPlayer.Character
            if not rootPart22 then return end
            local rootPart13 = rootPart22:FindFirstChild("HumanoidRootPart")
            if not rootPart13 then return end
            State.stateField108 = State.stateField108 + recoveredValue206
            if State.stateField108 >= 0.15 then
                State.stateField108 = 0
                State.stateField52 = HelperFunction165(State.stateField52)
            end
            local target = State.stateField52
            if not target then State.stateField13 = nil; return end

            local distanceValue28
            if typeof(target) == "Instance" and not target:IsA("Player") then
                local part7 = GetScpModelRoot(target)
                if not part7 or not part7:IsA("BasePart") or not target.Parent then
                    State.stateField52 = nil; State.stateField13 = nil; return
                end
                distanceValue28 = part7.Position
            else
                local humanoid16 = target.Character
                if not humanoid16 then State.stateField52 = nil; State.stateField13 = nil; return end
                local humanoid7 = humanoid16:FindFirstChildOfClass("Humanoid")


                if not HelperFunction21(target, humanoid16, humanoid7) then
                    State.stateField52 = nil; State.stateField13 = nil; return
                end

                distanceValue28 = HelperFunction66(humanoid16)
            end
            if not distanceValue28 then State.stateField52 = nil; State.stateField13 = nil; return end
            local cameraValue3 = workspace.CurrentCamera
            if not cameraValue3 then return end
            local cframeValue5 = cameraValue3.CFrame
            local cframeValue6 = cframeValue5.Position
            local recoveredValue228 = cframeValue5.LookVector
            local cframeValue14 = Config.aimLockSmoothness
            local distanceValue22 = distanceValue28 - cframeValue6
            local distanceValue43 = distanceValue22.Magnitude
            local recoveredValue183 = (distanceValue28 - rootPart13.Position).Magnitude
            local recoveredValue350 = 4.0
            local cframeValue3
            if distanceValue43 >= recoveredValue350 and recoveredValue183 >= 1.5 then
                cframeValue3 = distanceValue22.Unit; State.stateField13 = cframeValue3
            elseif State["B0O0OI1_CB5A"] then
                cframeValue3 = State.stateField13
            else
                cframeValue3 = recoveredValue228
            end
            local cframeValue18 = recoveredValue228:Lerp(cframeValue3, cframeValue14)
            if cframeValue18.Magnitude < 0.001 then return end
            cameraValue3.CFrame = CFrame.new(cframeValue6, cframeValue6 + cframeValue18)
            local humanoid = rootPart22:FindFirstChildOfClass("Humanoid")
            if humanoid and not humanoid.AutoRotate then
                local vectorValue50 = cameraValue3.CFrame.LookVector
                local vectorValue24 = rootPart13.Position
                local vectorValue47 = Vector3.new(vectorValue50.X, 0, vectorValue50.Z)
                if vectorValue47.Magnitude > 0.001 then
                    local cframeValue15 = math.atan2(rootPart13.CFrame.LookVector.X, rootPart13.CFrame.LookVector.Z)
                    local recoveredValue48 = math.atan2(vectorValue47.X, vectorValue47.Z)
                    local distanceValue20 = recoveredValue48 - cframeValue15
                    distanceValue20 = ((distanceValue20 + math.pi) % (2 * math.pi)) - math.pi
                    local recoveredValue348 = cframeValue15 + distanceValue20 * 0.15
                    local vectorValue33 = math.sin(recoveredValue348)
                    local vectorValue22 = math.cos(recoveredValue348)
                    local vectorValue38 = vectorValue24 + Vector3.new(vectorValue33, (0.0), vectorValue22) * (900.0)
                    rootPart13.CFrame = CFrame.new(vectorValue24, Vector3.new(vectorValue38.X, vectorValue24.Y, vectorValue38.Z))
                end
            end
        end)
    end

    function StopCameralock()
        if State.connection15 then State.connection15:Disconnect(); State.connection15 = nil end
        State.stateField52 = nil; State.stateField13 = nil
    end
end

local function SetMaxCameraZoom(value)
    if State.distanceValue4 == nil then State.distanceValue4 = LocalPlayer.CameraMaxZoomDistance end
    LocalPlayer.CameraMaxZoomDistance = value
end

local function ApplyMaxCameraZoom()
    if State.distanceValue4 ~= nil then LocalPlayer.CameraMaxZoomDistance = State.distanceValue4 end
    State.distanceValue4 = nil
end

local function SetupCameraZoomForCharacter(char)
    if not char then return nil end
    local success, attributeValue15 = pcall(function() return char:FindFirstChild("SmoothCamera") end)
    if success and attributeValue15 then return attributeValue15 end
    return nil
end

local function SetSmoothCamera(value)
    local attributeValue15 = SetupCameraZoomForCharacter(LocalPlayer.Character)
    if not attributeValue15 then return false end
    if State.origCamStiffness == nil then
        local cur = 8
        pcall(function() cur = attributeValue15:GetAttribute("CameraStiffness") or 8 end)
        State.origCamStiffness = cur
    end
    pcall(function() attributeValue15:SetAttribute("CameraStiffness", value) end)
    return true
end

local function StartSmoothCamera()
    if State.origCamStiffness ~= nil then
        local attributeValue15 = SetupCameraZoomForCharacter(LocalPlayer.Character)
        if attributeValue15 then pcall(function() attributeValue15:SetAttribute("CameraStiffness", State.origCamStiffness) end) end
    end
    State.origCamStiffness = nil
end

do


    LocalPlayer.CharacterAdded:Connect(function(char)
        task.spawn(function()
            task.wait(1)
            if Config.smoothCameraEnabled and LocalPlayer.Character == char then
                SetSmoothCamera(Config.cameraStiffness)
            end
        end)
    end)

    RegisterUpdateTask("CamStiffness", 0.5, function()
        if not Config.smoothCameraEnabled then return end
        local attributeValue15 = SetupCameraZoomForCharacter(LocalPlayer.Character)
        if not attributeValue15 then return end
        local successFlag, cur = pcall(function() return attributeValue15:GetAttribute("CameraStiffness") end)
        if successFlag and cur ~= Config.cameraStiffness then
            pcall(function() attributeValue15:SetAttribute("CameraStiffness", Config.cameraStiffness) end)
        end
    end)
end

local function SetStretchedResolution(value)
    local camera = workspace.CurrentCamera
    if not camera then return end
    if State.stateField101 == nil then State.stateField101 = camera.FieldOfView end
    camera.FieldOfView = value
end

local function ApplyStretchedResolution()
    local camera = workspace.CurrentCamera
    if camera and State.stateField101 then camera.FieldOfView = State.stateField101 end
    State.stateField101 = nil
end

do
    LocalPlayer:GetPropertyChangedSignal("CameraMaxZoomDistance"):Connect(function()
        if Config.maxCameraZoomEnabled and LocalPlayer.CameraMaxZoomDistance ~= Config.cameraZoomValue then
            LocalPlayer.CameraMaxZoomDistance = Config.cameraZoomValue
        end
    end)

    local function HelperFunction41()
        local camera = workspace.CurrentCamera
        if not camera then return end
        camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
            if Config.lockFovEnabled and camera.FieldOfView ~= Config.fovValue then
                camera.FieldOfView = Config.fovValue
            end
        end)
    end
    pcall(HelperFunction41)
end

local cameraScaleState = { m = (1.0), n = (1.0) }
local function ResetCameraScale()
    pcall(function() RunService:UnbindFromRenderStep("BlehHub_Aspect") end)
    cameraScaleState.m, cameraScaleState.n = 1, 1
end

local function UpdateCameraScale()
    ResetCameraScale()
    cameraScaleState.m, cameraScaleState.n = (1.0), 1
    pcall(function()
        RunService:UnbindFromRenderStep("BlehHub_Aspect")
        RunService:BindToRenderStep("BlehHub_Aspect", Enum.RenderPriority.Camera.Value + (2.0), function(recoveredValue206)
            if not Config.stretchedResolutionEnabled then return end
            local camera = workspace.CurrentCamera
            if not camera then return end
            local cameraValue4 = camera.ViewportSize
            if cameraValue4.Y < 1 then return end
            local recoveredValue309 = cameraValue4.X / cameraValue4.Y
            local recoveredValue335 = tonumber(Config.stretchedResolutionRatio) or (16 / 9)
            local m, n = 1, 1
            if math.abs(recoveredValue335 - recoveredValue309) > 0.03 then
                if recoveredValue335 < recoveredValue309 then
                    m = (1.0)
                    n = math.clamp(recoveredValue335 / recoveredValue309, 0.1, 1)
                else
                    m = math.clamp(recoveredValue309 / recoveredValue335, 0.1, 1)
                    n = 1
                end
            end

            local recoveredValue208 = math.clamp(recoveredValue206 or 0.0167, 0.0005, 0.1)
            local distanceValue7 = math.clamp(1 - math.exp(-12 * recoveredValue208), 0.001, (1.0))
            cameraScaleState.m = cameraScaleState.m + (m - cameraScaleState.m) * distanceValue7
            cameraScaleState.n = cameraScaleState.n + (n - cameraScaleState.n) * distanceValue7
            if math.abs(cameraScaleState.m - 1) < 0.002 and math.abs(cameraScaleState.n - (1.0)) < 0.002 then
                cameraScaleState.m, cameraScaleState.n = (1.0), 1
                return
            end
            local contextValue = camera.CFrame
            local targetPlayer = contextValue.Position
            if targetPlayer.X ~= targetPlayer.X or targetPlayer.Y ~= targetPlayer.Y or targetPlayer.Z ~= targetPlayer.Z then return end
            if contextValue.RightVector.Magnitude < 0.01 or contextValue.UpVector.Magnitude < 0.01 then return end
            local cframeValue = CFrame.fromMatrix(targetPlayer, contextValue.RightVector.Unit, contextValue.UpVector.Unit)
            camera.CFrame = cframeValue * CFrame.new(0, 0, (0.0), cameraScaleState.m, (0.0), 0, 0, cameraScaleState.n, 0, 0, (0.0), 1)
        end)
    end)
end

local function ApplyCameraScale()

    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        return
    end


    State.stateField50 = UserInputService.MouseIconEnabled
    State.stateField114   = UserInputService.MouseBehavior


    UserInputService.MouseIconEnabled = true
    UserInputService.MouseBehavior     = Enum.MouseBehavior.Default


    if State.connection2 then State.connection2:Disconnect() end
    if State.connection14 then State.connection14:Disconnect() end


    State.connection2 = UserInputService:GetPropertyChangedSignal("MouseIconEnabled"):Connect(function()
        if Config.forceMouseCursor and not UserInputService.MouseIconEnabled then
            UserInputService.MouseIconEnabled = true
        end
    end)

    State.connection14 = UserInputService:GetPropertyChangedSignal("MouseBehavior"):Connect(function()
        if Config.forceMouseCursor and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
            UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        end
    end)
end

local function RestoreCameraSettings()

    if State.connection2 then
        State.connection2:Disconnect()
        State.connection2 = nil
    end
    if State.connection14 then
        State.connection14:Disconnect()
        State.connection14 = nil
    end

    if State.stateField50 ~= nil then
        UserInputService.MouseIconEnabled = State.stateField50
        State.stateField50 = nil
    end
    if State.stateField114 ~= nil then
        UserInputService.MouseBehavior = State.stateField114
        State.stateField114 = nil
    end
end

local StartPerfMonitor, StopPerfMonitor, StartPrediction, StopPrediction
do
    local function HelperFunction86()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "BlehHubPerfMon"; screenGui.ResetOnSpawn = false
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; screenGui.IgnoreGuiInset = false; screenGui.Parent = PlayerGui
        local frame4 = Instance.new("Frame")
        frame4.Name = "PerfFrame"; frame4.Size = UDim2.fromOffset(160, (28.0))
        frame4.AnchorPoint = Vector2.new(1, 0); frame4.Position = UDim2.new((1.0), (-10.0), (0.0), 10)
        frame4.BackgroundColor3 = Color3.fromRGB(10, 10, 14); frame4.BorderSizePixel = 0
        frame4.Active = true; frame4.Parent = screenGui
        local recoveredValue226 = Instance.new("UICorner"); recoveredValue226.CornerRadius = UDim.new(0, (8.0)); recoveredValue226.Parent = frame4
        local colorValue14 = Instance.new("UIStroke"); colorValue14.Color = Color3.fromRGB((60.0), 60, 75)
        colorValue14.Thickness = 1; colorValue14.Parent = frame4
        local infoLabel = Instance.new("TextLabel")
        infoLabel.Name = "InfoLabel"; infoLabel.Size = UDim2.new(1, 0, 1, (0.0))
        infoLabel.BackgroundTransparency = 1; infoLabel.Text = "FPS — | PING —"
        infoLabel.TextColor3 = Color3.fromRGB(200, 200, 210); infoLabel.TextSize = 12
        infoLabel.Font = Enum.Font.GothamBold; infoLabel.TextXAlignment = Enum.TextXAlignment.Center
        infoLabel.TextYAlignment = Enum.TextYAlignment.Center; infoLabel.RichText = true; infoLabel.Parent = frame4
        local recoveredValue194, recoveredValue414, distanceValue3
        frame4.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                recoveredValue194 = true; recoveredValue414 = input.Position; distanceValue3 = frame4.Position
            end
        end)
        frame4.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                recoveredValue194 = false
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if recoveredValue194 and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local vectorValue40 = input.Position - recoveredValue414
                frame4.Position = UDim2.new(1, distanceValue3.X.Offset + vectorValue40.X, (0.0), distanceValue3.Y.Offset + vectorValue40.Y)
            end
        end)
        return screenGui, infoLabel
    end

    RegisterUpdateTask("PerfMonitor", 0.5, function()
        if not State.stateField41 then return end
        local recoveredValue210 = math.floor(State.stateField89 / math.max(State.stateField100, 0.001))
        local ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"].GetValue(Stats.Network.ServerStatsItem["Data Ping"]))
        local recoveredValue252 = recoveredValue210 >= 50 and "rgb(80,220,100)" or recoveredValue210 >= 30 and "rgb(255,200,60)" or "rgb(255,70,70)"
        local recoveredValue313 = ping <= 80 and "rgb(80,220,100)" or ping <= 150 and "rgb(255,200,60)" or "rgb(255,70,70)"
        if State.stateField8 and State.stateField8.Parent then
            local label = State.stateField8:FindFirstChild("PerfFrame"):FindFirstChild("InfoLabel")
            if label then
                label.Text = string.format("<font color=\"%s\">FPS %d</font> <font color=\"rgb(60,60,75)\">|</font> <font color=\"%s\">PING %d</font>", recoveredValue252, recoveredValue210, recoveredValue313, ping)
            end
        end
        State.stateField100 = 0; State.stateField89 = 0
    end)

    RegisterUpdateTask("PerfCounter", 0, function(recoveredValue206)
        if State.stateField41 then
            State.stateField89 = State.stateField89 + 1
            State.stateField100 = State.stateField100 + recoveredValue206
        end
    end)

    function StartPerfMonitor()
        if State.stateField8 then State.stateField8:Destroy() end
        local screenGui, infoLabel = HelperFunction86()
        State.stateField8 = screenGui; State.stateField41 = true
        State.stateField100 = 0; State.stateField89 = (0.0)
    end

    function StopPerfMonitor()
        State.stateField41 = false
        if State.stateField8 then State.stateField8:Destroy(); State.stateField8 = nil end
    end


    local function HelperFunction44(instance, name)
        if not instance then return nil end
        local attributeValue17 = instance:GetAttribute(name)
        if attributeValue17 ~= nil then return attributeValue17 end
        local child = instance:FindFirstChild(name)
        if child then
            local successFlag4, val = pcall(function() return child.Value end)
            if successFlag4 then return val end
        end
        return nil
    end

    local function HelperFunction155()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "BlehHubPrediction"
        screenGui.ResetOnSpawn = false
        screenGui.IgnoreGuiInset = true
        screenGui.DisplayOrder = 9999999
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

        local recoveredValue162 = nil
        pcall(function() recoveredValue162 = gethui() end)
        if not recoveredValue162 then
            pcall(function() recoveredValue162 = game:GetService("CoreGui") end)
        end
        if not recoveredValue162 then
            recoveredValue162 = PlayerGui
        end
        screenGui.Parent = recoveredValue162

        local infoLabel = Instance.new("TextLabel")
        infoLabel.Name = "InfoLabel"
        infoLabel.AnchorPoint = Vector2.new(0.5, 0)


        if State.stateField14 then
            infoLabel.Position = State.stateField14
        else
            infoLabel.Position = UDim2.new(0.5, 0, 0, 50)
        end

        infoLabel.BackgroundTransparency = 1
        infoLabel.AutomaticSize = Enum.AutomaticSize.XY
        infoLabel.Text = "Map: â | Killer: â"
        infoLabel.TextColor3 = Color3.fromRGB(252, (235.0), (229.0))
        infoLabel.TextSize = (14.0)
        infoLabel.Font = Enum.Font.GothamBold
        infoLabel.TextXAlignment = Enum.TextXAlignment.Center
        infoLabel.TextYAlignment = Enum.TextYAlignment.Center
        infoLabel.RichText = true
        infoLabel.Active = true
        infoLabel.Parent = screenGui

        local colorValue14 = Instance.new("UIStroke")
        colorValue14.Name = "Outline"
        colorValue14.Color = Color3.new(0, (0.0), (0.0))
        colorValue14.Thickness = 1
        colorValue14.Transparency = 0.2
        colorValue14.Parent = infoLabel

        local recoveredValue194 = false
        local recoveredValue414 = Vector2.new()
        local distanceValue3 = UDim2.new()

        infoLabel.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                recoveredValue194 = true
                recoveredValue414 = input.Position
                distanceValue3 = infoLabel.Position
            end
        end)

        infoLabel.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                recoveredValue194 = false
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if recoveredValue194 and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local vectorValue40 = input.Position - recoveredValue414
                local recoveredValue405 = UDim2.new(
                    distanceValue3.X.Scale, distanceValue3.X.Offset + vectorValue40.X,
                    distanceValue3.Y.Scale, distanceValue3.Y.Offset + vectorValue40.Y
                )
                infoLabel.Position = recoveredValue405
                State.stateField14 = recoveredValue405
            end
        end)

        return screenGui, infoLabel
    end

    local function HelperFunction60()
        if State.connection18 then return end
        task.spawn(function()
            local success, remote = pcall(function()
                return ReplicatedStorage:WaitForChild("Remotes", (10.0))
                    :WaitForChild("Messages", 10)
                    :WaitForChild("Mapinfo", 10)
            end)
            if success and remote and remote:IsA("RemoteEvent") then
                State.connection18 = remote.OnClientEvent:Connect(function(mapName, mapId)
                    if type(mapName) == "string" and mapName ~= "" then
                        State.stateField97 = mapName
                    end
                end)
            end
        end)
    end

    RegisterUpdateTask("PredictionMonitor", 1, function()
        if not State.stateField10 then return end


        if not State.stateField60 or not State.stateField60.Parent then
            if State.stateField60 then State.stateField60:Destroy() end
            local screenGui, infoLabel = HelperFunction155()
            State.stateField60 = screenGui
            State.stateField36 = infoLabel
        end

        local infoLabel = State.stateField60:FindFirstChild("InfoLabel")
        if not infoLabel then return end


        local recoveredValue357 = Players:GetPlayers()

        table.sort(recoveredValue357, function(attributeValue12, attributeValue22)
            local recoveredValue398 = HelperFunction44(attributeValue12, "AllowKiller")
            local recoveredValue377 = HelperFunction44(attributeValue22, "AllowKiller")

            local recoveredValue338 = (recoveredValue398 == false)
            local recoveredValue139 = (recoveredValue377 == false)

            if recoveredValue338 ~= recoveredValue139 then
                return not recoveredValue338
            end

            if not recoveredValue338 and not recoveredValue139 then
                return (HelperFunction44(attributeValue12, "KillerChance") or 0) > (HelperFunction44(attributeValue22, "KillerChance") or (0.0))
            end

            return (HelperFunction44(attributeValue12, "KillerChance") or 0) < (HelperFunction44(attributeValue22, "KillerChance") or 0)
        end)

        local recoveredValue192 = recoveredValue357[1]
        local recoveredValue302 = '<font color="rgb(100,110,130)">—</font>'

        if recoveredValue192 then
            local name = recoveredValue192.Name
            local recoveredValue17 = HelperFunction44(recoveredValue192, "SelectedKiller")
            local recoveredValue49    = HelperFunction44(recoveredValue192, "AllowKiller")

            if recoveredValue192 == LocalPlayer then
                name = "YOU"
            end

            local recoveredValue156
            if recoveredValue49 == false then
                recoveredValue156 = "rgb(255,0,30)"
            else
                recoveredValue156 = "rgb(252,235,229)"
            end

            if recoveredValue17 and type(recoveredValue17) == "string" and recoveredValue17 ~= "" then
                recoveredValue302 = string.format(
                    "<font color=\"%s\">%s</font> <font color=\"rgb(255,0,30)\">(%s)</font>",
                    recoveredValue156, name, recoveredValue17
                )
            else
                recoveredValue302 = string.format(
                    "<font color=\"%s\">%s</font>",
                    recoveredValue156, name
                )
            end
        end


        local recoveredValue14 = State.stateField97 or "—"
        infoLabel.Text = string.format(
            "<font color=\"rgb(255,210,60)\">Map:</font> <font color=\"rgb(252,235,229)\">%s</font>  <font color=\"rgb(80,80,85)\">|</font>  <font color=\"rgb(255,210,60)\">Killer:</font> %s",
            recoveredValue14, recoveredValue302
        )
    end)

    function StartPrediction()
        if State.stateField60 then State.stateField60:Destroy() end
        State.stateField97 = nil
        HelperFunction60()

        local screenGui, infoLabel = HelperFunction155()
        State.stateField60 = screenGui
        State.stateField36 = infoLabel
        State.stateField10 = true
    end

    function StopPrediction()
        State.stateField10 = false
        if State.connection18 then
            pcall(function() State.connection18:Disconnect() end)
            State.connection18 = nil
        end
        if State.stateField60 then
            State.stateField60:Destroy()
            State.stateField60 = nil
        end
    end
end

CROSSHAIR_STYLES = {
   "Dot", "Circle", "Circle + Dot", "Plus", "Cross (X)", "T-Shape", "Square"
}

local Crosshair
do
    local recoveredValue88   = 80
    local recoveredValue245 = recoveredValue88 / 2


    local cache8 = {}


    local function CreateCrosshairPart(centerX, centerY, width, length, rotation, color, recoveredValue4, name)
        local frame = Instance.new("Frame")
        frame.Name               = name or "CH_Part"
        frame.BackgroundColor3   = color
        frame.BackgroundTransparency = recoveredValue4
        frame.BorderSizePixel    = 0
        frame.Size               = UDim2.fromOffset(math.max(1, math.round(width)), math.max(1, math.round(length)))
        frame.AnchorPoint        = Vector2.new(0.5, 0.5)
        frame.Position           = UDim2.fromOffset(math.round(centerX), math.round(centerY))
        if rotation ~= 0 then frame.Rotation = rotation end
        return frame
    end


    local function GetCrosshairScale(size)
        return 0.3 + (math.clamp(size, (1.0), 100) / 100) * 2.2
    end

    cache8.Plus = function(size, color, recoveredValue4)
        local parts2 = {}
        local recoveredValue236 = GetCrosshairScale(size)

        local recoveredValue296 = math.max(2, math.round(2 * recoveredValue236))
        local recoveredValue177 = math.max(8, math.round(25 * recoveredValue236))
        local contextValue = recoveredValue245


        table.insert(parts2, CreateCrosshairPart(contextValue, contextValue, recoveredValue296, recoveredValue177, 0, color, recoveredValue4))
        table.insert(parts2, CreateCrosshairPart(contextValue, contextValue, recoveredValue177, recoveredValue296, 0, color, recoveredValue4))
        return parts2, {}, {}
    end

    cache8["Cross (X)"] = function(size, color, recoveredValue4)
        local parts2 = {}
        local recoveredValue236 = GetCrosshairScale(size)
        local recoveredValue296 = math.max(2, math.round((2.0) * recoveredValue236))
        local recoveredValue177 = math.max(8, math.round((25.0) * recoveredValue236))
        local contextValue = recoveredValue245


        table.insert(parts2, CreateCrosshairPart(contextValue, contextValue, recoveredValue296, recoveredValue177, 45, color, recoveredValue4))
        table.insert(parts2, CreateCrosshairPart(contextValue, contextValue, recoveredValue296, recoveredValue177, (-45.0), color, recoveredValue4))
        return parts2, {}, {}
    end

    cache8.Dot = function(size, color, recoveredValue4)
        local parts2 = {}
        local recoveredValue236 = GetCrosshairScale(size)
        local recoveredValue331 = math.max(3, math.round(8 * recoveredValue236))
        local contextValue = recoveredValue245

        local dot = CreateCrosshairPart(contextValue, contextValue, recoveredValue331, recoveredValue331, (0.0), color, recoveredValue4, "CH_Dot")
        local recoveredValue226 = Instance.new("UICorner")
        recoveredValue226.CornerRadius = UDim.new(1, 0)
        recoveredValue226.Parent = dot
        table.insert(parts2, dot)
        return parts2, {}, {}
    end

    cache8.Circle = function(size, color, recoveredValue4)
        local parts2, strokes = {}, {}
        local recoveredValue236 = GetCrosshairScale(size)
        local vectorValue62 = math.max(4, math.round(12 * recoveredValue236))
        local recoveredValue296 = math.max(2, math.round(2 * recoveredValue236))
        local contextValue = recoveredValue245

        local indicatorFrame = Instance.new("Frame")
        indicatorFrame.Name = "CH_Ring"
        indicatorFrame.BackgroundTransparency = 1
        indicatorFrame.Size = UDim2.fromOffset(vectorValue62 * 2, vectorValue62 * 2)
        indicatorFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        indicatorFrame.Position = UDim2.fromOffset(contextValue, contextValue)

        local recoveredValue226 = Instance.new("UICorner")
        recoveredValue226.CornerRadius = UDim.new(1, 0)
        recoveredValue226.Parent = indicatorFrame

        local colorValue14 = Instance.new("UIStroke")
        colorValue14.Name = "CH_Stroke"
        colorValue14.Color = color
        colorValue14.Thickness = recoveredValue296
        colorValue14.Transparency = recoveredValue4
        colorValue14.Parent = indicatorFrame

        table.insert(parts2, indicatorFrame)
        table.insert(strokes, colorValue14)
        return parts2, strokes, {}
    end

    cache8["Circle + Dot"] = function(size, color, recoveredValue4)
        local parts2, strokes, dots = {}, {}, {}
        local recoveredValue236 = GetCrosshairScale(size)
        local vectorValue62 = math.max(4, math.round(12 * recoveredValue236))
        local recoveredValue296 = math.max(2, math.round(2 * recoveredValue236))
        local recoveredValue331 = math.max(2, math.round(4 * recoveredValue236))
        local contextValue = recoveredValue245


        local indicatorFrame = Instance.new("Frame")
        indicatorFrame.Name = "CH_Ring"
        indicatorFrame.BackgroundTransparency = 1
        indicatorFrame.Size = UDim2.fromOffset(vectorValue62 * 2, vectorValue62 * 2)
        indicatorFrame.AnchorPoint = Vector2.new(0.5, 0.5)
        indicatorFrame.Position = UDim2.fromOffset(contextValue, contextValue)

        local recoveredValue226 = Instance.new("UICorner")
        recoveredValue226.CornerRadius = UDim.new(1, 0)
        recoveredValue226.Parent = indicatorFrame

        local colorValue14 = Instance.new("UIStroke")
        colorValue14.Name = "CH_Stroke"
        colorValue14.Color = color
        colorValue14.Thickness = recoveredValue296
        colorValue14.Transparency = recoveredValue4
        colorValue14.Parent = indicatorFrame

        table.insert(parts2, indicatorFrame)
        table.insert(strokes, colorValue14)


        local dot = CreateCrosshairPart(contextValue, contextValue, recoveredValue331, recoveredValue331, (0.0), color, recoveredValue4, "CH_Dot")
        local recoveredValue316 = Instance.new("UICorner")
        recoveredValue316.CornerRadius = UDim.new(1, 0)
        recoveredValue316.Parent = dot
        table.insert(parts2, dot)
        table.insert(dots, dot)

        return parts2, strokes, dots
    end

    cache8["T-Shape"] = function(size, color, recoveredValue4)
        local parts2 = {}
        local recoveredValue236 = GetCrosshairScale(size)
        local recoveredValue296 = math.max((2.0), math.round(2 * recoveredValue236))
        local recoveredValue177 = math.max(8, math.round(25 * recoveredValue236))
        local contextValue = recoveredValue245
        local vectorValue16 = math.round(recoveredValue177 * 0.25)


        table.insert(parts2, CreateCrosshairPart(contextValue, contextValue - vectorValue16, recoveredValue177, recoveredValue296, 0, color, recoveredValue4))

        table.insert(parts2, CreateCrosshairPart(contextValue, contextValue - vectorValue16 + recoveredValue177/2, recoveredValue296, recoveredValue177, (0.0), color, recoveredValue4))
        return parts2, {}, {}
    end

    cache8.Square = function(size, color, recoveredValue4)
        local parts2 = {}
        local recoveredValue236 = GetCrosshairScale(size)
        local recoveredValue296 = math.max((2.0), math.round(2 * recoveredValue236))
        local recoveredValue341 = math.max(8, math.round((22.0) * recoveredValue236))
        local strokeSize = math.max((3.0), math.round(recoveredValue341 * 0.4))
        local contextValue = recoveredValue245
        local halfSize = recoveredValue341 / 2


        table.insert(parts2, CreateCrosshairPart(contextValue - halfSize + strokeSize/(2.0), contextValue - halfSize, strokeSize, recoveredValue296, 0, color, recoveredValue4))
        table.insert(parts2, CreateCrosshairPart(contextValue - halfSize, contextValue - halfSize + strokeSize/2, recoveredValue296, strokeSize, 0, color, recoveredValue4))

        table.insert(parts2, CreateCrosshairPart(contextValue + halfSize - strokeSize/2, contextValue - halfSize, strokeSize, recoveredValue296, 0, color, recoveredValue4))
        table.insert(parts2, CreateCrosshairPart(contextValue + halfSize, contextValue - halfSize + strokeSize/2, recoveredValue296, strokeSize, (0.0), color, recoveredValue4))

        table.insert(parts2, CreateCrosshairPart(contextValue - halfSize + strokeSize/2, contextValue + halfSize, strokeSize, recoveredValue296, 0, color, recoveredValue4))
        table.insert(parts2, CreateCrosshairPart(contextValue - halfSize, contextValue + halfSize - strokeSize/(2.0), recoveredValue296, strokeSize, 0, color, recoveredValue4))

        table.insert(parts2, CreateCrosshairPart(contextValue + halfSize - strokeSize/2, contextValue + halfSize, strokeSize, recoveredValue296, 0, color, recoveredValue4))
        table.insert(parts2, CreateCrosshairPart(contextValue + halfSize, contextValue + halfSize - strokeSize/(2.0), recoveredValue296, strokeSize, 0, color, recoveredValue4))

        return parts2, {}, {}
    end


    local CrosshairController = {}
    CrosshairController.__index = CrosshairController

    function CrosshairController.new()
        local self = setmetatable({}, CrosshairController)
        self.config = {
            enabled      = false,
            style        = "Plus",
            size         = 1,
            opacity      = 1.0,
            offsetX      = 0,
            offsetY      = (0.0),
            color        = Color3.fromRGB(255, 255, 255),
            smooth       = true,
            smoothSpeed  = 0.25,
        }
        self.gui            = nil
        self.container      = nil
        self.parent         = nil
        self.parts          = { frames = {}, strokes = {}, dots = {} }
        self.connections    = {}
        self.renderConn     = nil
        self.currentOffset  = Vector2.new((0.0), 0)
        self.targetOffset   = Vector2.new((0.0), 0)
        self._frameCount    = 0
        return self
    end

    local function HelperFunction103()
        local parentObject
        pcall(function() if gethui then parentObject = gethui() end end)
        if parentObject and parentObject.Parent then return parentObject end
        pcall(function() parentObject = game:GetService("CoreGui") end)
        if parentObject and parentObject.Parent then return parentObject end
        return PlayerGui
    end

    function CrosshairController:_createGui()
        if self.gui and self.gui.Parent then return end

        local screenGui = Instance.new("ScreenGui")
        screenGui.Name             = "BlehHubCrosshair"
        screenGui.ResetOnSpawn     = false
        screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
        screenGui.IgnoreGuiInset   = true
        screenGui.DisplayOrder     = 999999

        local parentObject = HelperFunction103()
        screenGui.Parent = parentObject
        self.parent = parentObject

        local frame8 = Instance.new("Frame")
        frame8.Name             = "Container"
        frame8.Size             = UDim2.fromOffset(recoveredValue88, recoveredValue88)
        frame8.AnchorPoint      = Vector2.new(0.5, 0.5)
        frame8.BackgroundTransparency = (1.0)
        frame8.BorderSizePixel  = 0
        frame8.Parent = screenGui

        self.gui       = screenGui
        self.container = frame8

        self:_rebuild()

        self.targetOffset  = Vector2.new(self.config.offsetX, self.config.offsetY)
        self.currentOffset = self.targetOffset
        self:_updatePosition()
    end

    function CrosshairController:_rebuild()
        if not self.container then return end

        for _, frame in ipairs(self.parts.frames) do
            pcall(function() frame:Destroy() end)
        end
        self.parts = { frames = {}, strokes = {}, dots = {} }

        local recoveredValue408 = cache8[self.config.style]
        if not recoveredValue408 then return end

        local recoveredValue4 = (1.0) - self.config.opacity
        local frames, strokes, dots = recoveredValue408(self.config.size, self.config.color, recoveredValue4)

        for _, frame in ipairs(frames) do
            frame.Parent = self.container
            table.insert(self.parts.frames, frame)
        end
        for _, recoveredValue236 in ipairs(strokes) do
            table.insert(self.parts.strokes, recoveredValue236)
        end
        self.parts.dots = dots or {}
    end

    function CrosshairController:_updateColors()
        local color = self.config.color
        local recoveredValue4 = 1 - self.config.opacity

        local colorValue4 = {}
        for _, distance in ipairs(self.parts.dots) do colorValue4[distance] = true end

        for _, frame in ipairs(self.parts.frames) do
            if frame and frame.Parent then
                frame.BackgroundColor3 = colorValue4[frame] and Color3.fromRGB(255, (255.0), (255.0)) or color

                if not frame:FindFirstChildWhichIsA("UIStroke") then
                    frame.BackgroundTransparency = recoveredValue4
                end
            end
        end
        for _, recoveredValue236 in ipairs(self.parts.strokes) do
            if recoveredValue236 and recoveredValue236.Parent then
                recoveredValue236.Color        = color
                recoveredValue236.Transparency = recoveredValue4
            end
        end
    end

    function CrosshairController:_updatePosition()
        if not self.container then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        local viewportOrPoint = camera.ViewportSize
        self.container.Position = UDim2.fromOffset(
            viewportOrPoint.X * 0.5 + self.currentOffset.X,
            viewportOrPoint.Y * 0.5 + self.currentOffset.Y
        )
    end

    function CrosshairController:_hookCamera()
        if self.connections.camViewport then
            self.connections.camViewport:Disconnect()
            self.connections.camViewport = nil
        end
        local camera = workspace.CurrentCamera
        if camera then
            self.connections.camViewport =
                camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
                    self:_updatePosition()
                end)
        end
    end

    function CrosshairController:_setupConnections()
        self:_hookCamera()

        if not self.connections.camChange then
            self.connections.camChange =
                workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
                    self:_hookCamera()
                    self:_updatePosition()
                end)
        end

        if not self.connections.childRemoved then
            self.connections.childRemoved =
                self.parent.ChildRemoved:Connect(function(child)
                    if child == self.gui and self.config.enabled then
                        self.gui       = nil
                        self.container = nil
                        self.parts     = { frames = {}, strokes = {}, dots = {} }
                        task.wait(0.05)
                        if self.config.enabled then
                            self:_createGui()
                        end
                    end
                end)
        end

        if not self.connections.touchChanged then
            self.connections.touchChanged =
                UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(function()
                    self:_updatePosition()
                end)
        end
    end

    function CrosshairController:_startRender()
        if self.renderConn then return end
        self.renderConn = RunService.RenderStepped:Connect(function(recoveredValue206)
            if not self.config.enabled then return end

            if not self.gui or not self.gui.Parent then
                self:_createGui()
                return
            end

            if not self.gui.Enabled then
                self.gui.Enabled = true
            end

            self._frameCount = self._frameCount + 1
            if self._frameCount % 30 == 0 then
                local recoveredValue211 = false
                for _, frame in ipairs(self.parts.frames) do
                    if frame and frame.Parent then recoveredValue211 = true; break end
                end
                if not recoveredValue211 and #self.parts.frames > (0.0) then
                    self:_rebuild()
                end
            end

            if self.config.smooth then
                local distanceValue20 = self.targetOffset - self.currentOffset
                if distanceValue20.Magnitude > 0.01 then
                    local recoveredValue71 =
                        1 - math.pow((1.0) - self.config.smoothSpeed, recoveredValue206 * (60.0))
                    self.currentOffset =
                        self.currentOffset:Lerp(self.targetOffset, recoveredValue71)
                    self:_updatePosition()
                end
            end
        end)
    end

    function CrosshairController:_stopRender()
        if self.renderConn then
            self.renderConn:Disconnect()
            self.renderConn = nil
        end
    end

    function CrosshairController:SetEnabled(enabled)
        self.config.enabled = enabled
        if enabled then
            if not self.gui or not self.gui.Parent then
                self:_createGui()
                self:_setupConnections()
            end
            self.gui.Enabled = true
            self.targetOffset  = Vector2.new(self.config.offsetX, self.config.offsetY)
            self.currentOffset = self.targetOffset
            self:_updatePosition()
            self:_startRender()
        else
            self:_stopRender()
            if self.gui then
                self.gui.Enabled = false
            end
        end
    end

    function CrosshairController:SetStyle(style)
        self.config.style = style
        if self.config.enabled and self.gui then
            self:_rebuild()
        end
    end

    function CrosshairController:SetSize(size)
        self.config.size = size
        if self.config.enabled and self.gui then
            self:_rebuild()
        end
    end

    function CrosshairController:SetOpacity(opacity)
        self.config.opacity = opacity
        if self.config.enabled and self.gui then
            self:_updateColors()
        end
    end

    function CrosshairController:SetColor(color)
        self.config.color = color
        if self.config.enabled and self.gui then
            self:_updateColors()
        end
    end

    function CrosshairController:SetOffsetX(recoveredValue286)
        self.config.offsetX = recoveredValue286
        self.targetOffset = Vector2.new(recoveredValue286, self.config.offsetY)
        if not self.config.smooth and self.config.enabled then
            self.currentOffset = self.targetOffset
            self:_updatePosition()
        end
    end

    function CrosshairController:SetOffsetY(recoveredValue173)
        self.config.offsetY = recoveredValue173
        self.targetOffset = Vector2.new(self.config.offsetX, recoveredValue173)
        if not self.config.smooth and self.config.enabled then
            self.currentOffset = self.targetOffset
            self:_updatePosition()
        end
    end

    function CrosshairController:Destroy()
        self.config.enabled = false
        self:_stopRender()
        for _, connection in pairs(self.connections) do
            pcall(function() connection:Disconnect() end)
        end
        self.connections = {}
        if self.gui then
            pcall(function() self.gui:Destroy() end)
        end
        self.gui       = nil
        self.container = nil
        self.parts     = { frames = {}, strokes = {}, dots = {} }
    end

    Crosshair = CrosshairController.new()
end

local StartProtectName, StopProtectName, _ApplyCopiedAvatarToUI, _HookAllAvatarSlots, _EnsureAvatarUiWatchers
do
    local function HelperFunction63(player)
        if not State.stateField63[player] then
            State.stateField63[player] = ProtectedDisplayNames[1]
        end
        return State.stateField63[player]
    end

    local function HelperFunction59(char, recoveredValue270)
        if not char then return end
        local rootPart19 = char:FindFirstChild("Head")
        if not rootPart19 then return end
        for _, gui in ipairs(rootPart19:GetChildren()) do
            if gui:IsA("BillboardGui") then
                local textLabel = gui:FindFirstChildWhichIsA("TextLabel", true)
                if textLabel then textLabel.Text = recoveredValue270 end
            end
        end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then pcall(function() humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end) end
    end

    local function HelperFunction76(char, recoveredValue223)
        if not char then return end
        local rootPart19 = char:FindFirstChild("Head")
        if rootPart19 then
            for _, gui in ipairs(rootPart19:GetChildren()) do
                if gui:IsA("BillboardGui") then
                    local textLabel = gui:FindFirstChildWhichIsA("TextLabel", true)
                    if textLabel then textLabel.Text = recoveredValue223 end
                end
            end
        end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then pcall(function() humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Limit end) end
    end

    local function HelperFunction77(attributeValue20)
        local recoveredValue361 = PlayerGui:FindFirstChild("Survivor-mob")
        if not recoveredValue361 then return nil end
        local frame4 = recoveredValue361:FindFirstChild("Frame")
        if not frame4 then return nil end
        for index = 1, 5 do
            local attributeValue13 = frame4:FindFirstChild("Survivor" .. index)
            if attributeValue13 and attributeValue13:GetAttribute("UserId") == attributeValue20 then
                return attributeValue13:FindFirstChild("TextLabel")
            end
        end
        return nil
    end

    local function HelperFunction113(player)
        local recoveredValue78 = (player == LocalPlayer)
        local recoveredValue270 = HelperFunction63(player)
        if not recoveredValue78 then
            if State.espObjects[player] then State.espObjects[player].nameLabel.Text = recoveredValue270 end
            if player.Character then HelperFunction59(player.Character, recoveredValue270) end
        end
        local textLabel = HelperFunction77(player.UserId)
        if textLabel then textLabel.Text = recoveredValue270 end
        if not recoveredValue78 and not State.pnameNameConns[player] then
            State.pnameNameConns[player] = player.CharacterAdded:Connect(function(char)
                if not State.stateField110 then return end
                local fn = HelperFunction63(player)
                task.wait(0.5)
                HelperFunction59(char, fn)
                if State.espObjects[player] then State.espObjects[player].nameLabel.Text = fn end
                local recoveredValue199 = HelperFunction77(player.UserId)
                if recoveredValue199 then recoveredValue199.Text = fn end
            end)
        end
    end

    local function HelperFunction93(player)
        local recoveredValue78 = (player == LocalPlayer)
        local recoveredValue223 = player.Name
        if not recoveredValue78 then
            if State.espObjects[player] then State.espObjects[player].nameLabel.Text = recoveredValue223 end
            if player.Character then HelperFunction76(player.Character, recoveredValue223) end
            if State.pnameNameConns[player] then
                State.pnameNameCono5[player].Disconnect(State.pnameNameConns[player])
                State.pnameNameConns[player] = nil
            end
        end
        local textLabel = HelperFunction77(player.UserId)
        if textLabel then textLabel.Text = recoveredValue223 end
    end

    local function HelperFunction27(attributeValue13, textLabel)
        local recoveredValue222 = attributeValue13.Name
        if State.pnameSlotConns[recoveredValue222] then
            State.pnameSlotConns[recoveredValue222].Disconnect(State.pnameSlotConns[recoveredValue222])
            State.pnameSlotConns[recoveredValue222] = nil
        end
        local attributeValue18 = attributeValue13:GetAttribute("UserId")
        if not attributeValue18 then return end
        local recoveredValue438
        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            if targetPlayer.UserId == attributeValue18 then recoveredValue438 = targetPlayer; break end
        end
        if not recoveredValue438 then return end
        local fn = HelperFunction63(recoveredValue438)
        State.pnameSlotConns[recoveredValue222] = textLabel:GetPropertyChangedSignal("Text"):Connect(function()
            if not State.stateField110 then return end
            local attributeValue6 = attributeValue13:GetAttribute("UserId")
            if not attributeValue6 then return end
            local recoveredValue7
            for _, targetPlayer in ipairs(Players:GetPlayers()) do
                if targetPlayer.UserId == attributeValue6 then recoveredValue7 = targetPlayer; break end
            end
            if not recoveredValue7 then return end
            local recoveredValue442 = HelperFunction63(recoveredValue7)
            if textLabel.Text ~= recoveredValue442 then textLabel.Text = recoveredValue442 end
        end)
    end

    local function HelperFunction100()
        for recoveredValue222, connection in pairs(State.pnameSlotConns) do
            connection:Disconnect()
            State.pnameSlotConns[recoveredValue222] = nil
        end
        local recoveredValue361 = PlayerGui:FindFirstChild("Survivor-mob")
        if not recoveredValue361 then return end
        local frame4 = recoveredValue361:FindFirstChild("Frame")
        if not frame4 then return end
        for index = 1, (5.0) do
            local attributeValue13 = frame4:FindFirstChild("Survivor" .. index)
            if attributeValue13 then
                local textLabel = attributeValue13:FindFirstChild("TextLabel")
                if textLabel then HelperFunction27(attributeValue13, textLabel) end
            end
        end
    end


    local function HelperFunction195(text)
        if type(text) ~= "string" or text == "" then return nil end
        local cache28 = {}
        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            for _, nm in ipairs({ targetPlayer.Name, targetPlayer.DisplayName }) do
                if type(nm) == "string" and #nm >= 3 then
                    cache28[#cache28 + 1] = { nm = nm, fake = HelperFunction63(targetPlayer) }
                end
            end
        end
        table.sort(cache28, function(attributeValue12, attributeValue22) return #attributeValue12.nm > #attributeValue22.nm end)
        for _, contextValue in ipairs(cache28) do
            if string.find(text, contextValue.nm, 1, true) then
                local recoveredValue367 = contextValue.nm:gsub("(%W)", "%%%1")
                return (text:gsub(recoveredValue367, contextValue.fake, 1))
            end
        end
        return nil
    end

    local function HelperFunction87(instance)
        local recoveredValue443 = instance.Parent
        for _ = (1.0), 6 do
            if not recoveredValue443 then break end
            if recoveredValue443.Name == "Survivor-mob" then return true end
            recoveredValue443 = recoveredValue443.Parent
        end
        return false
    end

    local function HelperFunction97(instance)
        if not State.stateField110 then return end
        local success, isText = pcall(function()
            return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
        end)
        if not success or not isText then return end
        if HelperFunction87(instance) then return end
        local successFlag3, cur = pcall(function() return instance.Text end)
        if not successFlag3 or type(cur) ~= "string" then return end
        local recoveredValue387 = HelperFunction195(cur)
        if not recoveredValue387 or recoveredValue387 == cur then return end
        State.pnameGenConns = State.pnameGenConns or {}
        State.pnameGenOrig = State.pnameGenOrig or {}
        State.pnameGenCount = State.pnameGenCount or (0.0)
        if State.pnameGenOrig[instance] == nil and State.pnameGenCount < 200 then
            State.pnameGenOrig[instance] = cur
            State.pnameGenCount = State.pnameGenCount + 1
        end
        pcall(function() instance.Text = recoveredValue387 end)
        if not State.pnameGenConns[instance] then
            State.pnameGenConns[instance] = instance:GetPropertyChangedSignal("Text"):Connect(function()
                if not State.stateField110 then return end
                local recoveredValue166 = State.pnameGenOrig[instance]
                if not recoveredValue166 then return end
                local recoveredValue304 = HelperFunction195(recoveredValue166)
                if recoveredValue304 then
                    local successFlag7, curNow = pcall(function() return instance.Text end)
                    if successFlag7 and curNow ~= recoveredValue304 then
                        pcall(function() instance.Text = recoveredValue304 end)
                    end
                end
            end)
        end
    end

    function StartProtectName()
        State.stateField110 = true
        for _, player in ipairs(Players:GetPlayers()) do HelperFunction113(player) end
        HelperFunction100()
        pcall(function()
            local recoveredValue40 = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if recoveredValue40 then
                for _, descendant in ipairs(recoveredValue40:GetDescendants()) do HelperFunction97(descendant) end
            end
        end)
        if not State.connection7 then
            State.connection7 = PlayerGui.ChildAdded:Connect(function(child)
                if child.Name == "Survivor-mob" then
                    task.wait(0.2)
                    if State.stateField110 then
                        HelperFunction100()
                        for _, player in ipairs(Players:GetPlayers()) do HelperFunction113(player) end
                    end
                end
            end)
        end
        if not State.connection11 then
            State.connection11 = Players.PlayerAdded:Connect(function(player)
                if State.stateField110 then
                    task.wait(1)
                    HelperFunction113(player)
                    HelperFunction100()
                end
            end)
        end
        if not State.pnameGenConn then
            State.pnameGenConn = PlayerGui.DescendantAdded:Connect(function(instance)
                task.defer(function()
                    if State.stateField110 then HelperFunction97(instance) end
                end)
            end)
        end
    end

    function StopProtectName()
        State.stateField110 = false
        for recoveredValue222, connection in pairs(State.pnameSlotConns) do
            connection:Disconnect()
            State.pnameSlotConns[recoveredValue222] = nil
        end
        if State.connection7 then
            State.connection7:Disconnect()
            State.connection7 = nil
        end
        if State.pnameGenConn then
            pcall(function() State.pnameGenConn:Disconnect() end)
            State.pnameGenConn = nil
        end
        for textLabel, connection in pairs(State.pnameGenConns or {}) do
            pcall(function() connection:Disconnect() end)
        end
        State.pnameGenConns = {}
        for textLabel, recoveredValue166 in pairs(State.pnameGenOrig or {}) do
            pcall(function()
                if textLabel and textLabel.Parent then textLabel.Text = recoveredValue166 end
            end)
        end
        State.pnameGenOrig = {}
        State.pnameGenCount = (0.0)
        for _, player in ipairs(Players:GetPlayers()) do HelperFunction93(player) end
        State.stateField63 = {}
        if State.connection11 then
            State.connection11:Disconnect()
            State.connection11 = nil
        end
    end


    local function HelperFunction14(attributeValue20)
        if State.stateField65 == attributeValue20 and State.stateField80 then
            return State.stateField80
        end
        local recoveredValue60 = nil
        for _ = 1, 3 do
            local success, recoveredValue81, ready = pcall(function()
                return Players:GetUserThumbnailAsync(attributeValue20, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
            end)
            if success and recoveredValue81 and recoveredValue81 ~= "" then
                recoveredValue60 = recoveredValue81
                if ready then break end
            end
            task.wait(1)
        end
        if recoveredValue60 then
            State.stateField80 = recoveredValue60
            State.stateField65 = attributeValue20
        end
        return recoveredValue60
    end

    local function HelperFunction184()
        local recoveredValue361 = PlayerGui:FindFirstChild("Survivor-mob")
        if not recoveredValue361 then return nil, nil end
        local frame4 = recoveredValue361:FindFirstChild("Frame")
        if not frame4 then return nil, nil end
        for index = (1.0), 5 do
            local attributeValue13 = frame4:FindFirstChild("Survivor" .. index)
            if attributeValue13 and attributeValue13:GetAttribute("UserId") == LocalPlayer.UserId then
                local recoveredValue81 = attributeValue13:FindFirstChild("ImageLabel")
                if recoveredValue81 then return attributeValue13, recoveredValue81 end
            end
        end
        return nil, nil
    end

    function _ApplyCopiedAvatarToUI()
        if not State.stateField23 or not State.stateField then return end
        local _, recoveredValue81 = HelperFunction184()
        if not recoveredValue81 then return end
        local recoveredValue60 = HelperFunction14(State.stateField)
        if recoveredValue60 and recoveredValue81.Parent and recoveredValue81.Image ~= recoveredValue60 then
            pcall(function() recoveredValue81.Image = recoveredValue60 end)
        end
    end

    local function HelperFunction205(attributeValue13, recoveredValue81)
        local recoveredValue222 = attributeValue13.Name
        local connection20 = State.avatarUiSlotConns[recoveredValue222]
        if connection20 then
            if type(connection20) == "table" then
                for _, contextValue in ipairs(connection20) do pcall(function() contextValue:Disconnect() end) end
            else
                pcall(function() connection20:Disconnect() end)
            end
            State.avatarUiSlotConns[recoveredValue222] = nil
        end
        local connection13 = {}
        connection13[#connection13 + 1] = recoveredValue81:GetPropertyChangedSignal("Image"):Connect(function()
            if not State.stateField23 or not State.stateField then return end
            if attributeValue13:GetAttribute("UserId") ~= LocalPlayer.UserId then return end
            local recoveredValue387 = State.stateField80
            if recoveredValue387 and recoveredValue81.Parent and recoveredValue81.Image ~= recoveredValue387 then
                pcall(function() recoveredValue81.Image = recoveredValue387 end)
            end
        end)
        connection13[#connection13 + 1] = attributeValue13:GetAttributeChangedSignal("UserId"):Connect(function()
            if not State.stateField23 or not State.stateField then return end
            task.wait(0.3)
            if attributeValue13:GetAttribute("UserId") == LocalPlayer.UserId then
                _ApplyCopiedAvatarToUI()
            end
        end)
        State.avatarUiSlotConns[recoveredValue222] = connection13
    end

    function _HookAllAvatarSlots()
        for recoveredValue222, connection13 in pairs(State.avatarUiSlotConns) do
            if type(connection13) == "table" then
                for _, contextValue in ipairs(connection13) do pcall(function() contextValue:Disconnect() end) end
            else
                pcall(function() connection13:Disconnect() end)
            end
            State.avatarUiSlotConns[recoveredValue222] = nil
        end
        local recoveredValue361 = PlayerGui:FindFirstChild("Survivor-mob")
        if not recoveredValue361 then return end
        local frame4 = recoveredValue361:FindFirstChild("Frame")
        if not frame4 then return end
        for index = 1, 5 do
            local attributeValue13 = frame4:FindFirstChild("Survivor" .. index)
            if attributeValue13 then
                local recoveredValue81 = attributeValue13:FindFirstChild("ImageLabel")
                if recoveredValue81 then HelperFunction205(attributeValue13, recoveredValue81) end
            end
        end
    end

    function _EnsureAvatarUiWatchers()
        if not State.stateField2 then
            State.stateField2 = PlayerGui.ChildAdded:Connect(function(child)
                if child.Name == "Survivor-mob" then
                    task.wait(0.2)
                    if State.stateField23 and State.stateField then
                        _HookAllAvatarSlots()
                        _ApplyCopiedAvatarToUI()
                    end
                end
            end)
        end
        if not State.stateField62 then
            State.stateField62 = LocalPlayer.CharacterAdded:Connect(function()
                if not State.stateField then return end
                task.wait(1)
                if State.stateField then
                    State.stateField23 = true
                    HandlePerfMonitorInput(tostring(State.stateField))
                end
            end)
        end
    end
end

local function ApplyLightingPreset(darknessMode)
    darknessMode = darknessMode or false
    local camera = Workspace.CurrentCamera
    local cameraValue2 = State.skipEndScreenConns


    local recoveredValue234 = false
    local recoveredValue108 = false
    local recoveredValue142 = false


    pcall(function()
        local recoveredValue409 = ReplicatedStorage:FindFirstChild("Remotes")
        if not recoveredValue409 then return end

        local function HelperFunction174(remote)
            if remote and remote:IsA("RemoteEvent") then
                for _, connection in ipairs(getconnections(remote.OnClientEvent)) do
                    connection:Disable()
                    connection:Disconnect()
                end
            end
        end

        local recoveredValue32 = recoveredValue409:FindFirstChild("Game")
        if recoveredValue32 then
            for _, name in ipairs({"cutscene", "cutsceneEnd", "cutsceneEnd2", "endscreencutscene", "cutsceneEndwithownchar", "shake"}) do
                HelperFunction174(recoveredValue32:FindFirstChild(name))
            end
        end

        local recoveredValue402 = recoveredValue409:FindFirstChild("Killers")
        if recoveredValue402 then HelperFunction174(recoveredValue402:FindFirstChild("Startmori")) end


        if darknessMode then
            HelperFunction174(recoveredValue409:FindFirstChild("Darkness2"))
        end
    end)


    local function HelperFunction106()
        if not camera then return end
        if camera.CameraType == Enum.CameraType.Scriptable then
            recoveredValue234 = true
            camera.CameraType = Enum.CameraType.Custom
            recoveredValue234 = false
        end
    end

    if camera then
        HelperFunction106()
        table.insert(cameraValue2, camera:GetPropertyChangedSignal("CameraType"):Connect(function()
            if not recoveredValue234 then HelperFunction106() end
        end))

        table.insert(cameraValue2, camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
            if recoveredValue108 or Config.lockFovEnabled then return end
            if camera.FieldOfView ~= 70 then
                recoveredValue108 = true
                camera.FieldOfView = 70
                recoveredValue108 = false
            end
        end))
    end

    table.insert(cameraValue2, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        camera = Workspace.CurrentCamera
        if camera then HelperFunction106() end
    end))


    table.insert(cameraValue2, LocalPlayer:GetAttributeChangedSignal("isspectating"):Connect(function()
        if recoveredValue142 then return end
        if LocalPlayer:GetAttribute("isspectating") then
            recoveredValue142 = true
            LocalPlayer:SetAttribute("isspectating", false)
            recoveredValue142 = false
        end
    end))

    table.insert(cameraValue2, LocalPlayer:GetAttributeChangedSignal("killerend"):Connect(function()
        if recoveredValue142 then return end
        if LocalPlayer:GetAttribute("killerend") then
            recoveredValue142 = true
            LocalPlayer:SetAttribute("killerend", false)
            recoveredValue142 = false
        end
    end))


    local function HelperFunction5()
        local recoveredValue363 = Workspace:FindFirstChild("Map")
        if recoveredValue363 then
            local recoveredValue328 = recoveredValue363:FindFirstChild("endscreen")
            if recoveredValue328 then
                pcall(function() recoveredValue328.Parent = nil end)
            end
        end

        local recoveredValue188 = Workspace:FindFirstChild("BackgroundSounds")
        if recoveredValue188 then
            pcall(function() recoveredValue188:Destroy() end)
        end
    end

    HelperFunction5()

    table.insert(cameraValue2, Workspace.DescendantAdded:Connect(function(descendant)
        if descendant.Name == "endscreen" and descendant.Parent and descendant.Parent.Name == "Map" then
            task.wait(0.01)
            pcall(function() descendant.Parent = nil end)
        elseif descendant.Name == "BackgroundSounds" then
            pcall(function() descendant:Destroy() end)
        end
    end))


    local function HelperFunction11(gui)
        if not gui or not gui.Parent then return end
        pcall(function()

            if darknessMode and gui.Name == "Darkness" and gui:IsA("ScreenGui") then
                gui.Enabled = false
            end

            local function HelperFunction118(descendant)
                if descendant:IsA("VideoFrame") then
                    descendant:Destroy()
                elseif descendant:IsA("Frame") and (descendant.Name == "Frame2" or descendant.Name == "blackout") then
                    descendant.BackgroundTransparency = (1.0)
                    if darknessMode then
                        descendant.Visible = false

                        descendant:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
                            if descendant.BackgroundTransparency < 1 then descendant.BackgroundTransparency = (1.0) end
                        end)
                        descendant:GetPropertyChangedSignal("Visible"):Connect(function()
                            if descendant.Visible then descendant.Visible = false end
                        end)
                    end
                elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
                    descendant.Enabled = false
                end
                for _, child in ipairs(descendant:GetChildren()) do HelperFunction118(child) end
            end
            HelperFunction118(gui)
        end)
    end

    for _, child in ipairs(PlayerGui:GetChildren()) do
        local n = child.Name
        if n == "Darkness" or n == "EndScreen" or n == "Cutscene" or n == "Results" then
            HelperFunction11(child)
        end
    end

    table.insert(cameraValue2, PlayerGui.ChildAdded:Connect(function(child)
        local n = child.Name
        if n == "Darkness" or n == "EndScreen" or n == "Cutscene" or n == "Results" then
            task.wait(0.05)
            HelperFunction11(child)
        end
    end))
end

local function GetLightingPresetName()
    for _, connection10 in ipairs(State.skipEndScreenConns) do
        pcall(function() connection10:Disconnect() end)
    end
    table.clear(State.skipEndScreenConns)
end

local SetParryRadiusEspEnabled
do
    local timeValue20=98163597193511
    local recoveredValue337="rbxassetid://"..timeValue20
    local recoveredValue158=30
    local recoveredValue213=13.8
    local recoveredValue61=0.08
    local cache23={
        ["rbxassetid://117070354890871"]={type="lungehold",length=2.00,speed=1.00},
        ["rbxassetid://106871536134254"]={type="attack",length=3.00,speed=1.00},
        ["rbxassetid://109402730355822"]={type="attack",length=2.95,speed=1.00}
    }
    local recoveredValue365=4.5
    local recoveredValue27=2.75
    local recoveredValue171=1
    local recoveredValue369=0.18
    local recoveredValue218=2.25
    local cache19={
        [113255068724446]={type="lungehold",length=1.00,speed=1.00,triggerProgress=0.018,triggerTime=0.018},
        [74968262036854]={type="attack",length=1.70,speed=1.00,triggerProgress=0.018,triggerTime=0.030},
        [135002183282873]={type="lungehold",length=1.50,speed=1.00,triggerProgress=0.015,triggerTime=0.022},
        [121216847022485]={type="attack",length=1.75,speed=1.00,triggerProgress=0.015,triggerTime=0.025},
        [117042998468241]={type="lungehold",length=1.00,speed=1.00,triggerProgress=0.018,triggerTime=0.018},
        [133963973694098]={type="attack",length=1.72,speed=1.00,triggerProgress=0.016,triggerTime=0.025},
        [110355011987939]={type="lungehold",length=1.00,speed=1.00,triggerProgress=0.012,triggerTime=0.012},
        [139369275981139]={type="attack",length=1.72,speed=1.00,triggerProgress=0.014,triggerTime=0.022},
        [118907603246885]={type="lungehold",length=0.83,speed=1.00,triggerProgress=0.010,triggerTime=0.010},
        [78432063483146]={type="attack",length=1.72,speed=1.00,triggerProgress=0.018,triggerTime=0.025},
        [122812055447896]={type="lungehold",length=0.75,speed=1.00,triggerProgress=0.010,triggerTime=0.008},
        [78935059863801]={type="attack",length=1.63,speed=1.00,triggerProgress=0.016,triggerTime=0.022},
        [129784271201071]={type="lungehold",length=1.00,speed=1.00,triggerProgress=0.015,triggerTime=0.015},
        [132817836308238]={type="attack",length=1.72,speed=1.00,triggerProgress=0.017,triggerTime=0.025},
        [105374834496520]={type="lungehold",length=1.00,speed=1.00,triggerProgress=0.010,triggerTime=0.010},
        [111920872708571]={type="attack",length=1.72,speed=1.00,triggerProgress=0.014,triggerTime=0.022}
    }
    local cache44={}
    for id,profile in pairs(cache19) do
        cache44["rbxassetid://"..id]=profile
    end

    local function HelperFunction82(player,char)
        if not player or not char then return nil end
        if player==LocalPlayer then
            local attributeValue17=LocalPlayer:GetAttribute("SelectedKiller")
            if attributeValue17 then return attributeValue17 end
        end
        local success,values=pcall(function() return char:WaitForChild("Values",2) end)
        if success and values then
            local recoveredValue89=values:FindFirstChild("KillerName")
            if recoveredValue89 and recoveredValue89:IsA("StringValue") then return recoveredValue89.Value end
        end
        local attributeValue17=player:GetAttribute("SelectedKiller")
        if attributeValue17 then return attributeValue17 end
        return nil
    end
    local function HelperFunction150()
        local char=LocalPlayer.Character
        if not char then return end
        local recoveredValue23=PlayerGui:FindFirstChild("Survivor-mob")
        local recoveredValue118=recoveredValue23 and recoveredValue23:FindFirstChild("Controls")
        local recoveredValue274=recoveredValue118 and recoveredValue118:FindFirstChild("Gui-mob")
        if recoveredValue274 and recoveredValue274:IsA("ImageButton") then
            firesignal(recoveredValue274.MouseButton1Down)
            task.defer(function()
                if recoveredValue274 and recoveredValue274.Parent then firesignal(recoveredValue274.MouseButton1Up) end
            end)
        else
            local success,fakeInput=pcall(function()
                local instance=Instance.new("InputObject")
                instance.UserInputType=Enum.UserInputType.MouseButton2
                instance.UserInputState=Enum.UserInputState.Begin
                return instance
            end)
            if success and fakeInput then
                for _,connection in getconnections(UserInputService.InputBegan) do
                    connection:Fire(fakeInput,false)
                end
            else
                VirtualInputManager:SendMouseButtonEvent(0,0,1,true,game,(0.0))
            end
        end
        local rootPart2=char:FindFirstChild("HumanoidRootPart")
        if rootPart2 then
            pcall(function()
                if CollectionService:HasTag(rootPart2,"doing action") then
                    CollectionService:RemoveTag(rootPart2,"doing action")
                end
            end)
        end
    end
    local function HelperFunction216(force,rootPart23,distanceValue6)
        if not State.autoParryEnabled then return false end
        local timeValue12=tick()
        if timeValue12-State.stateField107<0.01 then return false end
        if rootPart23 and distanceValue6 then
            local recoveredValue128=State.parryRadius
            local recoveredValue203=false
            local timeValue4=State.stateField4[rootPart23]
            if timeValue4 and timeValue4.profile and timeValue4.profile.type=="lungehold" then
                recoveredValue203=true
            end
            if distanceValue6>recoveredValue128 then return false end

            local skipLOS = force and distanceValue6<=recoveredValue27

            local function HelperFunction206()
                if skipLOS then return true end
                local rootPart4=LocalPlayer.Character
                local rootPart6=rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")
                local rootPart14=rootPart23:FindFirstChild("HumanoidRootPart")
                if not rootPart6 or not rootPart14 then return false end
                local recoveredValue332=rootPart6.Position
                local target=rootPart14.Position
                local distanceValue58=target-recoveredValue332
                if distanceValue58.Magnitude<=0.05 then return true end
                local recoveredValue280=RaycastParams.new()
                recoveredValue280.FilterType=Enum.RaycastFilterType.Exclude
                recoveredValue280.FilterDescendantsInstances={rootPart4,rootPart23}
                recoveredValue280.IgnoreWater=true

                local vectorValue21={
                    Vector3.new(0,  0,    0),   -- center (original)
                    Vector3.new(0,  1.1,  0),   -- upper (original)
                    Vector3.new(0, -0.75, 0),   -- lower (original)
                    Vector3.new(0,  0.5,  0),   -- mid-high: covers running lean
                    Vector3.new(0, -0.3,  0),   -- mid-low: covers crouched root
                    Vector3.new(0,  1.6,  0),   -- head height: covers standing/vaulting
                }
                local recoveredValue34=false
                for _,vectorValue16 in ipairs(vectorValue21) do
                    local recoveredValue248=Workspace:Raycast(recoveredValue332+vectorValue16,distanceValue58,recoveredValue280)
                    if not recoveredValue248 then
                        return true
                    end
                    local vectorValue4=recoveredValue248.Instance
                    if vectorValue4 then
                        local n=vectorValue4.Name:lower()
                        if n:find("vault") or n:find("window") or n:find("ledge") then
                            recoveredValue34=true
                        end
                    end
                end
                if recoveredValue203 and recoveredValue34 and distanceValue6<=recoveredValue128+recoveredValue218 then
                    return true
                end
                return false
            end
            if not HelperFunction206() then
                return false
            end
        end
        State.stateField107=timeValue12
        HelperFunction150()
        return true
    end
    local function HelperFunction36()
        if not State.autoParryEnabled then return false end
        local timeValue12=tick()
        if timeValue12-State.stateField46<0.003 then return false end
        State.stateField46=timeValue12
        HelperFunction150()
        return true
    end
    local function HelperFunction53(recoveredValue74)
        if typeof(recoveredValue74)~="string" then return false end
        local name=recoveredValue74:lower()
        return name=="the masked (duck)" or name=="the masked"
    end
    local function HelperFunction81(char)
        local rootPart4=LocalPlayer.Character
        local rootPart6=rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")
        local rootPart14=char and char:FindFirstChild("HumanoidRootPart")
        if not rootPart6 or not rootPart14 then return math.huge end
        local attributeValue12=rootPart6.Position
        local attributeValue22=rootPart14.Position
        return (Vector3.new(attributeValue12.X,(0.0),attributeValue12.Z)-Vector3.new(attributeValue22.X,0,attributeValue22.Z)).Magnitude
    end
    local function HelperFunction115(char,timeValue4)
        if timeValue4.timeValue19 or not State.autoParryEnabled then return false end
        if timeValue4.name:lower()~="the hidden" then return false end
        local distanceValue6=HelperFunction81(char)
        if distanceValue6<=recoveredValue158 then
            if HelperFunction36() then
                timeValue4.timeValue19=true
                return true
            end
        end
        return false
    end
    local function HelperFunction89(char,timeValue3,track)
        if timeValue3:lower()~="the hidden" then return end
        local timeValue4={name=timeValue3,track=track,type="skill",started=tick(),timeValue19=false,skillId=timeValue20}
        State.stateField21[char]=timeValue4
        local connection
        connection=track.Stopped:Connect(function()
            if connection then connection:Disconnect() end
            task.defer(function()
                if State.stateField21[char] and State.stateField21[char].track==track then
                    State.stateField21[char]=nil
                end
            end)
        end)
        HelperFunction115(char,timeValue4)
    end
    local function HelperFunction57(char,timeValue3,track,profile,timeValue9)
        if not HelperFunction53(timeValue3) then return end
        local timeValue4={name=timeValue3,track=track,type="maskedfast",started=tick(),timeValue19=false,id=timeValue9,profile=profile}
        State.stateField93[char]=timeValue4
        local connection
        connection=track.Stopped:Connect(function()
            if connection then connection:Disconnect() end
            task.defer(function()
                if State.stateField93[char] and State.stateField93[char].track==track then
                    State.stateField93[char]=nil
                end
            end)
        end)
        local distanceValue6=HelperFunction81(char)
        if distanceValue6<=State.parryRadius then
            if HelperFunction36() then timeValue4.timeValue19=true end
        end
    end
    local function HelperFunction140(player,char)
        if player==LocalPlayer then return end
        task.wait(0.5)
        if not char.Parent then return end
        local recoveredValue74=HelperFunction82(player,char)
        if recoveredValue74 or (player.Team and player.Team.Name:lower():find("killer")) then
            local timeValue3=recoveredValue74 or "Unknown Killer"
            State.killerCharacters[char]={player=player,name=timeValue3}
            char.AncestryChanged:Connect(function(_,parentObject)
                if not parentObject then
                    State.killerCharacters[char]=nil
                    State.stateField4[char]=nil
                    State.stateField21[char]=nil
                    State.stateField93[char]=nil
                end
            end)
            local humanoid10=char:WaitForChild("Humanoid",3)
            if humanoid10 then
                local recoveredValue400=humanoid10:WaitForChild("Animator",3)
                if recoveredValue400 then
                    recoveredValue400.AnimationPlayed:Connect(function(track)
                        if not State.autoParryEnabled then return end
                        if not track or not track.Animation then return end
                        local timeValue9=track.Animation.AnimationId
                        if timeValue9==recoveredValue337 and timeValue3:lower()=="the hidden" then
                            HelperFunction89(char,timeValue3,track)
                            return
                        end
                        local recoveredValue22=cache23[timeValue9]
                        if recoveredValue22 and HelperFunction53(timeValue3) then
                            HelperFunction57(char,timeValue3,track,recoveredValue22,tonumber(timeValue9:match("%d+")))
                            return
                        end
                        local profile=cache44[timeValue9]
                        if not profile then return end
                        local timeValue15=tonumber(timeValue9:match("%d+"))
                        local timeValue4={name=timeValue3,track=track,type=profile.type,id=timeValue15,profile=profile,started=tick(),timeValue19=false,parried=false,lastTimePosition=(-1.0)}
                        State.stateField4[char]=timeValue4
                        local connection
                        connection=track.Stopped:Connect(function()
                            if connection then connection:Disconnect() end
                            task.delay(0.15,function()
                                if State.stateField4[char] and State.stateField4[char].track==track then
                                    State.stateField4[char]=nil
                                end
                            end)
                        end)
                    end)
                end
            end
        end
    end
    local function HelperFunction181(player)
        if player==LocalPlayer then return end
        if player.Character then
            task.spawn(function()
                HelperFunction140(player,player.Character)
            end)
        end
        player.CharacterAdded:Connect(function(char)
            task.spawn(function()
                HelperFunction140(player,char)
            end)
        end)
    end
    for _,player in ipairs(Players:GetPlayers()) do
        if player~=LocalPlayer then HelperFunction181(player) end
    end
    Players.PlayerAdded:Connect(HelperFunction181)
    local function GetParryMotion(killerRoot, playerRoot)
        if not killerRoot or not playerRoot then return nil end
        local sep = playerRoot.Position - killerRoot.Position
        local sep2D = Vector3.new(sep.X, 0, sep.Z)
        local killerVel3 = killerRoot.AssemblyLinearVelocity
        local playerVel3 = playerRoot.AssemblyLinearVelocity
        local killerVel = Vector3.new(killerVel3.X, 0, killerVel3.Z)
        local playerVel = Vector3.new(playerVel3.X, 0, playerVel3.Z)
        local relativeVel = killerVel - playerVel
        return sep2D, killerVel, playerVel, relativeVel
    end

    local function RelativeApproach(killerRoot, playerRoot)
        local sep2D, _, _, relativeVel = GetParryMotion(killerRoot, playerRoot)
        if not sep2D or sep2D.Magnitude <= 0.001 then return 0 end
        return relativeVel:Dot(sep2D.Unit)
    end

    local function PredictedDistance(killerRoot, playerRoot, leadTime)
        local sep2D, _, _, relativeVel = GetParryMotion(killerRoot, playerRoot)
        if not sep2D then return math.huge end
        leadTime = math.max(tonumber(leadTime) or 0, 0)
        return (sep2D - relativeVel * leadTime).Magnitude
    end

    local function MarkAttackParried(entry)
        if not entry then return end
        entry.parried = true
        entry.timeValue19 = true -- preserve legacy flag for the rest of the recovered engine
    end

    RegisterUpdateTask("CloseRangeMonitor",(0.0),function()
        if not State.autoParryEnabled then return end
        local rootPart4=LocalPlayer.Character
        local rootPart6=rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")
        if not rootPart6 then return end

        for rootPart23,_ in pairs(State.killerCharacters) do
            if not rootPart23 or not rootPart23.Parent then
                State.killerCharacters[rootPart23]=nil
            else
                local attack=State.stateField4[rootPart23]
                local track=attack and attack.track
                if attack and track and track.IsPlaying and not attack.parried and not attack.timeValue19 then
                    local rootPart14=rootPart23:FindFirstChild("HumanoidRootPart")
                    if rootPart14 then
                        local liveSep=Vector3.new(
                            rootPart6.Position.X-rootPart14.Position.X,
                            0,
                            rootPart6.Position.Z-rootPart14.Position.Z
                        )
                        local distanceValue6=liveSep.Magnitude
                        local approach=RelativeApproach(rootPart14,rootPart6)
                        local ping=math.clamp(LocalPlayer:GetNetworkPing(),0,0.3)
                        local predicted=PredictedDistance(rootPart14,rootPart6,ping)

                        local playerVel3=rootPart6.AssemblyLinearVelocity
                        local playerSpeed2D=Vector3.new(playerVel3.X,0,playerVel3.Z).Magnitude
                        local adjustedInner2=recoveredValue27+(playerSpeed2D>8 and 1.2 or playerSpeed2D>4 and 0.6 or 0)

                        local closeCandidate=false
                        if distanceValue6<=adjustedInner2 then
                            closeCandidate=true
                        elseif distanceValue6<=recoveredValue365 and approach>=recoveredValue171 then
                            local timeToClose=distanceValue6/math.max(approach,0.001)
                            if timeToClose<=recoveredValue369 or predicted<=3.75 then
                                closeCandidate=true
                            end
                        end

                        if closeCandidate and HelperFunction216(true,rootPart23,distanceValue6) then
                            MarkAttackParried(attack)
                        end
                    end
                end
            end
        end
    end)

    RegisterUpdateTask("AttackersMonitor",0,function()
        if not State.autoParryEnabled then return end
        if next(State.stateField4)==nil then return end

        for rootPart23,timeValue4 in pairs(State.stateField4) do
            if not rootPart23 or not rootPart23.Parent or not timeValue4.track then
                State.stateField4[rootPart23]=nil
            elseif not timeValue4.track.IsPlaying then
                State.stateField4[rootPart23]=nil
            elseif not timeValue4.timeValue19 and not timeValue4.parried then
                local profile=timeValue4.profile
                local rootPart14=rootPart23:FindFirstChild("HumanoidRootPart")
                local rootPart4=LocalPlayer.Character
                local rootPart6=rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")

                if rootPart14 and rootPart6 and profile then
                    local liveSep,killerVel,playerVel,relativeVel=GetParryMotion(rootPart14,rootPart6)
                    if liveSep then
                        local distanceValue6=liveSep.Magnitude
                        local approach=liveSep.Magnitude>0.001 and relativeVel:Dot(liveSep.Unit) or 0

                        local closeAttack=false
                        if distanceValue6<=recoveredValue27 then
                            closeAttack=true
                        elseif distanceValue6<=recoveredValue365 and approach>=recoveredValue171 then
                            local timeToClose=distanceValue6/math.max(approach,0.001)
                            if timeToClose<=recoveredValue369 then closeAttack=true end
                        end

                        local playerSpeed=playerVel.Magnitude
                        local adjustedInner=recoveredValue27+(playerSpeed>8 and 1.2 or playerSpeed>4 and 0.6 or 0)

                        if distanceValue6<=adjustedInner then
                            closeAttack=true
                        end

                        if closeAttack then
                            if HelperFunction216(true,rootPart23,distanceValue6) then
                                MarkAttackParried(timeValue4)
                            end
                        else
                            local tp=timeValue4.track.TimePosition or 0
                            local trackLength=timeValue4.track.Length
                            local length=(trackLength and trackLength>0) and trackLength or profile.length
                            local speed=profile.speed or 1
                            local scaledTp=tp*speed
                            local scaledLength=length/speed
                            local progress=scaledLength>0 and scaledTp/scaledLength or 0
                            local triggerTime=(profile.triggerTime or 0)/speed
                            local triggerProgress=profile.triggerProgress or 0

                            local elapsed=tick()-timeValue4.started
                            local attackWindowReached=tp>=triggerTime or progress>=triggerProgress
                                or elapsed>=(triggerTime+0.016) -- one extra frame of slack

                            local lungePredict=false
                            local lungeUrgent=false
                            if profile.type=="lungehold" then
                                local effectiveRange=3.5
                                local gap=math.max(distanceValue6-effectiveRange,0)
                                local timeToRange=math.huge
                                if approach>0 then timeToRange=gap/approach end
                                lungePredict=approach>=6 and timeToRange<=0.32
                                lungeUrgent=approach>=4 and timeToRange<=0.16
                            end

                            if attackWindowReached or lungePredict or lungeUrgent then
                                local directionOK=true
                                local liveDir=Vector3.new(
                                    rootPart6.Position.X-rootPart14.Position.X,
                                    0,
                                    rootPart6.Position.Z-rootPart14.Position.Z
                                )
                                if liveDir.Magnitude>0.001 and killerVel.Magnitude>6 then
                                    local threshold=math.clamp(tonumber(State.parryAimStrictness) or 0.1,-1,1)
                                    directionOK=killerVel.Unit:Dot(liveDir.Unit)>=threshold
                                end

                                if directionOK then
                                    local ping=math.clamp(LocalPlayer:GetNetworkPing(),0,0.3)
                                    local predicted=PredictedDistance(rootPart14,rootPart6,ping)

                                    if distanceValue6<=State.parryRadius and predicted<=State.parryRadius+2 then
                                        if HelperFunction216(false,rootPart23,distanceValue6) then
                                            MarkAttackParried(timeValue4)
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    RunService.Heartbeat:Connect(function()
        if not State.autoParryEnabled then return end
        local rootPart4=LocalPlayer.Character
        local rootPart6=rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")
        if not rootPart6 then return end
        local vectorValue63=rootPart6.Position
        local vectorValue14=rootPart6.AssemblyLinearVelocity
        local vectorValue28=Vector3.new(vectorValue14.X,0,vectorValue14.Z)
        for rootPart23,timeValue4 in pairs(State.stateField21) do
            if not rootPart23 or not rootPart23.Parent or not timeValue4 or not timeValue4.track then
                State.stateField21[rootPart23]=nil
            elseif not timeValue4.track.IsPlaying then
                State.stateField21[rootPart23]=nil
            elseif not timeValue4.timeValue19 and timeValue4.skillId==timeValue20 and timeValue4.name and timeValue4.name:lower()=="the hidden" then
                local rootPart14=rootPart23:FindFirstChild("HumanoidRootPart")
                if rootPart14 then
                    local vectorValue11=rootPart14.Position
                    local vectorValue53=rootPart14.AssemblyLinearVelocity
                    local vectorValue45=Vector3.new(vectorValue53.X,0,vectorValue53.Z)
                    local vectorValue10=Vector3.new(vectorValue63.X-vectorValue11.X,0,vectorValue63.Z-vectorValue11.Z)
                    local distanceValue6=vectorValue10.Magnitude
                    if distanceValue6<=recoveredValue158 then
                        if HelperFunction36() then timeValue4.timeValue19=true end
                    else
                        local distanceValue61=vectorValue45-vectorValue28
                        local vectorValue7=vectorValue10.Magnitude>0 and distanceValue61:Dot(vectorValue10.Unit) or 0
                        if vectorValue7>0 then
                            local vectorValue27=distanceValue6-vectorValue7*recoveredValue61
                            if vectorValue27<=recoveredValue158 then
                                local recoveredValue388=HelperFunction81(rootPart23)
                                if recoveredValue388<=recoveredValue158 then
                                    if HelperFunction36() then timeValue4.timeValue19=true end
                                end
                            end
                        end
                    end
                end
            end
        end
        for rootPart23,timeValue4 in pairs(State.stateField93) do
            if not rootPart23 or not rootPart23.Parent or not timeValue4 or not timeValue4.track then
                State.stateField93[rootPart23]=nil
            elseif not timeValue4.track.IsPlaying then
                State.stateField93[rootPart23]=nil
            elseif not timeValue4.timeValue19 and HelperFunction53(timeValue4.name) then
                local rootPart14=rootPart23:FindFirstChild("HumanoidRootPart")
                if rootPart14 then
                    local vectorValue11=rootPart14.Position
                    local vectorValue53=rootPart14.AssemblyLinearVelocity
                    local vectorValue45=Vector3.new(vectorValue53.X,(0.0),vectorValue53.Z)
                    local vectorValue10=Vector3.new(vectorValue63.X-vectorValue11.X,0,vectorValue63.Z-vectorValue11.Z)
                    local distanceValue6=vectorValue10.Magnitude
                    if distanceValue6<=State.parryRadius then
                        if HelperFunction36() then timeValue4.timeValue19=true end
                    else
                        local distanceValue61=vectorValue45-vectorValue28
                        local vectorValue7=vectorValue10.Magnitude>0 and distanceValue61:Dot(vectorValue10.Unit) or 0
                        if vectorValue7>0 then
                            local vectorValue27=distanceValue6-vectorValue7*0.05
                            if vectorValue27<=State.parryRadius then
                                local recoveredValue388=HelperFunction81(rootPart23)
                                if recoveredValue388<=State.parryRadius then
                                    if HelperFunction36() then timeValue4.timeValue19=true end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)


    local cache33    = {}
    local connection25    = nil
    local cache45   = {}
    local recoveredValue167   = 32
    local recoveredValue38 = (-1.0)

    local function CreateParryRadiusRing()
        for _, targetPlayer in ipairs(cache33) do
            if targetPlayer and targetPlayer.Parent then targetPlayer:Destroy() end
        end
        cache33  = {}
        cache45 = {}

        local recoveredValue208 = (2 * math.pi) / recoveredValue167
        for index = 1, recoveredValue167 do
            local recoveredValue168     = recoveredValue208 * (index - (1.0))
            local recoveredValue366 = recoveredValue208 * index
            cache45[index] = {
                cx  = math.cos(recoveredValue168),
                cz  = math.sin(recoveredValue168),
                nx  = math.cos(recoveredValue366),
                nz  = math.sin(recoveredValue366),
            }

            local colorValue2 = Instance.new("Part")
            colorValue2.Shape        = Enum.PartType.Block
            colorValue2.Anchored     = true
            colorValue2.CanCollide   = false
            colorValue2.CanQuery     = false
            colorValue2.CastShadow   = false
            colorValue2.Material     = Enum.Material.Neon
            colorValue2.Color        = Color3.fromRGB((255.0), 60, 60)
            colorValue2.Transparency = 0.15
            colorValue2.Size         = Vector3.new(0.08, 0.08, 0.1)
            colorValue2.Name         = "BlehHubESP_Seg"
            colorValue2.Parent       = Workspace
            cache33[index]       = colorValue2
        end
    end

    local function ResizeParryRadiusRing(vectorValue62)
        local vectorValue58 = (2 * math.pi * vectorValue62) / recoveredValue167
        for _, colorValue2 in ipairs(cache33) do
            if colorValue2 and colorValue2.Parent then
                colorValue2.Size = Vector3.new(0.08, 0.08, vectorValue58 + 0.02)
            end
        end
    end

    local function DestroyParryRadiusRing()
        for _, targetPlayer in ipairs(cache33) do
            if targetPlayer and targetPlayer.Parent then targetPlayer:Destroy() end
        end
        cache33  = {}
        cache45 = {}
        recoveredValue38 = (-1.0)
    end

    function SetParryRadiusEspEnabled(attributeValue4)
        if attributeValue4 then
            CreateParryRadiusRing()
            connection25 = RunService.RenderStepped:Connect(function()
                if not LocalPlayer.Character then return end
                local rootPart2 = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if not rootPart2 then return end

                local vectorValue62 = State.parryRadius
                if vectorValue62 ~= recoveredValue38 then
                    ResizeParryRadiusRing(vectorValue62)
                    recoveredValue38 = vectorValue62
                end

                local cameraValue11 = rootPart2.Position - Vector3.new(0, rootPart2.Size.Y / (2.0) + 1.5, 0)

                for index, colorValue2 in ipairs(cache33) do
                    if colorValue2 and colorValue2.Parent then
                        local contextValue   = cache45[index]
                        local pos = cameraValue11 + Vector3.new(contextValue.cx * vectorValue62, 0, contextValue.cz * vectorValue62)
                        local vectorValue43 = cameraValue11 + Vector3.new(contextValue.nx * vectorValue62, 0, contextValue.nz * vectorValue62)
                        colorValue2.CFrame = CFrame.lookAt(pos, vectorValue43) * CFrame.new(0, 0, -colorValue2.Size.Z / (2.0))
                    end
                end
            end)
        else
            if connection25 then connection25:Disconnect(); connection25 = nil end
            DestroyParryRadiusRing()
        end
    end
end

local function SavePerformanceSettings()
    for _, part6 in ipairs(State.worldEspObjects.Gates) do
        ApplyGhostGateToObj(part6, State.ghostGateLegitMode)
    end
end

local function LoadPerformanceSettings()
    local char = LocalPlayer.Character
    local rootPart2 = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart2 then Notify("Teleport", "Character not found!", 2); return end
    local cframeValue2 = workspace:FindFirstChild("Fininshline", true)
    if not cframeValue2 then Notify("Teleport", "Finish line not found on the map!", 2); return end
    local vectorValue2 = cframeValue2.Position
    local vectorValue30 = RaycastParams.new()
    vectorValue30.FilterType = Enum.RaycastFilterType.Exclude
    vectorValue30.FilterDescendantsInstances = {char, cframeValue2.Parent}
    local vectorValue56 = nil
    local vectorValue49 = vectorValue2 + Vector3.new(0, 10, 0)
    local vectorValue4 = workspace:Raycast(vectorValue49, Vector3.new((0.0), (-30.0), (0.0)), vectorValue30)
    if vectorValue4 then
        local vectorValue36 = workspace:Raycast(vectorValue4.Posin5on + Vector3.new(0, (5.0), 0), Vector3.new(0, 5, 0), vectorValue30)
        if not vectorValue36 then vectorValue56 = vectorValue4.Position + Vector3.new(0, 3, 0) end
    end
    if vectorValue56 then
        pcall(function() rootPart2.CFrame = CFrame.new(vectorValue56) end)
    else
        pcall(function() rootPart2.CFrame = cframeValue2.CFrame end)
    end
end

local SetCrouchState
do
    local recoveredValue134 = "80411309607666"
    local function HelperFunction156(timeValue9)
        if not timeValue9 then return "" end
        return tostring(timeValue9):match("%d+") or ""
    end
    local function GetMobileCrouchButton()
        local recoveredValue285 = LocalPlayer:FindFirstChild("PlayerGui")
        if not recoveredValue285 then return nil end
        local recoveredValue352 = recoveredValue285:FindFirstChild("Survivor-mob")
        if not recoveredValue352 then return nil end
        local recoveredValue317 = recoveredValue352:FindFirstChild("Controls")
        if not recoveredValue317 then return nil end
        local recoveredValue274 = recoveredValue317:FindFirstChild("crouch")
        if recoveredValue274 and recoveredValue274:IsA("GuiButton") then return recoveredValue274 end
        return nil
    end
    function SetCrouchState(attributeValue4)
        if State.crouchingForced ~= attributeValue4 then
            State.crouchingForced = attributeValue4
            local char = LocalPlayer.Character
            if char then
                char:SetAttribute("Crouchingserver", attributeValue4)
                char:SetAttribute("Crouching", attributeValue4)
            end
            pcall(function()
                ReplicatedStorage.Remotes.Mechanics.ChangeAttribute:FireServer("Crouchingserver", attributeValue4)
                ReplicatedStorage.Remotes.Mechanics.ChangeAttribute:FireServer("Crouching", attributeValue4)
            end)
            local recoveredValue113 = not UserInputService.TouchEnabled and UserInputService.KeyboardEnabled
            if recoveredValue113 then
                VirtualInputManager:SendKeyEvent(attributeValue4, Enum.KeyCode.C, false, game)
                VirtualInputManager:SendKeyEvent(attributeValue4, Enum.KeyCode.LeftControl, false, game)
            else
                local recoveredValue274 = GetMobileCrouchButton()
                if recoveredValue274 and type(firesignal) == "function" then
                    if attributeValue4 then
                        firesignal(recoveredValue274.MouseButton1Down)
                        if recoveredValue274.MouseButton1Click then firesignal(recoveredValue274.MouseButton1Click) end
                    else
                        firesignal(recoveredValue274.MouseButton1Up)
                        if recoveredValue274.MouseButton1Click then firesignal(recoveredValue274.MouseButton1Click) end
                    end
                end
            end
        end
    end
    local function HelperFunction173(char)
        if not char then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        if State.autoCrouchAnimConns[humanoid] then return end
        State.autoCrouchAnimConns[humanoid] = humanoid.AnimationPlayed:Connect(function(track)
            if not Config.autoCrouchEnabled then return end
            local animation2 = track.Animation
            if animation2 then
                local recoveredValue321 = HelperFunction156(animation2.AnimationId)
                if recoveredValue321 == recoveredValue134 then
                    State.autoCrouchActiveSlashers[char] = true
                    track.Stopped:Connect(function()
                        task.wait(0.2)
                        State.autoCrouchActiveSlashers[char] = nil
                    end)
                end
            end
        end)
         humanoid.Died:Connect(function()
          State.autoCrouchActiveSlashers[char] = nil


           if State.autoCrouchAnimConns[humanoid] then
             State.autoCrouchAnimConns[humanoid].Disconnect(State.autoCrouchAnimConns[humanoid])
             State.autoCrouchAnimConns[humanoid] = nil
           end
        end)
    end
    RegisterUpdateTask("AutoCrouch", 0, function()
        if not Config.autoCrouchEnabled then return end
        local rootPart4 = LocalPlayer.Character
        if not rootPart4 then return end
        local rootPart6 = rootPart4:FindFirstChild("HumanoidRootPart")
        if not rootPart6 then return end
        local recoveredValue258 = false
        for rootPart23, _ in pairs(State.autoCrouchActiveSlashers) do
            if rootPart23 and rootPart23.Parent then
                local rootPart11 = rootPart23:FindFirstChild("HumanoidRootPart")
                local humanoid5 = rootPart23:FindFirstChildOfClass("Humanoid")
                if rootPart11 and humanoid5 and humanoid5.Health > 0 then
                    local dist = (rootPart11.Position - rootPart6.Position).Magnitude
                    if dist <= Config.autoCrouchRadius then
                        recoveredValue258 = true
                        break
                    end
                end
            else
                State.autoCrouchActiveSlashers[rootPart23] = nil
            end
        end
        SetCrouchState(recoveredValue258)
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then HelperFunction173(player.Character) end
        if player ~= LocalPlayer then
            player.CharacterAdded:Connect(function(newChar)
                task.wait((1.0))
                HelperFunction173(newChar)
            end)
        end
    end
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(newChar)
            task.wait(1)
            if Config.autoCrouchEnabled then HelperFunction173(newChar) end
        end)
    end)
end

local function HandlePerfMonitorInput(input)
    if not input or input:gsub("%s+", "") == "" then return end
    input = input:gsub("%s+", "")

    task.spawn(function()

        local attributeValue20 = tonumber(input)
        if not attributeValue20 then
            local recoveredValue85 = pcall(function() attributeValue20 = Players:GetUserIdFromNameAsync(input) end)
            if not recoveredValue85 or not attributeValue20 then return end
        end

        local char = LocalPlayer.Character
        local humanoid10 = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not humanoid10 then return end


        local descendant = Players:GetHumanoidDescriptionFromUserId(attributeValue20)
        if not descendant then return end

        local recoveredValue255 = Players:CreateHumanoidModelFromDescription(descendant, humanoid10.RigType)
        if not recoveredValue255 then return end


        for _, instance in ipairs(char:GetChildren()) do
            if instance:IsA("Accessory") or instance:IsA("Shirt") or instance:IsA("Pants") or instance:IsA("ShirtGraphic") or instance:IsA("BodyColors") or instance:IsA("CharacterMesh") then
                instance:Destroy()
            end
        end
        for _, child3 in ipairs(char:GetChildren()) do
            if child3:IsA("BasePart") then
                for _, child in ipairs(child3:GetChildren()) do
                    if child:IsA("SpecialMesh") or child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance") then
                        child:Destroy()
                    end
                end
            end
        end


        local recoveredValue76 = recoveredValue255:FindFirstChildOfClass("BodyColors")
        if recoveredValue76 then
            recoveredValue76:Clone().Parent = char
            local cache49 = {
                Head = recoveredValue76.HeadColor3, Torso = recoveredValue76.TorsoColor3,
                ["Left Arm"] = recoveredValue76.LeftArmColor3, ["Right Arm"] = recoveredValue76.RightArmColor3,
                ["Left Leg"] = recoveredValue76.LeftLegColor3, ["Right Leg"] = recoveredValue76.RightLegColor3,
                UpperTorso = recoveredValue76.TorsoColor3, LowerTorso = recoveredValue76.TorsoColor3,
                LeftHand = recoveredValue76.LeftArmColor3, RightHand = recoveredValue76.RightArmColor3,
                LeftLowerArm = recoveredValue76.LeftArmColor3, RightLowerArm = recoveredValue76.RightArmColor3,
                LeftUpperArm = recoveredValue76.LeftArmColor3, RightUpperArm = recoveredValue76.RightArmColor3,
                LeftFoot = recoveredValue76.LeftLegColor3, RightFoot = recoveredValue76.RightLegColor3,
                LeftLowerLeg = recoveredValue76.LeftLegColor3, RightLowerLeg = recoveredValue76.RightLegColor3,
                LeftUpperLeg = recoveredValue76.LeftLegColor3, RightUpperLeg = recoveredValue76.RightLegColor3,
            }
            for recoveredValue233, color in pairs(cache49) do
                local part = char:FindFirstChild(recoveredValue233)
                if part then pcall(function() part.Color = color end) end
            end
        end

        for _, instance in ipairs(recoveredValue255:GetChildren()) do
            if instance:IsA("Shirt") or instance:IsA("Pants") or instance:IsA("ShirtGraphic") or instance:IsA("CharacterMesh") then
                instance:Clone().Parent = char
            end
        end


        for _, child2 in ipairs(recoveredValue255:GetChildren()) do
            if child2:IsA("BasePart") then
                local child3 = char:FindFirstChild(child2.Name)
                if child3 and child3:IsA("BasePart") then
                    if child2:IsA("MeshPart") and child3:IsA("MeshPart") then
                        pcall(function()
                            child3.MeshId = child2.MeshId
                            child3.TextureID = child2.TextureID
                            child3.Color = child2.Color
                            child3.Transparency = child2.Transparency
                        end)
                    end
                    for _, child in ipairs(child2:GetChildren()) do
                        if child:IsA("SpecialMesh") or child:IsA("Decal") or child:IsA("Texture") or child:IsA("SurfaceAppearance") then
                            child:Clone().Parent = child3
                        end
                    end
                end
            end
        end


        local function HelperFunction154(acc)
            local recoveredValue136 = acc:Clone()
            recoveredValue136.Parent = char
            local cframeValue17 = recoveredValue136:FindFirstChild("Handle")
            if not cframeValue17 then return end

            cframeValue17.Anchored = false
            cframeValue17.CanCollide = false
            pcall(function() cframeValue17.Massless = true end)


            for _, child in ipairs(cframeValue17:GetChildren()) do
                if child:IsA("Weld") or child:IsA("WeldConstraint") or child:IsA("Motor6D") then
                    child:Destroy()
                end
            end


            pcall(function() humanoid10:AddAccessory(recoveredValue136) end)


            local recoveredValue422 = false
            for _, child in ipairs(cframeValue17:GetChildren()) do
                if (child:IsA("Weld") or child:IsA("WeldConstraint")) and child.Part1 and child.Part1:IsDescendantOf(char) then
                    recoveredValue422 = true
                    break
                end
            end


            if not recoveredValue422 then
                local cframeValue7 = cframeValue17:FindFirstChildOfClass("Attachment")
                local rootPart10 = nil
                local cframeValue4 = nil

                if cframeValue7 then
                    local rootPart9 = char:FindFirstChild(cframeValue7.Name, true)
                    if rootPart9 and rootPart9:IsA("Attachment") then
                        rootPart10 = rootPart9.Parent
                        cframeValue4 = rootPart9
                    end
                end

                if not rootPart10 then rootPart10 = char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart") end

                if rootPart10 then
                    if cframeValue4 and cframeValue7 then
                        cframeValue17.CFrame = rootPart10.CFrame * cframeValue4.CFrame * cframeValue7.CFrame:Inverse()
                    else
                        cframeValue17.CFrame = rootPart10.CFrame
                    end
                    local recoveredValue230 = Instance.new("WeldConstraint")
                    recoveredValue230.Name = "BlehHubWeld"
                    recoveredValue230.Part0 = cframeValue17
                    recoveredValue230.Part1 = rootPart10
                    recoveredValue230.Parent = cframeValue17
                end
            end
        end


        for _, instance in ipairs(recoveredValue255:GetChildren()) do
            if instance:IsA("Accessory") then
                pcall(function() HelperFunction154(instance) end)
            end
        end


        recoveredValue255:Destroy()


        if attributeValue20 then
            if State.stateField ~= attributeValue20 then
                State.stateField = attributeValue20
                State.stateField80 = nil
                State.stateField65 = nil
            end
            State.stateField23 = true
            _EnsureAvatarUiWatchers()
            _HookAllAvatarSlots()
            _ApplyCopiedAvatarToUI()
        end
    end)
end

local EnableFullbright, restoreLighting, removeVisualEffects, restoreVisualEffects
do
    local cache22 = {
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        ColorShift_Bottom = Lighting.ColorShift_Bottom,
        ColorShift_Top = Lighting.ColorShift_Top,
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        GlobalShadows = Lighting.GlobalShadows,
        FogStart = Lighting.FogStart,
        FogEnd = Lighting.FogEnd,
        FogColor = Lighting.FogColor,
        ExposureCompensation = Lighting.ExposureCompensation,
        EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
        EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
    }
    local cache52 = {}

    function EnableFullbright()
        Lighting.Ambient = Color3.fromRGB(178, (178.0), 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, (178.0))
        Lighting.ColorShift_Bottom = Color3.new((0.0), 0, (0.0))
        Lighting.ColorShift_Top = Color3.new(0, 0, 0)
        Lighting.Brightness = (3.0); Lighting.ClockTime = (12.0); Lighting.GlobalShadows = false
        Lighting.FogStart = 9e9; Lighting.FogEnd = 9e9; Lighting.ExposureCompensation = (0.0)
        Lighting.EnvironmentDiffuseScale = 0; Lighting.EnvironmentSpecularScale = 0
    end

    function restoreLighting()
        for distanceValue7, value2 in pairs(cache22) do pcall(function() Lighting[distanceValue7] = value2 end) end
    end

    function removeVisualEffects()
        cache52 = {}
        for _, effect in ipairs(Lighting:GetChildren()) do
            if effect:IsA("PostEffect") or effect:IsA("Clouds") or effect:IsA("Atmosphere") or effect:IsA("Sky") then
                cache52[effect] = { Enabled = effect.Enabled, Parent = effect.Parent }
                pcall(function()
                    if effect:IsA("Sky") then effect.Parent = nil else effect.Enabled = false end
                end)
            end
        end
    end

    function restoreVisualEffects()
        for currentValue, timeValue4 in pairs(cache52) do
            if currentValue then
                pcall(function()
                    if currentValue:IsA("Sky") then currentValue.Parent = timeValue4.Parent else currentValue.Enabled = timeValue4.Enabled end
                end)
            end
        end
        cache52 = {}
    end

    RegisterUpdateTask("LightingEnforcer", 0.5, function()
        if State.fullbrightEnabled then EnableFullbright() end
        if State.removeVisualEffectsEnabled then
            for _, effect in ipairs(Lighting:GetChildren()) do
                if effect:IsA("PostEffect") or effect:IsA("Clouds") or effect:IsA("Atmosphere") or effect:IsA("Sky") then
                    pcall(function()
                        if effect:IsA("Sky") then
                            if effect.Parent then effect.Parent = nil end
                        else
                            if effect.Enabled then effect.Enabled = false end
                        end
                    end)
                end
            end
        end
    end)

    Lighting.ChildAdded:Connect(function(child)
        if State.removeVisualEffectsEnabled then
            if child:IsA("PostEffect") or child:IsA("Clouds") or child:IsA("Atmosphere") or child:IsA("Sky") then
                task.spawn(function()
                    pcall(function()
                        if child:IsA("Sky") then child.Parent = nil else child.Enabled = false end
                    end)
                end)
            end
        end
    end)
end

do
    local function HelperFunction119()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "BlehHubFOV"; screenGui.ResetOnSpawn = false; screenGui.DisplayOrder = 999999
        pcall(function() screenGui.Parent = (gethui and gethui() or game:GetService("CoreGui")) end)
        if not screenGui.Parent then screenGui.Parent = PlayerGui end
        State.frame6 = Instance.new("Frame")
        State.frame6.Size = UDim2.new(0, Config.silentAimFovRadius * 2, 0, Config.silentAimFovRadius * 2)
        State.frame6.Position = UDim2.new(0.5, 0, 0.5, (0.0))
        State.frame6.AnchorPoint = Vector2.new(0.5, 0.5)
        State.frame6.BackgroundColor3 = Color3.fromRGB(255, (255.0), 255)
        State.frame6.BackgroundTransparency = 1; State.frame6.Visible = false
        State.frame6.Parent = screenGui
        local recoveredValue226 = Instance.new("UICorner"); recoveredValue226.CornerRadius = UDim.new(1, (0.0)); recoveredValue226.Parent = State.frame6
        local colorValue14 = Instance.new("UIStroke")
        colorValue14.Color = NotifyColor; colorValue14.Thickness = 2; colorValue14.Transparency = 0.2; colorValue14.Parent = State.frame6
    end
    pcall(HelperFunction119)

    local function HelperFunction94(char)
        if not char then return nil end
        local part4 = char:FindFirstChild("UpperTorso")
        if part4 and part4:IsA("BasePart") then return part4.Position end
        local part2 = char:FindFirstChild("Torso")
        if part2 and part2:IsA("BasePart") then return part2.Position end
        local rootPart2 = char:FindFirstChild("HumanoidRootPart")
        if rootPart2 then return rootPart2.Position end
        return nil
    end

    local function HelperFunction65()
        local char = LocalPlayer.Character
        if not char then return nil end
        local success, gun = pcall(function()
            return char:FindFirstChild("Twist of Fate"):FindFirstChild("Right Arm"):FindFirstChild("gun"):FindFirstChild("gun")
        end)
        if success and gun and gun:IsA("BasePart") then return gun.Position end
        local recoveredValue323 = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
        if recoveredValue323 then return recoveredValue323.Position end
        return nil
    end

    local function ResolveTwistOfFateRemote()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage
        local items = remotes:FindFirstChild("Items", true)
        local twistOfFate = items and items:FindFirstChild("Twist of Fate", true)
        return (twistOfFate and FindRemoteEvent(twistOfFate, "Fire"))
            or (items and FindRemoteEvent(items, "Fire"))
    end
    local remote32 = ResolveTwistOfFateRemote()

    task.defer(function()
        local deadline = tick() + 8
        while not (remote32 and remote32.Parent) and tick() < deadline do
            task.wait(0.25)
            remote32 = ResolveTwistOfFateRemote()
        end
        if not (remote32 and remote32:IsA("RemoteEvent")) then
            return
        end
        if typeof(hookmetamethod) ~= "function" or typeof(getnamecallmethod) ~= "function" then
            warn("[Bleh Hub BOOT] Executor lacks hookmetamethod/getnamecallmethod - Twist of Fate hook disabled")
            return
        end

        local recoveredValue184
        local okToFHook, errToFHook = pcall(function()
            recoveredValue184 = hookmetamethod(game, "__namecall", function(self, ...)
                local remote27 = getnamecallmethod()
                if remote27 == "FireServer" and rawequal(self, remote32) then
                    local recoveredValue111 = table.pack(...)
                    if State.silentAimEnabled and typeof(State.vectorValue44) == "Vector3" then
                        if recoveredValue111.n >= (3.0) and typeof(recoveredValue111[(3.0)]) == "Vector3" then
                            recoveredValue111[3] = State.vectorValue44
                            if State.silentAimLaserEspEnabled then State.stateField88 = true end
                            local distanceValue54 = State.stateField43
                            if distanceValue54 then
                                print(string.format("[ToF] fire dist=%.0f tof=%.2f lead=%.1f vel=%.1f pred=%d damp=%d zig=%d dot=%.2f ping=%.0fms", distanceValue54.dist or 0, distanceValue54.tof or 0, distanceValue54.lead or 0, distanceValue54.vel or (0.0), distanceValue54.pred or 0, distanceValue54.damp or 0, distanceValue54.zig or 0, distanceValue54.dot or (0.0), (distanceValue54.ping or 0) * (1000.0)))
                            end
                        elseif recoveredValue111.n >= (2.0) and typeof(recoveredValue111[(2.0)]) == "Vector3" then
                            recoveredValue111[2] = State.vectorValue44
                            if State.silentAimLaserEspEnabled then State.stateField88 = true end
                            local distanceValue54 = State.stateField43
                            if distanceValue54 then
                                print(string.format("[ToF] fire dist=%.0f tof=%.2f lead=%.1f vel=%.1f pred=%d damp=%d zig=%d dot=%.2f ping=%.0fms", distanceValue54.dist or 0, distanceValue54.tof or (0.0), distanceValue54.lead or (0.0), distanceValue54.vel or 0, distanceValue54.pred or 0, distanceValue54.damp or 0, distanceValue54.zig or 0, distanceValue54.dot or 0, (distanceValue54.ping or 0) * (1000.0)))
                            end
                        end
                    end
                    return recoveredValue184(self, table.unpack(recoveredValue111, 1, recoveredValue111.n))
                end
                return recoveredValue184(self, ...)
            end)
        end)
        if not okToFHook then
            warn("[Bleh Hub BOOT] Twist of Fate hook failed: " .. tostring(errToFHook))
        end
    end)

    RegisterUpdateTask("UpdateSilentAimTarget", 0.02, function()
        if State.frame6 then
            State.frame6.Visible = State.silentAimFovCircleEnabled
            local recoveredValue63 = Config.silentAimFovRadius * 2
            if State.frame6.Size.X.Offset ~= recoveredValue63 then
                State.frame6.Size = UDim2.new((0.0), recoveredValue63, 0, recoveredValue63)
            end
        end
        if not State.silentAimEnabled then
            State.stateField79 = nil; State.vectorValue44 = nil; State.stateField30 = nil
            State.stateField87 = nil; State.stateField74 = {}; State.stateField43 = nil; return
        end
        local rootPart22 = LocalPlayer.Character
        if not rootPart22 then return end
        local rootPart13 = rootPart22:FindFirstChild("HumanoidRootPart")
        if not rootPart13 then return end
        local cameraValue9 = workspace.CurrentCamera
        if not cameraValue9 then return end
        local distanceValue5 = nil
        local closestDistance = math.huge
        local rootPart5 = nil
        local recoveredValue417 = Config.silentAimTargetType or "Killer"

        if recoveredValue417 == "Zombie" then

            if tick() - zombieCacheTime > 0.5 then RefreshZombieCache() end
            for index = 1, #recoveredValue189 do
                local rootPart15 = recoveredValue189[index]
                if rootPart15 and rootPart15.Parent then
                    local rootPart2 = GetScpModelRoot(rootPart15)
                    if rootPart2 then
                        local pos = rootPart2.Position
                        local dist = (pos - rootPart13.Position).Magnitude
                        if dist < closestDistance then closestDistance = dist; distanceValue5 = pos; rootPart5 = rootPart15 end
                    end
                end
            end
        else
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    if recoveredValue417 == "Killer" and GetPlayerRole(player) ~= "killer" then continue end
                    if recoveredValue417 == "Survivor" and GetPlayerRole(player) ~= "survivor" then continue end
                    local humanoid9 = player.Character
                    if humanoid9 then
                        local humanoid12 = humanoid9:FindFirstChildOfClass("Humanoid")
                        local distanceValue26 = HelperFunction94(humanoid9)
                        if humanoid12 and humanoid12.Health > 0 and typeof(distanceValue26) == "Vector3" then
                            local dist = (distanceValue26 - rootPart13.Position).Magnitude
                            if dist < closestDistance then closestDistance = dist; distanceValue5 = distanceValue26; rootPart5 = humanoid9 end
                        end
                    end
                end
            end
        end

        local timeValue12 = tick()
        local vectorValue39 = State.vectorValue52
        if typeof(vectorValue39) ~= "Vector3" then vectorValue39 = Vector3.new((0.0), 0, 0) end
        local distanceValue8 = 0
        local recoveredValue92 = false
        if typeof(distanceValue5) == "Vector3" then
            if State.stateField87 ~= rootPart5 then
                State.stateField87 = rootPart5
                State.stateField74 = {}
                vectorValue39 = Vector3.new(0, 0, (0.0))
            end
            local hist = State.stateField74
            table.insert(hist, { pos = distanceValue5, t = timeValue12 })
            while #hist > 1 and hist[1].t < timeValue12 - 0.4 do table.remove(hist, (1.0)) end
            if #hist >= 2 then
                local attributeValue12 = hist[#hist - (1.0)]
                local attributeValue22 = hist[#hist]
                local recoveredValue206 = attributeValue22.t - attributeValue12.t
                if recoveredValue206 > 0.001 then
                    local vectorValue23 = (attributeValue22.pos - attributeValue12.pos) / recoveredValue206
                    local currentValue = Vector3.new(vectorValue23.X, 0, vectorValue23.Z)
                    local rootPart2 = rootPart5 and rootPart5:FindFirstChild("HumanoidRootPart")
                    if rootPart2 and rootPart2:IsA("BasePart") then
                        local success, av = pcall(function() return rootPart2.AssemblyLinearVelocity end)
                        if success and typeof(av) == "Vector3" then
                            local vectorValue51 = Vector3.new(av.X, 0, av.Z)
                            if vectorValue51.Magnitude > 0.5 and vectorValue51.Magnitude < 100 then
                                currentValue = currentValue:Lerp(vectorValue51, 0.5)
                            end
                        end
                    end
                    if currentValue.Magnitude > (65.0) then currentValue = currentValue.Unit * 65 end
                    if Config.silentAimAdaptiveDamping and vectorValue39.Magnitude > (2.0) and currentValue.Magnitude > (2.0) then
                        distanceValue8 = vectorValue39:Dot(currentValue) / (vectorValue39.Magnitude * currentValue.Magnitude)
                        if distanceValue8 < 0 then
                            currentValue = currentValue * 0.7
                            recoveredValue92 = true
                        end
                    end
                    vectorValue39 = vectorValue39:Lerp(currentValue, TOF_VEL_LERP)
                end
            end
            local vectorValue54 = Vector3.new(vectorValue39.X, 0, vectorValue39.Z)
            if vectorValue54.Magnitude > 65 then vectorValue54 = vectorValue54.Unit * 65 end
            vectorValue39 = vectorValue54
        else
            State.stateField87 = nil
            State.stateField74 = {}
            vectorValue39 = Vector3.new(0, 0, 0)
        end
        State.vectorValue65 = vectorValue39
        State.vectorValue52 = vectorValue39

        if typeof(distanceValue5) == "Vector3" then
            local vectorValue57 = distanceValue5
            if typeof(vectorValue57) == "Vector3" then
                local recoveredValue389 = true
                local recoveredValue254, onScreen = cameraValue9:WorldToViewportPoint(vectorValue57)
                if onScreen then
                    local cameraValue11 = Vector2.new(cameraValue9.ViewportSize.X / (2.0), cameraValue9.ViewportSize.Y / 2)
                    local distanceValue25 = (Vector2.new(recoveredValue254.X, recoveredValue254.Y) - cameraValue11).Magnitude
                    if distanceValue25 > Config.silentAimFovRadius then recoveredValue389 = false end
                else
                    recoveredValue389 = false
                end
                if recoveredValue389 then
                    local cframeValue10 = HelperFunction65()
                    if typeof(cframeValue10) ~= "Vector3" then cframeValue10 = cameraValue9.CFrame.Position end
                    local vectorValue3 = vectorValue57 - Vector3.new((0.0), 1.2, 0)
                    local distanceValue22 = vectorValue3 - cframeValue10
                    local distanceValue11 = distanceValue22.Magnitude
                    if distanceValue11 > 0.1 then
                        local vectorValue37 = vectorValue3
                        local distanceValue38 = distanceValue11 / 200 + 0.1
                        local distanceValue33 = 0
                        local vectorValue18 = 0
                        if typeof(State.vectorValue52) == "Vector3" then
                            vectorValue18 = Vector3.new(State.vectorValue52.X, 0, State.vectorValue52.Z).Magnitude
                        end
                        if Config.silentAimAutoPrediction then
                            local recoveredValue439 = State.vectorValue52
                            local pingComp = TOF_BASE_LAG
                            pcall(function()
                                if typeof(Spear_PingSec) == "function" then
                                    pingComp = math.clamp((Spear_PingSec() or 0) * 0.5 + TOF_BASE_LAG, TOF_BASE_LAG, 0.25)
                                end
                            end)
                            -- iterasi 1: estimasi kasar
                            local tof = distanceValue11 / TOF_BULLET_SPEED + pingComp
                            vectorValue37 = vectorValue3 + recoveredValue439 * tof
                            -- iterasi 2: refine dengan jarak baru ke predicted pos
                            local distanceValue32 = vectorValue37 - cframeValue10
                            if distanceValue32.Magnitude > 0.1 then
                                tof = distanceValue32.Magnitude / TOF_BULLET_SPEED + pingComp
                                vectorValue37 = vectorValue3 + recoveredValue439 * tof
                            end
                            -- iterasi 3: final refinement
                            distanceValue32 = vectorValue37 - cframeValue10
                            if distanceValue32.Magnitude > 0.1 then
                                tof = distanceValue32.Magnitude / TOF_BULLET_SPEED + pingComp
                                vectorValue37 = vectorValue3 + recoveredValue439 * tof
                            end
                            distanceValue38 = tof
                            distanceValue33 = (vectorValue37 - vectorValue3).Magnitude
                            State.stateField30 = vectorValue37
                        else
                            State.stateField30 = nil
                        end
                        local vectorValue31 = vectorValue37 - cframeValue10
                        local vectorValue32 = vectorValue31.Magnitude
                        if vectorValue32 > 0.1 then
                            State.stateField79 = vectorValue57
                            State.vectorValue44 = Vector3.new(vectorValue31.X / vectorValue32, vectorValue31.Y / vectorValue32, vectorValue31.Z / vectorValue32)
                            if typeof(State.stateField112) == "Vector3" then
                            State.stateField112 = State.stateField112:Lerp(vectorValue37, 0.25)
                            else
                            State.stateField112 = vectorValue37
                            end
                        State.stateField9 = cframeValue10
                            local timeValue10 = (0.0)
                            pcall(function()
                                if typeof(Spear_PingSec) == "function" then timeValue10 = Spear_PingSec() or 0 end
                            end)
                            State.stateField43 = {
                                dist = distanceValue11, tof = distanceValue38, lead = distanceValue33, vel = vectorValue18,
                                pred = Config.silentAimAutoPrediction and 1 or 0,
                                damp = Config.silentAimAdaptiveDamping and 1 or 0,
                                zig = recoveredValue92 and 1 or 0, dot = distanceValue8 or 0,
                                ping = timeValue10, t = tick(),
                            }
                        else
                            State.stateField79 = nil; State.vectorValue44 = nil
                            State.stateField43 = nil
                        end
                    else
                        State.stateField79 = nil; State.vectorValue44 = nil
                        State.stateField43 = nil
                    end
                else
                    State.stateField79 = nil; State.vectorValue44 = nil
                    State.stateField43 = nil
                end
            else
                State.stateField79 = nil; State.vectorValue44 = nil
                State.stateField43 = nil
            end
        else
            State.stateField79 = nil; State.vectorValue44 = nil
            State.stateField43 = nil
        end
    end)

    local _laserAdornment = nil
    local _laserHandle    = nil

    local function _EnsureLaserAdornment()
        if _laserAdornment and _laserAdornment.Parent then return end
        -- buat handle invisible sebagai anchor
        _laserHandle = Instance.new("Part")
        _laserHandle.Name = "BlehHubLaserHandle"
        _laserHandle.Anchored = true
        _laserHandle.CanCollide = false
        _laserHandle.Transparency = 1
        _laserHandle.Size = Vector3.new(0.1, 0.1, 0.1)
        _laserHandle.Parent = workspace

        _laserAdornment = Instance.new("CylinderHandleAdornment")
        _laserAdornment.Name = "BlehHubLaserESP"
        _laserAdornment.Adornee = _laserHandle
        _laserAdornment.Color3 = Color3.fromRGB(255, 40, 40)
        _laserAdornment.Transparency = 0.15
        _laserAdornment.Radius = 0.06
        _laserAdornment.Height = 1
        _laserAdornment.CFrame = CFrame.new()
        _laserAdornment.ZIndex = 5
        _laserAdornment.AlwaysOnTop = true
        _laserAdornment.Visible = false
        _laserAdornment.Parent = _laserHandle
    end
    pcall(_EnsureLaserAdornment)

    RegisterUpdateTask("DrawLaserESP", 0, function()
        pcall(_EnsureLaserAdornment)
        if not (_laserAdornment and _laserAdornment.Parent) then return end

        local shouldShow = State.silentAimEnabled
            and State.silentAimLaserEspEnabled
            and typeof(State.vectorValue44) == "Vector3"
            and typeof(State.stateField9) == "Vector3"
            and typeof(State.stateField112) == "Vector3"

        if not shouldShow then
            _laserAdornment.Visible = false
            return
        end

        local origin = State.stateField9     -- gun muzzle position
        local target = State.stateField112   -- predicted target position

        local diff   = target - origin
        local dist   = diff.Magnitude
        if dist < 0.1 then
            _laserAdornment.Visible = false
            return
        end

        local midpoint = origin + diff * 0.5
        _laserHandle.CFrame   = CFrame.new(midpoint, target)
        _laserAdornment.Height = dist
        _laserAdornment.CFrame = CFrame.new(0, 0, 0)  -- relative to handle
        _laserAdornment.Visible = true

        -- Briefly brighten the red flash when firing.
        if State.stateField88 then
            State.stateField88 = false
            _laserAdornment.Color3 = Color3.fromRGB(255, 255, 0)  -- kuning = fired
            task.delay(0.12, function()
                if _laserAdornment then
                    _laserAdornment.Color3 = Color3.fromRGB(255, 40, 40)
                end
            end)
        end
    end)

end

do
    local distanceValue47 = 30

    local function HelperFunction162(char)
        if not char then return false end
        if char:FindFirstChild("Flashlight") then return true end
        for _, child in ipairs(char:GetDescendants()) do
            if child.Name == "Flashlight" and (child:IsA("Model") or child:IsA("Tool") or child:IsA("Accessory")) then
                return true
            end
        end
        return false
    end

    local function HelperFunction(character)
        if not character then return false end
        local humanoid10 = character:FindFirstChildOfClass("Humanoid")
        if not humanoid10 or humanoid10.Health <= 50 then return false end
        local attributeValue9 = character:GetAttribute("IsHooked") or character:GetAttribute("isHooked")
        if attributeValue9 == true then return false end
        return true
    end

    local function HelperFunction135(char)
        if not char then return nil end
        local rootPart19 = char:FindFirstChild("Head")
        if rootPart19 and rootPart19:IsA("BasePart") then return rootPart19 end
        return char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("HumanoidRootPart")
    end

    local function HelperFunction152()
        local rootPart4 = LocalPlayer.Character
        local rootPart6 = rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")
        if not rootPart6 then return nil end
        local recoveredValue109, closestDistance = nil, math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and HelperFunction(player.Character) then
                if GetPlayerRole(player) == "killer" then
                    local part = HelperFunction135(player.Character)
                    if part and part:IsA("BasePart") then
                        local dist = (rootPart6.Position - part.Position).Magnitude
                        if dist <= distanceValue47 and dist < closestDistance then
                            closestDistance = dist
                            recoveredValue109 = part
                        end
                    end
                end
            end
        end
        return recoveredValue109
    end

    local remote3 = nil
    pcall(function()
        local recoveredValue409 = ReplicatedStorage:FindFirstChild("Remotes")
        local items = recoveredValue409 and recoveredValue409:FindFirstChild("Items")
        local recoveredValue196 = items and items:FindFirstChild("Flashlight")
        local remote33 = recoveredValue196 and recoveredValue196:FindFirstChild("Activate")
        if remote33 and remote33:IsA("RemoteEvent") then
            remote3 = remote33
        end
    end)

    local recoveredValue69
    pcall(function()
        recoveredValue69 = hookmetamethod(game, "__namecall", function(self, ...)
            local remote27 = getnamecallmethod()
            if remote27 == "FireServer" and remote3 and rawequal(self, remote3) then
                local recoveredValue111 = table.pack(...)
                pcall(function() State.flashlightActive = (recoveredValue111[(2.0)] == true) end)
            end
            return recoveredValue69(self, ...)
        end)
    end)

    RegisterUpdateTask("FlashAimLock", 0.02, function()
        if not State.flashlightAimlockEnabled then return end
        local recoveredValue318 = HelperFunction162(LocalPlayer.Character)
        local recoveredValue249 = GetPlayerRole(LocalPlayer) ~= "killer"
        if not (recoveredValue318 and recoveredValue249 and State.flashlightActive) then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        local recoveredValue299 = HelperFunction152()
        if not recoveredValue299 then return end
        local vectorValue9 = recoveredValue299.Position
        local smooth = math.clamp(tonumber(State.flashlightAimSmoothness) or 0.35, 0.05, 1)
        pcall(function()
            camera.CFrame = camera.CFrame:Lerp(CFrame.new(camera.CFrame.Position, vectorValue9), smooth)
        end)
        pcall(function()
            local char = LocalPlayer.Character
            local rootPart16 = char and char:FindFirstChild("HumanoidRootPart")
            if rootPart16 then
                rootPart16.CFrame = CFrame.new(rootPart16.Position, Vector3.new(vectorValue9.X, rootPart16.Position.Y, vectorValue9.Z))
            end
        end)
    end)
end

local SetInvisibleEnabled
do
    local vectorValue42 = Vector3.new(0, -6000, 0)
    local recoveredValue293 = 0.5
    local recoveredValue181 = 5

    local cache31 = {}

    local function HelperFunction16()
        local success, remote2 = pcall(function()
            local remote10 = game:GetService("ReplicatedStorage")
            local recoveredValue409 = remote10:FindFirstChild("Remotes")
            if not recoveredValue409 then return nil end
            local textLabel4 = recoveredValue409:FindFirstChild("Game")
            if not textLabel4 then return nil end
            local e = textLabel4:FindFirstChild("UpdateCharacterLook")
            if e and e:IsA("RemoteEvent") then return e end
            return nil
        end)
        if success then return remote2 end
        return nil
    end

    local function HelperFunction127(...)
        local cache18 = {}
        local n = select("#", ...)
        for index = (1.0), n do
            local value2 = select(index, ...)
            if typeof(value2) == "CFrame" then
                value2 = value2 + vectorValue42
            end
            cache18[index] = value2
        end
        return table.unpack(cache18, 1, n)
    end

    local function SendInvisibleState()
        if not State.invisibleEnabled then return false end
        local recoveredValue424 = State.invisibleRemoteArgs
        if type(recoveredValue424) ~= "table" or #recoveredValue424 ~= 5 then return false end
        local remote2 = HelperFunction16()
        if not remote2 then return false end
        local recoveredValue133 = table.pack(pcall(HelperFunction127, table.unpack(recoveredValue424)))
        if not recoveredValue133[1] then return false end
        local remote9 = remote2.FireServer
        if typeof(remote9) ~= "function" then return false end
        local recoveredValue394 = pcall(remote9, remote2, table.unpack(recoveredValue133, 2, recoveredValue133.n))
        if recoveredValue394 then
            State.stateField59 = 0
            State.stateField27 = State.stateField27 + (1.0)
        else
            State.stateField59 = State.stateField59 + (1.0)
        end
        return recoveredValue394
    end

    local function RestoreInvisibleState()
        if State.invisibleEnabled then return false end
        local recoveredValue424 = State.invisibleRemoteArgs
        if type(recoveredValue424) ~= "table" or #recoveredValue424 ~= 5 then return false end
        local remote2 = HelperFunction16()
        if not remote2 then return false end
        local remote9 = remote2.FireServer
        if typeof(remote9) ~= "function" then return false end
        return pcall(remote9, remote2, table.unpack(recoveredValue424))
    end

    local function RemoveInvisibleHighlight(character)
        if character == nil then return end
        for _, child in ipairs(character:GetChildren()) do
            if child.Name == "BlehHub_Invis" and child:IsA("Highlight") then
                pcall(function() child:Destroy() end)
            end
        end
    end

    local function HelperFunction178(character)
        if State.invisTagConn then
            pcall(function() State.invisTagConn:Disconnect() end)
            State.invisTagConn = nil
        end
        if character == nil then return end
        local rootPart19 = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
        if rootPart19 then
            local connection20 = rootPart19:FindFirstChild("BlehHub_InvisTag")
            if connection20 then pcall(function() connection20:Destroy() end) end
        end
    end

    local function HelperFunction35(character, recoveredValue62)
        if character == nil then return end
        HelperFunction178(character)
        if not recoveredValue62 then return end
        local rootPart19 = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
        if not rootPart19 then return end
        local success, billboardGui = pcall(function()
            local gui = Instance.new("BillboardGui")
            gui.Name = "BlehHub_InvisTag"
            gui.AlwaysOnTop = true
            gui.Size = UDim2.fromOffset(112, 24)
            gui.StudsOffset = Vector3.new(0, 1.7, 0)
            gui.Adornee = rootPart19

            local textLabel = Instance.new("TextLabel")
            textLabel.Name = "Label"
            textLabel.Size = UDim2.new(1, 0, 1, 0)
            textLabel.BackgroundTransparency = 1
            textLabel.Text = "[ INVISIBLE ]"
            textLabel.TextColor3 = Color3.fromRGB(225, 216, 255)
            textLabel.TextStrokeColor3 = Color3.fromRGB(20, 12, 38)
            textLabel.TextStrokeTransparency = 0.15
            textLabel.TextSize = 12
            textLabel.Font = Enum.Font.GothamBold
            textLabel.Parent = gui
            gui.Parent = rootPart19

            if State.invisTagConn then
                pcall(function() State.invisTagConn:Disconnect() end)
                State.invisTagConn = nil
            end
            State.invisTagConn = RunService.RenderStepped:Connect(function()
                if not gui.Parent then return end
                local camera = Workspace.CurrentCamera
                if not camera or not rootPart19.Parent then return end
                local dist = math.max((camera.CFrame.Position - rootPart19.Position).Magnitude, 1)
                local scale = math.clamp(25 / dist, 0.55, 1.25)
                gui.Size = UDim2.fromOffset(math.floor(112 * scale + 0.5), math.floor(24 * scale + 0.5))
                textLabel.TextSize = math.max(9, math.floor(12 * scale + 0.5))
            end)
            return gui
        end)
        if not success or not billboardGui then
            HelperFunction178(character)
        end
    end

    local function ApplyInvisibleToCharacter(character, recoveredValue62)
        if character == nil then return end
        RemoveInvisibleHighlight(character)
        if not recoveredValue62 then
            HelperFunction178(character)
            for _, part in ipairs(cache31) do
                if part and part.Parent then
                    pcall(function() part.Transparency = (0.0) end)
                end
            end
            cache31 = {}
            return
        end
        cache31 = {}
        for _, descendant in ipairs(character:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant.Transparency == (0.0) then
                cache31[#cache31 + (1.0)] = descendant
            end
        end
        for _, part in ipairs(cache31) do
            pcall(function() part.Transparency = recoveredValue293 end)
        end
        local success, currentValue = pcall(function() return Instance.new("Highlight") end)
        if success and currentValue then
            currentValue.Name = "BlehHub_Invis"
            currentValue.Adornee = character
            currentValue.FillColor = Color3.fromRGB(184, 106, 4)
            currentValue.OutlineColor = Color3.fromRGB(255, (255.0), 255)
            currentValue.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            currentValue.FillTransparency = 1
            currentValue.OutlineTransparency = (0.0)
            currentValue.Parent = character
        end
        HelperFunction35(character, true)
    end

    local function HelperFunction32()
        if State.stateField38 then return end
        local success = pcall(function()
            assert(typeof(hookmetamethod) == "function", "hookmetamethod missing")
            assert(typeof(getnamecallmethod) == "function", "getnamecallmethod missing")
            assert(typeof(checkcaller) == "function", "checkcaller missing")
            local recoveredValue277
            recoveredValue277 = hookmetamethod(game, "__namecall", function(self, ...)
                if checkcaller() then
                    return recoveredValue277(self, ...)
                end
                if getnamecallmethod() ~= "FireServer" then
                    return recoveredValue277(self, ...)
                end
                local successFlag2, nm = pcall(function() return self.Name end)
                if not successFlag2 or typeof(nm) ~= "string" then
                    return recoveredValue277(self, ...)
                end
                if string.lower(nm) ~= "updatecharacterlook" then
                    return recoveredValue277(self, ...)
                end
                if not State.invisibleEnabled then
                    if select("#", ...) == 5 then
                        local attributeValue12, attributeValue22, contextValue, distance, e = ...
                        if typeof(attributeValue12) == "CFrame" and typeof(attributeValue22) == "CFrame" and typeof(contextValue) == "CFrame" and typeof(distance) == "CFrame" and typeof(e) == "CFrame" then
                            State.invisibleRemoteArgs = { attributeValue12, attributeValue22, contextValue, distance, e }
                        end
                    end
                    return recoveredValue277(self, ...)
                end
                local rootPart18 = LocalPlayer.Character
                local rootPart17 = rootPart18 and rootPart18:FindFirstChild("HumanoidRootPart")
                if rootPart17 == nil then
                    return recoveredValue277(self, ...)
                end
                if select("#", ...) ~= 5 then
                    State.stateField102 = State.stateField102 + 1
                    return nil
                end
                local recoveredValue133 = table.pack(pcall(HelperFunction127, ...))
                if not recoveredValue133[1] then
                    return recoveredValue277(self, ...)
                end
                if State.stateField59 >= recoveredValue181 then
                    return recoveredValue277(self, table.unpack(recoveredValue133, 2, recoveredValue133.n))
                end
                local remote9 = self.FireServer
                local recoveredValue394 = false
                if typeof(remote9) == "function" then
                    recoveredValue394 = pcall(remote9, self, table.unpack(recoveredValue133, 2, recoveredValue133.n))
                end
                if recoveredValue394 then
                    State.stateField59 = 0
                    State.stateField27 = State.stateField27 + (1.0)
                else
                    State.stateField59 = State.stateField59 + 1
                end
                return nil
            end)
        end)
        if success then State.stateField38 = true end
    end

    function SetInvisibleEnabled(recoveredValue62)
        State.invisibleEnabled = recoveredValue62 and true or false
        local char = LocalPlayer.Character
        if char then ApplyInvisibleToCharacter(char, State.invisibleEnabled) end
        if State.invisibleEnabled then
            SendInvisibleState()
        else
            RestoreInvisibleState()
        end
    end

    if not State.invisibleCharacterConnection then
        State.invisibleCharacterConnection = LocalPlayer.CharacterAdded:Connect(function(char)
            State.invisibleRemoteArgs = nil
            if State.invisibleEnabled then
                task.spawn(function()
                    task.wait((1.0))
                    if State.invisibleEnabled then ApplyInvisibleToCharacter(char, true) end
                end)
            end
        end)
    end

    pcall(function()
        local char = LocalPlayer.Character
        if char then
            RemoveInvisibleHighlight(char)
            HelperFunction178(char)
        end
    end)
    State.invisibleEnabled = false
    do
        local okInvisibleHook, errInvisibleHook = pcall(HelperFunction32)
        if not okInvisibleHook then
            warn("[Bleh Hub BOOT] Invisible hook init failed: " .. tostring(errInvisibleHook))
        end
    end
end

local StartHiddenM2Hook, StopHiddenM2Hook
do
    local distanceValue12 = 50
    local timeValue16 = 1.5

    local function HelperFunction67(character)
        if not character then return false end
        local humanoid10 = character:FindFirstChildOfClass("Humanoid")
        if not humanoid10 or humanoid10.Health <= 0 then return false end
        if character:GetAttribute("Knocked") then return false end
        if character:GetAttribute("IsHooked") then return false end
        if character:GetAttribute("IsCarried") then return false end
        return true
    end

    local function HelperFunction70()
        local rootPart4 = LocalPlayer.Character
        local rootPart6 = rootPart4 and rootPart4:FindFirstChild("HumanoidRootPart")
        if not rootPart6 then return nil end
        local recoveredValue109, closestDistance = nil, math.huge
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character and HelperFunction67(player.Character) then
                if GetPlayerRole(player) ~= "killer" then
                    local part = player.Character:FindFirstChild("HumanoidRootPart")
                        or player.Character:FindFirstChild("Head")
                    if part and part:IsA("BasePart") then
                        local dist = (rootPart6.Position - part.Position).Magnitude
                        if dist <= distanceValue12 and dist < closestDistance then
                            closestDistance = dist
                            recoveredValue109 = part
                        end
                    end
                end
            end
        end
        return recoveredValue109
    end

    local function HelperFunction98()
        if not State.mayersAimlockM2Enabled then return end
        local successFlag5, isKiller = pcall(function() return GetPlayerRole(LocalPlayer) == "killer" end)
        if not successFlag5 or not isKiller then return end
        State.timeValue8 = tick() + timeValue16
    end

    function StartHiddenM2Hook()
        if State.connection17 then return end
        pcall(function()
            local recoveredValue409 = ReplicatedStorage:FindFirstChild("Remotes")
            local recoveredValue402 = recoveredValue409 and recoveredValue409:FindFirstChild("Killers")
            local recoveredValue157 = recoveredValue402 and recoveredValue402:FindFirstChild("Hidden")
            local remote17 = recoveredValue157 and recoveredValue157:FindFirstChild("preparem2")
            if remote17 and remote17:IsA("BindableEvent") then
                State.connection17 = remote17.Event:Connect(HelperFunction98)
            elseif remote17 and remote17:IsA("RemoteEvent") then
                State.connection17 = remote17.OnClientEvent:Connect(HelperFunction98)
            else
                Notify("AIMLOCK M2", "M2 preparation was not found.", 2)
            end
        end)
    end

    function StopHiddenM2Hook()
        if State.connection17 then
            pcall(function() State.connection17:Disconnect() end)

            State.connection17 = nil
        end
        State.timeValue8 = 0
    end

    RegisterUpdateTask("HiddenM2Aimlock", 0.02, function()
        if not State.mayersAimlockM2Enabled then return end
        if tick() > State.timeValue8 then return end
        local successFlag5, isKiller = pcall(function() return GetPlayerRole(LocalPlayer) == "killer" end)
        if not successFlag5 or not isKiller then return end
        local camera = workspace.CurrentCamera
        if not camera then return end
        local recoveredValue299 = HelperFunction70()
        if not recoveredValue299 then return end
        local vectorValue9 = recoveredValue299.Position
        local smooth = math.clamp(tonumber(State.mayersAimlockSmoothness) or 1.0, 0.05, 1)
        pcall(function()
            camera.CFrame = camera.CFrame:Lerp(CFrame.new(camera.CFrame.Position, vectorValue9), smooth)
        end)
        pcall(function()
            local char = LocalPlayer.Character
            local rootPart16 = char and char:FindFirstChild("HumanoidRootPart")
            if rootPart16 then
                rootPart16.CFrame = CFrame.new(rootPart16.Position, Vector3.new(vectorValue9.X, rootPart16.Position.Y, vectorValue9.Z))
            end
        end)
    end)
end

__BlehHubBootProbe:Set("PRE SPEAR SYSTEM")

do
    local vectorValue41 = { hist = {}, char = nil, vectorValue46 = Vector3.new(0, (0.0), 0) }
    local function HelperFunction199(char)
        if not char then return nil end
        local part4 = char:FindFirstChild("UpperTorso")
        if part4 and part4:IsA("BasePart") then return part4.Position end
        local part2 = char:FindFirstChild("Torso")
        if part2 and part2:IsA("BasePart") then return part2.Position end
        local rootPart2 = char:FindFirstChild("HumanoidRootPart")
        if rootPart2 then return rootPart2.Position + Vector3.new((0.0), 0.5, (0.0)) end
        return nil
    end
    local function HelperFunction96(cameraValue9, targetPosition, fovRadius)
        local recoveredValue254, onScreen = cameraValue9:WorldToViewportPoint(targetPosition)
        if not onScreen then return false end
        local cameraValue11 = Vector2.new(cameraValue9.ViewportSize.X / 2, cameraValue9.ViewportSize.Y / (2.0))
        local recoveredValue372 = Vector2.new(recoveredValue254.X, recoveredValue254.Y)
        local distanceValue25 = (recoveredValue372 - cameraValue11).Magnitude
        return distanceValue25 <= fovRadius
    end
    local function HelperFunction47()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "BlehHubSpearFOV"; screenGui.ResetOnSpawn = false; screenGui.DisplayOrder = 999999
        pcall(function() screenGui.Parent = (gethui and gethui() or game:GetService("CoreGui")) end)
        if not screenGui.Parent then screenGui.Parent = PlayerGui end
        State.frame11 = Instance.new("Frame")
        State.frame11.Size = UDim2.new(0, Config.spearFovRadius * 2, 0, Config.spearFovRadius * 2)
        State.frame11.Position = UDim2.new(0.5, 0, 0.5, 0)
        State.frame11.AnchorPoint = Vector2.new(0.5, 0.5)
        State.frame11.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        State.frame11.BackgroundTransparency = 1; State.frame11.Visible = false
        State.frame11.Parent = screenGui
        local recoveredValue226 = Instance.new("UICorner"); recoveredValue226.CornerRadius = UDim.new(1, 0); recoveredValue226.Parent = State.frame11
        local colorValue14 = Instance.new("UIStroke")
        colorValue14.Color = NotifyColor; colorValue14.Thickness = 2; colorValue14.Transparency = 0.2; colorValue14.Parent = State.frame11
    end
    pcall(HelperFunction47)

    local function HelperFunction15()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "SpearIndicatorUI"; screenGui.ResetOnSpawn = false; screenGui.Enabled = false
        screenGui.DisplayOrder = 999998; screenGui.IgnoreGuiInset = true
        pcall(function() screenGui.Parent = (gethui and gethui() or game:GetService("CoreGui")) end)
        if not screenGui.Parent then screenGui.Parent = PlayerGui end
        State.frame5 = Instance.new("Frame")
        State.frame5.Name = "MainFrame"
        State.frame5.Size = UDim2.new(0, (180.0), (0.0), 42)
        State.frame5.Position = UDim2.new(0.5, (0.0), 0.82, 0)
        State.frame5.AnchorPoint = Vector2.new(0.5, 0.5)
        State.frame5.BackgroundColor3 = Color3.fromRGB((20.0), 20, 25)
        State.frame5.BackgroundTransparency = 0.1
        State.frame5.BorderSizePixel = 0
        State.frame5.Parent = screenGui
        local recoveredValue226 = Instance.new("UICorner"); recoveredValue226.CornerRadius = UDim.new((0.0), 8); recoveredValue226.Parent = State.frame5
        local colorValue14 = Instance.new("UIStroke")
        colorValue14.Color = Color3.fromRGB(45, 45, (55.0)); colorValue14.Thickness = 1; colorValue14.Transparency = 0.2; colorValue14.Parent = State.frame5
        local recoveredValue322 = Instance.new("UIGradient")
        recoveredValue322.Color = ColorSequence.new({
            ColorSequenceKeypoint.new((0.0), Color3.fromRGB((35.0), 35, 40)),
            ColorSequenceKeypoint.new((1.0), Color3.fromRGB(15, (15.0), 20))
        })
        recoveredValue322.Rotation = 90; recoveredValue322.Parent = State.frame5
        State.frame3 = Instance.new("Frame")
        State.frame3.Name = "AccentBar"
        State.frame3.Size = UDim2.new(0, (3.0), 1, -12)
        State.frame3.Position = UDim2.new(0, (6.0), 0, 6)
        State.frame3.BackgroundColor3 = Color3.fromRGB(200, (200.0), (200.0))
        State.frame3.BorderSizePixel = 0; State.frame3.Parent = State.frame5
        local recoveredValue33 = Instance.new("UICorner"); recoveredValue33.CornerRadius = UDim.new(1, (0.0)); recoveredValue33.Parent = State.frame3
        State.textLabel5 = Instance.new("TextLabel")
        State.textLabel5.Name = "StatusText"
        State.textLabel5.Size = UDim2.new(1, -18, 0, 18)
        State.textLabel5.Position = UDim2.new(0, 14, 0, 5)
        State.textLabel5.BackgroundTransparency = 1
        State.textLabel5.Text = "NO TARGET"
        State.textLabel5.TextColor3 = Color3.fromRGB(255, 255, 255)
        State.textLabel5.TextSize = 13; State.textLabel5.Font = Enum.Font.GothamBold
        State.textLabel5.TextXAlignment = Enum.TextXAlignment.Left
        State.textLabel5.TextTruncate = Enum.TextTruncate.AtEnd
        State.textLabel5.Parent = State.frame5
        State.textLabel6 = Instance.new("TextLabel")
        State.textLabel6.Name = "InfoText"
        State.textLabel6.Size = UDim2.new((1.0), (-18.0), 0, (14.0))
        State.textLabel6.Position = UDim2.new(0, 14, (0.0), (23.0))
        State.textLabel6.BackgroundTransparency = (1.0)
        State.textLabel6.Text = "Aim to Survivor"
        State.textLabel6.TextColor3 = Color3.fromRGB(160, 160, 170)
        State.textLabel6.TextSize = (10.0); State.textLabel6.Font = Enum.Font.Gotham
        State.textLabel6.TextXAlignment = Enum.TextXAlignment.Left
        State.textLabel6.TextTruncate = Enum.TextTruncate.AtEnd
        State.textLabel6.Parent = State.frame5
        State.stateField39 = screenGui
    end
    pcall(HelperFunction15)

    local function HelperFunction153()
        State.screenGui2 = Instance.new("ScreenGui")
        State.screenGui2.Name = "SpearAssist_SnapLine"
        State.screenGui2.IgnoreGuiInset = true; State.screenGui2.ResetOnSpawn = false
        State.screenGui2.DisplayOrder = 999999
        pcall(function() State.screenGui2.Parent = (gethui and gethui() or game:GetService("CoreGui")) end)
        if not State.screenGui2.Parent then State.screenGui2.Parent = PlayerGui end
        State.frame2 = Instance.new("Frame")
        State.frame2.Name = "Line"
        State.frame2.AnchorPoint = Vector2.new(0.5, 0.5)
        State.frame2.BorderSizePixel = 0
        State.frame2.BackgroundColor3 = Color3.fromRGB(255, 220, (0.0))
        State.frame2.BackgroundTransparency = 0.35
        State.frame2.Visible = false; State.frame2.Parent = State.screenGui2
        State.frame7 = Instance.new("Frame")
        State.frame7.Name = "Dot"
        State.frame7.AnchorPoint = Vector2.new(0.5, 0.5)
        State.frame7.BorderSizePixel = (0.0)
        State.frame7.BackgroundColor3 = Color3.fromRGB((255.0), 220, 0)
        State.frame7.BackgroundTransparency = 0
        State.frame7.Size = UDim2.fromOffset(4, 4)
        State.frame7.Visible = false; State.frame7.Parent = State.screenGui2
        local recoveredValue115 = Instance.new("UICorner"); recoveredValue115.CornerRadius = UDim.new(1, 0); recoveredValue115.Parent = State.frame7
        State.textLabel2 = Instance.new("TextLabel")
        State.textLabel2.Name = "InfoText"
        State.textLabel2.AnchorPoint = Vector2.new(0.5, 1)
        State.textLabel2.Size = UDim2.new(0, 200, 0, 16)
        State.textLabel2.BackgroundTransparency = 1
        State.textLabel2.Text = ""
        State.textLabel2.TextColor3 = Color3.fromRGB(255, 255, 255)
        State.textLabel2.TextSize = 12; State.textLabel2.Font = Enum.Font.GothamBold
        State.textLabel2.TextStrokeTransparency = 0
        State.textLabel2.TextStrokeColor3 = Color3.new(0, (0.0), (0.0))
        State.textLabel2.TextXAlignment = Enum.TextXAlignment.Center
        State.textLabel2.TextTruncate = Enum.TextTruncate.AtEnd
        State.textLabel2.Visible = false; State.textLabel2.Parent = State.screenGui2
    end
    pcall(HelperFunction153)

    local function HelperFunction208(distanceValue31, recoveredValue168, speed, distanceValue9)
        local recoveredValue126 = math.cos(recoveredValue168)
        if recoveredValue126 <= 0.015 then return nil, nil end
        local travelTime = distanceValue31 / (speed * recoveredValue126)
        if travelTime ~= travelTime or travelTime <= 0 then return nil, nil end
        local recoveredValue219 = 1 / 60
        local recoveredValue265 = 0.5 * distanceValue9 * recoveredValue219 * travelTime
        local recoveredValue43 = speed * math.sin(recoveredValue168) * travelTime - (0.5 * distanceValue9 * travelTime * travelTime) - recoveredValue265
        return recoveredValue43, travelTime
    end
    local function HelperFunction91(distanceValue31, recoveredValue263, recoveredValue168, speed, distanceValue9)
        local recoveredValue241, travelTime = HelperFunction208(distanceValue31, recoveredValue168, speed, distanceValue9)
        if not recoveredValue241 or not travelTime then return nil end
        if travelTime < 0.025 or travelTime > 5 then return nil end
        local recoveredValue82 = math.abs(recoveredValue241 - recoveredValue263)
        local recoveredValue324 = math.max(recoveredValue168 - PITCH_COMPENSATION_ANGLE, (0.0)) * 0.35
        local recoveredValue161 = math.max(travelTime - 1.3, 0) * 0.25
        return recoveredValue82 + recoveredValue324 + recoveredValue161, recoveredValue82, travelTime
    end
    local function HelperFunction136(recoveredValue379, vectorValue9, speed, distanceValue9)
        if speed <= 0 then speed = 142.5 end
        if distanceValue9 <= 0 then distanceValue9 = 196.2 end
        local vectorValue40 = vectorValue9 - recoveredValue379
        local vectorValue20 = Vector3.new(vectorValue40.X, 0, vectorValue40.Z)
        local distanceValue31 = vectorValue20.Magnitude
        local recoveredValue263 = vectorValue40.Y
        if vectorValue40.Magnitude <= 0.001 then return nil end
        if distanceValue31 <= 0.35 or distanceValue9 <= 0.001 then
            return vectorValue40.Unit, math.clamp(vectorValue40.Magnitude / speed, 0.025, 5)
        end
        local vectorValue35 = vectorValue20.Unit
        local recoveredValue176 = math.atan2(recoveredValue263, distanceValue31)
        local recoveredValue98 = math.max(-MIN_PITCH_ANGLE, recoveredValue176 - PITCH_BIAS_ANGLE)
        local recoveredValue397 = MAX_PITCH_ANGLE
        local vectorValue29, bestScore, bestError, bestTime = nil, math.huge, math.huge, nil

        local recoveredValue240 = distanceValue31 > 80
        local recoveredValue359 = recoveredValue240 and 44 or 30
        local recoveredValue140 = recoveredValue240 and 0.08 or DEFAULT_PREDICTION_STEP
        for index = 0, recoveredValue359 do
            local recoveredValue168 = recoveredValue98 + (recoveredValue397 - recoveredValue98) * (index / recoveredValue359)
            local recoveredValue151, recoveredValue82, travelTime = HelperFunction91(distanceValue31, recoveredValue263, recoveredValue168, speed, distanceValue9)
            if recoveredValue151 and recoveredValue151 < bestScore then
                bestScore, bestError, vectorValue29, bestTime = recoveredValue151, recoveredValue82, recoveredValue168, travelTime
                if bestError < recoveredValue140 then break end
            end
        end
        if vectorValue29 then
            local recoveredValue46 = (recoveredValue397 - recoveredValue98) / recoveredValue359 * 2.5
            local recoveredValue10 = (bestError < recoveredValue140) and 1 or (recoveredValue240 and 6 or 4)
            for _ = 1, recoveredValue10 do
                local recoveredValue244, localBestScore, localBestError, localBestTime = vectorValue29, bestScore, bestError, bestTime
                for index2 = -3, 3 do
                    local recoveredValue168 = math.clamp(vectorValue29 + recoveredValue46 * (index2 / (3.0)), recoveredValue98, recoveredValue397)
                    local recoveredValue151, recoveredValue82, travelTime = HelperFunction91(distanceValue31, recoveredValue263, recoveredValue168, speed, distanceValue9)
                    if recoveredValue151 and recoveredValue151 < localBestScore then
                        localBestScore, localBestError, recoveredValue244, localBestTime = recoveredValue151, recoveredValue82, recoveredValue168, travelTime
                    end
                end
                vectorValue29, bestScore, bestError, bestTime = recoveredValue244, localBestScore, localBestError, localBestTime
                if bestError < recoveredValue140 then break end
                recoveredValue46 = recoveredValue46 * 0.38
            end
        end
        if not vectorValue29 then
            local recoveredValue50 = math.clamp(distanceValue31 / speed, 0.025, 5)


            local vectorValue68 = math.min(0.5 * distanceValue9 * recoveredValue50 * recoveredValue50, 15)
            local vectorValue37 = vectorValue9 + Vector3.new((0.0), vectorValue68, (0.0))
            local distanceValue44 = vectorValue37 - recoveredValue379
            if distanceValue44.Magnitude <= 0.001 then return nil end
            return distanceValue44.Unit, recoveredValue50
        end
        local vectorValue61 = vectorValue35 * math.cos(vectorValue29) + Vector3.new((0.0), math.sin(vectorValue29), 0)
        if vectorValue61.Magnitude <= 0.001 then return nil end
        return vectorValue61.Unit, bestTime
    end
    local function HelperFunction8(distanceValue31, recoveredValue263, speed, distanceValue9)
        if speed <= 0 or distanceValue9 <= 0 then return false end
        local recoveredValue286, recoveredValue173, value2, textLabel4 = distanceValue31, recoveredValue263, speed, distanceValue9
        local recoveredValue294 = (textLabel4 * recoveredValue286 * recoveredValue286) / (2 * value2 * value2)
        if recoveredValue294 <= 0 then return false end
        local attributeValue12, attributeValue22, contextValue = recoveredValue294, -recoveredValue286, recoveredValue173 + recoveredValue294
        return (attributeValue22*attributeValue22 - (4.0)*attributeValue12*contextValue) >= 0
    end
    local function HelperFunction146(distanceValue31, recoveredValue263, distanceValue9)
        for t = 0.1, 3.0, 0.05 do
            local recoveredValue236 = 23
            if t < 1 then recoveredValue236 = math.max(23, t * 150)
            elseif t < 2 then recoveredValue236 = 142.5
            else recoveredValue236 = 165 end
            if HelperFunction8(distanceValue31, recoveredValue263, recoveredValue236, distanceValue9) then return t end
        end
        return nil
    end

    do
        task.defer(function()

            local function ResolveSpearRemotes()
                local remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage
                local killers = remotes:FindFirstChild("Killers", true)
                local killerFolder = killers and killers:FindFirstChild(string.char(86, 101, 105, 108), true)
                local spearRemote = (killerFolder and FindRemoteEvent(killerFolder, "Spearthrow"))
                    or FindRemoteEvent(killers or remotes, "Spearthrow")
                local mechanics = remotes:FindFirstChild("Mechanics", true)
                local visualizeRemote = (mechanics and FindRemoteEvent(mechanics, "visualize"))
                    or FindRemoteEvent(remotes, "visualize")
                return spearRemote, visualizeRemote
            end

            local remote16, recoveredValue384 = ResolveSpearRemotes()
            local deadline = tick() + 8
            while (not remote16 or not recoveredValue384) and tick() < deadline do
                task.wait(0.25)
                local foundSpear, foundVisualize = ResolveSpearRemotes()
                remote16 = remote16 or foundSpear
                recoveredValue384 = recoveredValue384 or foundVisualize
            end

            if recoveredValue384 and recoveredValue384:IsA("RemoteEvent") then
                recoveredValue384.OnClientEvent:Connect(function(ownerChar, spearDir, spearSpeed, gravityMult)
                    if ownerChar == LocalPlayer.Character then
                        if type(spearSpeed) == "number" and spearSpeed >= 15 and spearSpeed <= 800 then State.spearSpeedEstimate = spearSpeed end
                        if type(gravityMult) == "number" and gravityMult > 0.2 and gravityMult <= (5.0) then State.spearGravityMultiplier = gravityMult end

                        local distanceValue54 = State.spearLastShot
                        if distanceValue54 and (tick() - (distanceValue54.t or 0)) < (5.0) and (distanceValue54.speed or 0) > 1
                            and type(spearSpeed) == "number" and spearSpeed >= 15 and spearSpeed <= 800 then
                            local recoveredValue326 = spearSpeed / distanceValue54.speed
                            if recoveredValue326 > 0.2 and recoveredValue326 < 5 then
                                local recoveredValue29 = tonumber(State.distanceValue57) or 1.0
                                State.distanceValue57 = math.clamp(recoveredValue29 + (recoveredValue326 - 1) * 0.3, 0.5, 2.0)
                            end
                        end
                    end
                end)
            end

            if not (remote16 and remote16:IsA("RemoteEvent")) then
                return
            end

            if typeof(hookmetamethod) ~= "function" or typeof(getnamecallmethod) ~= "function" then
                warn("[Bleh Hub] Executor lacks hookmetamethod/getnamecallmethod - Silent Spear hook disabled")
                return
            end

            local okHooks, hookErr = pcall(function()
                local recoveredValue106
                recoveredValue106 = hookmetamethod(game, "__namecall", function(...)
                    local remote27 = getnamecallmethod()
                    if remote27 == "FireServer" then
                        local recoveredValue111 = table.pack(...)
                        local self = recoveredValue111[1]
                        if typeof(self) == "Instance" and rawequal(self, remote16) then
                            if State.silentSpearEnabled and typeof(State.stateField109) == "Vector3" then
                                if recoveredValue111.n >= 4 and typeof(recoveredValue111[2]) == "Vector3" and typeof(recoveredValue111[4]) == "Vector3" then
                                    recoveredValue111[2] = State.stateField109
                                    return recoveredValue106(table.unpack(recoveredValue111, 1, recoveredValue111.n))
                                end
                            end
                        end
                    end
                    return recoveredValue106(...)
                end)

                if typeof(newcclosure) == "function" then
                    local recoveredValue150
                    recoveredValue150 = hookmetamethod(game, "__index", function(t, distanceValue7)
                        if distanceValue7 == "FireServer" and typeof(t) == "Instance" and rawequal(t, remote16) then
                            return newcclosure(function(...)
                                local recoveredValue111 = table.pack(...)
                                if State.silentSpearEnabled and typeof(State.stateField109) == "Vector3" then
                                    if recoveredValue111.n >= (4.0) and typeof(recoveredValue111[2]) == "Vector3" and typeof(recoveredValue111[4]) == "Vector3" then
                                        recoveredValue111[(2.0)] = State.stateField109
                                    end
                                end
                                return recoveredValue150(t, distanceValue7)(table.unpack(recoveredValue111, 1, recoveredValue111.n))
                            end)
                        end
                        return recoveredValue150(t, distanceValue7)
                    end)
                end
            end)

            if not okHooks then
                warn("[Bleh Hub] Spear hook initialization failed: " .. tostring(hookErr))
            else
            end
        end)
    end

    do
        local cache13 = {}
        local function HelperFunction151(currentValue, name)
            local recoveredValue59 = currentValue and currentValue.Parent
            while recoveredValue59 do
                if recoveredValue59.Name == name then return true end
                recoveredValue59 = recoveredValue59.Parent
            end
            return false
        end
        local function HelperFunction39(currentValue)
            if not (currentValue and currentValue:IsA("GuiButton")) then return false end
            if currentValue.Name ~= "attack" and currentValue.Name ~= "Gui-mob" then return false end
            if not HelperFunction151(currentValue, "Slasher-mob") and not HelperFunction151(currentValue, "Survivor-mob") then return false end
            if not HelperFunction151(currentValue, "Control") and not HelperFunction151(currentValue, "Controls") then return false end
            return true
        end
        local function HelperFunction80(recoveredValue274)
            if not HelperFunction39(recoveredValue274) then return end
            if cache13[recoveredValue274] then return end
            cache13[recoveredValue274] = true
            recoveredValue274.InputBegan:Connect(function(input)
                local t = input.UserInputType
                if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
                local char = LocalPlayer.Character
                if char and char:GetAttribute("spearmode") then
                    State.timeValue18 = true; State.timeValue17 = tick()
                end
            end)
            recoveredValue274.InputEnded:Connect(function(input)
                local t = input.UserInputType
                if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then return end
                State.timeValue18 = false; State.timeValue17 = nil
            end)
        end
        local function HelperFunction210()
            local recoveredValue40 = LocalPlayer:FindFirstChildOfClass("PlayerGui") or PlayerGui
            if not recoveredValue40 then return end
            pcall(function()
                local function HelperFunction46(screenName)
                    local recoveredValue209 = recoveredValue40:FindFirstChild(screenName, true)
                    if not recoveredValue209 then return end
                    local recoveredValue73 = recoveredValue209:FindFirstChild("Control") or recoveredValue209:FindFirstChild("Controls")
                    if recoveredValue73 then
                        local function HelperFunction213(parentObject)
                            for _, child in ipairs(parentObject:GetChildren()) do
                                HelperFunction80(child)
                                HelperFunction213(child)
                            end
                        end
                        HelperFunction213(recoveredValue73)
                    end
                    local button = recoveredValue209:FindFirstChild("Gui-mob", true)
                    if button and button:IsA("GuiButton") then HelperFunction80(button) end
                end
                HelperFunction46("Slasher-mob")
                HelperFunction46("Survivor-mob")
            end)
            recoveredValue40.DescendantAdded:Connect(function(descendant) HelperFunction80(descendant) end)
        end
        UserInputService.InputBegan:Connect(function(input, recoveredValue58)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                local char = LocalPlayer.Character
                if char and char:GetAttribute("spearmode") then
                    State.timeValue18 = true; State.timeValue17 = tick()
                end
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                State.timeValue18 = false; State.timeValue17 = nil
            end
        end)
        pcall(HelperFunction210)
    end

    RegisterUpdateTask("Spear_UpdateSnapLine", 0, function(recoveredValue206)
        local dummy = State.SPEAR_SNAPLINE
        if not dummy.enabled then
            if State.frame2 then State.frame2.Visible = false end
            if State.frame7 then State.frame7.Visible = false end
            if State.textLabel2 then State.textLabel2.Visible = false end
            dummy.stateField34 = false; dummy.stateField57 = nil; dummy.distanceValue48 = ""
            return
        end
        local cameraValue9 = Workspace.CurrentCamera
        if not cameraValue9 then
            if State.frame2 then State.frame2.Visible = false end
            if State.frame7 then State.frame7.Visible = false end
            if State.textLabel2 then State.textLabel2.Visible = false end
            return
        end
        local rootPart22 = LocalPlayer.Character
        local attributeValue24 = rootPart22 and rootPart22:GetAttribute("spearmode")
        if not attributeValue24 then
            if State.frame2 then State.frame2.Visible = false end
            if State.frame7 then State.frame7.Visible = false end
            if State.textLabel2 then State.textLabel2.Visible = false end
            return
        end
        local cameraValue = cameraValue9.ViewportSize
        local cameraValue11 = Vector2.new(cameraValue.X / 2, cameraValue.Y / 2)
        local rootPart13 = rootPart22 and rootPart22:FindFirstChild("HumanoidRootPart")
        local function HelperFunction23()
            local distanceValue17 = nil
            local distanceValue55 = math.huge
            local bestDist3D = math.huge
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and GetPlayerRole(player) == "survivor" then
                    local humanoid15 = player.Character
                    if humanoid15 then
                        local humanoid13 = humanoid15:FindFirstChildOfClass("Humanoid")
                        local distanceValue50 = HelperFunction199(humanoid15)
                        if distanceValue50 and humanoid13 and humanoid13.Health > (0.0) and humanoid13.Health > 50 and not humanoid15:GetAttribute("IsHooked") then
                            local distanceValue37 = rootPart13 and (distanceValue50 - rootPart13.Position).Magnitude or (0.0)
                            if distanceValue37 <= Config.spearSnaplineMaxDistance then
                                local recoveredValue254, onScreen = cameraValue9:WorldToViewportPoint(distanceValue50)
                                if onScreen then
                                    local distanceValue25 = (Vector2.new(recoveredValue254.X, recoveredValue254.Y) - cameraValue11).Magnitude
                                    if distanceValue25 <= Config.spearFovRadius then
                                        if distanceValue25 < distanceValue55 then
                                            distanceValue55 = distanceValue25; bestDist3D = distanceValue37; distanceValue17 = player
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            return distanceValue17, distanceValue55, bestDist3D
        end
        if State.timeValue18 and not dummy.stateField34 then
            local distanceValue17, _, bestDist3D = HelperFunction23()
            if distanceValue17 then
                dummy.stateField34 = true; dummy.stateField57 = distanceValue17
                dummy.distanceValue48 = distanceValue17.Name; dummy.distanceValue46 = bestDist3D
            end
        end
        if not State.timeValue18 then
            dummy.stateField34 = false; dummy.stateField57 = nil; dummy.distanceValue48 = ""
        end
        local recoveredValue93 = false
        local recoveredValue174 = nil
        local recoveredValue392 = (0.0)
        local recoveredValue246 = nil
        if dummy.stateField34 and dummy.stateField57 then
            local humanoid15 = dummy.stateField57.Character
            if humanoid15 then
                local humanoid13 = humanoid15:FindFirstChildOfClass("Humanoid")
                local distanceValue50 = HelperFunction199(humanoid15)
                if distanceValue50 and humanoid13 and humanoid13.Health > 50 and not humanoid15:GetAttribute("IsHooked") then
                    local recoveredValue254, onScreen = cameraValue9:WorldToViewportPoint(distanceValue50)
                    if onScreen then
                        local distanceValue25 = (Vector2.new(recoveredValue254.X, recoveredValue254.Y) - cameraValue11).Magnitude
                        if distanceValue25 <= Config.spearFovRadius * 1.15 then
                            recoveredValue174 = Vector2.new(recoveredValue254.X, recoveredValue254.Y)
                            recoveredValue392 = rootPart13 and (distanceValue50 - rootPart13.Position).Magnitude or 0
                            recoveredValue246 = distanceValue50; recoveredValue93 = true
                            dummy.distanceValue46 = recoveredValue392
                        end
                    end
                end
            end
            if not recoveredValue93 then
                dummy.stateField34 = false; dummy.stateField57 = nil; dummy.distanceValue48 = ""
            end
        end
        local recoveredValue232 = nil
        local distanceValue30 = 0
        local distanceValue59 = nil
        local distanceValue2 = nil
        if not dummy.stateField34 then
            local distanceValue17, _, bestDist3D = HelperFunction23()
            if distanceValue17 then
                local distanceValue50 = HelperFunction199(distanceValue17.Character)
                local recoveredValue254, _ = cameraValue9:WorldToViewportPoint(distanceValue50)
                recoveredValue232 = Vector2.new(recoveredValue254.X, recoveredValue254.Y)
                distanceValue30 = bestDist3D; distanceValue59 = distanceValue50
                distanceValue2 = distanceValue17; dummy.distanceValue46 = bestDist3D
            end
        end
        local recoveredValue110 = false
        if State.timeValue18 and State.timeValue17 and rootPart13 then
            local recoveredValue26 = recoveredValue246 or (distanceValue2 and HelperFunction199(distanceValue2.Character))
            if recoveredValue26 then
                local recoveredValue379 = cameraValue9.CFrame.Position
                local vectorValue40 = recoveredValue26 - recoveredValue379
                local vectorValue20 = Vector3.new(vectorValue40.X, 0, vectorValue40.Z)
                local distanceValue31 = vectorValue20.Magnitude
                local recoveredValue263 = vectorValue40.Y
                local distanceValue9 = Workspace.Gravity * (State.spearGravityMultiplier or (1.0))
                local recoveredValue79 = HelperFunction146(distanceValue31, recoveredValue263, distanceValue9)
                if recoveredValue79 then
                    local timeValue22 = tick() - State.timeValue17
                    if timeValue22 >= recoveredValue79 then recoveredValue110 = true end
                end
            end
        end
        local recoveredValue282 = nil
        local recoveredValue153 = ""
        local recoveredValue386 = 0
        if dummy.stateField34 and recoveredValue93 then
            recoveredValue282 = recoveredValue174; recoveredValue153 = dummy.distanceValue48
            recoveredValue386 = recoveredValue392
        elseif recoveredValue232 then
            recoveredValue282 = recoveredValue232; recoveredValue153 = distanceValue2 and distanceValue2.Name or ""
            recoveredValue386 = distanceValue30
        end
        local success = pcall(function()
            if not State.frame2 or not State.frame7 or not State.textLabel2 or not cameraValue9 then
                if State.frame2 then State.frame2.Visible = false end
                if State.frame7 then State.frame7.Visible = false end
                if State.textLabel2 then State.textLabel2.Visible = false end
                return
            end
            if not recoveredValue282 then
                State.frame2.Visible = false; State.frame7.Visible = false
                State.textLabel2.Visible = false; dummy.distanceValue46 = math.huge
                return
            end
            local distanceValue3 = cameraValue11; local distanceValue34 = recoveredValue282
            local distanceValue42 = distanceValue34 - distanceValue3; local length = distanceValue42.Magnitude
            if length < 2 then
                State.frame2.Visible = false; State.frame7.Visible = false
                State.textLabel2.Visible = false; return
            end
            local colorValue9 = recoveredValue110
            local colorValue3 = colorValue9 and Color3.fromRGB(0, (255.0), 120) or Color3.fromRGB(255, 220, (0.0))
            local recoveredValue239 = colorValue9 and 0.08 or 0.35
            State.frame2.BackgroundColor3 = colorValue3
            State.frame2.BackgroundTransparency = recoveredValue239
            State.frame2.Size = UDim2.fromOffset(length, colorValue9 and 2 or 1)
            State.frame2.Position = UDim2.fromOffset((distanceValue3.X + distanceValue34.X) * 0.5, (distanceValue3.Y + distanceValue34.Y) * 0.5)
            State.frame2.Rotation = math.deg(math.atan2(distanceValue42.Y, distanceValue42.X))
            State.frame2.Visible = true
            State.frame7.BackgroundColor3 = colorValue3
            State.frame7.Position = UDim2.fromOffset(distanceValue34.X, distanceValue34.Y)
            State.frame7.Visible = true
            if Config.spearShowNameAndDistance and recoveredValue153 ~= "" then
                State.textLabel2.Text = string.format("%s [%dm]", recoveredValue153, math.floor(recoveredValue386))
                State.textLabel2.TextColor3 = colorValue3
                State.textLabel2.Position = UDim2.fromOffset(distanceValue34.X, distanceValue34.Y - 14)
                State.textLabel2.Visible = true
            else
                State.textLabel2.Visible = false
            end
        end)
        if not success then
            if State.frame2 then State.frame2.Visible = false end
            if State.frame7 then State.frame7.Visible = false end
            if State.textLabel2 then State.textLabel2.Visible = false end
        end
    end)

    RegisterUpdateTask("Spear_UpdateSpearSystem", 0, function()
        if State.frame11 then
            State.frame11.Visible = State.silentSpearFovCircleEnabled
            local recoveredValue63 = Config.spearFovRadius * 2
            if State.frame11.Size.X.Offset ~= recoveredValue63 then
                State.frame11.Size = UDim2.new(0, recoveredValue63, 0, recoveredValue63)
            end
        end
        if not State.silentSpearEnabled then
            State.stateField42 = nil; State.stateField109 = nil
        end
        local rootPart22 = LocalPlayer.Character
        local attributeValue24 = rootPart22 and rootPart22:GetAttribute("spearmode")
        if not State.spearAimIndicatorEnabled or not attributeValue24 then
            if State.stateField39 then State.stateField39.Enabled = false end
            if not State.silentSpearEnabled or not attributeValue24 then return end
        end
        local rootPart13 = rootPart22 and rootPart22:FindFirstChild("HumanoidRootPart")
        if not rootPart13 then return end
        local cameraValue9 = workspace.CurrentCamera
        if not cameraValue9 then return end
        if State.spearAimIndicatorEnabled and attributeValue24 and State.stateField39 then
            State.stateField39.Enabled = true
        end
        local distanceValue17 = nil
        local distanceValue55 = math.huge
        local bestDist3D = math.huge
        local distanceValue10 = false
        local cameraValue7 = Vector2.new(cameraValue9.ViewportSize.X / 2, cameraValue9.ViewportSize.Y / (2.0))
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and GetPlayerRole(player) == "survivor" then
                local humanoid15 = player.Character
                if humanoid15 then
                    local humanoid13 = humanoid15:FindFirstChildOfClass("Humanoid")
                    local distanceValue50 = HelperFunction199(humanoid15)
                    local rootPart8 = humanoid15:FindFirstChild("HumanoidRootPart")
                    if humanoid13 and humanoid13.Health > 50 and typeof(distanceValue50) == "Vector3" and rootPart8 and not humanoid15:GetAttribute("IsHooked") then
                        local distanceValue37 = (distanceValue50 - rootPart13.Position).Magnitude
                        local recoveredValue254, onScreen = cameraValue9:WorldToViewportPoint(distanceValue50)
                        if onScreen then
                            local distanceValue25 = (Vector2.new(recoveredValue254.X, recoveredValue254.Y) - cameraValue7).Magnitude
                            if distanceValue25 <= Config.spearFovRadius then
                                if distanceValue25 < distanceValue55 then
                                    distanceValue55 = distanceValue25; bestDist3D = distanceValue37
                                    distanceValue17 = player; distanceValue10 = true
                                end
                            elseif not distanceValue10 and distanceValue37 < bestDist3D then
                                bestDist3D = distanceValue37; distanceValue17 = player
                            end
                        elseif not distanceValue10 and distanceValue37 < bestDist3D then
                            bestDist3D = distanceValue37; distanceValue17 = player
                        end
                    end
              end
            end
        end
        if distanceValue17 and distanceValue17.Character then
            local distanceValue50 = HelperFunction199(distanceValue17.Character)
            if distanceValue50 then distanceValue10 = HelperFunction96(cameraValue9, distanceValue50, Config.spearFovRadius) end
        end
        if State.spearAimIndicatorEnabled and attributeValue24 then
            if not distanceValue17 or not distanceValue17.Character then
                State.textLabel5.Text = "NO TARGET"
                State.textLabel5.TextColor3 = Color3.fromRGB(200, 200, 200)
                State.frame3.BackgroundColor3 = Color3.fromRGB((80.0), 80, (80.0))
                State.textLabel6.Text = "Aim to Survivor"; return
            end
            local distanceValue50 = HelperFunction199(distanceValue17.Character)
            local recoveredValue379 = cameraValue9.CFrame.Position
            local vectorValue40 = distanceValue50 - recoveredValue379
            local vectorValue20 = Vector3.new(vectorValue40.X, 0, vectorValue40.Z)
            local distanceValue31 = vectorValue20.Magnitude
            local recoveredValue263 = vectorValue40.Y
            local distanceValue37 = vectorValue40.Magnitude
            local distanceValue9 = Workspace.Gravity * (State.spearGravityMultiplier or 1)
            local recoveredValue79 = HelperFunction146(distanceValue31, recoveredValue263, distanceValue9)
            local recoveredValue91 = distanceValue17.Name
            local recoveredValue272 = string.format("%.0f", distanceValue37)
            if not recoveredValue79 then
                State.textLabel5.Text = "OUT OF RANGE"
                State.textLabel5.TextColor3 = Color3.fromRGB(255, (80.0), 80)
                State.frame3.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
                State.textLabel6.Text = string.format("%s | %s studs", recoveredValue91, recoveredValue272)
            elseif not distanceValue10 then
                State.textLabel5.Text = "AIM AT TARGET"
                State.textLabel5.TextColor3 = Color3.fromRGB(255, 150, (150.0))
                State.frame3.BackgroundColor3 = Color3.fromRGB((255.0), 100, 100)
                local recoveredValue254, onScreen = cameraValue9:WorldToViewportPoint(distanceValue50)
                local cameraValue10 = Vector2.new(cameraValue9.ViewportSize.X / 2, cameraValue9.ViewportSize.Y / 2)
                local distanceValue25 = (Vector2.new(recoveredValue254.X, recoveredValue254.Y) - cameraValue10).Magnitude
                local recoveredValue202 = string.format("%.0f", distanceValue25 - Config.spearFovRadius)
                if not onScreen then
                    State.textLabel6.Text = "Target di belakang kamera"
                else
                    State.textLabel6.Text = string.format("Masuk FOV: %s px lagi", recoveredValue202)
                end
            elseif not State.timeValue18 then
                State.textLabel5.Text = "READY"
                State.textLabel5.TextColor3 = Color3.fromRGB(255, 255, (255.0))
                State.frame3.BackgroundColor3 = Color3.fromRGB((150.0), 150, 200)
                State.textLabel6.Text = string.format("%s | %s studs | Hold: %ss", recoveredValue91, recoveredValue272, string.format("%.2f", recoveredValue79))
            else
                local timeValue22 = tick() - State.timeValue17
                local recoveredValue401 = string.format("%.2f", timeValue22)
                local recoveredValue428 = string.format("%.2f", recoveredValue79)
                local recoveredValue308 = HelperFunction96(cameraValue9, distanceValue50, Config.spearFovRadius)
                if not recoveredValue308 then
                    State.textLabel5.Text = "AIM AT TARGET"
                    State.textLabel5.TextColor3 = Color3.fromRGB(255, (150.0), 150)
                    State.frame3.BackgroundColor3 = Color3.fromRGB(255, (100.0), (100.0))
                    State.textLabel6.Text = "Target keluar FOV!"
                elseif timeValue22 >= recoveredValue79 then

                    local stabNow = State.spearLastStab
                    if stabNow ~= nil and stabNow < 0.35 then
                        State.textLabel5.Text = "UNSTABLE!"
                        State.textLabel5.TextColor3 = Color3.fromRGB(255, (150.0), (50.0))
                        State.frame3.BackgroundColor3 = Color3.fromRGB((255.0), 150, (50.0))
                        State.textLabel6.Text = "Target bermanuver, tahan dulu..."
                    else
                        State.textLabel5.Text = "RELEASE!"
                        State.textLabel5.TextColor3 = Color3.fromRGB((80.0), 255, 120)
                        State.frame3.BackgroundColor3 = Color3.fromRGB((50.0), 255, (100.0))
                        State.textLabel6.Text = string.format("Hold: %ss | Ideal: %ss", recoveredValue401, recoveredValue428)
                    end
                else
                    State.textLabel5.Text = "HOLD..."
                    State.textLabel5.TextColor3 = Color3.fromRGB(255, (220.0), 100)
                    State.frame3.BackgroundColor3 = Color3.fromRGB((255.0), 200, (50.0))
                    State.textLabel6.Text = string.format("Hold: %ss | Ideal: %ss", recoveredValue401, recoveredValue428)
                end
            end
        end
        if State.silentSpearEnabled and attributeValue24 and distanceValue17 and distanceValue17.Character then
            local distanceValue50 = HelperFunction199(distanceValue17.Character)
            local rootPart8 = distanceValue17.Character:FindFirstChild("HumanoidRootPart")
            if typeof(distanceValue50) == "Vector3" and rootPart8 then
                local recoveredValue389 = HelperFunction96(cameraValue9, distanceValue50, Config.spearFovRadius)
                if recoveredValue389 then
                    local recoveredValue379 = cameraValue9.CFrame.Position
                    local distanceValue22 = distanceValue50 - recoveredValue379
                    local distanceValue11 = distanceValue22.Magnitude
                    if distanceValue11 > 0.1 then
                        local distanceValue40 = 142.5
                        if State.timeValue18 and State.timeValue17 then
                            local timeValue13 = tick() - State.timeValue17
                            if timeValue13 >= 2 then distanceValue40 = 165
                            elseif timeValue13 >= 1 then distanceValue40 = 142.5
                            else distanceValue40 = math.max((23.0), timeValue13 * 150) end
                        end

                        local distanceValue35 = distanceValue40
                        distanceValue40 = distanceValue35 * (tonumber(State.distanceValue57) or 1.0)
                        local distanceValue9 = Workspace.Gravity * (State.spearGravityMultiplier or 1)
                        local vectorValue66, stabNow = nil, 1
                        if Config.spearAutoPrediction then
                            vectorValue66, stabNow = UpdateTargetVelocityHistory(vectorValue41, distanceValue17.Character, distanceValue50)
                        else
                            vectorValue41.char, vectorValue41.hist, vectorValue41.vectorValue46 = nil, {}, Vector3.new((0.0), 0, 0)
                            vectorValue41.turn = 0
                            local vel = rootPart8.AssemblyLinearVelocity
                            vectorValue66 = Vector3.new(vel.X, (0.0), vel.Z)
                            if vectorValue66.Magnitude > 65 then vectorValue66 = vectorValue66.Unit * 65 end
                        end
                        State.vectorValue64 = vectorValue66
                        State.spearLastStab = math.clamp(stabNow or 1, 0, 1)

                        local recoveredValue437 = 1
                        if Config.spearAntiStrafing then recoveredValue437 = 0.55 + 0.45 * State.spearLastStab end
                        local distanceValue63, travelTime = HelperFunction136(recoveredValue379, distanceValue50, distanceValue40, distanceValue9)
                        if distanceValue63 and travelTime then

                            local distanceValue62 = Spear_PingSec() * (tonumber(Config.spearPingLead) or 1.0)
                            local lead = State.vectorValue64 * ((travelTime + distanceValue62) * recoveredValue437)

                            local distanceValue18 = math.max(distanceValue11 * 0.4, 4)
                            if lead.Magnitude > distanceValue18 then lead = lead.Unit * distanceValue18 end
                            local predictedPos = distanceValue50 + lead
                            local recoveredValue42, finalTime = HelperFunction136(recoveredValue379, predictedPos, distanceValue40, distanceValue9)

                            if recoveredValue42 and finalTime and finalTime > 0.35 then
                                local distanceValue41 = State.vectorValue64 * ((finalTime + distanceValue62) * recoveredValue437)
                                if distanceValue41.Magnitude > distanceValue18 then distanceValue41 = distanceValue41.Unit * distanceValue18 end
                                local recoveredValue342 = distanceValue50 + distanceValue41
                                local recoveredValue67 = HelperFunction136(recoveredValue379, recoveredValue342, distanceValue40, distanceValue9)
                                if recoveredValue67 then recoveredValue42, predictedPos = recoveredValue67, recoveredValue342 end
                            end
                            if recoveredValue42 then
                                State.stateField42 = predictedPos; State.stateField109 = recoveredValue42
                                State.spearLastShot = { dist = distanceValue11, speed = distanceValue40, raw = distanceValue35, tof = travelTime, lead = lead.Magnitude, ping = distanceValue62, t = tick(), grav = (State.spearGravityMultiplier or 1), stab = State.spearLastStab }
                            else
                                State.stateField42 = nil; State.stateField109 = nil
                                State.spearLastShot = nil
                            end
                        else
                            State.stateField42 = nil; State.stateField109 = nil
                        end
                    else
                        State.stateField42 = nil; State.stateField109 = nil
                    end
                else
                    State.stateField42 = nil; State.stateField109 = nil
                end
            else
                State.stateField42 = nil; State.stateField109 = nil
            end
        else
            State.stateField42 = nil; State.stateField109 = nil
        end
    end)
end


local StartNoclip, StopNoclip
do
    local connection22 = nil


    local cache25 = {}


    local recoveredValue152 = (getgenv and getgenv()) or _G
    recoveredValue152.BlehHubNoclipGen = (tonumber(recoveredValue152.BlehHubNoclipGen) or 0) + 1
    local recoveredValue47 = recoveredValue152.BlehHubNoclipGen


    local function HelperFunction188(char, collideOn)
        if not char then return end
        if not cache25[char] then cache25[char] = {} end
        local part5 = cache25[char]
        if collideOn then
            for part, _ in pairs(part5) do
                if part and part.Parent then
                    pcall(function() part.CanCollide = true end)
                end
            end
            cache25[char] = {}
        else
            for _, value2 in ipairs(char:GetDescendants()) do
                if value2:IsA("BasePart") and part5[value2] == nil then
                    local success, cur = pcall(function() return value2.CanCollide end)
                    if success and cur then
                        part5[value2] = true
                        pcall(function() value2.CanCollide = false end)
                    end
                end
            end
        end
    end

    local function HelperFunction157()
        local cache29 = {}
        for char, _ in pairs(cache25) do
            if not char or not char.Parent then cache29[#cache29 + (1.0)] = char end
        end
        for _, char in ipairs(cache29) do cache25[char] = nil end
    end

    function StartNoclip()
        StopNoclip()
        State.noclipEnabled = true
        connection22 = RunService.Stepped:Connect(function()
            if recoveredValue47 ~= recoveredValue152.BlehHubNoclipGen then
                pcall(function() connection22:Disconnect() end)
                connection22 = nil
                return
            end
            if not State.noclipEnabled then return end
            local char = LocalPlayer.Character
            if char then HelperFunction188(char, false) end
        end)
    end

    function StopNoclip()
        State.noclipEnabled = false
        if connection22 then
            pcall(function() connection22:Disconnect() end)
            connection22 = nil
        end
        HelperFunction157()
        local char = LocalPlayer.Character
        if char then HelperFunction188(char, true) end
    end

    LocalPlayer.CharacterAdded:Connect(function()
        HelperFunction157()
    end)


    pcall(HelperFunction157)
    pcall(function()
        local char = LocalPlayer.Character
        if char then HelperFunction188(char, true) end
    end)
end

local StartFlyGui, StopFlyGui
do
    local recoveredValue339 = "https://raw.githubusercontent.com/b00l08g87b/trbg/refs/heads/main/FlyGuiV3.lua"

    local function HelperFunction24()
        local char = LocalPlayer.Character
        if not char then return end
        local rootPart16 = char:FindFirstChild("HumanoidRootPart")
        if rootPart16 then
            pcall(function() rootPart16.AssemblyLinearVelocity = Vector3.zero end)
        end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            pcall(function() humanoid.PlatformStand = false end)
            for _, vectorValue6 in ipairs(Enum.HumanoidStateType:GetEnumItems()) do


                if vectorValue6 ~= Enum.HumanoidStateType.None then
                    pcall(function() humanoid:SetStateEnabled(vectorValue6, true) end)
                end
            end
        end


        for _, descendant in ipairs(char:GetDescendants()) do
            if descendant:IsA("BodyGyro") or descendant:IsA("BodyVelocity")
                or descendant:IsA("BodyPosition") or descendant:IsA("BodyForce") then
                pcall(function() descendant:Destroy() end)
            end
        end
        local recoveredValue9 = char:FindFirstChild("Animate")
        if recoveredValue9 then pcall(function() recoveredValue9.Disabled = false end) end
    end

    function StartFlyGui()
        pcall(function()
            local connection20 = PlayerGui:FindFirstChild("main")
            if connection20 then connection20:Destroy() end
        end)
        local success, err = pcall(function()
            loadstring(game:HttpGet(recoveredValue339))()
        end)
        if not success then
            Notify("Fly GUI", "Failed to load: " .. tostring(err), 2)
        end
    end

    function StopFlyGui()


        pcall(function()
            local textLabel4 = (getgenv and getgenv()) or _G
            textLabel4.nowe = false
            textLabel4.tpwalking = false
        end)
        pcall(function()
            local gui = PlayerGui:FindFirstChild("main")
            if gui then gui:Destroy() end
        end)
        HelperFunction24()
    end


    pcall(function()
        local textLabel4 = (getgenv and getgenv()) or _G
        textLabel4.nowe = false
        textLabel4.tpwalking = false
    end)
end

(function() -- local-limit isolation: runtime hooks
    local function HelperFunction116(player, char)
        if player == LocalPlayer then return end
        if not char or not char.Parent or player.Character ~= char then return end
        AttachESPToChar(player, char)
        AttachOutlineToChar(player, char)
        if Config.hitboxModifierEnabled then
            task.wait(0.3)
            if player.Character == char and char.Parent then
                ApplyHitboxModifier(player, char)
            end
        end
        if Config.hitboxEspEnabled then AttachHitboxEsp(player, char) end
        if State.autoParryEnabled or (AP_State and AP_State.Enabled) then
            if AP_HookKiller then AP_HookKiller(player, char) end
        end
    end

    local function HelperFunction3(player)
        if player == LocalPlayer then return end
        UpdatePlayerRole(player)
        HelperFunction191(player)
        HelperFunction2(player)
        player:GetPropertyChangedSignal("Team"):Connect(function()
            UpdatePlayerRole(player)
            task.wait(0.2)
            if State.autoParryEnabled or (AP_State and AP_State.Enabled) then
                if AP_HookKiller then AP_HookKiller(player) end
            end
        end)
        if player.Character then
            task.spawn(function() HelperFunction116(player, player.Character) end)
        end
        player.CharacterAdded:Connect(function(char)
            task.spawn(function() HelperFunction116(player, char) end)
        end)
    end

    local function HelperFunction203(player)
        RemovePlayerESP(player)
        RemoveHitboxEsp(player)
        if player.Character then RestoreHitboxModifier(player, player.Character) end
    end

    Players.PlayerAdded:Connect(HelperFunction3)
    Players.PlayerRemoving:Connect(HelperFunction203)

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local okPlayerInit, playerInitErr = pcall(HelperFunction3, player)
            if not okPlayerInit then warn("[Bleh Hub Init] player " .. tostring(player.Name) .. ": " .. tostring(playerInitErr)) end
        end
    end


    local function HelperFunction189(char)
        State.stateField15 = false; State.humanoid4 = nil
        State.stateField83 = false; State.stateField33 = false
        CV_ClearLock()
        if State.stateField26 then task.defer(CV_ScanAttackButtons) end
        task.spawn(SetupMovementForChar, char)
        if State.stateField12 then
            task.wait(0.3); StopGodMode(); StartGodMode()
        end
        if Config.lockFovEnabled then
            task.wait(0.1); State.stateField101 = nil; SetStretchedResolution(Config.fovValue)
        end
        if Config.maxCameraZoomEnabled then
            task.wait(0.1); State.distanceValue4 = nil; SetMaxCameraZoom(Config.cameraZoomValue)
        end
        if Config.showGenBoostButton then
            task.delay(1, function()
                pcall(DestroyGenBoostButton)
                pcall(CreateGenBoostButton)
            end)
        end
        if GetPlayerRole(LocalPlayer) ~= "killer" and FP_ReArm then
            task.delay(1, function()
                if GetPlayerRole(LocalPlayer) ~= "killer" then pcall(FP_ReArm) end
            end)
        end
    end

    if LocalPlayer.Character then
        task.spawn(HelperFunction189, LocalPlayer.Character)
    end
    LocalPlayer.CharacterAdded:Connect(function(char)
        task.spawn(HelperFunction189, char)
    end)
end)()

do

    local remote25    = nil
    local remote22 = nil
    local function HelperFunction122()
        local window = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("Window")
        if not window then return end
        remote25    = window:FindFirstChild("fastvault")
        remote22 = window:FindFirstChild("VaultCompleteEventpart1")
    end
    pcall(HelperFunction122)


    local function HelperFunction108()
        if not Config.forceFlowstatePerk then return end
        local timeValue12 = tick()
        if timeValue12 < State.stateField49 then return end

        State.stateField3 = timeValue12 + 0.5
        State.stateField49 = timeValue12 + (Config.flowstateCooldown or 15)
    end


    local function HelperFunction167()
        local recoveredValue312 = false
        local function HelperFunction176(descendant)
            return descendant:IsA("BasePart") and (descendant.Name == "VaultTrigger" or descendant.Name == "VaultPoint")
        end
        local function HelperFunction198(descendant)
            if not HelperFunction176(descendant) then return end
            for _, viewportOrPoint in ipairs(State.fastVaultPoints) do
                if viewportOrPoint == descendant then return end
            end
            table.insert(State.fastVaultPoints, descendant)
        end
        local function HelperFunction37(descendant)
            for index, viewportOrPoint in ipairs(State.fastVaultPoints) do
                if viewportOrPoint == descendant then table.remove(State.fastVaultPoints, index) break end
            end
        end
        if recoveredValue312 then return end
        recoveredValue312 = true
        for _, recoveredValue267 in ipairs(CollectionService:GetTagged("VaultPoint")) do
            HelperFunction198(recoveredValue267)
        end
        Workspace.DescendantAdded:Connect(HelperFunction198)
        Workspace.DescendantRemoving:Connect(HelperFunction37)
    end
    pcall(HelperFunction167)


    local function HelperFunction159(pos, vectorValue62)
        local recoveredValue70, distanceValue60 = nil, vectorValue62
        for _, viewportOrPoint in ipairs(State.fastVaultPoints) do
            if viewportOrPoint and viewportOrPoint.Parent then
                local distance = (viewportOrPoint.Position - pos).Magnitude
                if distance < distanceValue60 then
                    distanceValue60 = distance
                    recoveredValue70 = viewportOrPoint
                end
            end
        end
        return recoveredValue70
    end


    RegisterUpdateTask("FastVault", 0.05, function()
        if not Config.alwaysFastVault then return end
        if GetPlayerRole(LocalPlayer) == "killer" then return end

        local char = LocalPlayer.Character
        local rootPart2 = char and char:FindFirstChild("HumanoidRootPart")
        if not char or not rootPart2 then return end


        if HelperFunction159(rootPart2.Position, (6.0)) then
            pcall(function()
                char:SetAttribute("Sprinting", true)
                char:SetAttribute("IsRunning", true)
            end)
        end
    end)


    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if not Config.alwaysFastVault then return end
        if GetPlayerRole(LocalPlayer) == "killer" then return end
        if gameProcessed then return end

        local recoveredValue222 = input.KeyCode
        if recoveredValue222 ~= Enum.KeyCode.Space and recoveredValue222 ~= Enum.KeyCode.E then return end

        local char = LocalPlayer.Character
        local rootPart2 = char and char:FindFirstChild("HumanoidRootPart")
        if not char or not rootPart2 then return end

        local viewportOrPoint = HelperFunction159(rootPart2.Position, 9)
        if not viewportOrPoint then return end


        local vectorValue61 = viewportOrPoint.Position - rootPart2.Position
        vectorValue61 = Vector3.new(vectorValue61.X, 0, vectorValue61.Z)
        if vectorValue61.Magnitude > 0.05 then
            vectorValue61 = vectorValue61.Unit
        else
            vectorValue61 = Vector3.new(rootPart2.CFrame.LookVector.X, 0, rootPart2.CFrame.LookVector.Z).Unit
        end


        local vel = rootPart2.AssemblyLinearVelocity
        local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
        if speed < 13 then
            pcall(function()
                char:SetAttribute("Sprinting", true)
                char:SetAttribute("IsRunning", true)
            end)
            rootPart2.CFrame = CFrame.new(rootPart2.Position, rootPart2.Position + vectorValue61)
            rootPart2.AssemblyLinearVelocity = vectorValue61 * 22
        end
    end)


    local success, SurvivorActions = pcall(function()
        local recoveredValue418 = ReplicatedStorage:FindFirstChild("Modules", true)
        local recoveredValue15 = recoveredValue418 and recoveredValue418:FindFirstChild("SurvivorActions", true)
        return recoveredValue15 and require(recoveredValue15)
    end)
    if success and SurvivorActions and SurvivorActions.startVault then
        local recoveredValue107 = SurvivorActions.startVault
        SurvivorActions.startVault = (newcclosure or function(fn) return fn end)(function(controller, vaultPoint)


            HelperFunction108()
            if not Config.alwaysFastVault then
                return recoveredValue107(controller, vaultPoint)
            end


            pcall(function()
                local char = controller and controller.character
                if char then
                    char:SetAttribute("Sprinting", true)
                    char:SetAttribute("IsRunning", true)
                    local rootPart2 = char:FindFirstChild("HumanoidRootPart")
                    if rootPart2 then
                        local viewportOrPoint = vaultPoint and (vaultPoint.Position or (vaultPoint:IsA("Model") and vaultPoint.PrimaryPart and vaultPoint.PrimaryPart.Position))
                        if viewportOrPoint then
                            local vectorValue61 = viewportOrPoint - rootPart2.Position
                            vectorValue61 = Vector3.new(vectorValue61.X, 0, vectorValue61.Z)
                            if vectorValue61.Magnitude > 0.05 then
                                rootPart2.AssemblyLinearVelocity = vectorValue61.Unit * 22
                            end
                        end
                    end
                end
            end)
            local cache37 = { recoveredValue107(controller, vaultPoint) }

            if remote25 then
                pcall(function() remote25:FireServer(LocalPlayer) end)
            end
            if remote22 then
                pcall(function() remote22:FireServer() end)
            end
            return unpack(cache37)
        end)
    end


    pcall(function()
        local recoveredValue418 = ReplicatedStorage:FindFirstChild("Modules", true)
        local recoveredValue333 = recoveredValue418 and recoveredValue418:FindFirstChild("SurvivorAnimationsController", true)
        local recoveredValue30 = recoveredValue333 and require(recoveredValue333)
        if recoveredValue30 and recoveredValue30._isFacingStraightEnough then
            local recoveredValue87 = recoveredValue30._isFacingStraightEnough
            recoveredValue30._isFacingStraightEnough = (newcclosure or function(fn) return fn end)(function(...)
                if not Config.alwaysFastVault then
                    return recoveredValue87(...)
                end
                return true
            end)
        end
    end)


    local function HelperFunction85()
        local cache34 = {
        gui      = nil,
        panel    = nil,
        rows     = nil,
        taskName = "KillerPerksInfo",
        stateField95  = nil,
        dragConn = {},
        perkSet  = {},
        stateField45 = false,
        stateField70  = nil,
        stateField47 = false,
    }

    local cache46 = {
        "Predator", "Eternal Torment", "Play With Your Food", "Terror Spread",
        "Sloppy Mess", "Resentment Clinger", "Echo Location", "Enhanced Senses",
        "Next in Line", "Corrupted Path", "Abyssal Covenant", "Shadow Trace",
        "Piercing Reverie", "Blood Between Worlds", "Echo Of The Void",
        "Excitement", "Brutal Strength", "Offscreen Scare", "Hard Swing",
        "Combo Streak", "Crackdown", "Sustenance", "Foundation Staff",
        "Desire For The Living", "Deep Wound", "All Seeing Eye", "Touch Of Death",
        "Murderous Acrobatics", "Eyes Of Hell", "Stage Fright",
        "Trade Off", "Containment", "King's Scourge",
    }

    local function HelperFunction7(name)
        if not name then return "" end
        return tostring(name):lower():gsub("[^%a%d]", ""):gsub("excitment", "excitement")
    end

    local cache42 = {
        exposuretherapy = true,
    }

    local function HelperFunction56(name)
        if not name or name == "" then return end
        local cframeValue = HelperFunction7(name)
        if cframeValue == "" then return end
        if cache42[cframeValue] then return end
        cache34.perkSet[cframeValue] = name
    end

    local function HelperFunction26()
        if cache34.stateField45 then return end
        cache34.stateField45 = true
        for _, recoveredValue301 in ipairs(cache46) do
            HelperFunction56(recoveredValue301)
        end
        pcall(function()
            local cache10 = {
                ReplicatedStorage:FindFirstChild("Killers"),
                ReplicatedStorage:FindFirstChild("ShopKillers"),
                ReplicatedStorage:FindFirstChild("Perks"),
                ReplicatedStorage:FindFirstChild("KillerPerks"),
            }
            for _, recoveredValue122 in ipairs(cache10) do
                if recoveredValue122 then
                    for _, child in ipairs(recoveredValue122:GetChildren()) do
                        if recoveredValue122.Name == "Perks" or recoveredValue122.Name == "KillerPerks" then
                            HelperFunction56(child.Name)
                        else
                            local recoveredValue243 = child:FindFirstChild("Perks")
                            if recoveredValue243 then
                                for _, recoveredValue236 in ipairs(recoveredValue243:GetChildren()) do
                                    HelperFunction56(recoveredValue236.Name)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    local function HelperFunction179()
        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            if GetPlayerRole(targetPlayer) == "killer" then
                return targetPlayer
            end
        end
        for _, targetPlayer in ipairs(Players:GetPlayers()) do
            local success, team = pcall(function() return targetPlayer.Team and targetPlayer.Team.Name or "" end)
            if success and tostring(team):lower():find("killer") then
                return targetPlayer
            end
        end
        return nil
    end

    local function HelperFunction43(cframeValue, cache37)
        if cframeValue == "" then return end
        for recoveredValue404, recoveredValue101 in pairs(cache34.perkSet) do
            if cframeValue == recoveredValue404 or cframeValue:find(recoveredValue404, (1.0), true) or recoveredValue404:find(cframeValue, 1, true) then
                if not cache37[recoveredValue101] then
                    cache37[recoveredValue101] = true
                end
                return
            end
        end
    end

    local function HelperFunction48(killer)
        local cache37 = {}
        local function HelperFunction72(name)
            HelperFunction43(HelperFunction7(name), cache37)
        end
        local char = killer.Character

        pcall(function()
            for _, value2 in pairs(killer:GetAttributes()) do
                HelperFunction72(tostring(value2))
            end
            for name in pairs(killer:GetAttributes()) do
                HelperFunction72(name)
            end
        end)

        pcall(function()
            local recoveredValue36 = killer:FindFirstChild("EquippedPerks") or killer:FindFirstChild("Perks")
            if recoveredValue36 then
                for _, child in ipairs(recoveredValue36:GetChildren()) do
                    HelperFunction72(child.Name)
                    if child:IsA("ValueBase") and type(child.Value) == "string" then
                        HelperFunction72(child.Value)
                    end
                end
            end
        end)

        if char then
            pcall(function()
                for _, value2 in pairs(char:GetAttributes()) do
                    HelperFunction72(tostring(value2))
                end
                for name in pairs(char:GetAttributes()) do
                    HelperFunction72(name)
                end
            end)
            pcall(function()
                for _, child in ipairs(char:GetChildren()) do
                    HelperFunction72(child.Name)
                end
            end)
        end
        return cache37
    end

    local function HelperFunction149()
        local success, parentObject = pcall(function()
            if gethui then return gethui() end
            return nil
        end)
        if success and parentObject then return parentObject end
        local successFlag6, core = pcall(function() return game:GetService("CoreGui") end)
        if successFlag6 and core then return core end
        return PlayerGui
    end

    local function HelperFunction50()
        local screenGui = Instance.new("ScreenGui")
        screenGui.Name = "BlehHubKillerPerksInfo"
        screenGui.ResetOnSpawn = false
        screenGui.IgnoreGuiInset = true
        screenGui.DisplayOrder = 9999998
        screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        screenGui.Parent = HelperFunction149()

        local panel = Instance.new("Frame")
        panel.Name = "Panel"
        panel.BackgroundColor3 = Color3.fromRGB(10, (10.0), 14)
        panel.BackgroundTransparency = 0.06
        panel.BorderSizePixel = (0.0)
        panel.Size = UDim2.fromOffset(220, 0)
        panel.AutomaticSize = Enum.AutomaticSize.Y
        panel.Position = State.kpiPos or UDim2.new((1.0), -12, 0, 12)
        panel.AnchorPoint = Vector2.new(1, 0)
        panel.Active = true
        panel.Parent = screenGui

        local recoveredValue226 = Instance.new("UICorner")
        recoveredValue226.CornerRadius = UDim.new((0.0), (8.0))
        recoveredValue226.Parent = panel

        local colorValue14 = Instance.new("UIStroke")
        colorValue14.Color = Color3.fromRGB(60, 60, 75)
        colorValue14.Thickness = 1
        colorValue14.Parent = panel

        local recoveredValue395 = Instance.new("UIPadding")
        recoveredValue395.PaddingLeft = UDim.new(0, 8)
        recoveredValue395.PaddingRight = UDim.new(0, (8.0))
        recoveredValue395.PaddingTop = UDim.new((0.0), (6.0))
        recoveredValue395.PaddingBottom = UDim.new(0, 6)
        recoveredValue395.Parent = panel

        local recoveredValue362 = Instance.new("UIListLayout")
        recoveredValue362.Padding = UDim.new(0, 3)
        recoveredValue362.SortOrder = Enum.SortOrder.LayoutOrder
        recoveredValue362.Parent = panel

        local frame12 = Instance.new("Frame")
        frame12.Name = "Header"
        frame12.LayoutOrder = (1.0)
        frame12.BackgroundTransparency = 1
        frame12.BorderSizePixel = 0
        frame12.Size = UDim2.new(1, 0, 0, 16)
        frame12.Parent = panel

        local labelOrTitle = Instance.new("TextLabel")
        labelOrTitle.Name = "Title"
        labelOrTitle.BackgroundTransparency = (1.0)
        labelOrTitle.BorderSizePixel = 0
        labelOrTitle.Size = UDim2.new(1, (-20.0), (0.0), 16)
        labelOrTitle.Text = "KILLER"
        labelOrTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        labelOrTitle.TextSize = 11
        labelOrTitle.Font = Enum.Font.GothamBold
        labelOrTitle.TextXAlignment = Enum.TextXAlignment.Left
        labelOrTitle.TextYAlignment = Enum.TextYAlignment.Center
        labelOrTitle.RichText = true
        labelOrTitle.Parent = frame12

        local button2 = Instance.new("TextButton")
        button2.Name = "Minimize"
        button2.BackgroundTransparency = 1
        button2.BorderSizePixel = 0
        button2.Size = UDim2.new(0, (16.0), 0, 16)
        button2.Position = UDim2.new(1, (-16.0), 0, 0)
        button2.Text = "-"
        button2.TextColor3 = Color3.fromRGB((160.0), 162, 170)
        button2.TextSize = (13.0)
        button2.Font = Enum.Font.GothamBold
        button2.Parent = frame12

        button2.MouseButton1Click:Connect(function()
            cache34.minimized = not cache34.minimized
            if cache34.rows then
                cache34.rows.Visible = not cache34.minimized
            end
            local recoveredValue429 = panel:FindFirstChild("Divider")
            if recoveredValue429 then recoveredValue429.Visible = not cache34.minimized end
        end)

        local frame10 = Instance.new("Frame")
        frame10.Name = "Divider"
        frame10.LayoutOrder = 1.5
        frame10.BackgroundColor3 = Color3.fromRGB((60.0), (60.0), (75.0))
        frame10.BackgroundTransparency = 0.4
        frame10.BorderSizePixel = 0
        frame10.Size = UDim2.new(1, 0, (0.0), 1)
        frame10.Parent = panel

        local rows = Instance.new("Frame")
        rows.Name = "Rows"
        rows.LayoutOrder = 3
        rows.BackgroundTransparency = 1
        rows.BorderSizePixel = 0
        rows.Size = UDim2.new((1.0), 0, 0, 0)
        rows.AutomaticSize = Enum.AutomaticSize.Y
        rows.Parent = panel

        local recoveredValue99 = Instance.new("UIListLayout")
        recoveredValue99.Padding = UDim.new(0, 2)
        recoveredValue99.SortOrder = Enum.SortOrder.LayoutOrder
        recoveredValue99.Parent = rows


        local recoveredValue194, recoveredValue414, distanceValue3
        frame12.Active = true
        frame12.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                recoveredValue194 = true
                recoveredValue414 = input.Position
                distanceValue3 = panel.Position
            end
        end)
        frame12.InputChanged:Connect(function(input)
            if recoveredValue194 and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local vectorValue40 = input.Position - recoveredValue414
                panel.Position = UDim2.new(1, distanceValue3.X.Offset + vectorValue40.X, 0, distanceValue3.Y.Offset + vectorValue40.Y)
            end
        end)
        frame12.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                recoveredValue194 = false
                State.kpiPos = panel.Position
            end
        end)

        cache34.gui = screenGui
        cache34.panel = panel
        cache34.rows = rows
    end

    local function HelperFunction79()

        if not cache34.gui or not cache34.gui.Parent then return end

        local killer = HelperFunction179()
        local recoveredValue222, text
        if not killer then
            recoveredValue222 = "none"
            text = "<font color=\"rgb(160,162,170)\">No killer detected.</font>"
        else
            local recoveredValue430 = HelperFunction48(killer)
            local cache6 = {}
            for name in pairs(recoveredValue430) do
                table.insert(cache6, name)
            end
            table.sort(cache6)
            recoveredValue222 = killer.Name .. "|" .. table.concat(cache6, ",")
            local cache14 = {}
            for _, name in ipairs(cache6) do
                table.insert(cache14, "<font color=\"rgb(200,200,210)\">- " .. name .. "</font>")
            end
            if #cache14 == 0 then
                text = "<font color=\"rgb(160,162,170)\">No perks detected.</font>"
            else
                text = table.concat(cache14, "\n")
            end
            recoveredValue222 = recoveredValue222 .. "#" .. tostring(killer.Character and killer.Character.Name or "")
        end

        if recoveredValue222 == cache34.stateField95 then return end
        cache34.stateField95 = recoveredValue222

        local labelOrTitle = cache34.panel and cache34.panel:FindFirstChild("Header") and cache34.panel:FindFirstChild("Header"):FindFirstChild("Title")
        if labelOrTitle then
            labelOrTitle.Text = killer and ('KILLER <font color="rgb(255,80,80)">•</font> <font color="rgb(252,235,229)">' .. killer.Name .. "</font>") or "KILLER"
        end

        if cache34.rows then
            cache34.rows.Visible = not cache34.minimized
            for _, child in ipairs(cache34.rows:GetChildren()) do
                if child:IsA("TextLabel") then
                    child:Destroy()
                end
            end
            local recoveredValue410 = 1
            for frame13 in string.gmatch(text, "[^\n]+") do
                local label = Instance.new("TextLabel")
                label.BackgroundTransparency = (1.0)
                label.BorderSizePixel = 0
                label.AutomaticSize = Enum.AutomaticSize.XY
                label.LayoutOrder = recoveredValue410
                recoveredValue410 = recoveredValue410 + 1
                label.Text = frame13
                label.TextColor3 = Color3.fromRGB(200, 200, 210)
                label.TextSize = 12
                label.Font = Enum.Font.Gotham
                label.RichText = true
                label.TextXAlignment = Enum.TextXAlignment.Left
                label.Parent = cache34.rows
            end
        end
    end

    function StartKillerPerksInfo()
        if not Config.killerPerksInfoEnabled then return end
        HelperFunction26()
        if cache34.gui and cache34.gui.Parent then
            cache34.gui.Enabled = true
        else
            HelperFunction50()
        end
        HelperFunction79()
        if not cache34.stateField47 then
            RegisterUpdateTask(cache34.taskName, 2, function()
                if not Config.killerPerksInfoEnabled then return end
                HelperFunction79()
            end)
            cache34.stateField47 = true
        end
    end

    function StopKillerPerksInfo()
        if cache34.gui then
            pcall(function() cache34.gui:Destroy() end)
            cache34.gui = nil
            cache34.panel = nil
            cache34.rows = nil
        end
        cache34.stateField95 = nil
    end

    function SetKPI_ToggleRef(toggle)
        cache34.stateField70 = toggle
    end
    end
    pcall(HelperFunction85)


    RegisterUpdateTask("Flowstate", 0.1, function()
        if not Config.forceFlowstatePerk then return end
        if GetPlayerRole(LocalPlayer) == "killer" then return end

        local char = LocalPlayer.Character
        local timeValue12 = tick()
        local active = not (timeValue12 < State.stateField49) or (timeValue12 < State.stateField3)


        local cache21 = { LocalPlayer, char }
        local cache24 = { "climb_obsessing", "climb_collisoning", "climb_collisioning", "climb_colliding" }
        local recoveredValue179 = false
        for _, name in ipairs(cache24) do
            local recoveredValue204 = Workspace:FindFirstChild(name)
            if recoveredValue204 then
                local recoveredValue243 = recoveredValue204:FindFirstChild(LocalPlayer.Name)
                if recoveredValue243 and recoveredValue243:IsA("Model") then
                    recoveredValue179 = true
                    table.insert(cache21, recoveredValue243)
                end
            end
        end
        if recoveredValue179 then HelperFunction108() end

        for _, target in ipairs(cache21) do
            if target then
                local cur = target:GetAttribute("Flowstate")
                if cur ~= active then
                    pcall(function() target:SetAttribute("Flowstate", active) end)
                end
            end
        end
    end)


    RegisterUpdateTask("FlowstateUI", 0.2, function()
        local recoveredValue40 = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not recoveredValue40 then return end

        local gui = recoveredValue40:FindFirstChild("FlowstateUIGui")
        local recoveredValue160 = Config.forceFlowstatePerk and not Config.hideFlowstateUi

        if not recoveredValue160 then
            if gui then pcall(function() gui:Destroy() end) end
            return
        end


        if not gui then
            gui = Instance.new("ScreenGui")
            gui.Name = "FlowstateUIGui"
            gui.IgnoreGuiInset = true
            gui.Parent = recoveredValue40

            local label = Instance.new("TextLabel")
            label.Name = "FlowstateCooldownLabel"
            label.BackgroundTransparency = 1
            label.TextXAlignment = Enum.TextXAlignment.Center
            label.TextYAlignment = Enum.TextYAlignment.Center
            label.TextScaled = false
            label.TextSize = (16.0)
            label.TextStrokeTransparency = 0
            label.TextStrokeColor3 = Color3.fromRGB(0, (0.0), 0)
            label.Size = UDim2.new(0, 220, 0, (22.0))
            label.Position = UDim2.new(0.5, 0, 0, (55.0))
            label.AnchorPoint = Vector2.new(0.5, 0)
            label.Font = Enum.Font.GothamBold
            label.Parent = gui
        end

        local label = gui:FindFirstChild("FlowstateCooldownLabel")
        if label then
            local timeValue12 = tick()
            if timeValue12 < State.stateField49 then
                label.Text = "FLOWSTATE: " .. tostring(math.ceil(State.stateField49 - timeValue12)) .. "s"
                label.TextColor3 = Color3.fromRGB(255, 60, (60.0))
            else
                label.Text = "FLOWSTATE: READY"
                label.TextColor3 = Color3.fromRGB((0.0), 255, 120)
            end
        end
    end)
end

local ApplyFakePerkBuff, FP_SetPerk
do
    State.fpBuffs = State.fpBuffs or {}
    State.fpConns = State.fpConns or {}
    State.fpOn = State.fpOn or {}
    if State.fpCooldown == nil then State.fpCooldown = 10 end
    if State.fpLastEnd == nil then State.fpLastEnd = 0 end

    local function HelperFunction29()
        return LocalPlayer.Character
    end

    local function HelperFunction160()
        local timeValue5 = 0
        local timeValue12 = tick()
        for _, attributeValue22 in pairs(State.fpBuffs or {}) do
            if timeValue12 < attributeValue22.endTime then timeValue5 = timeValue5 + attributeValue22.amt end
        end
        return timeValue5
    end


    local function HelperFunction143()
        if GetPlayerRole(LocalPlayer) == "killer" then return end
        local char = HelperFunction29()
        local timeValue5 = HelperFunction160()
        if char then
            pcall(function()
                char:SetAttribute("speedboost", timeValue5 > 0 and ((1.0) + timeValue5 / 14) or 1)
            end)
        end
    end

    function ApplyFakePerkBuff(name, amt, dur)
        if GetPlayerRole(LocalPlayer) == "killer" then return end
        if State.fpBuffs[name] then return end
        if tick() - State.fpLastEnd < (State.fpCooldown or 10) and next(State.fpBuffs) == nil then return end
        State.fpBuffs[name] = { amt = amt, endTime = tick() + dur }
        if name == "PerfectLanding" then State.fpPLAnnounced = false end
        HelperFunction143()
        Notify("Fake Perks", "[" .. name .. "] Activated! +" .. math.floor(amt / 14 * (100.0)) .. "% Speed (" .. dur .. "s)", (3.0))
    end

    local function HelperFunction99(name)
        local connection19 = State.fpConns[name]
        if connection19 then
            for _, contextValue in ipairs(connection19) do pcall(function() contextValue:Disconnect() end) end
            State.fpConns[name] = nil
        end
    end

    local function HelperFunction18(name, connection)
        if connection == nil then return end
        if not State.fpConns[name] then State.fpConns[name] = {} end
        table.insert(State.fpConns[name], connection)
    end

    local function HelperFunction49(name, fn)
        HelperFunction18(name, LocalPlayer.CharacterAdded:Connect(fn))
        local cur = HelperFunction29()
        if cur then pcall(fn, cur) end
    end

    function FP_SetPerk(name, recoveredValue62)
        if name == "Flowstate" then State.fpOn.Flowstate = nil; return end
        State.fpOn[name] = recoveredValue62 and true or false
        if not recoveredValue62 then
            HelperFunction99(name)
            State.fpBuffs[name] = nil
            if name == "PerfectLanding" then State.fpPLAnnounced = false end
            HelperFunction143()
            return
        end
        if name == "QuickRecovery" then


            local function HelperFunction128(_, sprintFlag)
                if not State.fpOn.QuickRecovery then return end
                if sprintFlag ~= true then return end
                ApplyFakePerkBuff("QuickRecovery", 5.6, 3)
            end
            pcall(function()
                local recoveredValue262 = ReplicatedStorage:FindFirstChild("Remotes")
                local recoveredValue96 = recoveredValue262 and recoveredValue262:FindFirstChild("Window")
                local recoveredValue117 = recoveredValue96 and recoveredValue96:FindFirstChild("Vaultbindable")
                if recoveredValue117 and recoveredValue117:IsA("BindableEvent") then HelperFunction18(name, recoveredValue117.Event:Connect(HelperFunction128)) end
            end)
        elseif name == "PerfectLanding" then
            HelperFunction49(name, function(ch)
                local humanoid = ch:FindFirstChildOfClass("Humanoid")
                if not humanoid then return end
                local timeValue14, fallStart = false, 0
                HelperFunction18(name, humanoid.StateChanged:Connect(function(_, new)
                    if not State.fpOn.PerfectLanding then return end
                    if new == Enum.HumanoidStateType.Freefall then
                        timeValue14, fallStart = true, tick()
                    elseif timeValue14 and (new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running) then
                        timeValue14 = false
                        if tick() - fallStart >= 0.25 then
                            ApplyFakePerkBuff("PerfectLanding", 5.6, 3)
                        end
                    end
                end))
            end)
        elseif name == "AdrenalineRush" then
            HelperFunction49(name, function(ch)
                local humanoid = ch:FindFirstChildOfClass("Humanoid")
                if not humanoid then return end
                local recoveredValue127 = humanoid.Health
                HelperFunction18(name, humanoid.HealthChanged:Connect(function(newHP)
                    if State.fpOn.AdrenalineRush and newHP < recoveredValue127 and newHP <= 50 and newHP > 0 then
                        ApplyFakePerkBuff("AdrenalineRush", 4, (5.0))
                    end
                    recoveredValue127 = newHP
                end))
            end)
        end
    end


    function FP_ReArm()
        for name, recoveredValue62 in pairs(State.fpOn or {}) do
            if recoveredValue62 then
                pcall(FP_SetPerk, name, false)
                pcall(FP_SetPerk, name, true)
            end
        end
    end

    RegisterUpdateTask("FakePerks", 0.1, function()
        if next(State.fpBuffs) == nil then return end
        local timeValue12 = tick()
        local recoveredValue368 = false
        for recoveredValue200, attributeValue22 in pairs(State.fpBuffs) do
            if timeValue12 >= attributeValue22.endTime then
                State.fpBuffs[recoveredValue200] = nil
                recoveredValue368 = true
            end
        end
        if recoveredValue368 and next(State.fpBuffs) == nil then
            State.fpLastEnd = timeValue12
        end


        local recoveredValue146 = State.fpBuffs.PerfectLanding
        if recoveredValue146 and timeValue12 < recoveredValue146.endTime then
            local char = LocalPlayer.Character
            if char then
                pcall(function()
                    if char:GetAttribute("MovementLocked") then
                        char:SetAttribute("MovementLocked", false)
                        if not State.fpPLAnnounced then
                            State.fpPLAnnounced = true
                            print("[FP] MovementLocked ditahan OFF (PerfectLanding)")
                        end
                    end
                end)
            end
        end
        HelperFunction143()
    end)
end

local StartPotatoMode, StopPotato
(function() -- local-limit isolation: potato/fake perk subsystem
    local recoveredValue278 = 800
    local timeValue = 0.008

    local cache7 = {
        generator=true,generators=true,character=true,avatar=true,
        survivor=true,killer=true,window=true,vault=true,
        wood=true,wooden=true,plank=true,planks=true,
        log=true,logs=true,trunk=true,tree=true,
        equipment=true,item=true,items=true,tool=true,tools=true,
        hitbox=true,interaction=true,interact=true,prompt=true,
        attack=true,weapon=true,weapons=true,spear=true,spears=true,
    }
    local cache17 = {
        Humanoid=true,Animator=true,Animation=true,
        AnimationController=true,Tool=true,ProximityPrompt=true,
        ClickDetector=true,Weld=true,WeldConstraint=true,
        Motor6D=true,ManualWeld=true,
    }
    local cache53 = {
        ParticleEmitter=true,Smoke=true,Fire=true,Beam=true,Sparkles=true,
    }
    local cache41 = {
        leaf=true,leaves=true,leaflet=true,leaflets=true,
        leafmesh=true,leaf_mesh=true,leafpart=true,leaf_part=true,
        leaftexture=true,leaf_texture=true,leafcard=true,leaf_card=true,
        leafplane=true,leaf_plane=true,leafcluster=true,leaf_cluster=true,
        leafgroup=true,leaf_group=true,foliageleaf=true,foliage_leaf=true,
        treetop=true,tree_top=true,treeleaves=true,tree_leaves=true,
        leavesmesh=true,leaves_mesh=true,
    }
    local cache35 = {
        grass=true,grassblade=true,grass_blade=true,
    }

    local recoveredValue94, LeafKeywords, GrassKeywords = {},{},{}
    for distanceValue7 in pairs(cache7) do recoveredValue94[#recoveredValue94+(1.0)] = distanceValue7 end
    for distanceValue7 in pairs(cache41) do LeafKeywords[#LeafKeywords+1] = distanceValue7 end
    for distanceValue7 in pairs(cache35) do GrassKeywords[#GrassKeywords+1] = distanceValue7 end

    local function NormalizeName(value2)
        return string.lower(tostring(value2))
    end

    local function NameContainsKeyword(name, connection19)
        name = NormalizeName(name)
        for index = 1, #connection19 do
            if string.find(name, connection19[index], 1, true) then
                return true
            end
        end
        return false
    end


    local cache4 = {
        "endscreen", "endscreencutscene", "cutsceneend",
        "cutsceneend2", "cutsceneendwithownchar", "endgame", "end_screen",
    }

    local function IsProtectedObject(instance)
        if not instance then return false end
        local contextValue = instance
        for _ = 1, 4 do
            if not contextValue then break end
            if NameContainsKeyword(contextValue.Name, cache4) then return true end
            contextValue = contextValue.Parent
        end
        return false
    end


    local cache26 = {
        "fog", "mist", "haze", "smoke", "steam", "vapor",
    }

    local function IsVisualEffectObject(instance)
        if not instance then return false end
        if not (instance:IsA("ParticleEmitter") or instance:IsA("Smoke") or instance:IsA("Beam")) then
            return false
        end
        local contextValue = instance
        for _ = (1.0), 12 do
            if not contextValue then break end
            local name = NormalizeName(contextValue.Name)
            if string.find(name, "exit", 1, true)
                or string.find(name, "escape", 1, true)
                or string.find(name, "door", 1, true) then
                if NameContainsKeyword(name, cache26) then return true end
            end
            if NameContainsKeyword(name, cache26) then
                local parentObject = contextValue.Parent
                for _ = 1, 8 do
                    if not parentObject then break end
                    local recoveredValue320 = NormalizeName(parentObject.Name)
                    if string.find(recoveredValue320, "exit", 1, true)
                        or string.find(recoveredValue320, "escape", 1, true)
                        or string.find(recoveredValue320, "door", 1, true) then
                        return true
                    end
                    parentObject = parentObject.Parent
                end
            end
            contextValue = contextValue.Parent
        end
        return false
    end

    local function MarkPotatoProcessed(contextValue)
        if contextValue then State.stateField73[contextValue] = true end
    end

    local function UnmarkPotatoProcessed(contextValue)
        if contextValue then
            State.stateField73[contextValue] = nil
            State.stateField86[contextValue] = nil
        end
    end

    local function IsKillerPlayer(targetPlayer)
        return targetPlayer and targetPlayer.Team and targetPlayer.Team.Name == "killer"
    end

    local function ProcessPlayerCharacter(targetPlayer)
        if not targetPlayer then return end
        local contextValue = targetPlayer.Character
        if contextValue then
            if IsKillerPlayer(targetPlayer) then
                State.stateField86[contextValue] = true
            else
                State.stateField86[contextValue] = nil
            end
        end
    end

    local function WatchPlayerForPotatoMode(targetPlayer)
        if not targetPlayer then return end
        if targetPlayer.Character then
            MarkPotatoProcessed(targetPlayer.Character)
            ProcessPlayerCharacter(targetPlayer)
        end
        table.insert(State.stateField44, targetPlayer.CharacterAdded:Connect(function(contextValue)
            MarkPotatoProcessed(contextValue)
            task.defer(function() ProcessPlayerCharacter(targetPlayer) end)
        end))
        table.insert(State.stateField44, targetPlayer.CharacterRemoving:Connect(function(contextValue)
            UnmarkPotatoProcessed(contextValue)
        end))
        table.insert(State.stateField44, targetPlayer:GetPropertyChangedSignal("Team"):Connect(function()
            ProcessPlayerCharacter(targetPlayer)
        end))
    end

    local function FindTopAncestor(instance)
        local contextValue = instance
        for _ = 1, 20 do
            if not contextValue then return false end
            if State.stateField73[contextValue] then return true end
            contextValue = contextValue.Parent
        end
        return false
    end

    local function IsRenderablePart(instance)
        if not instance or not cache53[instance.ClassName] then return false end
        local contextValue = instance
        for _ = 1, 20 do
            if not contextValue then return false end
            if State.stateField86[contextValue] then return true end
            contextValue = contextValue.Parent
        end
        return false
    end

    local function FindRenderableAncestor(instance)
        local contextValue = instance
        for _ = 1, 20 do
            if not contextValue then return false end
            if string.find(NormalizeName(contextValue.Name), "pallet", (1.0), true) then return true end
            contextValue = contextValue.Parent
        end
        return false
    end

    local function FindModelAncestor(instance)
        if not instance then return nil end
        local contextValue = instance
        for _ = (1.0), 20 do
            if not contextValue then return nil end
            if string.find(NormalizeName(contextValue.Name), "pallet", 1, true) then return contextValue end
            contextValue = contextValue.Parent
        end
        return nil
    end

    local function IsLeafDecoration(instance)
        if not instance then return false end
        if NameContainsKeyword(instance.Name, LeafKeywords) then return true end
        local targetPlayer = instance.Parent
        for _ = 1, (4.0) do
            if not targetPlayer then break end
            if NameContainsKeyword(targetPlayer.Name, LeafKeywords) then return true end
            targetPlayer = targetPlayer.Parent
        end
        return false
    end

    local function ShouldSkipPotatoObject(instance)
        if not instance then return true end
        if cache17[instance.ClassName] then return true end
        if FindTopAncestor(instance) then return true end
        if FindRenderableAncestor(instance) then return false end
        local contextValue = instance
        for _ = 1, 7 do
            if not contextValue then break end
            if NameContainsKeyword(contextValue.Name, recoveredValue94) then return true end
            contextValue = contextValue.Parent
        end
        return false
    end

    local function IsCameraScriptable()
        local cameraValue9 = workspace.CurrentCamera
        return cameraValue9 and cameraValue9.CameraType == Enum.CameraType.Scriptable
    end

    local function OptimizeMeshPart(instance)
        if not instance or not instance.Parent then return end
        if instance:IsA("MeshPart") then
            pcall(function()
                instance.Material = Enum.Material.SmoothPlastic
                instance.CastShadow = false
                instance.TextureID = ""
            end)
        elseif instance:IsA("BasePart") then
            pcall(function()
                instance.Material = Enum.Material.SmoothPlastic
                instance.CastShadow = false
            end)
        elseif instance:IsA("Decal") or instance:IsA("Texture") then
            pcall(function() instance.Transparency = 1 end)
        elseif instance:IsA("SurfaceAppearance") then
            pcall(function() instance:Destroy() end)
        elseif instance:IsA("SpecialMesh") then
            pcall(function() instance.TextureId = "" end)
        end
    end

    local function OptimizeInstance(instance)
        if not instance or not instance.Parent then return end
        if cache17[instance.ClassName] then return end
        if instance:IsA("BasePart") then
            pcall(function()
                instance.Transparency = 1
                instance.CanCollide = false
                instance.CanTouch = false
                instance.CanQuery = false
            end)
        elseif instance:IsA("Decal") or instance:IsA("Texture") then
            pcall(function() instance.Transparency = (1.0) end)
        elseif instance:IsA("SpecialMesh") then
            pcall(function() instance.TextureId = "" end)
        elseif instance:IsA("SurfaceAppearance") then
            pcall(function() instance:Destroy() end)
        elseif instance:IsA("ParticleEmitter")
            or instance:IsA("Beam")
            or instance:IsA("Smoke")
            or instance:IsA("Fire")
            or instance:IsA("Sparkles") then
            pcall(function() instance.Enabled = false end)
        end
    end


    local recoveredValue376 = false

    local function ProcessPotatoObject(instance)
        if not instance or not instance.Parent then return end
        if State.potatoProcessed[instance] then return end
        if IsProtectedObject(instance) then
            State.potatoProcessed[instance] = true
            return
        end
        if IsVisualEffectObject(instance) then
            pcall(function() instance.Enabled = false end)
            State.potatoProcessed[instance] = true
            return
        end
        if IsCameraScriptable() then return end
        if FindRenderableAncestor(instance) then
            local recoveredValue163 = FindModelAncestor(instance)
            if recoveredValue163 then
                State.potatoPallets[recoveredValue163] = true
                OptimizeMeshPart(instance)
                State.potatoProcessed[instance] = true
                return
            end
        end
        if IsRenderablePart(instance) then
            pcall(function() instance.Enabled = false end)
            State.potatoProcessed[instance] = true
            return
        end
        if FindTopAncestor(instance) then
            State.potatoProcessed[instance] = true
            return
        end
        if cache17[instance.ClassName] then
            State.potatoProcessed[instance] = true
            return
        end
        if IsLeafDecoration(instance) then
            OptimizeInstance(instance)
            State.potatoProcessed[instance] = true
            return
        end
        if ShouldSkipPotatoObject(instance) then
            State.potatoProcessed[instance] = true
            return
        end
        if NameContainsKeyword(instance.Name, GrassKeywords) then
            State.potatoProcessed[instance] = true
            return
        end
        if instance:IsA("BasePart") then
            pcall(function()
                instance.Material = Enum.Material.SmoothPlastic
                instance.CastShadow = false
            end)
            State.potatoProcessed[instance] = true
            return
        end
        if instance:IsA("Decal") or instance:IsA("Texture") then
            local targetPlayer = instance.Parent
            if not targetPlayer or not NameContainsKeyword(targetPlayer.Name, recoveredValue94) then
                pcall(function() instance.Transparency = (1.0) end)
            end
            State.potatoProcessed[instance] = true
            return
        end
        if instance:IsA("SurfaceAppearance") then
            local targetPlayer = instance.Parent
            if targetPlayer and IsLeafDecoration(targetPlayer) then
                pcall(function() instance:Destroy() end)
            end
            State.potatoProcessed[instance] = true
            return
        end
        if instance:IsA("SpecialMesh") then
            local targetPlayer = instance.Parent
            if targetPlayer and IsLeafDecoration(targetPlayer) then
                pcall(function() instance.TextureId = "" end)
            end
            State.potatoProcessed[instance] = true
            return
        end
        State.potatoProcessed[instance] = true
    end

    local function ShouldTrackWorkspaceChild(rootPart2)
        if not rootPart2 then return false end
        if rootPart2 == LocalPlayer.Character then return false end
        if State.stateField73[rootPart2] then return false end
        if rootPart2:IsA("Camera") or rootPart2:IsA("Terrain") then return false end
        return rootPart2:IsA("Model")
            or rootPart2:IsA("Folder")
            or (rootPart2:IsA("BasePart") and rootPart2.Parent == workspace)
    end

    local function HelperFunction166(instance)
        if not State.potatoModeEnabled or not instance or not instance.Parent then return end
        if recoveredValue376 then
            State.potatoProcessed[instance] = true
            return
        end
        if State.potatoProcessed[instance] or State.stateField37[instance] then return end
        if IsProtectedObject(instance) then
            State.potatoProcessed[instance] = true
            return
        end
        if IsVisualEffectObject(instance) then
            pcall(function() instance.Enabled = false end)
            State.potatoProcessed[instance] = true
            return
        end
        if cache17[instance.ClassName] then return end
        if FindTopAncestor(instance) and not IsRenderablePart(instance) then return end
        State.stateField68 = State.stateField68 + 1
        State.stateField84[State.stateField68] = instance
        State.stateField37[instance] = true
    end


    local function CompactPotatoQueue()
        if State.stateField11 > State.stateField68 then
            State.stateField84 = {}
            State.stateField11 = (1.0)
            State.stateField68 = 0
            State.stateField37 = {}
        end
    end


    local function ResetPotatoQueue()
        State.stateField84 = {}
        State.stateField11, State.stateField68, State.stateField37 = 1, (0.0), {}
        State.stateField81 = {}
        State.stateField90 = nil
        State.stateField56 = 1
    end

    local function HandleEndScreenForPotatoMode()
        if recoveredValue376 then return end
        recoveredValue376 = true
        ResetPotatoQueue()
    end

    local function IsEndScreenObject(instance)
        return instance ~= nil and instance.Name == "endscreen"
            and instance.Parent ~= nil and instance.Parent.Name == "Map"
    end

    local function HelperFunction219(timeValue11, recoveredValue436)
        if recoveredValue436 >= recoveredValue278 then return false end
        if os.clock() - timeValue11 >= timeValue then return false end
        if IsCameraScriptable() then return false end
        return true
    end

    function StartPotatoMode()
        if State.potatoModeEnabled then return end
        State.potatoModeEnabled = true
        recoveredValue376 = false
        pcall(function()
            local recoveredValue363 = workspace:FindFirstChild("Map")
            if recoveredValue363 and recoveredValue363:FindFirstChild("endscreen") then
                HandleEndScreenForPotatoMode()
            end
        end)
        pcall(function()
            State.stateField40 = settings().Rendering.QualityLevel
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
        pcall(function()
            local recoveredValue159 = game:GetService("Lighting")
            State.stateField67 = recoveredValue159.GlobalShadows
            State.stateField82 = recoveredValue159.FogEnd
            recoveredValue159.GlobalShadows = false
            recoveredValue159.FogEnd = 1000000
        end)
        State.stateField76 = {}
        pcall(function()
            for _, instance in ipairs(game:GetService("Lighting"):GetChildren()) do
                if instance:IsA("PostEffect") and instance.Enabled then
                    instance.Enabled = false
                    State.stateField76[#State.stateField76 + 1] = instance
                end
            end
        end)
        for _, targetPlayer in ipairs(Players:GetPlayers()) do WatchPlayerForPotatoMode(targetPlayer) end
        table.insert(State.stateField44, Players.PlayerAdded:Connect(WatchPlayerForPotatoMode))
        table.insert(State.stateField44, Players.PlayerRemoving:Connect(function(targetPlayer)
            if targetPlayer.Character then UnmarkPotatoProcessed(targetPlayer.Character) end
        end))
        table.insert(State.stateField44, workspace.ChildAdded:Connect(function(rootPart2)
            if not State.potatoModeEnabled then return end
            if recoveredValue376 then return end
            if IsProtectedObject(rootPart2) then return end
            if ShouldTrackWorkspaceChild(rootPart2) then
                State.stateField81[#State.stateField81 + 1] = rootPart2
            end
        end))
        table.insert(State.stateField44, workspace.DescendantAdded:Connect(function(instance)
            if not State.potatoModeEnabled or not instance or not instance.Parent then return end
            if IsEndScreenObject(instance) then
                HandleEndScreenForPotatoMode()
                return
            end
            if recoveredValue376 then
                State.potatoProcessed[instance] = true
                return
            end
            if State.potatoProcessed[instance] or State.stateField37[instance] then return end
            if IsProtectedObject(instance) then
                State.potatoProcessed[instance] = true
                return
            end
            if IsVisualEffectObject(instance) then
                pcall(function() instance.Enabled = false end)
                State.potatoProcessed[instance] = true
                return
            end
            if FindTopAncestor(instance) and not IsRenderablePart(instance) then return end
            if cache17[instance.ClassName] then return end
            HelperFunction166(instance)
        end))
        pcall(function()
            for _, rootPart2 in ipairs(workspace:GetChildren()) do
                if ShouldTrackWorkspaceChild(rootPart2) then
                    State.stateField81[#State.stateField81 + (1.0)] = rootPart2
                end
            end
        end)
    end

    function StopPotato()
        State.potatoModeEnabled = false
        recoveredValue376 = false
        for _, connection in ipairs(State.stateField44) do
            pcall(function() connection:Disconnect() end)
        end
        State.stateField44 = {}
        State.stateField81 = {}
        State.stateField90 = nil
        State.stateField56 = 1
        State.stateField84 = {}
        State.stateField11, State.stateField68, State.stateField37 = 1, 0, {}
        State.stateField73 = {}
        State.stateField86 = {}
        pcall(function()
            if State.stateField40 then
                settings().Rendering.QualityLevel = State.stateField40
            end
        end)
        pcall(function()
            local recoveredValue159 = game:GetService("Lighting")
            if State.stateField67 ~= nil then recoveredValue159.GlobalShadows = State.stateField67 end
            if State.stateField82 ~= nil then recoveredValue159.FogEnd = State.stateField82 end
            for _, instance in ipairs(State.stateField76) do
                if instance and instance.Parent then instance.Enabled = true end
            end
        end)
        State.stateField76 = {}
    end

    RegisterUpdateTask("PotatoStream", 0, function()
        if not State.potatoModeEnabled then return end
        if recoveredValue376 then return end
        if IsCameraScriptable() then return end
        local timeValue11 = os.clock()
        local recoveredValue436 = 0
        while State.stateField11 <= State.stateField68 and HelperFunction219(timeValue11, recoveredValue436) do
            local instance = State.stateField84[State.stateField11]
            State.stateField84[State.stateField11] = nil
            State.stateField11 = State.stateField11 + 1
            if instance then State.stateField37[instance] = nil end
            if instance and instance.Parent then ProcessPotatoObject(instance) end
            recoveredValue436 = recoveredValue436 + 1
        end
        CompactPotatoQueue()
        if State.stateField90 == nil and #State.stateField81 > 0 and HelperFunction219(timeValue11, recoveredValue436) then
            local rootPart2 = table.remove(State.stateField81, 1)
            if rootPart2 and rootPart2.Parent and ShouldTrackWorkspaceChild(rootPart2) then
                local success, objs = pcall(function() return rootPart2:GetDescendants() end)
                if success and objs then
                    State.stateField90 = objs
                    State.stateField56 = 1
                end
            end
        end
        while State.stateField90 ~= nil and HelperFunction219(timeValue11, recoveredValue436) do
            local connection19 = State.stateField90
            local recoveredValue135 = State.stateField56
            local instance = connection19[recoveredValue135]
            State.stateField56 = recoveredValue135 + 1
            if recoveredValue135 > #connection19 then
                State.stateField90 = nil
                State.stateField56 = 1
            elseif instance and instance.Parent then
                ProcessPotatoObject(instance)
            end
            recoveredValue436 = recoveredValue436 + 1
        end
    end)
end)()

RunService.Heartbeat:Connect(function(recoveredValue206)
    for index = 1, #UpdateTasks do
        local t = UpdateTasks[index]
        t.timer = t.timer + recoveredValue206
        if t.timer >= t.interval then
            t.timer = (0.0)
            local okTask, taskErr = pcall(t.fn, recoveredValue206)
            if not okTask then
                warn("[Bleh Hub Runtime] " .. tostring(t.name or "UpdateTask") .. ": " .. tostring(taskErr))
            end
        end
    end
end)

local HandleUnhookAction
local UnhookYourself
do
    local recoveredValue327 = false
    local recoveredValue344 = false
    local activeConnection
    local cframeValue9
    local remote23
    local remote12

    local function ResolveUnhookRemotes()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage
        local carry = remotes:FindFirstChild("Carry", true)
        local generator = remotes:FindFirstChild("Generator", true)

        remote23 = (carry and FindRemoteEvent(carry, "SelfUnHookEvent"))
            or FindRemoteEvent(remotes, "SelfUnHookEvent")
        remote12 = (generator and FindRemoteEvent(generator, "RepairEvent"))
            or FindRemoteEvent(remotes, "RepairEvent")

        return remote23, remote12
    end

    __BlehHubBootProbe:Set("UNHOOK/GENERATOR INIT")
    ResolveUnhookRemotes()

    local function FindNearestVaultPoint(pos)
        local distanceValue60 = nil
        local distanceValue52 = math.huge
        for _, item in ipairs(Workspace:GetDescendants()) do
            if item.Name == "Hook" and (item:IsA("Model") or item:IsA("BasePart")) and item.Parent then
                local success, cf = pcall(function()
                    if item:IsA("Model") then return item:GetPivot() end
                    return item.CFrame
                end)
                if success and cf then
                    local dist = (cf.Position - pos).Magnitude
                    if dist < distanceValue52 then
                        distanceValue52 = dist
                        distanceValue60 = cf
                    end
                end
            end
        end
        return distanceValue60
    end

    local function WatchKillerCharacter(rootPart16, char)
        if activeConnection then
            activeConnection:Disconnect()
            activeConnection = nil
        end
        recoveredValue344 = false
        rootPart16.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        rootPart16.AssemblyAngularVelocity = Vector3.new(0, (0.0), 0)
        if not cframeValue9 then
            char:PivotTo(rootPart16.CFrame * CFrame.new(0, 15, (0.0)))
        else
            char:PivotTo(cframeValue9 * CFrame.new((0.0), 3, 0))
        end
        task.wait(0.1)
        rootPart16.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
    end

    local function RefreshKillerWatcher()
        if LocalPlayer.Character then
            local killer = nil
            for _, targetPlayer in ipairs(Players:GetPlayers()) do
                local isKiller = targetPlayer.Team
                if isKiller then
                    isKiller = (targetPlayer.Team.Name == "Killer")
                end
                if isKiller then
                    killer = targetPlayer
                    break
                end
            end
            if killer then
                if activeConnection then
                    activeConnection:Disconnect()
                    activeConnection = nil
                end
                activeConnection = RunService.Heartbeat:Connect(function()
                    local char = LocalPlayer.Character
                    local rootPart16 = char
                    if rootPart16 then
                        rootPart16 = char:FindFirstChild("HumanoidRootPart")
                    end
                    local attributeValue25 = not recoveredValue344
                    if not attributeValue25 then
                        attributeValue25 = not char
                    end
                    if not attributeValue25 then
                        attributeValue25 = not rootPart16
                    end
                    if not attributeValue25 then
                        if char:GetAttribute("IsHooked") then
                            local rootPart20 = killer.Character
                            local rootPart12 = rootPart20
                            if rootPart12 then
                                rootPart12 = rootPart20:FindFirstChild("HumanoidRootPart")
                            end
                            if rootPart12 then
                                local attributeValue3 = char:GetAttribute("anticampCharge")
                                if not attributeValue3 then
                                    attributeValue3 = (0.0)
                                end
                                if not (attributeValue3 >= 100) then
                                    rootPart16.CFrame = rootPart12.CFrame * CFrame.new(0, (-15.0), 10)
                                    return
                                else
                                    WatchKillerCharacter(rootPart16, char)
                                    task.wait(0.9)
                                    if not remote23 or not remote23.Parent then ResolveUnhookRemotes() end
                                    if remote23 and remote23:IsA("RemoteEvent") then
                                        remote23:FireServer()
                                    end
                                    return
                                end
                            else
                                recoveredValue344 = false
                                return
                            end
                        else
                            WatchKillerCharacter(rootPart16, char)
                            return
                        end
                    else
                        if activeConnection then
                            activeConnection:Disconnect()
                            activeConnection = nil
                        end
                        return
                    end
                end)
                return
            else
                return
            end
        else
            return
        end
    end

    UnhookYourself = function()
        recoveredValue327 = true
        HandleUnhookAction()
    end

    HandleUnhookAction = function()
        if recoveredValue327 then
            local char = LocalPlayer.Character
            if char then
                if char:GetAttribute("IsHooked") then
                    recoveredValue344 = not recoveredValue344
                    if not recoveredValue344 then
                        if activeConnection then
                            activeConnection:Disconnect()
                            activeConnection = nil
                        end
                        return
                    else
                        local rootPart16 = char:FindFirstChild("HumanoidRootPart")
                        if rootPart16 then
                            cframeValue9 = FindNearestVaultPoint(rootPart16.Position)
                            task.wait(1)
                            local attributeValue25 = not recoveredValue344
                            if not attributeValue25 then
                                attributeValue25 = not char:GetAttribute("IsHooked")
                            end
                            if not attributeValue25 then
                                local recoveredValue343 = nil
                                for _, distance in ipairs(Workspace:GetDescendants()) do
                                    local m = distance.Name:match("^GeneratorPoint")
                                    if m then
                                        m = distance:IsA("BasePart")
                                    end
                                    if m then
                                        recoveredValue343 = distance
                                        break
                                    end
                                end
                                if recoveredValue343 then
                                    rootPart16.CFrame = recoveredValue343.CFrame + Vector3.new(0, (3.0), (0.0))
                                    task.wait(0.1)
                                    if not remote12 or not remote12.Parent then ResolveUnhookRemotes() end
                                    if remote12 and remote12:IsA("RemoteEvent") then
                                        remote12:FireServer(recoveredValue343, true)
                                        task.wait(0.25)
                                        remote12:FireServer(recoveredValue343, false)
                                    end
                                    task.wait(0.1)
                                    RefreshKillerWatcher()
                                end
                                return
                            else
                                return
                            end
                        else
                            return
                        end
                    end
                else
                    return
                end
            else
                return
            end
        else
            return
        end
    end
end


    -- Explicit bridge to the original Killer tab's functionality.
    local function SetNoCooldownEnabled(value)
        NoCooldownEnabled = value and true or false
        if NoCooldownEnabled then
            InstallNoCooldownHook()
        else
            RemoveNoCooldownHook()
        end
    end

    return {
        Config = Config,
        State = State,
        Notify = Notify,
        SetNoCooldownEnabled = SetNoCooldownEnabled,
        SetMayersNoCooldownEnabled = function(value)
            State.mayersNoCooldownEnabled = value and true or false
            if value and not NoCooldownEnabled then InstallNoCooldownHook() end
            if value then StartMayersMobileHook() else StopMayersMobileHook() end
        end,
        StartCameraAssist = StartCameraAssist,
        StopCameraAssist = StopCameraAssist,
        StartMayersMobileHook = StartMayersMobileHook,
        StopMayersMobileHook = StopMayersMobileHook,
        TriggerMayersGrabAttack = TriggerMayersGrabAttack,
        GetNearestSurvivorForMayers = GetNearestSurvivorForMayers,
        StartInfiniteLunge = StartInfiniteLunge,
        StopInfiniteLunge = StopInfiniteLunge,
        StartHiddenM2Hook = StartHiddenM2Hook,
        StopHiddenM2Hook = StopHiddenM2Hook,
        ApplyAntiLoopWindow = ApplyAntiLoopWindow,
        DisableAntiLoopWindow = DisableAntiLoopWindow,
        DropAllPallets = DropAllPallets,
        StartKillerPerksInfo = StartKillerPerksInfo,
        StopKillerPerksInfo = StopKillerPerksInfo,
        -- Survivor controls from the original source
        SetInvisibleEnabled = SetInvisibleEnabled,
        StartGodMode = StartGodMode,
        StopGodMode = StopGodMode,
        SetParryRadiusEspEnabled = SetParryRadiusEspEnabled,
        UnhookYourself = UnhookYourself,
        HandleUnhookAction = HandleUnhookAction,
        CreateGenBoostButton = CreateGenBoostButton,
        DestroyGenBoostButton = DestroyGenBoostButton,
        PerformGenBoost = PerformGenBoost,
        _StartAntiFallSlow = _StartAntiFallSlow,
        _StopAntiFallSlow = _StopAntiFallSlow,
        _StartNoSlowdown = _StartNoSlowdown,
        _StopNoSlowdown = _StopNoSlowdown,
        SetSpeedBoostEnabled = SetSpeedBoostEnabled,
        SetCrouchState = SetCrouchState,
        EnsureMoonwalkGui = EnsureMoonwalkGui,
        FP_SetPerk = FP_SetPerk,
        SavePerformanceSettings = SavePerformanceSettings,
        LoadPerformanceSettings = LoadPerformanceSettings,
        SetStretchedResolution = SetStretchedResolution,
        ApplyStretchedResolution = ApplyStretchedResolution,
        -- ESP controls from the original source
        RefreshPlayerESP = RefreshPlayerESP,
        RemoveScpESP = RemoveScpESP,
        RefreshScpEsp = RefreshScpEsp,
        RefreshWorldESP = RefreshWorldESP,
        StartPrediction = StartPrediction,
        StopPrediction = StopPrediction,
        -- Killer tracking options originally kept in Misc
        StartStunTimer = StartStunTimer,
        StopStunTimer = StopStunTimer,
        StartPerfMonitor = StartPerfMonitor,
        StopPerfMonitor = StopPerfMonitor,
        SetMaxCameraZoom = SetMaxCameraZoom,
        ApplyMaxCameraZoom = ApplyMaxCameraZoom,
        StartProtectName = StartProtectName,
        StopProtectName = StopProtectName,
        StartPotatoMode = StartPotatoMode,
        StopPotato = StopPotato,
        SetAntiAfkEnabled = SetAntiAfkEnabled,
    }
end

local KillerRuntime = CreateKillerRuntime()



-- ============================================================

-- UI HELPERS

-- ============================================================

local COLORS = {

    Window   = Color3.fromRGB(6,6,7),

    Panel    = Color3.fromRGB(10,10,16),

    Control  = Color3.fromRGB(35,35,39),

    White    = Color3.fromRGB(245,245,245),

    Text     = Color3.fromRGB(190,190,196),

    Dim      = Color3.fromRGB(120,120,130),

    Accent   = Color3.fromRGB(130,80,255),

    AccentDim= Color3.fromRGB(80,45,160),

}

local FLOWER_IMAGE = "rbxassetid://126860692354524"

local TWEEN_INFO   = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)



local function tw(obj, props) TweenService:Create(obj, TWEEN_INFO, props):Play() end

local function addCorner(o,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 8); c.Parent=o; return c end

local function addStroke(o,col,thick,trans)

    local s=Instance.new("UIStroke"); s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border

    s.Color=col; s.Thickness=thick or 1; s.Transparency=trans or 0; s.Parent=o; return s

end



-- ============================================================

-- SCREEN GUI + WINDOW

-- ============================================================

local gui = Instance.new("ScreenGui")

gui.Name="BlehHubAimbot"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true

gui.DisplayOrder=10000; gui.ZIndexBehavior=Enum.ZIndexBehavior.Global; gui.Parent=playerGui



local window = Instance.new("Frame")

window.Name="Window"; window.AnchorPoint=Vector2.new(0.5,0.5)

window.Position=UDim2.fromScale(0.5,0.5); window.Size=UDim2.fromOffset(324,480)

window.BackgroundColor3=COLORS.Window; window.BorderSizePixel=0

window.ClipsDescendants=true; window.ZIndex=1; window.Parent=gui

addCorner(window,14); addStroke(window,COLORS.White,1,0.58)



-- Flower background

local flower=Instance.new("ImageLabel"); flower.Size=UDim2.fromScale(1,1)

flower.BackgroundTransparency=1; flower.Image=FLOWER_IMAGE

flower.ScaleType=Enum.ScaleType.Crop; flower.ZIndex=1; flower.Parent=window

addCorner(flower,14)



local shade=Instance.new("Frame"); shade.Size=UDim2.fromScale(1,1)

shade.BackgroundColor3=Color3.new(0,0,0); shade.BackgroundTransparency=0.48

shade.BorderSizePixel=0; shade.ZIndex=2; shade.Parent=window

addCorner(shade,14)



-- Snow layer

local snowLayer=Instance.new("Frame"); snowLayer.Size=UDim2.fromScale(1,1)

snowLayer.BackgroundTransparency=1; snowLayer.BorderSizePixel=0

snowLayer.ClipsDescendants=true; snowLayer.Active=false

snowLayer.ZIndex=4; snowLayer.Parent=window



-- ============================================================

-- HEADER + DRAG

-- ============================================================

local header=Instance.new("Frame"); header.Name="Header"

header.Size=UDim2.new(1,0,0,54); header.BackgroundTransparency=1

header.Active=true; header.ZIndex=10; header.Parent=window



local titleLbl=Instance.new("TextLabel"); titleLbl.Size=UDim2.fromOffset(200,28)

titleLbl.Position=UDim2.fromOffset(16,10); titleLbl.BackgroundTransparency=1

titleLbl.Text="Bleh Hub"; titleLbl.TextSize=14; titleLbl.Font=Enum.Font.GothamBold

titleLbl.TextColor3=COLORS.White; titleLbl.TextXAlignment=Enum.TextXAlignment.Left

titleLbl.ZIndex=11; titleLbl.Parent=header



local rule=Instance.new("Frame"); rule.Size=UDim2.new(1,-34,0,1)

rule.Position=UDim2.fromOffset(17,46); rule.BackgroundColor3=COLORS.White

rule.BackgroundTransparency=0.68; rule.BorderSizePixel=0; rule.ZIndex=11; rule.Parent=header



local dragging,dragStart,startPos=false,nil,nil

header.InputBegan:Connect(function(input)

    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then

        dragging=true; dragStart=input.Position; startPos=window.Position

        input.Changed:Connect(function() if input.UserInputState==Enum.UserInputState.End then dragging=false end end)

    end

end)

UserInputService.InputChanged:Connect(function(input)

    if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then

        local d=input.Position-dragStart

        window.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)

    end

end)



-- ============================================================

-- SCROLLING CONTENT AREA

-- ============================================================

local CONTENT_Y = 86

local scroll=Instance.new("ScrollingFrame"); scroll.Name="AimbotScroll"

scroll.Size=UDim2.new(1,0,1,-(CONTENT_Y+24)); scroll.Position=UDim2.fromOffset(0,CONTENT_Y)

scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0

scroll.ScrollBarThickness=2; scroll.ScrollBarImageColor3=COLORS.Accent

scroll.CanvasSize=UDim2.fromOffset(0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y

scroll.ZIndex=10; scroll.Parent=window



local layout=Instance.new("UIListLayout"); layout.SortOrder=Enum.SortOrder.LayoutOrder

layout.Padding=UDim.new(0,8); layout.Parent=scroll



local pad=Instance.new("UIPadding"); pad.PaddingLeft=UDim.new(0,14)

pad.PaddingRight=UDim.new(0,14); pad.PaddingTop=UDim.new(0,8); pad.PaddingBottom=UDim.new(0,8)

pad.Parent=scroll


-- Main navigation: this is the original Bleh Hub window with Aimbot, Killer, Survivor, and ESP pages.
local tabBar = Instance.new("Frame")
tabBar.Name = "MainTabs"
tabBar.Position = UDim2.fromOffset(12, 52)
tabBar.Size = UDim2.new(1, -24, 0, 28)
tabBar.BackgroundTransparency = 1
tabBar.BorderSizePixel = 0
tabBar.ZIndex = 20
tabBar.Parent = window

local function makeTabButton(name, xScale)
    local button = Instance.new("TextButton")
    button.Name = name .. "TabButton"
    button.Position = UDim2.new(xScale, xScale == 0 and 0 or 3, 0, 0)
    button.Size = UDim2.new(0.25, -4, 1, 0)
    button.BackgroundColor3 = COLORS.Control
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = name
    button.TextSize = 11
    button.Font = Enum.Font.GothamBold
    button.TextColor3 = COLORS.Text
    button.ZIndex = 21
    button.Parent = tabBar
    addCorner(button, 7)
    return button
end

local aimbotTabButton = makeTabButton("Aimbot", 0)
local killerTabButton = makeTabButton("Killer", 0.25)
local survivorTabButton = makeTabButton("Survivor", 0.5)
local espTabButton = makeTabButton("ESP", 0.75)

local function createTabScroll(name)
    local frame = Instance.new("ScrollingFrame")
    frame.Name = name
    frame.Size = scroll.Size
    frame.Position = scroll.Position
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.ScrollBarThickness = 2
    frame.ScrollBarImageColor3 = COLORS.Accent
    frame.CanvasSize = UDim2.fromOffset(0, 0)
    frame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    frame.Visible = false
    frame.ZIndex = 10
    frame.Parent = window

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 8)
    list.Parent = frame

    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 14)
    padding.PaddingRight = UDim.new(0, 14)
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.Parent = frame
    return frame
end

local killerScroll = createTabScroll("KillerScroll")
local survivorScroll = createTabScroll("SurvivorScroll")
local espScroll = createTabScroll("ESPScroll")

local function showMainTab(name)
    scroll.Visible = name == "Aimbot"
    killerScroll.Visible = name == "Killer"
    survivorScroll.Visible = name == "Survivor"
    espScroll.Visible = name == "ESP"
    aimbotTabButton.BackgroundColor3 = name == "Aimbot" and COLORS.Accent or COLORS.Control
    killerTabButton.BackgroundColor3 = name == "Killer" and COLORS.Accent or COLORS.Control
    survivorTabButton.BackgroundColor3 = name == "Survivor" and COLORS.Accent or COLORS.Control
    espTabButton.BackgroundColor3 = name == "ESP" and COLORS.Accent or COLORS.Control
    aimbotTabButton.TextColor3 = COLORS.White
    killerTabButton.TextColor3 = COLORS.White
    survivorTabButton.TextColor3 = COLORS.White
    espTabButton.TextColor3 = COLORS.White
end

aimbotTabButton.MouseButton1Click:Connect(function() showMainTab("Aimbot") end)
killerTabButton.MouseButton1Click:Connect(function() showMainTab("Killer") end)
survivorTabButton.MouseButton1Click:Connect(function() showMainTab("Survivor") end)
espTabButton.MouseButton1Click:Connect(function() showMainTab("ESP") end)
showMainTab("Aimbot")




-- ============================================================

-- COMPONENT BUILDERS

-- ============================================================

local rowOrder = 0



local function makeSection(parent, title)

    rowOrder = rowOrder + 1
    local card=Instance.new("Frame"); card.Name="Sec_"..title:gsub("[^%w]","")
    card.LayoutOrder = rowOrder

    card.Size=UDim2.new(1,0,0,0); card.AutomaticSize=Enum.AutomaticSize.Y

    card.BackgroundColor3=COLORS.Panel; card.BackgroundTransparency=0.15

    card.BorderSizePixel=0; card.ZIndex=11; card.Parent=parent

    addCorner(card,8); addStroke(card,COLORS.White,1,0.82)



    local li=Instance.new("UIListLayout"); li.SortOrder=Enum.SortOrder.LayoutOrder

    li.Padding=UDim.new(0,0); li.Parent=card



    local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,10); p.PaddingRight=UDim.new(0,10)

    p.PaddingTop=UDim.new(0,6); p.PaddingBottom=UDim.new(0,8); p.Parent=card



    local hdr=Instance.new("TextLabel"); hdr.Size=UDim2.new(1,0,0,20)

    hdr.BackgroundTransparency=1; hdr.Text=title:upper(); hdr.TextSize=10

    hdr.Font=Enum.Font.GothamBold; hdr.TextColor3=COLORS.Accent

    hdr.TextXAlignment=Enum.TextXAlignment.Left; hdr.ZIndex=12

    hdr.LayoutOrder=0; hdr.Parent=card

    return card

end



local function makeRow(parent, labelText, height)

    rowOrder = rowOrder + 1

    local row=Instance.new("Frame"); row.Name="Row_"..labelText:gsub("[^%w]","")

    row.Size=UDim2.new(1,0,0,height or 28); row.BackgroundTransparency=1

    row.ZIndex=12; row.LayoutOrder=rowOrder; row.Parent=parent



    local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(0.62,0,1,0)

    lbl.BackgroundTransparency=1; lbl.Text=labelText; lbl.TextSize=11

    lbl.Font=Enum.Font.GothamMedium; lbl.TextColor3=COLORS.Text

    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.TextYAlignment=Enum.TextYAlignment.Center

    lbl.ZIndex=13; lbl.Parent=row

    return row

end



local function makeToggle(parent, labelText, default, callback)

    local row   = makeRow(parent, labelText)

    local state = default or false



    local track=Instance.new("TextButton"); track.Size=UDim2.fromOffset(36,20)

    track.Position=UDim2.new(1,-36,0.5,-10); track.BackgroundColor3=state and COLORS.Accent or COLORS.Control

    track.BorderSizePixel=0; track.Text=""; track.AutoButtonColor=false; track.ZIndex=13; track.Parent=row

    addCorner(track,10)



    local knob=Instance.new("Frame"); knob.Size=UDim2.fromOffset(14,14)

    knob.Position=state and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3)

    knob.BackgroundColor3=COLORS.White; knob.BorderSizePixel=0; knob.ZIndex=14; knob.Parent=track

    addCorner(knob,7)



    track.MouseButton1Click:Connect(function()

        state = not state

        tw(track,{BackgroundColor3=state and COLORS.Accent or COLORS.Control})

        tw(knob,{Position=state and UDim2.fromOffset(19,3) or UDim2.fromOffset(3,3)})

        pcall(callback, state)

    end)

end



local function makeDropdown(parent, labelText, options, default, callback)

    rowOrder = rowOrder + 1

    local current = default or options[1]



    local holder=Instance.new("Frame"); holder.Name="DD_"..labelText:gsub("[^%w]","")

    holder.Size=UDim2.new(1,0,0,50); holder.BackgroundTransparency=1

    holder.ZIndex=12; holder.LayoutOrder=rowOrder; holder.Parent=parent



    local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(1,0,0,18)

    lbl.BackgroundTransparency=1; lbl.Text=labelText; lbl.TextSize=11

    lbl.Font=Enum.Font.GothamMedium; lbl.TextColor3=COLORS.Text

    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.ZIndex=13; lbl.Parent=holder



    local btn=Instance.new("TextButton"); btn.Size=UDim2.new(1,0,0,26)

    btn.Position=UDim2.fromOffset(0,20); btn.BackgroundColor3=COLORS.Control

    btn.BackgroundTransparency=0.2; btn.BorderSizePixel=0

    btn.Text=current.."  ▾"; btn.TextSize=11; btn.Font=Enum.Font.GothamMedium

    btn.TextColor3=COLORS.White; btn.AutoButtonColor=false; btn.ZIndex=13; btn.Parent=holder

    addCorner(btn,6)



    local open=false; local optFrames={}

    local function closeMenu()

        open=false

        for _,f in ipairs(optFrames) do f:Destroy() end

        optFrames={}

        holder.Size=UDim2.new(1,0,0,50)

    end

    btn.MouseButton1Click:Connect(function()

        if open then closeMenu(); return end

        open=true; holder.Size=UDim2.new(1,0,0,50+#options*26)

        for i,opt in ipairs(options) do

            local ob=Instance.new("TextButton"); ob.Size=UDim2.new(1,0,0,24)

            ob.Position=UDim2.fromOffset(0,46+(i-1)*26)

            ob.BackgroundColor3=opt==current and COLORS.AccentDim or COLORS.Control

            ob.BackgroundTransparency=0.3; ob.BorderSizePixel=0

            ob.Text=opt; ob.TextSize=11; ob.Font=Enum.Font.GothamMedium

            ob.TextColor3=COLORS.White; ob.AutoButtonColor=false; ob.ZIndex=20; ob.Parent=holder

            addCorner(ob,5); table.insert(optFrames,ob)

            ob.MouseButton1Click:Connect(function()

                current=opt; btn.Text=opt.."  ▾"; pcall(callback,opt); closeMenu()

            end)

        end

    end)

end



local function makeSlider(parent, labelText, min, max, default, increment, callback)

    rowOrder = rowOrder + 1

    local current = default or min



    local holder=Instance.new("Frame"); holder.Name="SL_"..labelText:gsub("[^%w]","")

    holder.Size=UDim2.new(1,0,0,48); holder.BackgroundTransparency=1

    holder.ZIndex=12; holder.LayoutOrder=rowOrder; holder.Parent=parent



    local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(0.72,0,0,18)

    lbl.BackgroundTransparency=1; lbl.Text=labelText; lbl.TextSize=11

    lbl.Font=Enum.Font.GothamMedium; lbl.TextColor3=COLORS.Text

    lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.ZIndex=13; lbl.Parent=holder



    local valLbl=Instance.new("TextLabel"); valLbl.Size=UDim2.new(0.28,0,0,18)

    valLbl.Position=UDim2.new(0.72,0,0,0); valLbl.BackgroundTransparency=1

    valLbl.Text=tostring(current); valLbl.TextSize=11; valLbl.Font=Enum.Font.GothamMedium

    valLbl.TextColor3=COLORS.Accent; valLbl.TextXAlignment=Enum.TextXAlignment.Right

    valLbl.ZIndex=13; valLbl.Parent=holder



    local track=Instance.new("Frame"); track.Size=UDim2.new(1,0,0,6)

    track.Position=UDim2.fromOffset(0,24); track.BackgroundColor3=COLORS.Control

    track.BorderSizePixel=0; track.ZIndex=13; track.Parent=holder

    addCorner(track,3)



    local fill=Instance.new("Frame"); fill.Size=UDim2.new((current-min)/(max-min),0,1,0)

    fill.BackgroundColor3=COLORS.Accent; fill.BorderSizePixel=0; fill.ZIndex=14; fill.Parent=track

    addCorner(fill,3)



    local knob=Instance.new("Frame"); knob.Size=UDim2.fromOffset(12,12)

    knob.AnchorPoint=Vector2.new(0.5,0.5); knob.Position=UDim2.new((current-min)/(max-min),0,0.5,0)

    knob.BackgroundColor3=COLORS.White; knob.BorderSizePixel=0; knob.ZIndex=15; knob.Parent=track

    addCorner(knob,6)



    local sliding=false

    local function setVal(ax)

        local rel = math.clamp((ax - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)

        local raw = min + (max-min)*rel

        local snapped = math.round(raw/increment)*increment

        snapped = math.clamp(snapped, min, max)

        local places = math.max(0, -math.floor(math.log10(increment+1e-9)))

        snapped = math.floor(snapped*10^places+0.5)/10^places

        current = snapped

        local pct = (snapped-min)/(max-min)

        fill.Size=UDim2.new(pct,0,1,0); knob.Position=UDim2.new(pct,0,0.5,0)

        valLbl.Text=tostring(snapped); pcall(callback,snapped)

    end

    track.InputBegan:Connect(function(i)

        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then

            sliding=true; setVal(i.Position.X)

        end

    end)

    UserInputService.InputChanged:Connect(function(i)

        if sliding and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then

            setVal(i.Position.X)

        end

    end)

    UserInputService.InputEnded:Connect(function(i)

        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then

            sliding=false

        end

    end)

end



-- ============================================================

local function makeButton(parent, labelText, callback)
    rowOrder = rowOrder + 1
    local button = Instance.new("TextButton")
    button.Name = "Button_" .. labelText:gsub("[^%w]", "")
    button.Size = UDim2.new(1, 0, 0, 28)
    button.BackgroundColor3 = COLORS.Control
    button.BackgroundTransparency = 0.08
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = labelText
    button.TextSize = 11
    button.Font = Enum.Font.GothamMedium
    button.TextColor3 = COLORS.White
    button.ZIndex = 13
    button.LayoutOrder = rowOrder
    button.Parent = parent
    addCorner(button, 6)
    addStroke(button, COLORS.White, 1, 0.86)
    button.MouseEnter:Connect(function() tw(button, {BackgroundColor3 = COLORS.AccentDim}) end)
    button.MouseLeave:Connect(function() tw(button, {BackgroundColor3 = COLORS.Control}) end)
    button.MouseButton1Click:Connect(function()
        if callback then pcall(callback) end
    end)
    return button
end

local function makeKeybind(parent, labelText, defaultKey, callback)
    local row = makeRow(parent, labelText, 30)
    local current = defaultKey or Enum.KeyCode.Unknown
    local armed = false
    local button = Instance.new("TextButton")
    button.Size = UDim2.fromOffset(92, 22)
    button.Position = UDim2.new(1, -92, 0.5, -11)
    button.BackgroundColor3 = COLORS.Control
    button.BorderSizePixel = 0
    button.AutoButtonColor = false
    button.Text = current == Enum.KeyCode.Unknown and "Set key" or current.Name
    button.TextSize = 10
    button.Font = Enum.Font.GothamMedium
    button.TextColor3 = COLORS.White
    button.ZIndex = 13
    button.Parent = row
    addCorner(button, 6)
    button.MouseButton1Click:Connect(function()
        armed = true
        button.Text = "Press key..."
    end)
    UserInputService.InputBegan:Connect(function(input, gpe)
        if armed and input.UserInputType == Enum.UserInputType.Keyboard then
            current = input.KeyCode
            button.Text = current.Name
            armed = false
            return
        end
        if not gpe and not armed and current ~= Enum.KeyCode.Unknown
            and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == current then
            if callback then pcall(callback) end
        end
    end)
    return button
end

-- AIMBOT SECTIONS

-- ============================================================



-- ── Crosshair ────────────────────────────────────────────────

local chSec = makeSection(scroll, "Crosshair")

makeToggle(chSec, "Enable Crosshair", false, function(v) Crosshair:SetEnabled(v) end)

makeDropdown(chSec, "Style", CROSSHAIR_STYLES, "Dot", function(v) Crosshair:SetStyle(v) end)

makeSlider(chSec, "Size", 1, 100, 20, 1, function(v) Crosshair:SetSize(v) end)

makeSlider(chSec, "Opacity", 0, 100, 100, 1, function(v) Crosshair:SetOpacity(v/100) end)

makeSlider(chSec, "Offset X (px)", -200, 200, 0, 1, function(v) Crosshair:SetOffsetX(v) end)

makeSlider(chSec, "Offset Y (px)", -200, 200, 0, 1, function(v) Crosshair:SetOffsetY(v) end)



-- ── Aim Lock ─────────────────────────────────────────────────

local alSec = makeSection(scroll, "Aim Lock (Legit)")

makeToggle(alSec, "Enable Aim Lock", false, function(v)

    Config.aimLockEnabled = v

    if v then StartCameraLock() else StopCameralock() end

end)

makeDropdown(alSec, "Target Group", {"Zombie","Survivor","Killer"}, Config.aimLockTargetType, function(v)

    Config.aimLockTargetType = v

    -- re-clear current target so new group takes effect immediately

    State.stateField52 = nil

end)

makeDropdown(alSec, "Aim Part", {"Torso","Head"}, "Torso", function(v)

    Config.aimLockPart = v

end)

makeDropdown(alSec, "Lock Mode", {"Always Lock","Hold to Lock"}, "Always Lock", function(v)

    Config.aimLockMode = v

end)

makeSlider(alSec, "Max Distance (studs)", 20, 700, Config.aimLockMaxDistance, 5, function(v)

    Config.aimLockMaxDistance = v

end)

makeSlider(alSec, "Camera Smoothness", 0.01, 1, Config.aimLockSmoothness, 0.01, function(v)

    Config.aimLockSmoothness = v

end)



-- ============================================================

-- ============================================================
-- KILLER MENU — features and callbacks are ported from Bleh Hub
-- ============================================================

local spearSec = makeSection(killerScroll, "Silent Spear Assist")
makeToggle(spearSec, "Silent Spear", false, function(v)
    KillerRuntime.State.silentSpearEnabled = v
    if not v then
        KillerRuntime.State.spearSpeedEstimate = 142.5
        KillerRuntime.State.spearGravityMultiplier = 0.5
        KillerRuntime.State.spearLastShot = nil
    end
end)
makeToggle(spearSec, "FOV Circle", false, function(v) KillerRuntime.State.silentSpearFovCircleEnabled = v end)
makeToggle(spearSec, "Aim Indicator", false, function(v) KillerRuntime.State.spearAimIndicatorEnabled = v end)
makeToggle(spearSec, "SnapLine", false, function(v) KillerRuntime.State.SPEAR_SNAPLINE.enabled = v end)
makeToggle(spearSec, "Show Name / Studs", true, function(v) KillerRuntime.Config.spearShowNameAndDistance = v end)
makeSlider(spearSec, "Spear FOV Radius", 30, 500, 150, 5, function(v) KillerRuntime.Config.spearFovRadius = v end)
makeToggle(spearSec, "Spear Auto Prediction", true, function(v) KillerRuntime.Config.spearAutoPrediction = v end)
makeToggle(spearSec, "Spear Anti-Strafing", true, function(v) KillerRuntime.Config.spearAntiStrafing = v end)

local cameraAssistSec = makeSection(killerScroll, "Camera Assist")
makeToggle(cameraAssistSec, "Enable Camera Assist", false, function(v)
    KillerRuntime.Config.cameraAssistEnabled = v
    local ok = pcall(function()
        if v then KillerRuntime.StartCameraAssist() else KillerRuntime.StopCameraAssist() end
    end)
    if not ok then
        KillerRuntime.Config.cameraAssistEnabled = false
        KillerRuntime.Notify("Camera Assist", "Could not activate Camera Assist", 2)
    end
end)
makeToggle(cameraAssistSec, "SnapLine ESP", false, function(v)
    KillerRuntime.Config.cameraAssistSnaplineEnabled = v
    if not v then
        if KillerRuntime.State.cameraValue6 then KillerRuntime.State.cameraValue6.Visible = false end
        if KillerRuntime.State.cameraValue5 then KillerRuntime.State.cameraValue5.Visible = false end
    end
end)

local cooldownSec = makeSection(killerScroll, "Killer Cooldown Tools")
makeToggle(cooldownSec, "Enable No Cooldown Bypass", false, function(v)
    KillerRuntime.SetNoCooldownEnabled(v)
end)
makeButton(cooldownSec, "Fire Corrupt (Abyss)", function()
    pcall(function()
        game:GetService("ReplicatedStorage").Remotes.Killers.Abysswalker.corrupt:FireServer()
    end)
end)
makeButton(cooldownSec, "Fire Slash (Abyss)", function()
    pcall(function()
        game:GetService("ReplicatedStorage").Remotes.Attacks.BasicAttack:FireServer(true)
    end)
end)
makeButton(cooldownSec, "Fire Leap (Hidden)", function()
    pcall(function()
        game:GetService("ReplicatedStorage").Remotes.Killers.Hidden.Leap:FireServer(true)
    end)
end)
makeButton(cooldownSec, "Fire M2 (Hidden)", function()
    pcall(function()
        game:GetService("ReplicatedStorage").Remotes.Killers.Hidden.M2:FireServer({}, false)
    end)
end)

local mayersSec = makeSection(killerScroll, "Mayers / Stalker")
makeToggle(mayersSec, "Enable Mayers No Cooldown", false, function(v)
    KillerRuntime.SetMayersNoCooldownEnabled(v)
end)
makeToggle(mayersSec, "Stalk While Moving (Auto)", false, function(v)
    KillerRuntime.State.mayersAutoStalkEnabled = v
end)
makeButton(mayersSec, "Dash (Q) NoCD", function() KillerRuntime.TriggerMayersGrabAttack() end)
makeButton(mayersSec, "Grab Nearest", function()
    pcall(function()
        local target = KillerRuntime.GetNearestSurvivorForMayers(8)
        if target then
            local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
            local killers = remotes and remotes:FindFirstChild("Killers")
            local stalker = killers and killers:FindFirstChild("Stalker")
            local grab = stalker and stalker:FindFirstChild("grab")
            if grab then
                grab:FireServer(target)
                KillerRuntime.Notify("Mayers", "Grab fired: " .. target.Name, 1.2)
            end
        else
            KillerRuntime.Notify("Mayers", "No target within 8 studs", 1.2)
        end
    end)
end)

local lungeSec = makeSection(killerScroll, "Infinite Lunge")
makeToggle(lungeSec, "Enable Infinite Lunge", false, function(v)
    KillerRuntime.Config.infiniteLungeEnabled = v
    if v then KillerRuntime.StartInfiniteLunge() else KillerRuntime.StopInfiniteLunge() end
end)

local hiddenM2Sec = makeSection(killerScroll, "Hidden M2 Aimlock")
makeToggle(hiddenM2Sec, "Enable AIMLOCK M2", false, function(v)
    KillerRuntime.State.mayersAimlockM2Enabled = v
    if v then KillerRuntime.StartHiddenM2Hook() else KillerRuntime.StopHiddenM2Hook() end
end)
makeSlider(hiddenM2Sec, "Smoothness", 0.05, 1, 1, 0.01, function(v)
    KillerRuntime.State.mayersAimlockSmoothness = tonumber(v) or 1
end)

local maskedSec = makeSection(killerScroll, "Masked Skill Spammer")
local maskedPower = "Cobra"
makeDropdown(maskedSec, "Select Mask Power", {"Alex", "Brandon", "Cobra", "Rabbit", "Richter", "Tony"}, "Cobra", function(v)
    maskedPower = v
end)
makeButton(maskedSec, "Activate Power", function()
    pcall(function()
        game:GetService("ReplicatedStorage").Remotes.Killers.Masked.Activatepower:FireServer(maskedPower)
    end)
    KillerRuntime.Notify("Masked", "Power Activated: " .. maskedPower, 1.5)
end)
makeButton(maskedSec, "Deactivate Power", function()
    pcall(function()
        game:GetService("ReplicatedStorage").Remotes.Killers.Masked.Deactivatepower:FireServer()
    end)
    KillerRuntime.Notify("Masked", "Power Deactivated", 1.5)
end)

local antiBlindSec = makeSection(killerScroll, "Flashlight Protection")
makeToggle(antiBlindSec, "Anti Flashlight Blind", false, function(v)
    KillerRuntime.Config.antiFlashlightBlind = v
    if v then
        pcall(function()
            local env = (type(getgenv) == "function" and getgenv()) or _G
            if type(env.SetupAntiBlindHook) == "function" then env.SetupAntiBlindHook() end
        end)
    end
end)

local loopSec = makeSection(killerScroll, "Loop Counter")
makeToggle(loopSec, "Anti Loop Window", false, function(v)
    KillerRuntime.State.antiLoopWindowEnabled = v
    if v then KillerRuntime.ApplyAntiLoopWindow() else KillerRuntime.DisableAntiLoopWindow() end
end)
makeButton(loopSec, "Auto Drop All Pallets", function() KillerRuntime.DropAllPallets() end)

local perksSec = makeSection(killerScroll, "Killer Perks Info")
makeToggle(perksSec, "Enable Killer Perks Info", false, function(v)
    KillerRuntime.Config.killerPerksInfoEnabled = v
    if v then KillerRuntime.StartKillerPerksInfo() else KillerRuntime.StopKillerPerksInfo() end
end)

local hookSec = makeSection(killerScroll, "Hook Counter")
makeToggle(hookSec, "Show Hook Counter", false, function(v)
    KillerRuntime.Config.showHookCounter = v
    if v then
        if KillerRuntime.State._HookCounter_Enable then pcall(KillerRuntime.State._HookCounter_Enable) end
    else
        if KillerRuntime.State._HookCounter_Disable then pcall(KillerRuntime.State._HookCounter_Disable) end
    end
end)

-- Killer tracking features were listed under Misc in the source; keep them in Killer here.
local killerWarnSec = makeSection(killerScroll, "Killer Proximity Warning")
makeToggle(killerWarnSec, "Enable Killer Warning", false, function(v)
    KillerRuntime.Config.killerWarningEnabled = v
end)
local stunSec = makeSection(killerScroll, "Stun Timer")
makeToggle(stunSec, "Enable Stun Timer", false, function(v)
    if v then KillerRuntime.StartStunTimer() else KillerRuntime.StopStunTimer() end
end)
makeSlider(stunSec, "Max Distance", 50, 500, 250, 10, function(v)
    KillerRuntime.State.warningMaxDistance = v
    for _, board in pairs(KillerRuntime.State.stunTimerBoards) do
        pcall(function() board.MaxDistance = v end)
    end
end)

-- ============================================================
-- SURVIVOR MENU — source Survivor features inside the same Bleh Hub GUI
-- ============================================================
local survivorCfg = KillerRuntime.Config
local survivorState = KillerRuntime.State

local invisibleSec = makeSection(survivorScroll, "Stealth Mode")
makeToggle(invisibleSec, "Enable Invisible", false, function(v)
    KillerRuntime.SetInvisibleEnabled(v)
end)

local parrySec = makeSection(survivorScroll, "Auto Parry")
makeToggle(parrySec, "Auto Parry", false, function(v)
    survivorState.autoParryEnabled = v
    if not v then
        survivorState.stateField4 = {}
        survivorState.stateField21 = {}
        survivorState.stateField93 = {}
    end
end)
makeToggle(parrySec, "Radius ESP", false, function(v)
    survivorState.parryRadiusEspEnabled = v
    KillerRuntime.SetParryRadiusEspEnabled(v)
end)
makeSlider(parrySec, "Parry Radius (studs)", 4, 40, 13, 1, function(v)
    survivorState.parryRadius = v
end)
makeSlider(parrySec, "Aim Strictness", -1, 1, -0.2, 0.1, function(v)
    survivorState.parryAimStrictness = v
end)

local unhookSec = makeSection(survivorScroll, "Save Rescue")
makeToggle(unhookSec, "Hover Unhook Button", false, function(v)
    if v then
        if not State._BlehHoverUnhook or not State._BlehHoverUnhook.Parent then
            local root = Instance.new("ScreenGui")
            root.Name = "BlehHubHoverUnhook"
            root.ResetOnSpawn = false
            root.IgnoreGuiInset = true
            root.DisplayOrder = 2147483000
            root.Parent = playerGui
            local b = Instance.new("TextButton")
            b.Name = "UnhookButton"
            b.Size = UDim2.fromOffset(148, 42)
            b.Position = UDim2.new(1, -166, 0.5, -21)
            b.BackgroundColor3 = COLORS.Panel
            b.BorderSizePixel = 0
            b.Text = "Unhook Yourself"
            b.TextColor3 = COLORS.White
            b.Font = Enum.Font.GothamBold
            b.TextSize = 11
            b.Parent = root
            addCorner(b, 9)
            addStroke(b, COLORS.Accent, 1, 0.2)
            b.MouseButton1Click:Connect(function()
                pcall(function() KillerRuntime.UnhookYourself() end)
            end)
            local dragging, start, startPos = false, nil, nil
            b.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    start = input.Position
                    startPos = b.Position
                    input.Changed:Connect(function()
                        if input.UserInputState == Enum.UserInputState.End then dragging = false end
                    end)
                end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    local d = input.Position - start
                    b.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end)
            State._BlehHoverUnhook = root
        end
    else
        if State._BlehHoverUnhook then
            pcall(function() State._BlehHoverUnhook:Destroy() end)
            State._BlehHoverUnhook = nil
        end
    end
end)
makeButton(unhookSec, "Unhook Yourself", function()
    KillerRuntime.UnhookYourself()
end)
makeKeybind(unhookSec, "Unhook Keybind", Enum.KeyCode.Unknown, function()
    KillerRuntime.HandleUnhookAction()
end)

local twistSec = makeSection(survivorScroll, "Silent Aim (Twist of Fate)")
makeToggle(twistSec, "Silent Aim", false, function(v) survivorState.silentAimEnabled = v end)
makeDropdown(twistSec, "Target Type", {"Killer", "Survivor", "Zombie"}, survivorCfg.silentAimTargetType or "Killer", function(v)
    survivorCfg.silentAimTargetType = v
end)
makeToggle(twistSec, "FOV Circle", false, function(v) survivorState.silentAimFovCircleEnabled = v end)
makeToggle(twistSec, "Laser ESP", true, function(v) survivorState.silentAimLaserEspEnabled = v end)
makeToggle(twistSec, "Auto Prediction", true, function(v) survivorCfg.silentAimAutoPrediction = v end)
makeToggle(twistSec, "Adaptive Damping", true, function(v) survivorCfg.silentAimAdaptiveDamping = v end)
makeSlider(twistSec, "Aim FOV Radius", 30, 500, 150, 5, function(v) survivorCfg.silentAimFovRadius = v end)

local godSec = makeSection(survivorScroll, "God Mode")
makeToggle(godSec, "Enable God Mode", false, function(v)
    if v then KillerRuntime.StartGodMode() else KillerRuntime.StopGodMode() end
end)

local flashlightSec = makeSection(survivorScroll, "Aimlock Flashlight")
makeToggle(flashlightSec, "Enable Aimlock Flashlight", false, function(v)
    survivorState.flashlightAimlockEnabled = v
    if not v then survivorState.flashlightActive = false end
end)
makeSlider(flashlightSec, "Smoothness", 0.05, 1, 0.35, 0.01, function(v)
    survivorState.flashlightAimSmoothness = v
end)

local genSec = makeSection(survivorScroll, "Auto Generator")
makeToggle(genSec, "Auto Generator", survivorCfg.autoGeneratorEnabled, function(v) survivorCfg.autoGeneratorEnabled = v end)
makeDropdown(genSec, "Mode", {"Instant", "Perfect", "Normal", "Random"}, survivorCfg.autoGeneratorMode or "Instant", function(v)
    survivorCfg.autoGeneratorMode = v
end)

local boostSec = makeSection(survivorScroll, "Generator Boost")
makeToggle(boostSec, "Show GenBoost Button", false, function(v)
    survivorCfg.showGenBoostButton = v
    if v then KillerRuntime.CreateGenBoostButton() else KillerRuntime.DestroyGenBoostButton() end
end)
makeKeybind(boostSec, "GenBoost Keybind", Enum.KeyCode.Unknown, function() KillerRuntime.PerformGenBoost() end)

local antiFallSec = makeSection(survivorScroll, "Anti Fall Slow")
makeToggle(antiFallSec, "Anti Fall Slow", false, function(v)
    survivorState.antiFallSlowEnabled = v
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if v then KillerRuntime._StartAntiFallSlow(hum) else KillerRuntime._StopAntiFallSlow(hum) end
end)

local speedSec = makeSection(survivorScroll, "Speed Boost")
makeToggle(speedSec, "Speed Boost", false, function(v) KillerRuntime.SetSpeedBoostEnabled(v) end)
makeSlider(speedSec, "Boost Multiplier", 0, 2, 0.3, 0.01, function(v)
    survivorState.speedBoostMultiplier = v
    if survivorState.SB_Retarget then pcall(survivorState.SB_Retarget) end
end)
makeToggle(speedSec, "Count Speed Perks", true, function(v)
    survivorState.countSpeedPerks = v
    if survivorState.SB_RefreshAll then pcall(survivorState.SB_RefreshAll) end
end)
makeToggle(speedSec, "Pause when Crouching", false, function(v) survivorState.pauseSpeedWhenCrouching = v end)

local slowdownSec = makeSection(survivorScroll, "No Slowdown")
makeToggle(slowdownSec, "No Slowdown", false, function(v)
    survivorState.noSlowdownEnabled = v
    local ch = LocalPlayer.Character
    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
    if v then KillerRuntime._StartNoSlowdown(hum) else KillerRuntime._StopNoSlowdown() end
end)
makeToggle(slowdownSec, "Safe Mode (No Slowdown)", true, function(v) survivorState.safeNoSlowdownEnabled = v end)

local crouchSec = makeSection(survivorScroll, "Auto Crouch (Abyss)")
makeToggle(crouchSec, "Auto Crouch", false, function(v)
    survivorCfg.autoCrouchEnabled = v
    if not v then KillerRuntime.SetCrouchState(false) end
end)
makeSlider(crouchSec, "Crouch Radius (studs)", 4, 40, 18, 1, function(v) survivorCfg.autoCrouchRadius = v end)

local palletSec = makeSection(survivorScroll, "Pallet Safety")
makeToggle(palletSec, "Auto Drop Nearby Pallet", false, function(v)
    survivorState.autoDropNearbyPallet = v
    if v then survivorState.nearbyPallets = nil end
end)

local moonwalkSec = makeSection(survivorScroll, "Moonwalk")
makeToggle(moonwalkSec, "Enable Moonwalk (Mobile GUI)", false, function(v)
    survivorCfg.moonwalkEnabled = v
    if v then
        KillerRuntime.EnsureMoonwalkGui()
        if survivorState.moonwalkGui then survivorState.moonwalkGui.Enabled = true end
    else
        if survivorState.moonwalkGui then survivorState.moonwalkGui.Enabled = false end
        survivorState.moonwalkSwayPhase = 0
        survivorState.moonwalkForwardLocked = false
        survivorState.moonwalkBackwardLocked = false
    end
end)
makeDropdown(moonwalkSec, "Moonwalk Mode", {"Classic", "Sway"}, "Classic", function(v) survivorCfg.moonwalkMode = v end)
makeSlider(moonwalkSec, "Sway Width", 0.1, 1.5, 0.55, 0.05, function(v) survivorCfg.moonwalkSwayWidth = v end)
makeSlider(moonwalkSec, "Sway Speed", 1, 12, 6, 0.5, function(v) survivorCfg.moonwalkSwaySpeed = v end)
makeKeybind(moonwalkSec, "PC Lock Forward Key", Enum.KeyCode.Unknown, function()
    if survivorCfg.moonwalkEnabled then
        survivorState.moonwalkForwardLocked = not survivorState.moonwalkForwardLocked
        if survivorState.moonwalkForwardLocked then survivorState.moonwalkBackwardLocked = false end
    end
end)
makeKeybind(moonwalkSec, "PC Lock Backward Key", Enum.KeyCode.Unknown, function()
    if survivorCfg.moonwalkEnabled then
        survivorState.moonwalkBackwardLocked = not survivorState.moonwalkBackwardLocked
        if survivorState.moonwalkBackwardLocked then survivorState.moonwalkForwardLocked = false end
    end
end)

local vaultSec = makeSection(survivorScroll, "Fast Vault Op")
makeToggle(vaultSec, "Always Fast Vault", false, function(v) survivorCfg.alwaysFastVault = v end)

local flowstateSec = makeSection(survivorScroll, "Flowstate Tools")
makeToggle(flowstateSec, "Force Flowstate Perk", false, function(v)
    survivorCfg.forceFlowstatePerk = v
    if not v then
        pcall(function() LocalPlayer:SetAttribute("Flowstate", nil) end)
        local ch = LocalPlayer.Character
        if ch then pcall(function() ch:SetAttribute("Flowstate", nil) end) end
    end
end)
makeSlider(flowstateSec, "Flowstate Cooldown (s)", 0, 60, 15, 1, function(v) survivorCfg.flowstateCooldown = v end)
makeToggle(flowstateSec, "Hide Flowstate UI", false, function(v) survivorCfg.hideFlowstateUi = v end)

local fakePerksSec = makeSection(survivorScroll, "Fake Perks")
makeSlider(fakePerksSec, "Perk Cooldown", 0, 60, 10, 1, function(v) survivorState.fpCooldown = v end)
makeToggle(fakePerksSec, "Quick Recovery", false, function(v) KillerRuntime.FP_SetPerk("QuickRecovery", v) end)
makeToggle(fakePerksSec, "Perfect Landing", false, function(v) KillerRuntime.FP_SetPerk("PerfectLanding", v) end)
makeToggle(fakePerksSec, "Adrenaline Rush", false, function(v) KillerRuntime.FP_SetPerk("AdrenalineRush", v) end)

local gateSec = makeSection(survivorScroll, "Escape Gate")
makeButton(gateSec, "Auto Escape (Teleport)", function() KillerRuntime.LoadPerformanceSettings() end)
makeToggle(gateSec, "Ghost Gate (Legit Mode)", false, function(v)
    survivorState.ghostGateLegitMode = v
    KillerRuntime.SavePerformanceSettings()
end)

local fovSec = makeSection(survivorScroll, "Lock FOV")
makeToggle(fovSec, "Lock FOV", survivorCfg.lockFovEnabled, function(v)
    survivorCfg.lockFovEnabled = v
    if v then KillerRuntime.SetStretchedResolution(survivorCfg.fovValue) else KillerRuntime.ApplyStretchedResolution() end
end)
makeSlider(fovSec, "FOV Value", 30, 120, survivorCfg.fovValue or 70, 1, function(v)
    survivorCfg.fovValue = v
    if survivorCfg.lockFovEnabled then KillerRuntime.SetStretchedResolution(v) end
end)

-- ============================================================
-- ESP MENU — controls from the source Visual/ESP tab
-- ============================================================
local espCfg = KillerRuntime.Config
local espState = KillerRuntime.State

local killerEspSec = makeSection(espScroll, "Killer ESP")
makeToggle(killerEspSec, "Killer ESP", espCfg.killerEspShowName or espCfg.killerEspShowOutline, function(v)
    espCfg.killerEspShowName = v
    espCfg.killerEspShowOutline = v
    espCfg.killerEspOutlineOnly = false
    KillerRuntime.RefreshPlayerESP()
end)

local survivorEspSec = makeSection(espScroll, "Survivor ESP")
makeToggle(survivorEspSec, "Survivor ESP", espCfg.survivorEspShowName or espCfg.survivorEspShowOutline, function(v)
    espCfg.survivorEspShowName = v
    espCfg.survivorEspShowOutline = v
    espCfg.survivorEspOutlineOnly = false
    KillerRuntime.RefreshPlayerESP()
end)

local scpEspSec = makeSection(espScroll, "Zombie / SCP ESP")
makeToggle(scpEspSec, "Zombie / SCP ESP", espCfg.scpEspEnabled, function(v)
    espCfg.scpEspEnabled = v
    espCfg.scpEspShowName = true
    if not v then
        for root in pairs(espState.scpEspObjects) do KillerRuntime.RemoveScpESP(root) end
    else
        KillerRuntime.RefreshScpEsp()
    end
end)

local itemEspSec = makeSection(espScroll, "Survivor Item")
makeToggle(itemEspSec, "Show Equipped Item", espCfg.showEquippedItem, function(v)
    espCfg.showEquippedItem = v
end)

local worldEspSec = makeSection(espScroll, "Object ESP")
makeToggle(worldEspSec, "ESP Generator + Progress", espCfg.generatorEspEnabled or espCfg.generatorProgressEnabled, function(v)
    espCfg.generatorEspEnabled = v
    espCfg.generatorProgressEnabled = v
    for _, inst in ipairs(espState.worldEspObjects.Generators) do
        if inst and inst.Parent then
            inst:SetAttribute("__BlehHubGenLastPct__", nil)
            if not v then
                local progressGui = inst:FindFirstChild("__BlehHubGenProgress__")
                if progressGui then progressGui:Destroy() end
                local hl = inst:FindFirstChild("__BlehHubHL__")
                if hl then hl:Destroy() end
            end
        end
    end
    KillerRuntime.RefreshWorldESP()
end)
makeToggle(worldEspSec, "ESP Window", espCfg.windowEspEnabled, function(v)
    espCfg.windowEspEnabled = v
    KillerRuntime.RefreshWorldESP()
end)
makeToggle(worldEspSec, "ESP Pallet", espCfg.palletEspEnabled, function(v)
    espCfg.palletEspEnabled = v
    KillerRuntime.RefreshWorldESP()
end)
makeToggle(worldEspSec, "ESP Hook", espCfg.hookEspEnabled, function(v)
    espCfg.hookEspEnabled = v
    KillerRuntime.RefreshWorldESP()
end)
makeToggle(worldEspSec, "ESP Gate", espCfg.gateEspEnabled, function(v)
    espCfg.gateEspEnabled = v
    KillerRuntime.RefreshWorldESP()
end)

local predictionSec = makeSection(espScroll, "Prediction Monitor")
makeToggle(predictionSec, "Show Prediction Monitor", false, function(v)
    if v then KillerRuntime.StartPrediction() else KillerRuntime.StopPrediction() end
end)

-- FOOTER

-- ============================================================

local footer=Instance.new("TextLabel"); footer.Size=UDim2.new(1,-20,0,18)

footer.Position=UDim2.new(0,10,1,-22); footer.BackgroundTransparency=1

footer.Text="Bleh Hub  •  discord.gg/8vEFQkwwa6"; footer.TextSize=9; footer.Font=Enum.Font.GothamMedium

footer.TextColor3=COLORS.White; footer.TextXAlignment=Enum.TextXAlignment.Center

footer.TextStrokeColor3=COLORS.Window; footer.TextStrokeTransparency=0.35

footer.ZIndex=10; footer.Parent=window



-- ============================================================

-- SNOW

-- ============================================================

local rng=Random.new(); local alive=true

gui.Destroying:Connect(function() alive=false; ClearCrosshair() end)

for i=1,22 do

    task.spawn(function()

        local flake=Instance.new("Frame"); flake.Name="Snowflake"

        flake.AnchorPoint=Vector2.new(0.5,0.5); flake.BackgroundColor3=Color3.new(1,1,1)

        flake.BackgroundTransparency=0.35; flake.BorderSizePixel=0

        flake.Visible=false; flake.ZIndex=5; flake.Parent=snowLayer

        addCorner(flake,3)

        task.wait(rng:NextNumber(0,4))

        while alive and snowLayer.Parent do

            local sz=rng:NextInteger(2,4)

            local x1=rng:NextNumber(0.03,0.97)

            local x2=math.clamp(x1+rng:NextNumber(-0.12,0.12),0.02,0.98)

            local dur=rng:NextNumber(5.5,9)

            flake.Size=UDim2.fromOffset(sz,sz)

            flake.Position=UDim2.new(x1,0,-0.04,-sz)

            flake.BackgroundTransparency=rng:NextNumber(0.25,0.55)

            flake.Visible=true

            local tw2=TweenService:Create(flake,TweenInfo.new(dur,Enum.EasingStyle.Linear),{

                Position=UDim2.new(x2,0,1.04,sz),

                BackgroundTransparency=rng:NextNumber(0.45,0.75),

            })

            tw2:Play(); tw2.Completed:Wait()

            flake.Visible=false; task.wait(rng:NextNumber(0.1,0.4))

        end

        if flake.Parent then flake:Destroy() end

    end)

end
