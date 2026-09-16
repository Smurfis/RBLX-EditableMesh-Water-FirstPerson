-- Executes the real controller with mocked Roblox objects and vector/CFrame
-- math. Validates dispatch/sampling/forces; does not emulate Roblox physics.
local function signal()
	local callbacks = {}
	return { Connect = function(_, f) table.insert(callbacks, f) end,
		Fire = function(_, ...) for _, f in callbacks do f(...) end end }
end
local vectors = {}
vectors.__index = function(v, key)
	if key == "Magnitude" then return math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z) end
	if key == "Unit" then return v / v.Magnitude end
	return vectors[key]
end
local Vector3 = {}
function Vector3.new(x, y, z) return setmetatable({X=x, Y=y, Z=z}, vectors) end
function vectors.__add(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
function vectors.__sub(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
function vectors.__unm(a) return a * -1 end
function vectors.__mul(a,b) if type(a)=="number" then a,b=b,a end return Vector3.new(a.X*b,a.Y*b,a.Z*b) end
function vectors.__div(a,b) return a * (1/b) end
function vectors:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function vectors:Cross(b) return Vector3.new(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
function vectors:Lerp(b,t) return self+(b-self)*t end
Vector3.zero = Vector3.new(0,0,0); Vector3.yAxis = Vector3.new(0,1,0)
local Vector2 = {new=function(x,z) return Vector3.new(x,0,z) end}
local frames = {}; frames.__index = frames
local builtinTypeof = typeof
local function typeof(value)
	if getmetatable(value) == frames then return "CFrame" end
	return builtinTypeof(value)
end
local CFrame = {}
local function frame(p,x,y,z)
	local f=setmetatable({Position=p,RightVector=x,UpVector=y,LookVector=-z},frames)
	f.Rotation=setmetatable({Position=Vector3.zero,RightVector=x,UpVector=y,LookVector=-z},frames)
	return f
end
function CFrame.new(x,y,z)
	return frame(if type(x)=="table" then x else Vector3.new(x or 0,y or 0,z or 0),Vector3.new(1,0,0),Vector3.yAxis,Vector3.new(0,0,1))
end
function frames:VectorToWorldSpace(v) return self.RightVector*v.X+self.UpVector*v.Y-self.LookVector*v.Z end
function frames:PointToWorldSpace(v) return self.Position+self:VectorToWorldSpace(v) end
function frames:VectorToObjectSpace(v) return Vector3.new(v:Dot(self.RightVector),v:Dot(self.UpVector),v:Dot(-self.LookVector)) end
function frames:ToOrientation() return 0,math.atan2(-self.LookVector.X,-self.LookVector.Z),0 end
function frames:Inverse()
	local x,y,z=self.RightVector,self.UpVector,-self.LookVector
	return frame(-self:VectorToObjectSpace(self.Position),Vector3.new(x.X,y.X,z.X),Vector3.new(x.Y,y.Y,z.Y),Vector3.new(x.Z,y.Z,z.Z))
end
function frames.__mul(a,b) return frame(a:PointToWorldSpace(b.Position),a:VectorToWorldSpace(b.RightVector),a:VectorToWorldSpace(b.UpVector),-a:VectorToWorldSpace(b.LookVector)) end
function frames:Lerp(b,t) return frame(self.Position:Lerp(b.Position,t),self.RightVector:Lerp(b.RightVector,t),self.UpVector:Lerp(b.UpVector,t),-self.LookVector:Lerp(b.LookVector,t)) end
function CFrame.Angles(x,y,z)
	local sx,cx,sy,cy,sz,cz=math.sin(x),math.cos(x),math.sin(y),math.cos(y),math.sin(z),math.cos(z)
	return frame(Vector3.zero,Vector3.new(cy*cz,cx*sz+sx*sy*cz,sx*sz-cx*sy*cz),Vector3.new(-cy*sz,cx*cz-sx*sy*sz,sx*cz+cx*sy*sz),Vector3.new(sy,-sx*cy,cx*cy))
end
function CFrame.lookAt(p,target,up)
	local z=(p-target).Unit; local x=up:Cross(z).Unit
	return frame(p,x,z:Cross(x),z)
end
local nodes = {}
local function node(class,name,parent)
	local o={ClassName=class,Name=name,Parent=parent,attrs={},Enabled=true}
	table.insert(nodes,o)
	function o:IsA(c) return c==self.ClassName or (c=="BasePart" and (class=="MeshPart" or class=="VehicleSeat")) end
	function o:FindFirstChild(n,recursive)
		for _, v in nodes do
			if v.Name~=n then continue end
			local cursor=v.Parent
			while cursor do
				if cursor==self then return v end
				if not recursive then break end
				cursor=cursor.Parent
			end
		end
		return nil
	end
	function o:FindFirstChildOfClass(c) for _,v in nodes do if v.Parent==self and v.ClassName==c then return v end end return nil end
	function o:WaitForChild(n) return assert(self:FindFirstChild(n),n) end
	function o:GetAttribute(k) return self.attrs[k] end
	function o:SetAttribute(k,v) self.attrs[k]=v end
	function o:GetFullName() return self.Name end
	function o:Destroy() self.Parent=nil end
	return o
end
local Instance = {new=function(c) return node(c,c) end}
local Enum = {ActuatorRelativeTo={World="World"},OrientationAlignmentMode={OneAttachment="OneAttachment"},AlignType={PrimaryAxisParallel="PrimaryAxisParallel"},RenderPriority={Camera={Value=200}}}
local storage=node("Folder","ReplicatedStorage")
local modules=node("Folder","Modules",storage)
node("ModuleScript","WaterConfig",modules); node("ModuleScript","WaterWaveSampler",modules)
node("ModuleScript","BoatConfig",modules); node("ModuleScript","BoatPropulsion",modules)
local remote=node("RemoteEvent","BoatDynamicReady",storage)
local messages={}
function remote:FireServer(...) table.insert(messages,{...}) end
local workspace=node("Workspace","workspace"); workspace.Gravity=196.2
local folder=node("Folder","Boats",workspace)
workspace.CurrentCamera={CFrame=CFrame.new(0,10,0)}
local player={UserId=10,Character=node("Model","Character",workspace)}
local humanoid=node("Humanoid","Humanoid",player.Character); humanoid.Health=100
local added,removed=signal(),signal()
local pre=signal(); local render
local preFire = pre.Fire
function pre:Fire(dt) preFire(self, dt or 1/60) end
local services={Players={LocalPlayer=player},ReplicatedStorage=storage,
	RunService={PreSimulation=pre,BindToRenderStep=function(_,_,_,f) render=f end},
	CollectionService={GetTagged=function() return {} end,HasTag=function(_,o) return o.tagged end,
		GetInstanceAddedSignal=function() return added end,GetInstanceRemovedSignal=function() return removed end}}
local game={GetService=function(_,n) return services[n] end}
local clock=0; local os={clock=function() return clock end}
local task={delay=function() end}
local warnings={}; local function warn(m) table.insert(warnings,m) end
local sampled={}
local function heightAt(x,z) return .001*x*x + .02*z end
local BoatConfig = (function()
--[[BOAT_CONFIG_SOURCE]]
end)()
local Propulsion
local function require(module)
	if module.Name=="BoatConfig" then return BoatConfig end
	if module.Name=="BoatPropulsion" then return Propulsion end
	if module.Name=="WaterConfig" then return {GetSurfaceY=function() return 6 end} end
	assert(module.Name=="WaterWaveSampler", "unexpected ocean dependency")
	return {GetTime=function() return 12 end,Sample=function(x,z,time,octaves)
		table.insert(sampled,{x=x,z=z,time=time,octaves=octaves})
		return {Height=heightAt(x,z),Normal=Vector3.yAxis,Displacement=Vector3.zero}
	end}
end
Propulsion = (function()
--[[PROPULSION_SOURCE]]
end)();
(function()
--[[CONTROLLER_SOURCE]]
end)()

local boat=node("Model","SmallBoat",folder); boat.tagged=true
boat:SetAttribute("WaterProfile","Boat"); boat:SetAttribute("WaterDynamicPhysics",true)
boat:SetAttribute("WaterVerticalOffset",4.5); boat:SetAttribute("WaterBuoyancyStrength",2)
boat:SetAttribute("WaterRotationStrength",.4); boat:SetAttribute("WaterSampleCount",1)
local deck=node("Model","Deck",boat)
local root=node("MeshPart","BoatRoot",deck)
root.Size=Vector3.new(8,2,20); root.Anchored=true; root.AssemblyMass=math.huge
root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyRootPart=root
root.AssemblyAngularVelocity=Vector3.zero
function root:GetMass() return 50 end
function root:GetConnectedParts() return {} end
local function place(x,y,z,yaw)
	root.CFrame=CFrame.new(x,y,z)*CFrame.Angles(.1,yaw,.05); root.Position=root.CFrame.Position
end
place(10,12,30,math.pi/2)
boat.pivots=0
function boat:GetExtentsSize() error("Boat must never sample Model:GetExtentsSize") end
function boat:GetPivot() return root.CFrame end
function boat:PivotTo(cf) self.pivots+=1; root.CFrame=cf; root.Position=cf.Position end
local seat=node("VehicleSeat","BoatSeat",deck)
seat.Disabled=false; seat.SteerFloat=.5; seat.ThrottleFloat=1
boat.PrimaryPart=seat -- intentional wrong primary: BoatRoot must win
local function checkSamples(cf)
	assert(#sampled==6,"Boat must sample six points despite WaterSampleCount override")
	local offsets={Vector3.new(-3.2,0,-8),Vector3.new(3.2,0,-8),Vector3.new(-3.2,0,0),Vector3.new(3.2,0,0),Vector3.new(-3.2,0,8),Vector3.new(3.2,0,8)}
	local average=0
	for i,p in sampled do
		local expected=cf:PointToWorldSpace(offsets[i])
		assert(math.abs(p.x-expected.X)<1e-6 and math.abs(p.z-expected.Z)<1e-6,"wrong hull footprint")
		assert(p.time==12 and p.octaves==6,"lost Boat wave settings")
		average+=heightAt(p.x,p.z)/6
	end
	return average
end
added:Fire(boat)
local before=root.CFrame
render(1/30)
local avg=checkSamples(before)
local expectedY=12+(6+avg*2+4.5-12)*(1-math.exp(-7/30))
assert(math.abs(root.Position.Y-expectedY)<1e-6,"kinematic target lost six-point average or offsets")

seat.Occupant=humanoid; humanoid.SeatPart=seat
boat:SetAttribute("BoatPhysicsMode","DYNAMIC_PREPARING"); boat:SetAttribute("BoatDynamicSession",1)
sampled={}; pre:Fire()
assert(#messages==1 and messages[1][3]=="Ready","ready handshake missing")
local force=root:FindFirstChild("BoatDynamicBuoyancyForce")
local align=root:FindFirstChild("BoatDynamicAlignOrientation")
assert(force and force.Force.Y<math.huge and force.Force.Y>0,"anchored mass must not produce infinite force")
assert(force.ApplyAtCenterOfMass and align.AlignType=="PrimaryAxisParallel")
local pivots=boat.pivots; render(1/30); assert(boat.pivots==pivots,"PivotTo during preparation")

root.Anchored=false; root.AssemblyMass=50
boat:SetAttribute("BoatPhysicsMode","DYNAMIC_DRIVING"); boat:SetAttribute("BoatDynamicDriverUserId",10)
workspace.CurrentCamera=nil -- buoyancy must not depend on camera availability
place(100,12,-80,-1); sampled={}; pre:Fire()
avg=checkSamples(root.CFrame)
local target=6+avg*2+4.5
local expectedForce=50*math.clamp(196.2+(target-12)*14,0,196.2*2.5)
assert(math.abs(force.Force.Y-expectedForce)<1e-6,"wrong gravity cancellation/spring")
assert(force.Force.X==0 and force.Force.Z==0,"propulsion modified buoyancy force")
render(1/30); assert(boat.pivots==pivots,"PivotTo while driving")

-- Disabling a helper must stop the session and clean up all three objects.
force.Enabled=false; pre:Fire()
assert(messages[#messages][3]=="Stop" and not force.Parent and not align.Parent)
assert(not root:FindFirstChild("BoatDynamicPhysicsAttachment"))
pre:Fire(); assert(not root:FindFirstChild("BoatDynamicBuoyancyForce"),"failed session recreated helpers")

-- Exit resumes parked bobbing at the current location, never the spawn X/Z.
root.Anchored=true; seat.Occupant=nil; humanoid.SeatPart=nil
local leftTransform = root.CFrame
boat:SetAttribute("CurrentTransform", leftTransform)
boat:SetAttribute("BoatPhysicsMode","KINEMATIC_IDLE")
workspace.CurrentCamera={CFrame=CFrame.new(100,12,-80)}
pre:Fire(); render(1/30)
assert(math.abs(root.Position.X-100)<1e-6 and math.abs(root.Position.Z+80)<1e-6)
assert(boat:GetAttribute("CurrentTransform") == leftTransform, "docked bobbing overwrote resting transform")
for i=2,11 do
	seat.Occupant=humanoid; humanoid.SeatPart=seat
	boat:SetAttribute("BoatDynamicSession",i); boat:SetAttribute("BoatPhysicsMode","DYNAMIC_PREPARING")
	clock+=1; pre:Fire()
	local helpers=0
	for _,o in nodes do if o.Parent==root then helpers+=1 end end
	assert(helpers==5,"duplicated helpers on re-entry")
	seat.Occupant=nil; humanoid.SeatPart=nil; boat:SetAttribute("BoatPhysicsMode","KINEMATIC_IDLE")
	pre:Fire(); render(1/30)
	assert(not root:FindFirstChild("BoatDynamicBuoyancyForce"),"helper leaked on exit")
end
assert(#warnings==1)
-- An observer must neither run local forces nor kinematically move a driver-owned boat.
root.Anchored=false; seat.Occupant={}; humanoid.SeatPart=nil
boat:SetAttribute("BoatPhysicsMode","DYNAMIC_DRIVING"); boat:SetAttribute("BoatDynamicDriverUserId",99)
pivots=boat.pivots; pre:Fire(); render(1/30)
assert(boat.pivots==pivots and not root:FindFirstChild("BoatDynamicBuoyancyForce"))

-- Ordinary tagged props keep their kinematic path, with no boat helper/handshake.
local prop=node("MeshPart","FloatingProp",workspace)
prop.Size=Vector3.new(2,2,2); prop.CFrame=CFrame.new(100,8,-80); prop.Position=prop.CFrame.Position
prop.tagged=true
local messageCount=#messages
added:Fire(prop); sampled={}; pre:Fire(); render(1/30)
assert(#sampled==1 and prop.CFrame.Position.Y~=8 and #messages==messageCount)
assert(not prop:FindFirstChild("BoatDynamicBuoyancyForce"))
removed:Fire(prop); sampled={}; render(1/30); assert(#sampled==0)

-- Drive the actual helper in isolation to verify signed force/torque and
-- frame-rate response without pretending these mocks simulate Roblox physics.
root.Anchored=false; root.AssemblyMass=50
place(0,12,0,0)
local attach=node("Attachment","TestAttachment",root)
local drive=Propulsion.Create(root,attach)
local function step(throttle,steer,speed,dt)
	seat.ThrottleFloat=throttle; seat.SteerFloat=steer
	local look=root.CFrame.LookVector
	local forward=Vector3.new(look.X,0,look.Z).Unit
	root.AssemblyLinearVelocity=forward*speed
	Propulsion.Update(drive,boat,root,seat,attach,Vector3.yAxis,dt or 1/60)
	assert(drive.force.Force.Y==0,"thrust/drag must never add vertical lift")
	assert(drive.torque.Torque.X==0 and drive.torque.Torque.Z==0,"steering changed pitch/roll")
	return drive.force.Force:Dot(forward),drive.torque.Torque.Y
end
local thrust=step(1,0,0)
assert(thrust>0 and thrust<50*BoatConfig.Default.ForwardAcceleration,"throttle did not ramp")
for _=1,180 do step(1,0,0) end
local full=step(1,0,0)
assert(full>thrust)
Propulsion.Stop(drive)
for _=1,180 do step(-1,0,0) end
local reverseThrust=step(-1,0,0)
assert(reverseThrust<0 and -reverseThrust<full,"reverse should be weaker")
Propulsion.Stop(drive)
assert(step(0,0,10)<0,"coasting drag must oppose movement")
assert(step(1,0,100)<0,"overspeed should brake physically")
Propulsion.Stop(drive)
for _=1,180 do step(0,1,12) end
local _,rightTurn=step(0,1,12)
assert(rightTurn<0,"positive helm input must turn right")
local _,stationaryTurn=step(0,1,0)
assert(math.abs(stationaryTurn)<math.abs(rightTurn),"too much stationary turn authority")
local _,reverseTurn=step(-1,1,-12)
assert(reverseTurn>0,"reverse steering should invert")
Propulsion.Stop(drive)
for _=1,180 do step(0,-1,12) end
local _,leftTurn=step(0,-1,12)
assert(leftTurn>0,"negative helm input must turn left")
-- Current hull heading, not world Z; rotated hull still accelerates forward.
place(0,12,0,math.pi/2); Propulsion.Stop(drive)
assert(step(1,0,0)>0 and drive.force.Force.X<0)
root.AssemblyLinearVelocity=root.CFrame.RightVector*5
seat.ThrottleFloat=0; seat.SteerFloat=0; Propulsion.Stop(drive)
Propulsion.Update(drive,boat,root,seat,attach,Vector3.yAxis,1/60)
assert(drive.force.Force:Dot(root.CFrame.RightVector)<0,"lateral resistance missing")
local tiltedUp=Vector3.new(.1,1,.1).Unit
seat.SteerFloat=1
Propulsion.Update(drive,boat,root,seat,attach,tiltedUp,1/60)
assert(drive.torque.Torque:Cross(tiltedUp).Magnitude<1e-6,"torque must follow hull-up alignment axis")
Propulsion.Stop(drive)
for _=1,30 do step(1,0,0,1/30) end
local throttle30=drive.throttle
Propulsion.Stop(drive)
for _=1,60 do step(1,0,0,1/60) end
assert(math.abs(drive.throttle-throttle30)<1e-6,"frame-rate dependent input ramp")
root.Anchored=true; step(1,1,0)
assert(drive.force.Force.Magnitude==0 and drive.torque.Torque.Magnitude==0)
Propulsion.Destroy(drive)
assert(not drive.force.Parent and not drive.torque.Parent)
print("PASS: forward/reverse ramp, coasting drag, speed resistance, signed yaw, reverse/low-speed steering, hull-relative thrust, slip catch, frame-rate response and cleanup")
print("PASS: six BoatRoot samples, kinematic formula, finite preparation, physical lift, current footprint, no competing PivotTo, failure cleanup and ten re-entries")
