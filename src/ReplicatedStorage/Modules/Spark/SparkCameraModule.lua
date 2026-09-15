--!strict
-- ReplicatedStorage.Modules.Spark.SparkCameraModule
-- Owns the Spark-assisted handoff from the ReplicatedFirst intro camera
-- to the normal gameplay camera.
local RunService = game:GetService("RunService");
local Lighting = game:GetService("Lighting");
local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local ContextActionService = game:GetService("ContextActionService");
local SoundService = game:GetService("SoundService");
local ContentProvider = game:GetService("ContentProvider");
local TweenService = game:GetService("TweenService");

local FREEZE_ACTION_NAME: string = "SparkCamera_FreezeInput";
local SPARK_INTRO_FREEZE_ACTION_NAME: string =
	"SparkIntro_FreezeInput";

---------------------------------------------------------
-- CAMERA HEIGHT
---------------------------------------------------------

-- Matches the ReplicatedFirst loading camera:
-- CFrame.new(0, 2000, 0)
local SKY_CAMERA_ALTITUDE: number = 2000;

---------------------------------------------------------
-- CINEMATIC SPARK
---------------------------------------------------------

local SPARK_CINEMATIC_NAME: string = "CinematicSpark";
local SPARK_LOADING_BIND_NAME: string = "LoadingSparkCinematic";
local SPARK_CAMERA_HANDOFF_EVENT_NAME: string = "SparkCameraHandoff";
local SPARK_INTRO_READY_ATTRIBUTE: string =
	"SparkIntroReadyForCameraTransition";
local SPARK_INTRO_STAGE_ATTRIBUTE: string =
	"SparkIntroStage";
local SPARK_GAMEPLAY_READY_ATTRIBUTE: string =
	"SparkGameplayFollowerReady";
local SPARK_INITIAL_LOAD_COMPLETE_ATTRIBUTE: string =
	"SparkInitialLoadComplete";

local SPARK_BASE_ROLL: number = 45;
local SPARK_APPROACH_SPIN_DEGREES: number = 720;

-- Phase 2 camera-relative flight.
-- -Z is in front of the camera.
local SPARK_APPROACH_START_OFFSET: Vector3 =
	Vector3.new(-4, 10, -45);

local SPARK_APPROACH_CONTROL_OFFSET: Vector3 =
	Vector3.new(5, 4, -18);

local SPARK_APPROACH_END_OFFSET: Vector3 =
	Vector3.new(0, 1.5, -7);

local SPARK_FLY_UP_CONTROL_OFFSET: Vector3 =
	Vector3.new(-2, 12, -7);

local SPARK_FLY_UP_END_OFFSET: Vector3 =
	Vector3.new(6, 30, -15);

local SPARK_APPROACH_END_T: number = 0.68;
local SPARK_FLY_UP_END_T: number = 0.86;

local SPARK_SPOTLIGHT_BRIGHTNESS: number = 8;
local SPARK_SPOTLIGHT_RANGE: number = 70;
local SPARK_SPOTLIGHT_ANGLE: number = 70;

---------------------------------------------------------
-- CAMERA TRANSITION SOUNDS
---------------------------------------------------------

local CAMERA_MOVEMENT_SOUND_ID: string = "rbxassetid://101257187966211";
local FINAL_HANDOFF_SOUND_ID: string = "rbxassetid://128614591007939";
local FLIGHT_SOUND_ID: string = "rbxassetid://119780348141086";

local FLIGHT_SOUND_VOLUME: number = 0.55;
local FLIGHT_SOUND_DUCK_VOLUME: number = 0.16;

-- With the current 0.9s ascent this begins immediately and loops through
-- the initial sky movement until the exact max-flip cue takes over.
local CAMERA_PRE_FLIP_SOUND_LEAD_TIME: number = 1.5;

-- Final movement cue before the handoff cue.
local CAMERA_SETTLE_SOUND_BEFORE_END: number = 1.20;

---------------------------------------------------------
-- CINEMATIC SPARK HELPER
---------------------------------------------------------

local function getCinematicSpark(
	localPlayer: Player
): Model?
	task.delay(15, function()
		if localPlayer:GetAttribute(
			SPARK_INTRO_READY_ATTRIBUTE
		) ~= true then
			warn(string.format(
				"[SparkCameraModule]: Still waiting for the ReplicatedFirst Spark intro; current stage: %s.",
				tostring(localPlayer:GetAttribute(
					SPARK_INTRO_STAGE_ATTRIBUTE
				))
			));
		end;
	end);

	while localPlayer:GetAttribute(
		SPARK_INTRO_READY_ATTRIBUTE
	) ~= true do
		localPlayer:GetAttributeChangedSignal(
			SPARK_INTRO_READY_ATTRIBUTE
		):Wait();
	end;

	local cinematicSpark =
		workspace:FindFirstChild(
			SPARK_CINEMATIC_NAME
		);

	if not cinematicSpark
		or not cinematicSpark:IsA("Model")
	then
		warn(
			"[SparkCameraModule]: workspace.CinematicSpark was not found."
		);
		return nil;
	end;

	if cinematicSpark:GetAttribute(
		"ReadyForCameraTransition"
	) ~= true then
		warn(
			"[SparkCameraModule]: ReplicatedFirst reported ready without marking CinematicSpark ready."
		);
		return nil;
	end;

	return cinematicSpark;
end;

local function getGameplaySpark(
	localPlayer: Player
): Model?
	task.delay(15, function()
		if localPlayer:GetAttribute(
			SPARK_GAMEPLAY_READY_ATTRIBUTE
		) ~= true then
			warn(
				"[SparkCameraModule]: Still waiting for SparkFollower to prepare the gameplay Spark."
			);
		end;
	end);

	while localPlayer:GetAttribute(
		SPARK_GAMEPLAY_READY_ATTRIBUTE
	) ~= true do
		localPlayer:GetAttributeChangedSignal(
			SPARK_GAMEPLAY_READY_ATTRIBUTE
		):Wait();
	end;

	local gameplaySpark =
		workspace:FindFirstChild(
			localPlayer.Name .. "'s Spark"
		);

	if not gameplaySpark
		or not gameplaySpark:IsA("Model")
	then
		warn(
			"[SparkCameraModule]: Gameplay Spark was not found."
		);
		return nil;
	end;

	return gameplaySpark;
end;

local function getSparkCameraHandoffEvent(): BindableEvent
	local existingEvent =
		ReplicatedStorage:FindFirstChild(
			SPARK_CAMERA_HANDOFF_EVENT_NAME
		);

	if existingEvent
		and existingEvent:IsA("BindableEvent")
	then
		return existingEvent;
	end;

	if existingEvent then
		existingEvent:Destroy();
	end;

	local sparkCameraHandoffEvent =
		Instance.new("BindableEvent");

	sparkCameraHandoffEvent.Name =
		SPARK_CAMERA_HANDOFF_EVENT_NAME;

	sparkCameraHandoffEvent.Parent =
		ReplicatedStorage;

	return sparkCameraHandoffEvent;
end;

---------------------------------------------------------
-- REMOTE NETWORK SETUP
---------------------------------------------------------

local function getTransitionRemote(): RemoteFunction
	local remote = ReplicatedStorage:FindFirstChild("SparkCameraTransitionRemote") :: RemoteFunction?;

	if not remote then
		if RunService:IsServer() then
			remote = Instance.new("RemoteFunction");
			remote.Name = "SparkCameraTransitionRemote";
			remote.Parent = ReplicatedStorage;
		else
			remote = ReplicatedStorage:WaitForChild("SparkCameraTransitionRemote", 10) :: RemoteFunction?;
		end;
	end;

	return remote :: RemoteFunction;
end;

---------------------------------------------------------
-- TYPES & CONFIGURATION
---------------------------------------------------------

export type TransitionConfig = {
	AscentDuration: number,
	DescentDuration: number,
	ApexAltitude: number,
	StartFov: number,
	ApexFov: number,
	EndFov: number,
	MaxBlur: number,
	TargetOffset: Vector3,
};

local DEFAULT_CONFIG: TransitionConfig = {
	AscentDuration = 0.9,
	DescentDuration = 2.1,
	ApexAltitude = SKY_CAMERA_ALTITUDE,
	StartFov = 75,
	ApexFov = 115,
	EndFov = 70,
	MaxBlur = 28,
	TargetOffset = Vector3.new(0, 3, 12),
};

local SparkCameraModule = {};
SparkCameraModule.__index = SparkCameraModule;

---------------------------------------------------------
-- MATHEMATICAL HELPERS
---------------------------------------------------------

local function getBezierPoint(t: number, p0: Vector3, p1: Vector3, p2: Vector3): Vector3
	local oneMinusT: number = 1 - t;
	return (oneMinusT * oneMinusT * p0) + (2 * oneMinusT * t * p1) + (t * t * p2);
end;

local function easeInQuad(x: number): number
	return x * x;
end;

local function easeOutQuint(x: number): number
	return 1 - math.pow(1 - x, 5);
end;

---------------------------------------------------------
-- SCREEN-SPACE CLOUD OVERLAY & WHITEOUT
---------------------------------------------------------

local function createCloudOverlay(player: Player): (ScreenGui, Frame)
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui;
	local existing: Instance? = playerGui:FindFirstChild("SparkCamera_CloudOverlay");

	if existing then
		existing:Destroy();
	end;

	local screenGui = Instance.new("ScreenGui");
	screenGui.Name = "SparkCamera_CloudOverlay";
	screenGui.DisplayOrder = 999;
	screenGui.IgnoreGuiInset = true;
	screenGui.ResetOnSpawn = false;

	local cloudFrame = Instance.new("Frame");
	cloudFrame.Name = "CloudBurst";
	cloudFrame.Size = UDim2.fromScale(1.2, 1.2);
	cloudFrame.Position = UDim2.fromScale(-0.1, -0.1);
	cloudFrame.BackgroundColor3 = Color3.fromRGB(245, 248, 255);
	cloudFrame.BackgroundTransparency = 1;
	cloudFrame.BorderSizePixel = 0;
	cloudFrame.Parent = screenGui;

	screenGui.Parent = playerGui;

	return screenGui, cloudFrame;
end;

---------------------------------------------------------
-- PLAYER CONTROLS & BETA CONTROLLER HELPER
---------------------------------------------------------

local function setCharacterControlsEnabled(localPlayer: Player, enabled: boolean)
	-----------------------------------------------------
	-- STANDARD PLAYERMODULE CONTROLS
	-----------------------------------------------------

	local playerScripts = localPlayer:WaitForChild("PlayerScripts", 5) :: Instance?;

	if playerScripts then
		local playerModule = playerScripts:FindFirstChild("PlayerModule") :: ModuleScript?;

		if playerModule then
			pcall(function()
				local controls = require(playerModule):GetControls();

				if enabled then
					controls:Enable();
				else
					controls:Disable();
				end;
			end);
		end;
	end;

	-----------------------------------------------------
	-- BETA CHARACTER CONTROLLER
	-----------------------------------------------------

	local character: Model? = localPlayer.Character;

	if character then
		local controllerManager = character:FindFirstChildOfClass("ControllerManager") :: ControllerManager?;

		if controllerManager then
			if not enabled then
				controllerManager.MovingDirection = Vector3.zero;

				if controllerManager.ActiveController then
					character:SetAttribute("SparkCamera_SavedController", controllerManager.ActiveController.Name);
					controllerManager.ActiveController = nil;
				end;
			else
				local savedControllerName = character:GetAttribute("SparkCamera_SavedController") :: string?;

				if savedControllerName then
					local savedController = controllerManager:FindFirstChild(savedControllerName) :: BaseController?;

					if savedController then
						controllerManager.ActiveController = savedController;
					end;

					character:SetAttribute("SparkCamera_SavedController", nil);
				else
					local groundController = controllerManager:FindFirstChildOfClass("GroundController") :: BaseController?;

					if groundController then
						controllerManager.ActiveController = groundController;
					end;
				end;
			end;
		end;
	end;

	-----------------------------------------------------
	-- CONTEXT ACTION SERVICE FAILSAFE
	-----------------------------------------------------

	if not enabled then
		ContextActionService:BindActionAtPriority(
			FREEZE_ACTION_NAME,
			function(): Enum.ContextActionResult
				return Enum.ContextActionResult.Sink;
			end,
			false,
			10000,
			Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft,
			Enum.PlayerActions.CharacterRight,
			Enum.PlayerActions.CharacterJump
		);
	else
		ContextActionService:UnbindAction(FREEZE_ACTION_NAME);
	end;
end;

---------------------------------------------------------
-- CLASS IMPLEMENTATION
---------------------------------------------------------

function SparkCameraModule.new(customConfig: { [string]: any }?): any
	local self = setmetatable({}, SparkCameraModule);
	self._config = table.clone(DEFAULT_CONFIG);

	if customConfig then
		for key: string, value: any in pairs(customConfig) do
			-- Sky height is authoritative in this module so an older client
			-- ApexAltitude = 550 cannot pull us away from the 2000-stud loader.
			if key ~= "ApexAltitude" and (self._config :: any)[key] ~= nil then
				(self._config :: any)[key] = value;
			end;
		end;
	end;

	self._config.ApexAltitude = SKY_CAMERA_ALTITUDE;
	self._isTransitioning = false;

	return self;
end;

---------------------------------------------------------
-- EXECUTE CAMERA TRANSITION
---------------------------------------------------------

function SparkCameraModule:Execute(onCompleteCallback: (() -> ())?): boolean
	if not RunService:IsClient() then
		warn("[SparkCameraModule]: Cannot execute camera transition on the Server!");
		return false;
	end;

	local localPlayer: Player? = Players.LocalPlayer;

	if not localPlayer then
		return false;
	end;

	local camera = workspace.CurrentCamera :: Camera?;

	if not camera then
		return false;
	end;

	if self._isTransitioning then
		return false;
	end;

	self._isTransitioning = true;

	local cfg: TransitionConfig = self._config;

	if not game:IsLoaded() then
		game.Loaded:Wait();
	end;

	-----------------------------------------------------
	-- CHARACTER
	-----------------------------------------------------

	local character = (localPlayer.Character or localPlayer.CharacterAdded:Wait()) :: Model;
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?;
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?;

	if not rootPart or not humanoid then
		self._isTransitioning = false;
		return false;
	end;

	-----------------------------------------------------
	-- LOCK PLAYER
	-----------------------------------------------------

	setCharacterControlsEnabled(localPlayer, false);

	-- ReplicatedFirst freezes immediately, before PlayerModule/CCL are ready.
	-- This module now owns the freeze through the remainder of the transition.
	ContextActionService:UnbindAction(
		SPARK_INTRO_FREEZE_ACTION_NAME
	);

	-----------------------------------------------------
	-- STREAM PLAYER AREA
	-----------------------------------------------------

	if workspace.StreamingEnabled then
		pcall(function()
			localPlayer:RequestStreamAroundAsync(rootPart.Position);
		end);
	end;

	-----------------------------------------------------
	-- WAIT FOR BOTH SPARK OWNERS BEFORE CAMERA HANDOFF
	-----------------------------------------------------

	local cinematicSpark: Model? =
		getCinematicSpark(
			localPlayer
		);

	local gameplaySpark: Model? =
		getGameplaySpark(
			localPlayer
		);

	if not cinematicSpark or not gameplaySpark then
		setCharacterControlsEnabled(localPlayer, true);
		self._isTransitioning = false;
		return false;
	end;

	local sparkCameraHandoffEvent: BindableEvent =
		getSparkCameraHandoffEvent();

	-----------------------------------------------------
	-- POST PROCESSING
	-----------------------------------------------------

	local blur = Instance.new("BlurEffect");
	blur.Size = 0;
	blur.Name = "SparkCamera_DropBlur";
	blur.Parent = Lighting;

	local cloudGui: ScreenGui, cloudFrame: Frame = createCloudOverlay(localPlayer);

	-----------------------------------------------------
	-- CAMERA TRANSITION SOUNDS
	-----------------------------------------------------

	local cameraMovementSound = Instance.new("Sound");
	cameraMovementSound.Name = "SparkCamera_MovementSound";
	cameraMovementSound.SoundId = CAMERA_MOVEMENT_SOUND_ID;
	cameraMovementSound.Volume = 1;
	cameraMovementSound.Looped = false;
	cameraMovementSound.Parent = SoundService;

	local extraCameraMovementSound = Instance.new("Sound");
	extraCameraMovementSound.Name = "SparkCamera_ExtraMovementSound";
	extraCameraMovementSound.SoundId = CAMERA_MOVEMENT_SOUND_ID;
	extraCameraMovementSound.Volume = 1;
	extraCameraMovementSound.Looped = false;
	extraCameraMovementSound.Parent = SoundService;

	local finalHandoffSound = Instance.new("Sound");
	finalHandoffSound.Name = "SparkCamera_FinalHandoffSound";
	finalHandoffSound.SoundId = FINAL_HANDOFF_SOUND_ID;
	finalHandoffSound.Volume = 1;
	finalHandoffSound.Looped = false;
	finalHandoffSound.Parent = SoundService;

	local flightSound = Instance.new("Sound");
	flightSound.Name = "SparkCamera_FlightSound";
	flightSound.SoundId = FLIGHT_SOUND_ID;
	flightSound.Volume = 0;
	flightSound.Looped = true;
	flightSound.Parent = SoundService;

	pcall(function()
		ContentProvider:PreloadAsync({
			cameraMovementSound,
			extraCameraMovementSound,
			finalHandoffSound,
			flightSound,
		});
	end);

	local function tweenFlightVolume(volume: number, duration: number)
		TweenService:Create(
			flightSound,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Volume = volume }
		):Play();
	end;

	local hasPlayedCameraPreFlipSound: boolean = false;
	local hasPlayedCameraMaxFlipSound: boolean = false;
	local hasPlayedExtraCameraMovementSound: boolean = false;
	local hasPlayedCameraSettleSound: boolean = false;
	local hasPlayedFinalHandoffSound: boolean = false;

	-----------------------------------------------------
	-- CAMERA COORDINATES
	-----------------------------------------------------

	local forwardVector: Vector3 = rootPart.CFrame.LookVector;
	local targetCFrame: CFrame = rootPart.CFrame * CFrame.new(cfg.TargetOffset);
	local targetPos: Vector3 = targetCFrame.Position;
	local lookAtCenter: Vector3 = rootPart.Position + Vector3.new(0, 2, 0);

	local replicatedFirstCameraCFrame: CFrame = camera.CFrame;
	local replicatedFirstCameraPosition: Vector3 = replicatedFirstCameraCFrame.Position;
	local skyApexPos: Vector3 = targetPos + Vector3.new(0, cfg.ApexAltitude, 0);

	-----------------------------------------------------
	-- TAKE CAMERA OWNERSHIP FROM REPLICATEDFIRST
	-----------------------------------------------------

	camera.CameraType = Enum.CameraType.Scriptable;
	camera.CFrame = replicatedFirstCameraCFrame;

	RunService:UnbindFromRenderStep("LoadingCameraLock");

	-----------------------------------------------------
	-- TAKE CINEMATIC SPARK FROM REPLICATEDFIRST
	-----------------------------------------------------

	RunService:UnbindFromRenderStep(
		SPARK_LOADING_BIND_NAME
	);

	local cinematicSparkStartCFrame: CFrame? =
		if cinematicSpark
		then cinematicSpark:GetPivot()
		else nil;

	-----------------------------------------------------
	-- CINEMATIC SPARK SPOTLIGHT
	-----------------------------------------------------

	local cinematicSparkSpotlight: SpotLight? = nil;

	if cinematicSpark then
		local cinematicSparkLightPart =
			cinematicSpark:FindFirstChild(
				"SparkBody",
				true
			) :: BasePart?;

		if not cinematicSparkLightPart then
			cinematicSparkLightPart =
				cinematicSpark:FindFirstChildWhichIsA(
					"BasePart",
					true
				);
		end;

		if cinematicSparkLightPart then
			local spotlight =
				Instance.new("SpotLight");

			spotlight.Name =
				"CinematicSparkSpotlight";

			spotlight.Face =
				Enum.NormalId.Front;

			spotlight.Color =
				Color3.fromRGB(
					220,
					255,
					240
				);

			spotlight.Brightness = 0;
			spotlight.Range =
				SPARK_SPOTLIGHT_RANGE;

			spotlight.Angle =
				SPARK_SPOTLIGHT_ANGLE;

			spotlight.Shadows = false;
			spotlight.Enabled = false;
			spotlight.Parent =
				cinematicSparkLightPart;

			cinematicSparkSpotlight =
				spotlight;
		end;
	end;

	flightSound.TimePosition = 0;
	flightSound:Play();
	tweenFlightVolume(FLIGHT_SOUND_VOLUME, 0.25);

	-----------------------------------------------------
	-- TRANSITION CLOCK
	-----------------------------------------------------

	local startTime: number = os.clock();
	local totalDuration: number = cfg.AscentDuration + cfg.DescentDuration;
	local renderConnection: RBXScriptConnection? = nil;

	-----------------------------------------------------
	-- RENDER LOOP
	-----------------------------------------------------

	renderConnection = RunService.RenderStepped:Connect(function()
		local elapsed: number = os.clock() - startTime;

		-------------------------------------------------
		-- PHASE 1: SKYWARD ASCENT
		-------------------------------------------------

		if elapsed <= cfg.AscentDuration then
			local rawT: number = math.clamp(elapsed / cfg.AscentDuration, 0, 1);
			local t: number = easeInQuad(rawT);
			local currentPos: Vector3 = replicatedFirstCameraPosition:Lerp(skyApexPos, t);
			local skywardCFrame: CFrame = CFrame.new(currentPos, currentPos + Vector3.new(0, 1, 0));

			camera.CFrame = skywardCFrame;
			camera.FieldOfView = cfg.StartFov + ((cfg.ApexFov - cfg.StartFov) * t);

			blur.Size = cfg.MaxBlur * t;
			cloudFrame.BackgroundTransparency = 1 - t;

			-------------------------------------------------
			-- EARLY SUBTLE CAMERA MOVEMENT CUE
			-------------------------------------------------

			local ascentTimeRemaining: number = cfg.AscentDuration - elapsed;

			if not hasPlayedCameraPreFlipSound
				and ascentTimeRemaining <= CAMERA_PRE_FLIP_SOUND_LEAD_TIME then

				hasPlayedCameraPreFlipSound = true;

				cameraMovementSound:Stop();
				cameraMovementSound.Looped = true;
				cameraMovementSound.PlaybackSpeed = 1;
				cameraMovementSound.TimePosition = 1.2;
				cameraMovementSound:Play();
			end;

			-------------------------------------------------
			-- PHASE 2: MAX FLIP + DESCENT
			-------------------------------------------------

		elseif elapsed <= totalDuration then
			-------------------------------------------------
			-- EXACT MAX-FLIP CAMERA MOVEMENT CUE
			-------------------------------------------------

			if not hasPlayedCameraMaxFlipSound then
				hasPlayedCameraMaxFlipSound = true;

				tweenFlightVolume(FLIGHT_SOUND_DUCK_VOLUME, 0.08);

				cameraMovementSound:Stop();
				cameraMovementSound.Looped = false;
				cameraMovementSound.PlaybackSpeed = 1;
				cameraMovementSound.TimePosition = 0;
				cameraMovementSound:Play();

				task.delay(0.14, function()
					if flightSound.Parent then
						tweenFlightVolume(FLIGHT_SOUND_VOLUME, 0.20);
					end;
				end);
			end;

			local descentElapsed: number = elapsed - cfg.AscentDuration;
			local rawT: number = math.clamp(descentElapsed / cfg.DescentDuration, 0, 1);
			local t: number = easeOutQuint(rawT);

			-------------------------------------------------
			-- EXTRA INDEPENDENT CAMERA MOVEMENT CUE
			-------------------------------------------------

			if not hasPlayedExtraCameraMovementSound and elapsed >= 1.5 then
				hasPlayedExtraCameraMovementSound = true;

				extraCameraMovementSound.TimePosition = 1.2;
				extraCameraMovementSound:Play();
			end;

			-------------------------------------------------
			-- FINAL CAMERA MOVEMENT CUE NEAR SETTLE
			-------------------------------------------------

			local transitionTimeRemaining: number = totalDuration - elapsed;

			if not hasPlayedCameraSettleSound
				and transitionTimeRemaining <= CAMERA_SETTLE_SOUND_BEFORE_END then

				hasPlayedCameraSettleSound = true;

				tweenFlightVolume(0, 0.35);

				cameraMovementSound:Stop();
				cameraMovementSound.Looped = false;
				cameraMovementSound.PlaybackSpeed = 2;
				cameraMovementSound.TimePosition = 1;
				cameraMovementSound:Play();
			end;

			-------------------------------------------------
			-- BEZIER ARC
			-------------------------------------------------

			local p0: Vector3 = skyApexPos;
			local p1: Vector3 = targetPos
				+ Vector3.new(0, cfg.ApexAltitude * 0.4, 0)
			- (forwardVector * 80);
			local p2: Vector3 = targetPos;

			local currentPos: Vector3 = getBezierPoint(t, p0, p1, p2);
			local currentLookAt: Vector3 = lookAtCenter:Lerp(
				rootPart.Position + Vector3.new(0, 1.5, 0),
				t
			);

			camera.CFrame = CFrame.lookAt(currentPos, currentLookAt);
			camera.FieldOfView = cfg.ApexFov + ((cfg.EndFov - cfg.ApexFov) * t);

			blur.Size = cfg.MaxBlur * (1 - t);
			cloudFrame.BackgroundTransparency = t;

			-------------------------------------------------
			-- CINEMATIC SPARK FLIGHT
			--
			-- After the camera flips, keep Spark in front of
			-- the camera. He flies down toward us with his
			-- spotlight, then curves upward and leaves frame.
			-- The real Spark is revealed only at the final
			-- handoff.
			-------------------------------------------------

			if cinematicSpark
				and cinematicSpark.Parent
			then
				local sparkCameraOffset: Vector3;
				local sparkBank: number = 0;
				local sparkSpin: number = 0;

				if rawT <= SPARK_APPROACH_END_T then
					local approachT: number =
						math.clamp(
							rawT
							/ SPARK_APPROACH_END_T,
							0,
							1
						);

					local approachEase: number =
						easeOutQuint(
							approachT
						);

					sparkCameraOffset =
						getBezierPoint(
							approachEase,
							SPARK_APPROACH_START_OFFSET,
							SPARK_APPROACH_CONTROL_OFFSET,
							SPARK_APPROACH_END_OFFSET
						);

					sparkBank =
						-10
						+ (18 * approachEase);

					sparkSpin =
						SPARK_APPROACH_SPIN_DEGREES
						* approachT;

					if cinematicSparkSpotlight then
						cinematicSparkSpotlight.Enabled = true;
						cinematicSparkSpotlight.Brightness =
							SPARK_SPOTLIGHT_BRIGHTNESS
							* approachEase;
					end;
				elseif rawT <= SPARK_FLY_UP_END_T then
					local flyUpT: number =
						math.clamp(
							(
								rawT
								- SPARK_APPROACH_END_T
							)
							/ (
								SPARK_FLY_UP_END_T
								- SPARK_APPROACH_END_T
							),
							0,
							1
						);

					local flyUpEase: number =
						easeInQuad(
							flyUpT
						);

					sparkCameraOffset =
						getBezierPoint(
							flyUpEase,
							SPARK_APPROACH_END_OFFSET,
							SPARK_FLY_UP_CONTROL_OFFSET,
							SPARK_FLY_UP_END_OFFSET
						);

					sparkBank =
						8
						+ (18 * flyUpEase);

					if cinematicSparkSpotlight then
						cinematicSparkSpotlight.Enabled = true;
						cinematicSparkSpotlight.Brightness =
							SPARK_SPOTLIGHT_BRIGHTNESS
							* (1 - flyUpEase);
					end;
				else
					sparkCameraOffset =
						SPARK_FLY_UP_END_OFFSET;

					sparkBank = 26;

					if cinematicSparkSpotlight then
						cinematicSparkSpotlight.Enabled = false;
						cinematicSparkSpotlight.Brightness = 0;
					end;
				end;

				local sparkWorldPosition: Vector3 =
					camera.CFrame:PointToWorldSpace(
						sparkCameraOffset
					);

				local sparkWorldCFrame: CFrame =
					CFrame.lookAt(
						sparkWorldPosition,
						camera.CFrame.Position
					)
					* CFrame.Angles(
						0,
						0,
						math.rad(
							SPARK_BASE_ROLL
							+ sparkBank
							+ sparkSpin
						)
					);

				cinematicSpark:PivotTo(
					sparkWorldCFrame
				);
			end;

			-------------------------------------------------
			-- PHASE 3: COMPLETE
			-------------------------------------------------

		else
			if renderConnection then
				renderConnection:Disconnect();
				renderConnection = nil;
			end;

			blur:Destroy();
			cloudGui:Destroy();

			-------------------------------------------------
			-- FINAL HANDOFF CUE
			-------------------------------------------------

			if not hasPlayedFinalHandoffSound then
				hasPlayedFinalHandoffSound = true;

				finalHandoffSound:Stop();
				finalHandoffSound.TimePosition = 0;
				finalHandoffSound:Play();
			end;

			-------------------------------------------------
			-- RETURN CAMERA BEHIND CHARACTER
			-------------------------------------------------

			local finalTargetCFrame: CFrame = rootPart.CFrame * CFrame.new(cfg.TargetOffset);
			local finalCameraPosition: Vector3 = finalTargetCFrame.Position;
			local finalLookAt: Vector3 = rootPart.Position + Vector3.new(0, 1.5, 0);

			camera.CameraSubject = humanoid;
			camera.CFrame = CFrame.lookAt(finalCameraPosition, finalLookAt);
			camera.FieldOfView = cfg.EndFov;
			camera.CameraType = Enum.CameraType.Custom;

			-------------------------------------------------
			-- SPARK HANDOFF
			-------------------------------------------------

			if cinematicSpark
				and cinematicSpark.Parent
				and gameplaySpark
				and gameplaySpark.Parent
			then
				cinematicSpark:PivotTo(
					gameplaySpark:GetPivot()
				);
			end;

			sparkCameraHandoffEvent:Fire();

			if cinematicSpark then
				cinematicSpark:Destroy();
				cinematicSpark = nil;
			end;

			-------------------------------------------------
			-- SOUND CLEANUP
			-------------------------------------------------

			if cameraMovementSound.IsPlaying then
				cameraMovementSound.Ended:Once(function()
					cameraMovementSound:Destroy();
				end);
			else
				cameraMovementSound:Destroy();
			end;

			if extraCameraMovementSound.IsPlaying then
				extraCameraMovementSound.Ended:Once(function()
					extraCameraMovementSound:Destroy();
				end);
			else
				extraCameraMovementSound:Destroy();
			end;

			flightSound:Stop();
			flightSound:Destroy();

			if finalHandoffSound.IsPlaying then
				finalHandoffSound.Ended:Once(function()
					finalHandoffSound:Destroy();
				end);
			else
				finalHandoffSound:Destroy();
			end;

			-------------------------------------------------
			-- SERVER UNLOCK
			-------------------------------------------------

			task.spawn(function()
				local remote: RemoteFunction = getTransitionRemote();
				local canUnlock: boolean = remote:InvokeServer("TransitionFinished") == true;

				if canUnlock then
					localPlayer:SetAttribute(
						SPARK_INITIAL_LOAD_COMPLETE_ATTRIBUTE,
						true
					);

					setCharacterControlsEnabled(localPlayer, true);
				end;

				self._isTransitioning = false;

				if onCompleteCallback then
					onCompleteCallback();
				end;
			end);
		end;
	end);

	return true;
end;

return SparkCameraModule;
