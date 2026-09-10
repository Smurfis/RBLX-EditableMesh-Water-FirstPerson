--!strict

-- Local prototype for climbing out of water onto nearby ledges, including
-- moving WaterInteractable platforms.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaterConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("WaterConfig"))
local player = Players.LocalPlayer
local HANG_ID = "rbxassetid://14252434075"
local CLIMB_ID = "rbxassetid://14240367012"
local WALL_DISTANCE = 3.5
local MAX_CLIMB_HEIGHT = 4.5
local MAX_LEDGE_DROP = 4.5
local STANDOFF = 1.35
local HANG_DROP = 1.15
local CLIMB_TIME = 0.42
local DEBOUNCE = 0.35
local DEBUG = true

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local params: RaycastParams? = nil
local hangTrack: AnimationTrack? = nil
local climbTrack: AnimationTrack? = nil
local hangTarget: CFrame? = nil
local climbTarget: CFrame? = nil
local state = "Idle"
local lastInput = -math.huge

local function debugLog(message: string)
	if DEBUG then print("[WaterExitClimb] " .. message) end
end

local function track(animator: Animator, id: string, name: string): AnimationTrack
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = id
	local result = animator:LoadAnimation(animation)
	result.Priority = Enum.AnimationPriority.Action
	return result
end

local function clear()
	if hangTrack then hangTrack:Stop(0.12) end
	if climbTrack then climbTrack:Stop(0.12) end
	state = "Idle"
	hangTarget = nil
	climbTarget = nil
	if humanoid then
		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function nearWater(): boolean
	if not humanoid or not root then return false end
	return humanoid:GetState() == Enum.HumanoidStateType.Swimming
		or root.Position.Y <= WaterConfig.GetSurfaceY() + 2.5
end

local function findLedge(): (CFrame?, CFrame?)
	local currentRoot, rayParams = root, params
	if not currentRoot or not rayParams then return nil, nil end
	local wall = workspace:Raycast(currentRoot.Position + Vector3.new(0, 1.35, 0), currentRoot.CFrame.LookVector * WALL_DISTANCE, rayParams)
	if not wall or not wall.Instance:IsA("BasePart") or not wall.Instance.CanCollide then debugLog("Wall ray missed"); return nil, nil end
	local normal = Vector3.new(wall.Normal.X, 0, wall.Normal.Z)
	if normal.Magnitude < 0.5 then debugLog("Wall hit was not vertical"); return nil, nil end
	normal = normal.Unit
	local top = workspace:Raycast(wall.Position - normal * 0.25 + Vector3.new(0, MAX_CLIMB_HEIGHT, 0), Vector3.new(0, -MAX_CLIMB_HEIGHT - 2, 0), rayParams)
	if not top or not top.Instance:IsA("BasePart") or not top.Instance.CanCollide then debugLog("Top ray missed"); return nil, nil end
	if top.Position.Y < currentRoot.Position.Y - MAX_LEDGE_DROP or top.Position.Y > currentRoot.Position.Y + MAX_CLIMB_HEIGHT then debugLog("Top height outside climb range"); return nil, nil end
	local facing = CFrame.lookAt(Vector3.zero, -normal)
	local hang = CFrame.new(top.Position - Vector3.new(0, HANG_DROP, 0) + normal * STANDOFF) * facing
	local climb = CFrame.new(top.Position + Vector3.new(0, 2.5, 0) + normal * (STANDOFF + 0.35)) * facing
	return hang, climb
end

local function beginHang()
	if state ~= "Idle" then debugLog("Space ignored; state=" .. state); return end
	if not nearWater() then debugLog("Space received, but player is not near water"); return end
	local hang, climb = findLedge()
	if not hang or not climb then debugLog("No valid ledge found"); return end
	if not humanoid or not root then debugLog("Ledge found, but character is unavailable"); return end
	debugLog("Valid ledge found; entering hang")
	state, hangTarget, climbTarget = "Hanging", hang, climb
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	root.CFrame = hang
	if hangTrack then hangTrack.Looped = true; hangTrack:Play(0.12) end
end

local function beginClimb()
	if state ~= "Hanging" or not climbTarget or not root then return end
	debugLog("Starting climb tween")
	state = "Climbing"
	if hangTrack then hangTrack:Stop(0.08) end
	if climbTrack then climbTrack:Play(0.08) end
	local tween = TweenService:Create(root, TweenInfo.new(CLIMB_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = climbTarget })
	tween.Completed:Connect(function() if state == "Climbing" then clear() end end)
	tween:Play()
end

UserInputService.JumpRequest:Connect(function()
	debugLog("JumpRequest received; state=" .. state)
	if os.clock() - lastInput < DEBOUNCE then return end
	lastInput = os.clock()
	if state == "Hanging" then beginClimb() else beginHang() end
end)

local function bind(character: Model)
	clear()
	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local newParams = RaycastParams.new()
	newParams.FilterType = Enum.RaycastFilterType.Exclude
	newParams.FilterDescendantsInstances = { character }
	params = newParams
	local animator = humanoid:WaitForChild("Animator") :: Animator
	hangTrack = track(animator, HANG_ID, "WaterLedgeHang")
	climbTrack = track(animator, CLIMB_ID, "WaterLedgeClimb")
end

Players.LocalPlayer.CharacterAdded:Connect(bind)
if player.Character then task.spawn(bind, player.Character) end
RunService.RenderStepped:Connect(function()
	if state == "Hanging" and (not root or not root.Parent or not nearWater()) then clear() end
end)
