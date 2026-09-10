-- Test-object pickup and water-interaction setup for Workspace.Slime.
local CollectionService = game:GetService("CollectionService")

local item = workspace:WaitForChild("Slime", 10)
if not item then
	warn("[SlimePickup] Workspace.Slime was not found")
	return
end

local root = if item:IsA("BasePart") then item elseif item:IsA("Model") then (item.PrimaryPart or item:FindFirstChild("HumanoidRootPart")) else nil
if not root or not root:IsA("BasePart") then
	warn("[SlimePickup] Slime must be a BasePart or a Model with PrimaryPart")
	return
end
if item:IsA("Model") and not item.PrimaryPart then
	item.PrimaryPart = root
end

CollectionService:AddTag(item, "WaterInteractable")
item:SetAttribute("WaterProfile", "SmallProp")
item:SetAttribute("WaterBuoyancyStrength", 1)
item:SetAttribute("WaterRotationStrength", 1)
item:SetAttribute("WaterEnabled", true)

if item:IsA("BasePart") then
	item.Anchored = false
end

local prompt = root:FindFirstChildOfClass("ProximityPrompt") or Instance.new("ProximityPrompt")
prompt.Name = "SlimePickupPrompt"
prompt.ActionText = "Pick up"
prompt.ObjectText = "Slime"
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 10
prompt.RequiresLineOfSight = false
prompt.Parent = root

local dropEvent = prompt:FindFirstChild("DropEvent") or Instance.new("RemoteEvent")
dropEvent.Name = "DropEvent"
dropEvent.Parent = prompt

local holder: Player? = nil
local alignPos: AlignPosition? = nil
local alignOri: AlignOrientation? = nil
local itemAttachment: Attachment? = nil
local holdAttachment: Attachment? = nil
local deathConnection: RBXScriptConnection? = nil
local collisionStates: { [BasePart]: boolean } = {}
local shoulderTransforms: { [Motor6D]: CFrame } = {}

local function setHeldPose(character: Model, held: boolean)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and (descendant.Name == "LeftShoulder" or descendant.Name == "RightShoulder") then
			if held then
				shoulderTransforms[descendant] = descendant.Transform
				local side = if descendant.Name == "LeftShoulder" then -1 else 1
				descendant.Transform = CFrame.new(side * 0.35, 0, -0.15) * CFrame.Angles(math.rad(-12), math.rad(side * 18), math.rad(side * 8))
			else
				descendant.Transform = shoulderTransforms[descendant] or CFrame.identity
				shoulderTransforms[descendant] = nil
			end
		end
	end
end

local function dropItem()
	if alignPos then alignPos:Destroy(); alignPos = nil end
	if alignOri then alignOri:Destroy(); alignOri = nil end
	if holdAttachment then holdAttachment:Destroy(); holdAttachment = nil end
	if deathConnection then deathConnection:Disconnect(); deathConnection = nil end
	if itemAttachment then itemAttachment:Destroy(); itemAttachment = nil end
	for part, canCollide in collisionStates do
		if part.Parent then part.CanCollide = canCollide end
		collisionStates[part] = nil
	end
	if holder and holder.Character then setHeldPose(holder.Character, false) end
	if root and root:IsA("BasePart") then
		root:SetNetworkOwner(holder)
	end
	holder = nil
	prompt.Enabled = true
end

local function throwItem(player: Player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local direction = if hrp and hrp:IsA("BasePart") then hrp.CFrame.LookVector else Vector3.new(0, 0, -1)
	if character then
		setHeldPose(character, false)
	end
	dropItem()
	root.AssemblyLinearVelocity = direction * 28 + Vector3.new(0, 8, 0)
	root:ApplyImpulse(direction * root.AssemblyMass * 18 + Vector3.new(0, root.AssemblyMass * 6, 0))
end

prompt.Triggered:Connect(function(player)
	if holder then
		if holder == player then throwItem(player) end
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid or not hrp:IsA("BasePart") then return end

	holder = player
	prompt.Enabled = true
	setHeldPose(character, true)
	for _, descendant in item:GetDescendants() do
		if descendant:IsA("BasePart") then
			collisionStates[descendant] = descendant.CanCollide
			descendant.CanCollide = false
		end
	end
	root:SetNetworkOwner(player)
	itemAttachment = Instance.new("Attachment")
	itemAttachment.Name = "PickupAttachment"
	itemAttachment.Parent = root
	holdAttachment = Instance.new("Attachment")
	holdAttachment.Name = "HoldAttachment"
	holdAttachment.Position = Vector3.new(0, 0, -4)
	holdAttachment.Parent = hrp

	alignPos = Instance.new("AlignPosition")
	alignPos.Attachment0 = itemAttachment
	alignPos.Attachment1 = holdAttachment
	alignPos.MaxForce = 50000
	alignPos.Responsiveness = 15
	alignPos.Mode = Enum.PositionAlignmentMode.TwoAttachment
	alignPos.Parent = root

	alignOri = Instance.new("AlignOrientation")
	alignOri.Attachment0 = itemAttachment
	alignOri.Attachment1 = holdAttachment
	alignOri.MaxTorque = 50000
	alignOri.Responsiveness = 15
	alignOri.Mode = Enum.OrientationAlignmentMode.TwoAttachment
	alignOri.Parent = root
	deathConnection = humanoid.Died:Connect(dropItem)
end)

dropEvent.OnServerEvent:Connect(function(player)
	if player == holder then dropItem() end
end)
