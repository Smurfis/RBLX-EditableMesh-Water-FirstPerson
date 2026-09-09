-- StarterPlayerScripts, SwimmingController.client.lua
-- V2

--!native
--!strict

-- StarterPlayerScripts > SwimmingController
--
-- Responsibilities ONLY:
--   * Decide whether the local character is in the current test water.
--   * Apply neutral buoyancy for custom EditableMesh water.
--   * Camera-relative omnidirectional 3D swimming.
--   * Looking up/down + W naturally swims vertically.
--   * Space / controller A = explicit swim up.
--   * Ctrl/C / controller B = explicit swim down.
--
-- It does NOT manipulate the camera or water renderer.
--
-- V2 NOTES:
--   * Roblox Terrain water provides its own buoyancy.
--     EditableMesh water does not, so we cancel gravity ourselves.
--
--   * HumanoidStateType.Swimming is NOT relied upon for physics.
--
--   * W/S moves along the full camera LookVector.
--     This means looking straight up + W behaves like swimming upward.
--
--   * Space/Ctrl are blended into the same desired 3D direction.
--
--   * Horizontal and vertical maximum speeds can still be configured
--     separately using Speed and VerticalSpeed.


local Players =
	game:GetService("Players")

local RunService =
	game:GetService("RunService")

local ContextActionService =
	game:GetService("ContextActionService")

local ReplicatedStorage =
	game:GetService("ReplicatedStorage")

local Workspace =
	game:GetService("Workspace")


local WaterConfig =
	require(
		ReplicatedStorage
		:WaitForChild("Shared")
		:WaitForChild("Water")
		:WaitForChild("WaterConfig")
	)


local player =
	Players.LocalPlayer


local SwimSettings =
	WaterConfig.Swimming


----------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------

-- 1.0 = exactly cancel Roblox gravity.
--
-- Later we could use something slightly above 1 near the surface
-- to make the player naturally float upward.
local BUOYANCY_SCALE =
	SwimSettings.BuoyancyScale
	or 1.0


local ACTION_PRIORITY =
	Enum.ContextActionPriority.High.Value
	+ 10


----------------------------------------------------------------
-- CHARACTER STATE
----------------------------------------------------------------

local humanoid: Humanoid? =
	nil

local rootPart: BasePart? =
	nil


local swimAttachment: Attachment? =
	nil

local buoyancyForce: VectorForce? =
	nil


local bodyInWater =
	false


local swimUpHeld =
	false

local swimDownHeld =
	false

local swimControlsBound =
	false


----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------

local function lerpNumber(
	a: number,
	b: number,
	alpha: number
): number

	return a
		+ (b - a)
		* alpha
end


local function getSurfaceY(): number
	return WaterConfig.GetSurfaceY()
end


----------------------------------------------------------------
-- BUOYANCY
----------------------------------------------------------------

local function setBuoyancyEnabled(
	enabled: boolean
)

	local currentRoot =
		rootPart

	local force =
		buoyancyForce

	if
		not currentRoot
		or not force
	then
		return
	end


	if not enabled then
		force.Force =
			Vector3.zero

		return
	end


	-- AssemblyMass represents the entire connected character assembly.
	--
	-- Gravity force:
	--
	-- mass * gravity
	--
	-- Applying the opposite upward force gives approximately
	-- neutral buoyancy.

	local requiredForce =
		currentRoot.AssemblyMass
		* Workspace.Gravity
		* BUOYANCY_SCALE


	force.Force =
		Vector3.new(
			0,
			requiredForce,
			0
		)
end


----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------

local function swimUpAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult

	if not bodyInWater then
		return Enum.ContextActionResult.Pass
	end


	if
		inputState
		== Enum.UserInputState.Begin
	then

		swimUpHeld =
			true

	elseif
		inputState
		== Enum.UserInputState.End

		or inputState
		== Enum.UserInputState.Cancel
	then

		swimUpHeld =
			false
	end


	return Enum.ContextActionResult.Sink
end


local function swimDownAction(
	_actionName: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult

	if not bodyInWater then
		return Enum.ContextActionResult.Pass
	end


	if
		inputState
		== Enum.UserInputState.Begin
	then

		swimDownHeld =
			true

	elseif
		inputState
		== Enum.UserInputState.End

		or inputState
		== Enum.UserInputState.Cancel
	then

		swimDownHeld =
			false
	end


	return Enum.ContextActionResult.Sink
end


local function bindSwimControls()

	if swimControlsBound then
		return
	end


	swimControlsBound =
		true


	ContextActionService:BindActionAtPriority(
		"WaterSwimUp",
		swimUpAction,
		true,
		ACTION_PRIORITY,

		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA
	)


	ContextActionService:SetTitle(
		"WaterSwimUp",
		"↑"
	)


	ContextActionService:SetPosition(
		"WaterSwimUp",

		UDim2.new(
			1,
			-150,

			1,
			-220
		)
	)


	ContextActionService:BindActionAtPriority(
		"WaterSwimDown",
		swimDownAction,
		true,
		ACTION_PRIORITY,

		Enum.KeyCode.LeftControl,
		Enum.KeyCode.C,
		Enum.KeyCode.ButtonB
	)


	ContextActionService:SetTitle(
		"WaterSwimDown",
		"↓"
	)


	ContextActionService:SetPosition(
		"WaterSwimDown",

		UDim2.new(
			1,
			-80,

			1,
			-220
		)
	)
end


local function unbindSwimControls()

	if not swimControlsBound then
		return
	end


	swimControlsBound =
		false


	swimUpHeld =
		false

	swimDownHeld =
		false


	ContextActionService:UnbindAction(
		"WaterSwimUp"
	)


	ContextActionService:UnbindAction(
		"WaterSwimDown"
	)
end


----------------------------------------------------------------
-- ENTER / EXIT WATER
----------------------------------------------------------------

local function enterSwimming()

	if bodyInWater then
		return
	end


	bodyInWater =
		true


	bindSwimControls()

	setBuoyancyEnabled(
		true
	)


	-- This is only useful for whatever animation/state behaviour
	-- Roblox chooses to provide.
	--
	-- We DO NOT rely on this state for actual swimming physics.

	local currentHumanoid =
		humanoid

	if currentHumanoid then

		currentHumanoid:ChangeState(
			Enum.HumanoidStateType.Swimming
		)
	end
end


local function exitSwimming()

	if not bodyInWater then
		return
	end


	bodyInWater =
		false


	unbindSwimControls()

	setBuoyancyEnabled(
		false
	)


	local currentRoot =
		rootPart


	if currentRoot then

		local velocity =
			currentRoot.AssemblyLinearVelocity


		-- Prevent a massive swim-up velocity from launching the
		-- character into orbit after leaving the water.

		currentRoot.AssemblyLinearVelocity =
			Vector3.new(
				velocity.X,

				math.min(
					velocity.Y,
					8
				),

				velocity.Z
			)
	end
end


----------------------------------------------------------------
-- CHARACTER SETUP
----------------------------------------------------------------

local function setupCharacter(
	character: Model
)

	local foundHumanoid =
		character:WaitForChild(
			"Humanoid"
		)


	local foundRoot =
		character:WaitForChild(
			"HumanoidRootPart"
		)


	if foundHumanoid:IsA("Humanoid") then
		humanoid =
			foundHumanoid
	else
		humanoid =
			nil
	end


	if foundRoot:IsA("BasePart") then
		rootPart =
			foundRoot
	else
		rootPart =
			nil
	end


	bodyInWater =
		false


	swimUpHeld =
		false

	swimDownHeld =
		false


	unbindSwimControls()


	----------------------------------------------------------------
	-- CREATE BUOYANCY ACTUATOR
	----------------------------------------------------------------

	if rootPart then

		local currentRoot =
			rootPart


		local oldAttachment =
			currentRoot:FindFirstChild(
				"WaterSwimAttachment"
			)


		if oldAttachment then
			oldAttachment:Destroy()
		end


		local oldForce =
			currentRoot:FindFirstChild(
				"WaterBuoyancy"
			)


		if oldForce then
			oldForce:Destroy()
		end


		local attachment =
			Instance.new("Attachment")


		attachment.Name =
			"WaterSwimAttachment"


		attachment.Parent =
			currentRoot


		swimAttachment =
			attachment


		local force =
			Instance.new("VectorForce")


		force.Name =
			"WaterBuoyancy"


		force.Attachment0 =
			attachment


		force.RelativeTo =
			Enum.ActuatorRelativeTo.World


		force.ApplyAtCenterOfMass =
			true


		force.Force =
			Vector3.zero


		force.Parent =
			currentRoot


		buoyancyForce =
			force
	end
end


----------------------------------------------------------------
-- OMNIDIRECTIONAL SWIMMING
----------------------------------------------------------------

local function getOmnidirectionalSwimDirection(): Vector3

	local camera =
		Workspace.CurrentCamera


	local currentHumanoid =
		humanoid


	local currentRoot =
		rootPart


	if
		not camera
		or not currentHumanoid
	then

		return Vector3.zero
	end


	----------------------------------------------------------------
	-- GET ROBLOX MOVEMENT INPUT
	----------------------------------------------------------------

	-- Humanoid.MoveDirection gives us the player's normal WASD
	-- movement intent in world space.
	--
	-- Roblox normally flattens movement against the ground,
	-- so below we recover how much of that intent represents
	-- forwards/backwards and left/right relative to the camera.

	local moveDirection =
		currentHumanoid.MoveDirection


	----------------------------------------------------------------
	-- CAMERA BASIS
	----------------------------------------------------------------

	local cameraLook =
		camera.CFrame.LookVector


	local cameraRight =
		camera.CFrame.RightVector


	-- Flat camera vectors are used ONLY to determine what WASD
	-- input the player is providing.
	--
	-- Actual swimming uses the full cameraLook afterward.

	local flatForward =
		Vector3.new(
			cameraLook.X,
			0,
			cameraLook.Z
		)


	if
		flatForward.Magnitude
		<= 0.001
	then

		if currentRoot then

			local rootLook =
				currentRoot.CFrame.LookVector


			flatForward =
				Vector3.new(
					rootLook.X,
					0,
					rootLook.Z
				)
		end
	end


	if
		flatForward.Magnitude
		<= 0.001
	then

		flatForward =
			Vector3.new(
				0,
				0,
				-1
			)

	else

		flatForward =
			flatForward.Unit
	end


	local flatRight =
		Vector3.new(
			cameraRight.X,
			0,
			cameraRight.Z
		)


	if
		flatRight.Magnitude
		<= 0.001
	then

		flatRight =
			Vector3.new(
				-flatForward.Z,
				0,
				flatForward.X
			)

	else

		flatRight =
			flatRight.Unit
	end


	----------------------------------------------------------------
	-- EXTRACT FORWARD / RIGHT INPUT
	----------------------------------------------------------------

	local forwardAmount =
		0


	local rightAmount =
		0


	if
		moveDirection.Magnitude
		> 0.01
	then

		forwardAmount =
			moveDirection:Dot(
				flatForward
			)


		rightAmount =
			moveDirection:Dot(
				flatRight
			)
	end


	----------------------------------------------------------------
	-- EXPLICIT VERTICAL INPUT
	----------------------------------------------------------------

	local verticalAmount =
		0


	if swimUpHeld then
		verticalAmount +=
			1
	end


	if swimDownHeld then
		verticalAmount -=
			1
	end


	----------------------------------------------------------------
	-- BUILD ONE 3D MOVEMENT VECTOR
	----------------------------------------------------------------

	-- W/S:
	-- full camera LookVector
	--
	-- A/D:
	-- horizontal camera RightVector
	--
	-- Space/Ctrl:
	-- global vertical axis

	local desired =
		cameraLook
		* forwardAmount

		+ flatRight
		* rightAmount

		+ Vector3.yAxis
		* verticalAmount


	----------------------------------------------------------------
	-- PREVENT DIAGONAL SPEED BOOST
	----------------------------------------------------------------

	if desired.Magnitude > 1 then

		desired =
			desired.Unit
	end


	return desired
end


----------------------------------------------------------------
-- SWIM UPDATE
----------------------------------------------------------------

local function updateSwimming(
	dt: number
)

	local currentHumanoid =
		humanoid


	local currentRoot =
		rootPart


	if
		not currentHumanoid
		or not currentRoot
		or currentHumanoid.Health <= 0
	then

		return
	end


	----------------------------------------------------------------
	-- WATER ENTRY / EXIT
	----------------------------------------------------------------

	local surfaceY =
		getSurfaceY()


	if not bodyInWater then

		if
			currentRoot.Position.Y
			< surfaceY
			+ SwimSettings.EnterOffset
		then

			enterSwimming()
		end

	else

		if
			currentRoot.Position.Y
			> surfaceY
			+ SwimSettings.ExitOffset
		then

			exitSwimming()

			return
		end
	end


	if not bodyInWater then
		return
	end


	----------------------------------------------------------------
	-- KEEP BUOYANCY CURRENT
	----------------------------------------------------------------

	-- AssemblyMass can technically change if equipment/accessories
	-- modify the assembly, so recalculating this is inexpensive and
	-- keeps the buoyancy force correct.

	setBuoyancyEnabled(
		true
	)


	----------------------------------------------------------------
	-- OMNIDIRECTIONAL MOVEMENT
	----------------------------------------------------------------

	local swimDirection =
		getOmnidirectionalSwimDirection()


	-- Horizontal and vertical speeds remain independently tunable.
	--
	-- Therefore:
	--
	-- straight forward:
	--     Speed
	--
	-- straight upward:
	--     VerticalSpeed
	--
	-- diagonal upward:
	--     proportional mixture

	local targetVelocity =
		Vector3.new(

			swimDirection.X
			* SwimSettings.Speed,

			swimDirection.Y
			* SwimSettings.VerticalSpeed,

			swimDirection.Z
			* SwimSettings.Speed
		)


	----------------------------------------------------------------
	-- WATER DRAG / ACCELERATION
	----------------------------------------------------------------

	local currentVelocity =
		currentRoot.AssemblyLinearVelocity


	local alpha =
		1
	- math.exp(
		-SwimSettings.Acceleration
			* dt
	)


	currentRoot.AssemblyLinearVelocity =
		Vector3.new(

			lerpNumber(
				currentVelocity.X,
				targetVelocity.X,
				alpha
			),

			lerpNumber(
				currentVelocity.Y,
				targetVelocity.Y,
				alpha
			),

			lerpNumber(
				currentVelocity.Z,
				targetVelocity.Z,
				alpha
			)
		)
end


----------------------------------------------------------------
-- CHARACTER CONNECTIONS
----------------------------------------------------------------

if player.Character then

	setupCharacter(
		player.Character
	)
end


player.CharacterAdded:Connect(
	setupCharacter
)


player.CharacterRemoving:Connect(function()

	humanoid =
		nil


	rootPart =
		nil


	swimAttachment =
		nil


	buoyancyForce =
		nil


	bodyInWater =
		false


	unbindSwimControls()
end)


----------------------------------------------------------------
-- LOOP
----------------------------------------------------------------

RunService.Heartbeat:Connect(
	updateSwimming
)
