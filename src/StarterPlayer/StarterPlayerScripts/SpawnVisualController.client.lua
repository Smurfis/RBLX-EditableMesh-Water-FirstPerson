--!strict

-- StarterPlayer > StarterPlayerScripts > SpawnVisualController
--
-- EXPECTED HIERARCHY:
--
-- Workspace
-- └── Spawn
--     ├── FloatSpawn
--     ├── SpawnLocation
--     │   ├── Decal
--     │   └── Decal
--     │
--     └── Pedastal
--         ├── Blob
--         └── PlateAndStripe
--             └── WeldConstraint
--
-- SERVER:
--   Controls the real SpawnLocation movement/collision.
--   Controls Blob + PlateAndStripe.
--
-- CLIENT:
--   1. Real SpawnLocation decal gently fades in/out while idle.
--   2. On spawn, clone SpawnLocation locally.
--   3. Hide the real visual, but leave its collision untouched.
--   4. Clone rises to player's head.
--   5. Clone scans back down through the player.
--   6. Character body parts flicker/highlight as scanner crosses them.
--   7. Repeat for TWO passes.
--   8. Put clone exactly over real SpawnLocation.
--   9. Restore real SpawnLocation appearance.
--  10. Destroy temporary clone.
--
-- IMPORTANT:
--   This script NEVER changes Decal.Color3.
--   Your white decal stays whatever colour you authored in Studio.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer


--==============================================================
-- SETTINGS
--==============================================================

local SPAWN_MODEL_NAME = "Spawn"


--==============================================================
-- IDLE DECAL PULSE
--==============================================================

-- Time for one complete:
--
-- visible -> invisible -> visible
--
local IDLE_PULSE_DURATION = 2.5

local IDLE_MIN_TRANSPARENCY = 0
local IDLE_MAX_TRANSPARENCY = 1


--==============================================================
-- SPAWN SCANNER TIMING
--==============================================================

local START_DELAY = 0.25

-- Deliberately slower than before.
local RISE_TIME = 0.85
local HEAD_HOLD_TIME = 0.20
local DESCEND_TIME = 1.10

-- Number of complete:
--
-- floor -> head -> floor
--
-- passes.
local SCAN_PASSES = 2

local BETWEEN_PASSES_DELAY = 0.18


--==============================================================
-- SCANNER POSITION
--==============================================================

-- Scanner goes just above the top of the avatar's Head.
local HEAD_CLEARANCE = 0.15


--==============================================================
-- SCANNER ROTATION
--==============================================================

local SPIN_SPEED = 180 -- degrees per second


--==============================================================
-- SCANNER SIZE PULSE
--==============================================================

-- Keep the existing gentle expand/contract effect.
local SIZE_PULSE_AMOUNT = 0.08

local SIZE_PULSE_DURATION = 0.65


--==============================================================
-- SCANNER DECAL TRANSPARENCY
--==============================================================

-- While travelling around the avatar, the decal itself flashes:
--
-- transparency 1 -> 0 -> 1
--
local SCANNER_TRANSPARENCY_PULSE_DURATION = 0.55


--==============================================================
-- CHARACTER MATERIALISATION
--==============================================================

-- Range either side of scanner plane that can energise a limb.
local BODY_SCAN_HALF_HEIGHT = 0.52

-- Taller pieces get slightly more interaction range.
local BODY_HEIGHT_MULTIPLIER = 0.30

-- Strong outline, weaker internal fill.
local BODY_FILL_STRENGTH = 0.48

-- Creates unstable flicker.
local BODY_FLICKER_SPEED = 24
local BODY_FLICKER_AMOUNT = 0.30

-- 0 = completely opaque highlight.
local MIN_OUTLINE_TRANSPARENCY = 0.02
local MIN_FILL_TRANSPARENCY = 0.42

-- Materialisation colour.
--
-- This ONLY affects character Highlights.
-- It does NOT affect SpawnLocation decals.
local MATERIALISE_COLOR =
	Color3.fromRGB(255, 255, 255)


--==============================================================
-- FIND SPAWN
--==============================================================

local spawnModelInstance =
	Workspace:WaitForChild(
		SPAWN_MODEL_NAME,
		10
	)

if not spawnModelInstance then
	warn("[SpawnVisualController] Spawn model not found.")
	return
end

if not spawnModelInstance:IsA("Model") then
	warn(
		"[SpawnVisualController] Spawn exists but isn't a Model:",
		spawnModelInstance.ClassName
	)

	return
end

local spawnModel =
	spawnModelInstance :: Model


--==============================================================
-- FIND REAL SPAWNLOCATION
--==============================================================

local spawnLocationInstance =
	spawnModel:WaitForChild(
		"SpawnLocation",
		10
	)

if not spawnLocationInstance then
	warn(
		"[SpawnVisualController] SpawnLocation did not replicate."
	)

	return
end

if not spawnLocationInstance:IsA("BasePart") then
	warn(
		"[SpawnVisualController] SpawnLocation is not a BasePart:",
		spawnLocationInstance.ClassName
	)

	return
end

local spawnLocation =
	spawnLocationInstance :: BasePart


--==============================================================
-- SAVE ORIGINAL SPAWN APPEARANCE
--==============================================================

local originalPartLocalTransparency =
	spawnLocation.LocalTransparencyModifier


type DecalState = {
	decal: Decal,
	transparency: number,
	color: Color3,
}


local realDecalStates: {DecalState} = {}


for _, descendant in ipairs(
	spawnLocation:GetDescendants()
) do

	if descendant:IsA("Decal") then

		table.insert(
			realDecalStates,
			{
				decal = descendant,

				transparency =
					descendant.Transparency,

				color =
					descendant.Color3,
			}
		)
	end
end


--==============================================================
-- ACTIVE STATE
--==============================================================

local generation = 0

local isScanning = false

local activeScanner: BasePart? = nil

local activeRenderConnection:
	RBXScriptConnection? = nil

local activeHighlights: {Highlight} = {}


--==============================================================
-- BODY HIGHLIGHT TYPE
--==============================================================

type BodyHighlightEntry = {
	part: BasePart,
	highlight: Highlight,
	phase: number,
}


--==============================================================
-- IDLE PULSE STATE
--==============================================================

-- Starting from 0 means the real decal begins fully visible.
--
-- This is also reset to 0 when scanning finishes so it returns
-- visibly to its NORMAL appearance instead of ending invisible.
local idleElapsed = 0


--==============================================================
-- RESTORE REAL SPAWN EXACTLY
--==============================================================

local function restoreRealSpawn()

	spawnLocation.LocalTransparencyModifier =
		originalPartLocalTransparency


	for _, state in ipairs(
		realDecalStates
	) do

		local decal =
			state.decal


		if decal.Parent then

			------------------------------------------------------
			-- Restore BOTH original properties.
			--
			-- We actually never change Color3 intentionally,
			-- but restoring it here makes cleanup bulletproof.
			------------------------------------------------------

			decal.Color3 =
				state.color

			decal.Transparency =
				state.transparency
		end
	end
end


--==============================================================
-- HIDE REAL SPAWN VISUAL
--==============================================================

local function hideRealSpawn()

	-- Hides the BasePart visually on THIS client only.
	--
	-- CanCollide remains intact.
	spawnLocation.LocalTransparencyModifier =
		1


	for _, state in ipairs(
		realDecalStates
	) do

		if state.decal.Parent then

			-- NEVER touch Color3 here.
			state.decal.Transparency =
				1
		end
	end
end


--==============================================================
-- IDLE DECAL TRANSPARENCY PULSE
--==============================================================

RunService.RenderStepped:Connect(
	function(deltaTime)

		if isScanning then
			return
		end


		idleElapsed +=
			deltaTime


		----------------------------------------------------------
		-- Starts:
		--
		-- transparency = 0
		--
		-- then:
		--
		-- 0 -> 1 -> 0
		--
		-- This prevents the effect finishing on black/invisible.
		----------------------------------------------------------

		local phase =
			(
				idleElapsed
				/ IDLE_PULSE_DURATION
			)
			* math.pi
			* 2


		local wave =
			(
				1
				- math.cos(phase)
			)
			* 0.5


		local transparency =
			IDLE_MIN_TRANSPARENCY

			+ (
				IDLE_MAX_TRANSPARENCY
					- IDLE_MIN_TRANSPARENCY
			)

			* wave


		for _, state in ipairs(
			realDecalStates
		) do

			local decal =
				state.decal


			if decal.Parent then

				--------------------------------------------------
				-- ONLY transparency changes.
				--
				-- Color3 remains exactly what you set in Studio.
				--------------------------------------------------

				decal.Transparency =
					transparency
			end
		end
	end
)


--==============================================================
-- DESTROY HIGHLIGHTS
--==============================================================

local function destroyHighlights()

	for _, highlight in ipairs(
		activeHighlights
	) do

		if highlight.Parent then
			highlight:Destroy()
		end
	end


	table.clear(
		activeHighlights
	)
end

local function forceHideActiveHighlights()
	for _, highlight in ipairs(activeHighlights) do
		if highlight.Parent then
			highlight.FillTransparency = 1
			highlight.OutlineTransparency = 1
		end
	end
end


--==============================================================
-- CLEANUP
--==============================================================

local function cleanup()
	-- Clear the visible body effect before disconnecting the render callback.
	-- This closes the one-frame race where the last scanner update can leave
	-- a highlight partially visible after the materialisation has finished.
	forceHideActiveHighlights()

	if activeRenderConnection then

		activeRenderConnection:Disconnect()

		activeRenderConnection =
			nil
	end


	if activeScanner then

		activeScanner:Destroy()

		activeScanner =
			nil
	end


	destroyHighlights()


	--------------------------------------------------------------
	-- Restore exact authored spawn appearance.
	--------------------------------------------------------------

	restoreRealSpawn()


	--------------------------------------------------------------
	-- Restart idle pulse from FULLY VISIBLE.
	--
	-- Therefore we never finish the spawn animation with the
	-- decal stuck invisible/black.
	--------------------------------------------------------------

	idleElapsed =
		0


	isScanning =
		false

	-- Re-assert the final state on the next render boundary as a safety net
	-- for a callback already queued by RenderStepped.
	RunService.RenderStepped:Once(function()
		if not isScanning then
			forceHideActiveHighlights()
			restoreRealSpawn()
		end
	end)
end


--==============================================================
-- CREATE LOCAL SCANNER
--==============================================================

local function createScanner(): BasePart?

	local previousArchivable =
		spawnLocation.Archivable


	spawnLocation.Archivable =
		true


	local scanner =
		spawnLocation:Clone()


	spawnLocation.Archivable =
		previousArchivable


	if not scanner:IsA("BasePart") then

		scanner:Destroy()

		return nil
	end


	scanner.Name =
		"LocalSpawnScanner"


	--==========================================================
	-- LOCAL VISUAL ONLY
	--==========================================================

	scanner.Anchored =
		true

	scanner.CanCollide =
		false

	scanner.CanTouch =
		false

	scanner.CanQuery =
		false

	scanner.Massless =
		true


	if scanner:IsA("SpawnLocation") then

		-- Clone is NEVER another functional SpawnLocation.
		scanner.Enabled =
			false
	end


	--==========================================================
	-- REMOVE UNWANTED CONTENT
	--
	-- KEEP THE DECALS.
	--==========================================================

	for _, descendant in ipairs(
		scanner:GetDescendants()
	) do

		if
			descendant:IsA("Script")

			or descendant:IsA("LocalScript")

			or descendant:IsA("WeldConstraint")

			or descendant:IsA("Motor6D")

			or descendant:IsA("Constraint")
		then

			descendant:Destroy()
		end
	end


	--------------------------------------------------------------
	-- IMPORTANT:
	--
	-- NO:
	--
	--     scanner.Color = ...
	--
	-- NO:
	--
	--     decal.Color3 = ...
	--
	-- The clone retains the exact authored appearance.
	--------------------------------------------------------------


	scanner.Parent =
		spawnModel


	return scanner
end


--==============================================================
-- GET CLONED SCANNER DECALS
--==============================================================

local function getScannerDecals(
	scanner: BasePart
): {Decal}

	local decals: {Decal} = {}


	for _, descendant in ipairs(
		scanner:GetDescendants()
	) do

		if descendant:IsA("Decal") then

			table.insert(
				decals,
				descendant
			)
		end
	end


	return decals
end


--==============================================================
-- CREATE CHARACTER HIGHLIGHTS
--==============================================================

local function createBodyHighlights(
	character: Model,
	root: BasePart
): {BodyHighlightEntry}

	local entries: {BodyHighlightEntry} = {}


	for _, child in ipairs(
		character:GetChildren()
	) do

		----------------------------------------------------------
		-- Actual character body pieces only.
		--
		-- This automatically supports:
		--
		-- R15:
		--   Head
		--   UpperTorso
		--   LowerTorso
		--   arms
		--   hands
		--   legs
		--   feet
		--
		-- R6:
		--   Head
		--   Torso
		--   arms
		--   legs
		--
		-- HumanoidRootPart is ignored.
		----------------------------------------------------------

		if
			child:IsA("BasePart")
			and child ~= root
		then

			local highlight =
				Instance.new("Highlight")


			highlight.Name =
				"SpawnMaterialisationHighlight"


			highlight.Adornee =
				child


			highlight.FillColor =
				MATERIALISE_COLOR


			highlight.OutlineColor =
				MATERIALISE_COLOR


			highlight.FillTransparency =
				1


			highlight.OutlineTransparency =
				1


			highlight.DepthMode =
				Enum.HighlightDepthMode.Occluded


			highlight.Parent =
				character


			table.insert(
				activeHighlights,
				highlight
			)


			table.insert(
				entries,
				{
					part =
						child,

					highlight =
						highlight,

					phase =
						#entries
						* 1.731,
				}
			)
		end
	end


	return entries
end


--==============================================================
-- HIDE CHARACTER MATERIALISATION
--==============================================================

local function hideBodyHighlights(
	entries: {BodyHighlightEntry}
)

	for _, entry in ipairs(
		entries
	) do

		if entry.highlight.Parent then

			entry.highlight.FillTransparency =
				1


			entry.highlight.OutlineTransparency =
				1
		end
	end
end


--==============================================================
-- ANIMATION HELPER
--==============================================================

local function animate(
	duration: number,
	easingStyle: Enum.EasingStyle,
	easingDirection: Enum.EasingDirection,
	isValid: () -> boolean,
	update: (number) -> ()
): boolean

	local startTime =
		os.clock()


	while true do

		if not isValid() then
			return false
		end


		local elapsed =
			os.clock()
			- startTime


		local rawAlpha =
			math.clamp(
				elapsed / duration,
				0,
				1
			)


		local easedAlpha =
			TweenService:GetValue(
				rawAlpha,
				easingStyle,
				easingDirection
			)


		update(
			easedAlpha
		)


		if rawAlpha >= 1 then
			return true
		end


		RunService.RenderStepped:Wait()
	end
end


--==============================================================
-- PLAY SPAWN MATERIALISATION
--==============================================================

local function playScan(
	character: Model
)

	--------------------------------------------------------------
	-- Cancel previous scan safely.
	--------------------------------------------------------------

	generation += 1


	local thisGeneration =
		generation


	cleanup()


	--==========================================================
	-- FIND CHARACTER PARTS
	--==========================================================

	local rootInstance =
		character:WaitForChild(
			"HumanoidRootPart",
			5
		)


	local headInstance =
		character:WaitForChild(
			"Head",
			5
		)


	if
		not rootInstance

		or not rootInstance:IsA("BasePart")

		or not headInstance

		or not headInstance:IsA("BasePart")
	then

		return
	end


	local root =
		rootInstance :: BasePart


	local head =
		headInstance :: BasePart


	task.wait(
		START_DELAY
	)


	if
		not character.Parent
		or generation ~= thisGeneration
	then

		return
	end


	--==========================================================
	-- BEGIN SCAN
	--==========================================================

	isScanning =
		true


	--==========================================================
	-- CREATE LOCAL SPAWNLOCATION COPY
	--==========================================================

	local scanner =
		createScanner()


	if not scanner then

		isScanning =
			false


		warn(
			"[SpawnVisualController] Failed to clone SpawnLocation."
		)

		return
	end


	activeScanner =
		scanner


	local scannerDecals =
		getScannerDecals(
			scanner
		)


	--==========================================================
	-- CHARACTER EFFECTS
	--==========================================================

	local bodyHighlights =
		createBodyHighlights(
			character,
			root
		)


	local materialisationActive =
		false


	--==========================================================
	-- ORIGINAL SCANNER TRANSFORM
	--==========================================================

	local originalSize =
		spawnLocation.Size


	local originalRotation =
		spawnLocation.CFrame.Rotation


	local currentX =
		spawnLocation.Position.X


	local currentY =
		spawnLocation.Position.Y


	local currentZ =
		spawnLocation.Position.Z


	scanner.Size =
		originalSize


	scanner.CFrame =
		spawnLocation.CFrame


	--==========================================================
	-- HIDE REAL VISUAL
	--
	-- Collision continues to exist.
	--==========================================================

	hideRealSpawn()


	--==========================================================
	-- VISUAL STATE
	--==========================================================

	local visualElapsed =
		0


	local sizePulseStrength =
		0


	local scannerVisibility =
		1


	local function valid(): boolean

		return
			generation == thisGeneration

			and character.Parent ~= nil

			and scanner.Parent ~= nil
	end


	--==========================================================
	-- RENDER LOOP
	--==========================================================

	activeRenderConnection =
		RunService.RenderStepped:Connect(
			function(deltaTime)

				if not valid() then
					return
				end


				visualElapsed +=
					deltaTime


				--==================================================
				-- SPIN
				--==================================================

				local spinAngle =
					math.rad(
						(
							visualElapsed
								* SPIN_SPEED
						)
						% 360
					)


				--==================================================
				-- SIZE PULSE
				--==================================================

				local sizePhase =
					(
						visualElapsed
							/ SIZE_PULSE_DURATION
					)

					* math.pi
					* 2


				local sizeWave =
					math.sin(
						sizePhase
					)


				local scannerScale =
					1

					+ (
						sizeWave

						* SIZE_PULSE_AMOUNT

						* sizePulseStrength
					)


				scanner.Size =
					Vector3.new(

						originalSize.X
							* scannerScale,

						-- Keep the thin SpawnLocation thickness.
						originalSize.Y,

						originalSize.Z
							* scannerScale
					)


				--==================================================
				-- SCANNER DECAL TRANSPARENCY PULSE
				--
				-- 1 -> 0 -> 1
				--
				-- Only the CLONED moving scanner is affected.
				--==================================================

				local transparencyPhase =
					(
						visualElapsed
							/ SCANNER_TRANSPARENCY_PULSE_DURATION
					)

					* math.pi
					* 2


				local scannerTransparency =
					0.5

					+ (
						0.5
							* math.cos(
								transparencyPhase
							)
					)


				scannerVisibility =
					1
						- scannerTransparency


				for _, decal in ipairs(
					scannerDecals
				) do

					if decal.Parent then

						------------------------------------------------
						-- ONLY Transparency.
						--
						-- Never touch decal.Color3.
						------------------------------------------------

						decal.Transparency =
							scannerTransparency
					end
				end


				--==================================================
				-- SCANNER TRANSFORM
				--==================================================

				scanner.CFrame =
					CFrame.new(
						currentX,
						currentY,
						currentZ
					)

					* originalRotation

					* CFrame.Angles(
						0,
						spinAngle,
						0
					)


				--==================================================
				-- CHARACTER MATERIALISATION BAND
				--==================================================

				for index, entry in ipairs(
					bodyHighlights
				) do

					local bodyPart =
						entry.part


					local highlight =
						entry.highlight


					if
						not materialisationActive

						or not bodyPart.Parent

						or not highlight.Parent
					then

						if highlight.Parent then

							highlight.FillTransparency =
								1


							highlight.OutlineTransparency =
								1
						end


						continue
					end


					--------------------------------------------------
					-- Scanner's vertical distance from this limb.
					--------------------------------------------------

					local distance =
						math.abs(
							currentY
								- bodyPart.Position.Y
						)


					--------------------------------------------------
					-- Slight compensation for taller pieces.
					--------------------------------------------------

					local heightAllowance =
						math.min(
							bodyPart.Size.Y
								* BODY_HEIGHT_MULTIPLIER,

							0.55
						)


					local effectRange =
						BODY_SCAN_HALF_HEIGHT
							+ heightAllowance


					--------------------------------------------------
					-- 1 = scanner crossing centre of limb.
					-- 0 = scanner outside range.
					--------------------------------------------------

					local intensity =
						math.clamp(

							1
								- (
									distance
										/ effectRange
								),

							0,
							1
						)


					--------------------------------------------------
					-- Unstable individual-body-part flicker.
					--------------------------------------------------

					local noise =
						math.noise(

							visualElapsed
								* BODY_FLICKER_SPEED,

							entry.phase,

							index
								* 0.437
						)


					local normalizedNoise =
						(noise + 1)
							* 0.5


					local flicker =
						1
							- (
								normalizedNoise
									* BODY_FLICKER_AMOUNT
							)


					--------------------------------------------------
					-- Tie character instability loosely to the
					-- visible pulse of the scanner disc.
					--------------------------------------------------

					local scannerEnergy =
						0.55
							+ (
								scannerVisibility
									* 0.45
							)


					local energy =
						intensity
							* flicker
							* scannerEnergy


					--==================================================
					-- OUTLINE
					--==================================================

					highlight.OutlineTransparency =
						math.clamp(

							1 - energy,

							MIN_OUTLINE_TRANSPARENCY,
							1
						)


					--==================================================
					-- FILL
					--==================================================

					local fillEnergy =
						energy
							* BODY_FILL_STRENGTH


					highlight.FillTransparency =
						math.clamp(

							1 - fillEnergy,

							MIN_FILL_TRANSPARENCY,
							1
						)
				end
			end
		)


	--==============================================================
	-- TWO COMPLETE PASSES
	--==============================================================

	for passNumber = 1, SCAN_PASSES do

		if not valid() then

			cleanup()

			return
		end


		--==========================================================
		-- UPWARD PASS
		--
		-- SpawnLocation -> Head
		--
		-- CHARACTER effect stays OFF here.
		--==========================================================

		materialisationActive =
			false


		hideBodyHighlights(
			bodyHighlights
		)


		local riseStartY =
			spawnLocation.Position.Y


		currentY =
			riseStartY


		local riseWorked =
			animate(

				RISE_TIME,

				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,

				valid,

				function(alpha)

					--------------------------------------------------
					-- Keep scanner centred around player.
					--------------------------------------------------

					currentX =
						root.Position.X


					currentZ =
						root.Position.Z


					--------------------------------------------------
					-- Actual top of player's head.
					--------------------------------------------------

					local headTopY =
						head.Position.Y

						+ (
							head.Size.Y
								* 0.5
						)

						+ HEAD_CLEARANCE


					currentY =
						riseStartY

						+ (
							headTopY
								- riseStartY
						)

						* alpha


					--------------------------------------------------
					-- Gradually increase size breathing.
					--------------------------------------------------

					sizePulseStrength =
						math.clamp(
							alpha * 1.5,
							0,
							1
						)
				end
			)


		if not riseWorked then

			cleanup()

			return
		end


		--==========================================================
		-- HOLD JUST ABOVE HEAD
		--==========================================================

		local holdStarted =
			os.clock()


		while
			os.clock()
				- holdStarted
				< HEAD_HOLD_TIME
		do

			if not valid() then

				cleanup()

				return
			end


			currentX =
				root.Position.X


			currentZ =
				root.Position.Z


			currentY =
				head.Position.Y

				+ (
					head.Size.Y
						* 0.5
				)

				+ HEAD_CLEARANCE


			sizePulseStrength =
				1


			RunService.RenderStepped:Wait()
		end


		--==========================================================
		-- DOWNWARD MATERIALISATION PASS
		--
		-- Head -> real SpawnLocation
		--==========================================================

		materialisationActive =
			true


		local descentStartY =
			currentY


		local descendWorked =
			animate(

				DESCEND_TIME,

				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,

				valid,

				function(alpha)

					currentX =
						root.Position.X


					currentZ =
						root.Position.Z


					--------------------------------------------------
					-- Server is still floating real SpawnLocation.
					--
					-- Read its CURRENT Y continuously.
					--------------------------------------------------

					local platformY =
						spawnLocation.Position.Y


					currentY =
						descentStartY

						+ (
							platformY
								- descentStartY
						)

						* alpha


					sizePulseStrength =
						1
				end
			)


		if not descendWorked then

			cleanup()

			return
		end


		--------------------------------------------------------------
		-- Materialisation band off between passes.
		--------------------------------------------------------------

		materialisationActive =
			false


		hideBodyHighlights(
			bodyHighlights
		)


		--==========================================================
		-- SHORT REST BEFORE SECOND PASS
		--==========================================================

		if passNumber < SCAN_PASSES then

			local pauseStarted =
				os.clock()


			while
				os.clock()
					- pauseStarted
					< BETWEEN_PASSES_DELAY
			do

				if not valid() then

					cleanup()

					return
				end


				currentX =
					root.Position.X


				currentZ =
					root.Position.Z


				currentY =
					spawnLocation.Position.Y


				sizePulseStrength =
					1


				RunService.RenderStepped:Wait()
			end
		end
	end


	--==============================================================
	-- FINISHED
	--==============================================================

	materialisationActive =
		false


	hideBodyHighlights(
		bodyHighlights
	)


	--==============================================================
	-- EXACTLY MATCH REAL PLATFORM BEFORE SWAP
	--==============================================================

	scanner.Size =
		originalSize


	scanner.CFrame =
		spawnLocation.CFrame


	--==============================================================
	-- IMPORTANT:
	--
	-- Restore the real white SpawnLocation/decal BEFORE destroying
	-- the scanner.
	--
	-- This prevents the "finished black" frame.
	--==============================================================

	restoreRealSpawn()


	-- Reset idle animation so first idle frame starts visible.
	idleElapsed =
		0


	--==============================================================
	-- REMOVE TEMPORARY EFFECT
	--==============================================================

	if activeRenderConnection then

		activeRenderConnection:Disconnect()

		activeRenderConnection =
			nil
	end


	scanner:Destroy()


	activeScanner =
		nil


	destroyHighlights()


	isScanning =
		false
end

--==============================================================
-- SPAWN / DEATH SOUND
--==============================================================

local SPAWN_SOUND_ID = "rbxassetid://114988430237109"


local function playSpawnSound()

	local sound = Instance.new("Sound")

	sound.Name = "SpawnMaterialisationSound"
	sound.SoundId = SPAWN_SOUND_ID
	sound.Volume = 1

	sound.Parent = SoundService

	sound:Play()

	-- Safety cleanup after playback.
	Debris:AddItem(sound, 10)
end


--==============================================================
-- CHARACTER ADDED
--==============================================================

local function onCharacterAdded(
	character: Model
)

	task.spawn(
		function()

			local humanoid =
				character:WaitForChild(
					"Humanoid",
					5
				)

			character:WaitForChild(
				"HumanoidRootPart",
				5
			)

			character:WaitForChild(
				"Head",
				5
			)


			if not character.Parent then
				return
			end


			------------------------------------------------------
			-- PLAYER SPAWNED
			------------------------------------------------------

			playSpawnSound()


			------------------------------------------------------
			-- PLAY MATERIALISATION EFFECT
			------------------------------------------------------

			playScan(
				character
			)


			------------------------------------------------------
			-- PLAYER DIED
			------------------------------------------------------

			if
				humanoid
				and humanoid:IsA("Humanoid")
			then

				humanoid.Died:Once(
					function()

						playSpawnSound()

					end
				)
			end
		end
	)
end


--==============================================================
-- CHARACTER REMOVING
--==============================================================

local function onCharacterRemoving(
	_character: Model
)

	-- Cancel any active scanner / materialisation effect.
	generation += 1

	cleanup()
end


--==============================================================
-- CONNECTIONS
--==============================================================

if player.Character then

	onCharacterAdded(
		player.Character
	)
end


player.CharacterAdded:Connect(
	onCharacterAdded
)


player.CharacterRemoving:Connect(
	onCharacterRemoving
)
