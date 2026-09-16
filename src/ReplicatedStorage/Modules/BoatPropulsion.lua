--!strict

-- Force-only helper owned/ticked/cleaned up by WaterInteractionController.
-- No input bindings, water queries, ownership changes or update connections.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BoatConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BoatConfig"))

local BoatPropulsion = {}
export type State = {
	force: VectorForce,
	torque: Torque,
	throttle: number,
	steer: number,
}

local function finite(n: number): boolean
	return n == n and math.abs(n) < math.huge
end

local function setting(config: { [string]: number }, key: string, low: number, high: number): number
	local value = config[key]
	if not finite(value) then value = BoatConfig.Default[key] end
	return math.clamp(value, low, high)
end

function BoatPropulsion.Create(root: BasePart, attachment: Attachment): State
	local force = Instance.new("VectorForce")
	force.Name = "BoatPropulsionForce"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = root
	local torque = Instance.new("Torque")
	torque.Name = "BoatSteeringTorque"
	torque.Attachment0 = attachment
	torque.RelativeTo = Enum.ActuatorRelativeTo.World
	torque.Torque = Vector3.zero
	torque.Parent = root
	return { force = force, torque = torque, throttle = 0, steer = 0 }
end

function BoatPropulsion.Stop(state: State)
	state.force.Force = Vector3.zero
	state.torque.Torque = Vector3.zero
	state.throttle = 0
	state.steer = 0
end

function BoatPropulsion.Destroy(state: State)
	BoatPropulsion.Stop(state)
	state.force:Destroy()
	state.torque:Destroy()
end

function BoatPropulsion.Update(state: State, boat: Instance, root: BasePart, seat: VehicleSeat,
	attachment: Attachment, up: Vector3, dt: number)
	assert(state.force.Parent == root and state.torque.Parent == root
		and state.force.Enabled and state.torque.Enabled
		and state.force.Attachment0 == attachment and state.torque.Attachment0 == attachment,
		"boat propulsion helper missing or disabled")
	if root.Anchored or not finite(dt) or dt <= 0 then BoatPropulsion.Stop(state); return end
	local mass = root.AssemblyMass
	local velocity = root.AssemblyLinearVelocity
	local angularVelocity = root.AssemblyAngularVelocity
	assert(finite(mass) and mass > 0 and finite(velocity.Magnitude) and finite(angularVelocity.Magnitude),
		"invalid propulsion assembly mass/velocity")
	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 0.001 then BoatPropulsion.Stop(state); return end
	forward = forward.Unit
	local right = forward:Cross(Vector3.yAxis)
	local config = BoatConfig.Resolve(boat)
	local throttle = if finite(seat.ThrottleFloat) then math.clamp(seat.ThrottleFloat, -1, 1) else 0
	local steer = if finite(seat.SteerFloat) then math.clamp(seat.SteerFloat, -1, 1) else 0
	local response = setting(config, "DriveResponse", 0.1, 20)
	local steeringResponse = setting(config, "SteeringResponse", 0.1, 20)
	-- Bound a long frame's input jump; normal response is frame-rate independent.
	local step = math.min(dt, 0.1)
	state.throttle += (throttle - state.throttle) * (1 - math.exp(-response * step))
	state.steer += (steer - state.steer) * (1 - math.exp(-steeringResponse * step))
	local forwardSpeed = velocity:Dot(forward)
	local lateralSpeed = velocity:Dot(right)
	local direction = if state.throttle < 0 then -1 else 1
	local maximumSpeed = setting(config, if direction > 0 then "MaxForwardSpeed" else "MaxReverseSpeed", 0.1, 150)
	local acceleration = setting(config, if direction > 0 then "ForwardAcceleration" else "ReverseAcceleration", 0, 100)
	-- Opposite input brakes at full authority; taper only when already moving
	-- in the requested direction. No velocity assignment or hard stop.
	local available = 1 - math.clamp(forwardSpeed * direction / maximumSpeed, 0, 1)
	local drag = setting(config, if math.abs(throttle) > 0.01 then "ForwardDrag" else "IdleDrag", 0, 10)
	local planarAcceleration = forward * (state.throttle * acceleration * available - forwardSpeed * drag)
		- right * lateralSpeed * setting(config, "SideCatch", 0, 10)
	local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontalVelocity.Magnitude
	local limit = setting(config, "MaxHorizontalSpeed", 1, 200)
	if speed > limit then
		planarAcceleration -= horizontalVelocity.Unit * (speed - limit) * response
	end
	local maxAcceleration = setting(config, "SpeedGainLimit", 1, 150)
	if planarAcceleration.Magnitude > maxAcceleration then
		planarAcceleration = planarAcceleration.Unit * maxAcceleration
	end
	state.force.Force = planarAcceleration * mass

	local authority = math.clamp(math.abs(forwardSpeed) / setting(config, "SteeringFullAuthoritySpeed", 0.1, 100),
		setting(config, "MinimumSteeringAuthority", 0, 1), 1)
	local reverse = if math.abs(forwardSpeed) > 0.5 then forwardSpeed < 0 else state.throttle < -0.01
	-- Positive SteerFloat turns right. Positive torque about up turns left.
	local targetYawRate = -state.steer * setting(config, "TurnRate", 0, math.pi) * authority * (if reverse then -1 else 1)
	local maxYawAcceleration = setting(config, "SteeringStrength", 0, 10)
	local yawAcceleration = math.clamp((targetYawRate - angularVelocity:Dot(up)) * steeringResponse,
		-maxYawAcceleration, maxYawAcceleration)
	-- Rectangular hull inertia estimate makes tuning scale with hull dimensions
	-- and mass. Torque acts only about the same up axis buoyancy aligns.
	local yawInertia = mass * (root.Size.X * root.Size.X + root.Size.Z * root.Size.Z) / 12
	state.torque.Torque = up * yawInertia * yawAcceleration
	boat:SetAttribute("BoatConsumedSteerFloat", steer)
	boat:SetAttribute("BoatConsumedThrottleFloat", throttle)
end

return BoatPropulsion
