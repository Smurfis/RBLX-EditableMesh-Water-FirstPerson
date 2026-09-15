--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage");
local ReplicatedFirst = game:GetService("ReplicatedFirst");
local Players = game:GetService("Players");
local TweenService = game:GetService("TweenService");

-- Nuke Roblox default UI as early as possible
ReplicatedFirst:RemoveDefaultLoadingScreen();

local LocalPlayer: Player = Players.LocalPlayer;

local SparkCameraModule = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("Spark")
		:WaitForChild("SparkCameraModule")
);

---------------------------------------------------------
-- CAMERA TRANSITION CONFIG
---------------------------------------------------------

local ASCENT_DURATION: number = 0.9;
local DESCENT_DURATION: number = 2.1;

---------------------------------------------------------
-- CAMERA ENGINE
---------------------------------------------------------

local cameraEngine = SparkCameraModule.new({
	AscentDuration = ASCENT_DURATION,
	DescentDuration = DESCENT_DURATION,

	ApexAltitude = 2000,

	StartFov = 100,
	ApexFov = 115,
	EndFov = 70,
	MaxBlur = 18,
});

---------------------------------------------------------
-- LOADING SCREEN
---------------------------------------------------------

local function hideLoadingScreen()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui;
	local loadingGui = playerGui:FindFirstChild("LoadingGui") :: ScreenGui?;

	if not loadingGui then
		return;
	end;

	local mainFrame = loadingGui:FindFirstChildOfClass("Frame") :: Frame?;

	if mainFrame then
		local fade: Tween = TweenService:Create(
			mainFrame,
			TweenInfo.new(0.6),
			{
				BackgroundTransparency = 1,
			}
		);

		fade:Play();
		fade.Completed:Wait();
	end;

	loadingGui.Enabled = false;
end;

---------------------------------------------------------
-- EXECUTE SEQUENCE
---------------------------------------------------------

task.spawn(function()
	local transitionStarted: boolean = cameraEngine:Execute(function()
		print("[Client]: Spark Camera Spawn Transition Complete!");
		task.spawn(hideLoadingScreen);
	end);

	if not transitionStarted then
		warn("[Client]: Spark Camera Spawn Transition failed to start.");
		return;
	end;

end);
