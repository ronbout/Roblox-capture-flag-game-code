local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local GROUND_WAIT = 0.01
local VELOCITY_MULTIPLIER = 0.0625
local DEFAULT_PROGRESS_TIME_LIMIT = 5
local DEFAULT_PROGRESS_DISTANCE_LIMIT = 2

local Pathfinding = {}

Pathfinding.__index = Pathfinding

local DEFAULT_NPC_PARAMS = {
	AgentRadius = 2,
	AgentHeight = 5.46,
	AgentCanJump = false,
	AgentCanClimb = true,
}

-------------------------
-- Local helper functions
-------------------------

local function waitForGround(self)
	while self.humanoid.FloorMaterial == Enum.Material.Air do
		if self.humanoid.Sit then
			self.humanoid.Sit = false
		end
		task.wait(GROUND_WAIT)
	end
end

local function calcPath(self)
	-- Compute the path
	waitForGround(self)

	local success, _errorMessage = pcall(function()
		self.path:ComputeAsync(self.character.PrimaryPart.Position, self.targetPosition)
	end)
	if not success or self.path.Status ~= Enum.PathStatus.Success then
		return Enum.PathStatus.NoPath
	end
	return Enum.PathStatus.Success
end

-- CONSTRUCTOR
function Pathfinding.new(character, targetPosition, options)
	local self = setmetatable({}, Pathfinding)

	self.character = character
	self.humanoid = character:WaitForChild("Humanoid")
	self.humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	self.targetPosition = targetPosition
	self.options = options or {}

	self.debugFlag = options.debugFlag and options.debugFlag == true or false
	-- blocked event flag sets up an event to fire when the path is blocked rather than auto recalc
	self.blockedEventFlag = options.blockedEventFlag and options.blockedEventFlag == true or false
	self.npcParams = options.npcParams or DEFAULT_NPC_PARAMS
	self.progressTimeLimit = options.progressTimeLimit or DEFAULT_PROGRESS_TIME_LIMIT
	self.progressDistanceLimit = options.progressDistanceLimit or DEFAULT_PROGRESS_DISTANCE_LIMIT
	self.shouldAbort = options.shouldAbort or nil
	self.debugColor = options.debugColor or Color3.new(1, 0, 1)

	self.abort = false

	self.path = PathfindingService:CreatePath(self.npcParams)
	self.pathStatus = calcPath(self)

	self.waypoints = {}
	self.nextWaypointIndex = nil
	self.blockedConnection = nil
	self.currentWaypointReachedConnection = nil
	self.currentWaypointPlaneNormal = Vector3.zero
	self.currentWaypointPlaneDistance = 0

	-- will be used to make sure the NPC is making progress
	self.progressOrigDist = 0
	self.progressOrigTime = 0

	self.waypointsFolder = Instance.new("Folder")
	self.waypointsFolder.Parent = workspace

	self._onCompleteEvent = Instance.new("BindableEvent")
	self.OnComplete = self._onCompleteEvent.Event

	self._onNoProgressEvent = Instance.new("BindableEvent")
	self.OnNoProgress = self._onNoProgressEvent.Event

	self._onAbortEvent = Instance.new("BindableEvent")
	self.OnAbort = self._onAbortEvent.Event

	if self.blockedEventFlag then
		self._onBlockedEvent = Instance.new("BindableEvent")
		self.OnBlocked = self._onBlockedEvent.Event
	end

	return self
end

--local pathfinderWorking = false

local function disconnectCurrentWaypointReachedConnection(self)
	if not self.currentWaypointReachedConnection then
		return
	end
	self.currentWaypointReachedConnection:Disconnect()
	self.currentWaypointReachedConnection = nil
end

local function isCurrentWaypointReached(self, delta)
	if self.shouldAbort and self.shouldAbort() then
		resetWaypointData(self)
		self.waypoints = {}
		self.abort = true
		self._onAbortEvent:Fire()
		return true
	end

	if self.humanoid.FloorMaterial == Enum.Material.Air then
		if self.humanoid.Sit then
			self.humanoid.Sit = false
		end
		return false
	end

	local dist

	local reached = false
	if self.currentWaypointPlaneNormal ~= Vector3.zero then
		-- Compute the distance from humanoid to destination plane
		dist = self.currentWaypointPlaneNormal:Dot(self.humanoid.RootPart.Position) - self.currentWaypointPlaneDistance
		-- Compute the component of the humanoid velocity that is towards the plane
		local velocity = -self.currentWaypointPlaneNormal:Dot(self.humanoid.RootPart.AssemblyLinearVelocity)
		-- Compute the threshold from the destination plane based on humanoid velocity
		local threshold = math.max(1.0, VELOCITY_MULTIPLIER * velocity)
		-- Consider waypoint reached if less then threshold in front of the plane
		reached = dist < threshold
	else
		reached = true
	end

	if reached then
		self.currentWaypointPlaneNormal = Vector3.zero
		self.currentWaypointPlaneDistance = 0
		self.progressOrigDist = 0
		self.progressOrigTime = 0
		moveToNextWaypoint(self)
	else
		-- check for progress by comparing dist with previous distance and delta with previous delta
		--warn (self.progressOrigTime, delta, self.progressOrigDist, dist)
		self.progressOrigTime += delta
		if self.progressOrigTime >= self.progressTimeLimit then
			if self.progressOrigDist - dist < self.progressDistanceLimit then
				-- TODO: implement a "insufficient progress" routine
				warn(
					self.character.Name .. " is not making progress. Dist: ",
					self.progressOrigDist - dist,
					"  Time: ",
					self.progressOrigTime
				)
				self._onNoProgressEvent:Fire()
			else
				-- reset progress time
				self.progressOrigDist = dist
				self.progressOrigTime = 0
			end
		else
			-- if the distance has already been covered, start time over
			if self.progressOrigDist - dist >= self.progressDistanceLimit then
				self.progressOrigDist = dist
				self.progressOrigTime = 0
			end
		end
	end
	return reached
end

local function calculateNextWaypointApproach(self)
	if self.abort then
		return
	end
	self.nextWaypointIndex += 1
	if self.nextWaypointIndex > #self.waypoints then
		print("fire onComplete Event")
		self._onCompleteEvent:Fire()
		return false
	end
	local currentWaypoint = self.waypoints[self.nextWaypointIndex - 1]
	local nextWaypoint = self.waypoints[self.nextWaypointIndex]
	-- Build destination plane from next waypoint towards current one
	self.currentWaypointPlaneNormal = currentWaypoint.Position - nextWaypoint.Position
	-- Set normal perpendicular to Y plane when not climbing up
	if nextWaypoint.Label ~= "Climb" then
		self.currentWaypointPlaneNormal =
			Vector3.new(self.currentWaypointPlaneNormal.X, 0, self.currentWaypointPlaneNormal.Z)
	end
	if self.currentWaypointPlaneNormal.Magnitude > 0.000001 then
		self.currentWaypointPlaneNormal = self.currentWaypointPlaneNormal.Unit
		self.currentWaypointPlaneDistance = self.currentWaypointPlaneNormal:Dot(nextWaypoint.Position)
		self.progressOrigDist = self.currentWaypointPlaneNormal:Dot(self.humanoid.RootPart.Position)
			- self.currentWaypointPlaneDistance
		self.progressOrigTime = 0
	end

	return true
end

function resetWaypointData(self)
	self.humanoid:Move(Vector3.zero)
	self.currentWaypointPlaneNormal = Vector3.zero
	self.currentWaypointPlaneDistance = 0
	self.progressOrigDist = 0
	self.progressOrigTime = 0
	disconnectCurrentWaypointReachedConnection(self)
	--pathfinderWorking = false
	self.waypointsFolder:ClearAllChildren()
end

function moveToNextWaypoint(self)
	if self.abort then
		return
	end
	if calculateNextWaypointApproach(self) then
		disconnectCurrentWaypointReachedConnection(self)
		self.currentWaypointReachedConnection = RunService.Heartbeat:Connect(function(delta)
			isCurrentWaypointReached(self, delta)
		end)
		local nextWaypointPosition = self.waypoints[self.nextWaypointIndex].Position
		local nextWaypointAction = self.waypoints[self.nextWaypointIndex].Action
		self.humanoid:Move(nextWaypointPosition - self.humanoid.RootPart.Position)
		--print("Moving to waypoint " .. self.nextWaypointIndex, nextWaypointPosition, nextWaypointAction)
		if
			self.waypoints[self.nextWaypointIndex + 1]
			and self.waypoints[self.nextWaypointIndex + 1].Label == "UseBoat"
		then
			self.nextWaypointIndex += 1
			-- Call your own customized function to make agent use the boat
		elseif nextWaypointAction == Enum.PathWaypointAction.Jump then
			self.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			while self.humanoid.FloorMaterial ~= Enum.Material.Air do
				task.wait(GROUND_WAIT)
			end
			print(
				"moveToNextWaypoint after Jump: ",
				nextWaypointPosition,
				self.nextWaypointIndex,
				self.humanoid.RootPart.Position
			)
			self.humanoid:Move(nextWaypointPosition - self.humanoid.RootPart.Position)
		end
	else
		resetWaypointData(self)
	end
end

local function findStartingPoint(self)
	if self.abort then
		return
	end
	self.nextWaypointIndex = 1
	while self.nextWaypointIndex + 1 <= #self.waypoints do
		local dist = self.waypoints[self.nextWaypointIndex + 1].Position - self.humanoid.RootPart.Position
		dist = Vector3.new(dist.X, 0, dist.Z)
		if dist.magnitude >= 2 then
			return
		end
		self.nextWaypointIndex += 1
	end
end

local function drawDebugPath(self)
	for _, waypoint in self.waypoints do
		local part = Instance.new("Part")
		part.Position = waypoint.Position
		part.Size = Vector3.new(0.5, 0.5, 0.5)
		part.Color = self.debugColor
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.5
		part.Parent = self.waypointsFolder
	end
end

local function followPath(self)
	if self.abort then
		return
	end
	-- Get the path waypoints
	self.waypoints = self.path:GetWaypoints()

	if self.debugFlag == true then
		drawDebugPath(self)
	end

	--print ("Path computed successfully with " .. #self.waypoints .. " waypoints")

	-- Detect if path becomes blocked
	self.blockedConnection = self.path.Blocked:Connect(function(blockedWaypointIndex)
		print("blocked at waypoint " .. blockedWaypointIndex)
		-- Check if the obstacle is further down the path
		if blockedWaypointIndex >= self.nextWaypointIndex then
			if self.blockedEventFlag then
				self._onBlockedEvent:Fire({
					blockedNdx = blockedWaypointIndex,
					nextWaypointNdx = self.nextWaypointIndex,
				})
			else
				-- Stop detecting path blockage until path is re-computed
				print("within pathfinding blocked and rerouting")
				self.blockedConnection:Disconnect()
				resetWaypointData(self)
				-- Call function to re-compute new path
				self.pathStatus = calcPath(self)
				followPath(self)
			end
		end
	end)

	findStartingPoint(self)
	moveToNextWaypoint(self)
end

function Pathfinding:GetPath()
	return self.path
end

function Pathfinding:StartPath()
	if self.pathStatus ~= Enum.PathStatus.Success then
		warn("Cannot follow unsuccessful path")
		return false
	end
	followPath(self)
	return true
end

function Pathfinding:Destroy()
	resetWaypointData(self)
	self.waypointsFolder:Destroy()
	if self._onCompleteEvent then
		self._onCompleteEvent:Destroy()
	end
	if self._onNoProgressEvent then
		self._onNoProgressEvent:Destroy()
	end
	if self._onBlockedEvent then
		self._onBlockedEvent:Destroy()
	end
	if self._onAbortEvent then
		self._onAbortEvent:Destroy()
	end
end

return Pathfinding
