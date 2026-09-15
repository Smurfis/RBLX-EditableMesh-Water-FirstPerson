local event = game.ReplicatedStorage.Look
local lookVector = Vector3.zero
local eventTime = -math.huge
local scheduleEvent = false

workspace.CurrentCamera:GetPropertyChangedSignal("CFrame"):Connect(function()
	game.Players.LocalPlayer:SetAttribute("LooKVector", workspace.CurrentCamera.CFrame.LookVector)
	if scheduleEvent == true then return end
	if workspace.CurrentCamera.CFrame.LookVector:Dot(lookVector) > 0.99 then return end
	local deltaTime = time() - eventTime
	if deltaTime > 0.1 then
		eventTime = time()
		lookVector = workspace.CurrentCamera.CFrame.LookVector
		event:FireServer(lookVector)
	else
		scheduleEvent = true
		task.wait(0.1 - deltaTime)
		scheduleEvent = false
		eventTime = time()
		lookVector = workspace.CurrentCamera.CFrame.LookVector
		event:FireServer(lookVector)
	end
end)