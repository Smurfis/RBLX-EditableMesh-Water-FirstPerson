--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

---------------------------------------------------------
-- REMOVE DEFAULT ROBLOX LOADING SCREEN
---------------------------------------------------------

ReplicatedFirst:RemoveDefaultLoadingScreen()

---------------------------------------------------------
-- PLAYER
---------------------------------------------------------

local LocalPlayer: Player = Players.LocalPlayer

---------------------------------------------------------
-- SPARK CAMERA MODULE
---------------------------------------------------------

local Modules = ReplicatedStorage:WaitForChild("Modules") :: Folder

local SparkModulesFolder = Modules:WaitForChild("Spark") :: Folder

local SparkCameraModuleRoot = SparkModulesFolder:WaitForChild("SparkCameraModule") :: ModuleScript

local SparkCameraModule = require(SparkCameraModuleRoot)

---------------------------------------------------------
-- CAMERA TRANSITION CONFIG
---------------------------------------------------------

local ASCENT_DURATION: number = 0.9
local DESCENT_DURATION: number = 2.1

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
})

---------------------------------------------------------
-- EXECUTE SEQUENCE
---------------------------------------------------------

task.spawn(function()
	local transitionStarted: boolean = cameraEngine:Execute(function()
		print("[Client]: Spark Camera Spawn Transition Complete!")
	end)

	if not transitionStarted then
		warn("[Client]: Spark Camera Spawn Transition failed to start.")

		return
	end
end)
