local activeMap = workspace:WaitForChild("ActiveMap")

-- Level 3 Guard: Walks between flags, and attacks the player if they get too close.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameInfo = ReplicatedStorage:WaitForChild("GameInfo")
local GameParameters = require(GameInfo.GameParameters)

local SimpleStateMachine = require(ReplicatedStorage.Shared.SimpleStateMachine)
local Idle = require(ReplicatedStorage.Shared["Guard Script"].States.Idle)
local WalkToRandomFlag = require(ReplicatedStorage.Shared["Guard Script"].States.WalkToRandomFlag)
local Attack = require(ReplicatedStorage.Shared["Guard Script"].States.Attack)
local Chase = require(ReplicatedStorage.Shared["Guard Script"].States.Chase)

-- Types.
type Context = SimpleStateMachine.Context
type StateMachine = SimpleStateMachine.StateMachine

-- Constants.
local CLOSE_TO_FLAG_DISTANCE = 7
local IDLE_DURATION = 1
local CHASE_RANGE = script.Parent:GetAttribute("DetectionDistance")
local ATTACK_RANGE = 10

local character = script.Parent
local humanoid = script.Parent:FindFirstChildOfClass("Humanoid") :: Humanoid
local humanoidRootPart = script.Parent:WaitForChild("HumanoidRootPart")
--humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)

-- Check if the NPC is near the target flag.
local function isNearTargetFlag(context: Context): boolean
	local char = context.character :: Model
	local characterPosition = char:GetPivot().Position
	local flagPosition = context.targetFlag:GetPivot().Position :: Vector3
	-- need to equalize Y as the flag is taller than the person, but we don't care about that distance
	flagPosition = Vector3.new(flagPosition.X, characterPosition.Y, flagPosition.Z)
	local distance = (characterPosition - flagPosition).Magnitude
	--print ("Is near target flag distance: ", distance)
	--print ("character position: ", characterPosition)
	--print ("flag position: ", flagPosition)
	return distance <= CLOSE_TO_FLAG_DISTANCE
end

-- Check if the idle timer has elapsed.
local function isIdleTimerDone(context: Context): boolean
	return os.clock() - context.idleStartTime >= IDLE_DURATION
end

local function visualizeRay(context: Context, origin: Vector3, endPosition: Vector3, color: Color3)
	local distance = (endPosition - origin).Magnitude

	-- Create the visual part
	local part = character:WaitForChild("RayVisual" .. context.character.Name) :: Part
	part.Material = Enum.Material.Neon -- Makes it glow nicely
	part.Color = color
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(0.3, 0.3, distance)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 0

	-- Position it right in the middle, facing the origin
	part.CFrame = CFrame.lookAt(origin + (endPosition - origin) / 2, origin)
	--part.Parent = activeMap

	-- Remove it after 0.2 seconds
	task.delay(0.2, function()
		part.Transparency = 1
		--part.CFrame = CFrame.new(0, -1000, 0) -- Move it off-screen
		--part.Parent = character
		--part:Destroy()
	end)
end

-- Check if a player is within detection range.
local function isPlayerNearby(context: Context, detection_range: number, checkYAxis: boolean): boolean
	local char = context.character :: Model
	local characterPosition = char:GetPivot().Position
	local isChasing = character:GetAttribute("IsChasing")
	--print ("isChasing: ", isChasing)
	-- isChasing is set while pathfinding.  I don't want to stop the pathfinding if the player suddenly
	-- ducks out of sight.  The guard should still go to the position.
	-- BUT... this cannot be used for the attack test, so checkYAxis is only used for attack test
	if isChasing and not checkYAxis then
		return true
	end

	local nearbyPlayer = nil
	local nearestDistance = detection_range

	for _, player in Players:GetPlayers() do
		local playerCharacter = player.Character :: Model
		if not playerCharacter then
			continue
		end
		if not player:GetAttribute("ready") then
			return
		end
		local plrHumanoid = playerCharacter:FindFirstChild("Humanoid") :: Humanoid
		if plrHumanoid and plrHumanoid.Health > 0 and playerCharacter:FindFirstChild("HumanoidRootPart") then
			local playerPosition = playerCharacter:GetPivot().Position
			if checkYAxis then
				--[[
				
				TODO:	Instead of just checking Y position, use a downward raycast to see if the humanoid(s) 
						have jumped or are falling and will hit the ground soon.  Use the floor position for the
						Y comparison.
						
						If there is a floor position that is different than the humanoid Y position, the test for 
						distance should be done using the floor position
						
						Adjust the character Position to use the floor Y position for the distance calculation
				
				]]

				--print ('player Y: ', playerPosition.Y)
				--print ('character Y: ', characterPosition.Y)
				--print ('diff: ', math.abs(characterPosition.Y - playerPosition.Y))
				--print ('chase range: ', detection_range)
				if math.abs(characterPosition.Y - playerPosition.Y) > 10 then
					--print ('player Y out of range')
					continue
					-- else
					--print ('player Y in range')
				end
			end

			--print ('chase range: ', detection_range)
			--print ('player distance: ', (characterPosition - playerPosition).Magnitude)
			if (characterPosition - playerPosition).Magnitude <= nearestDistance then
				local raycastParams = RaycastParams.new()
				if activeMap:FindFirstChild("Castle") then
					raycastParams.ExcludeInstances = { character, activeMap.Castle.Railings }
				else
					raycastParams.FilterDescendantsInstances = { character }
				end
				local head = character:FindFirstChild("Head")
				local charEyePosition
				if head:IsA("MeshPart") then
					charEyePosition = head.Position
				elseif head:IsA("Model") then
					charEyePosition = head:FindFirstChild("Handle").Position
				else
					-- if can't find head, just take character getPivot and go up 2 studs
					charEyePosition = character:GetPivot().Position + Vector3.new(0, 2, 0)
				end
				--print ('character position: ', characterPosition)
				local rayDirection = (playerPosition - charEyePosition)
				local raycastResult = workspace:Raycast(charEyePosition, rayDirection, raycastParams)
				--print ('raycast result: ', raycastResult)
				if raycastResult then
					if GameParameters.raycastDebug then
						visualizeRay(context, charEyePosition, raycastResult.Position, Color3.fromRGB(0, 255, 0))
					end
					if raycastResult.Instance:IsDescendantOf(playerCharacter) then
						context.targetPlayer = player
						-- if detection_range == CHASE_RANGE then
						-- 	--print ('player is near for chase')
						-- else
						-- 	--print ('player is near for attack')
						-- end
						nearbyPlayer = player
						nearestDistance = (characterPosition - playerPosition).Magnitude
					else
						if character:GetAttribute("state") == "Attack" then
							print("player is blocked by: ", raycastResult.Instance.Name)
						end
					end
				else
					if GameParameters.raycastDebug then
						visualizeRay(
							context,
							charEyePosition,
							charEyePosition + rayDirection,
							Color3.fromRGB(255, 0, 0)
						)
					end
					print("player is not in eyesight")
				end
			end
		end
	end
	if nearbyPlayer then
		context.targetPlayer = nearbyPlayer
		return true
	else
		return false
	end
end

local function isPlayerNearbyForChase(context: Context): boolean
	return isPlayerNearby(context, CHASE_RANGE, false)
end

local function isPlayerNotNearbyForChase(context: Context): boolean
	return not isPlayerNearby(context, CHASE_RANGE, false)
end

local function isPlayerNearbyForAttack(context: Context): boolean
	return isPlayerNearby(context, ATTACK_RANGE, true)
end

local function isPlayerNotNearbyForAttack(context: Context): boolean
	local result = not isPlayerNearby(context, ATTACK_RANGE, true)
	if result then
		print("leave attack state for chase")
	end
	return result
end

-- Create transitions.
-- TODO: add a transition from attack to WalkToRandomFlag
local transitions = {
	-- If a player is close enough, attack.
	{
		startStates = { Idle, WalkToRandomFlag, Chase },
		endState = Attack,
		test = isPlayerNearbyForAttack,
	},
	-- If a player is nearby and in view, start chasing.
	{
		startStates = { Idle, WalkToRandomFlag },
		endState = Chase,
		test = isPlayerNearbyForChase,
	},
	-- If player gets away, stop attacking..
	{
		startStates = { Attack },
		endState = Chase,
		test = isPlayerNotNearbyForAttack,
	},
	-- If player is out of view or too far, stop chasing..
	{
		startStates = { Chase },
		endState = WalkToRandomFlag,
		test = isPlayerNotNearbyForChase,
	},
	-- When idle timer is done, walk to a flag.
	{
		startStates = { Idle },
		endState = WalkToRandomFlag,
		test = isIdleTimerDone,
	},
	-- When we reach the flag, idle.
	{
		startStates = { WalkToRandomFlag },
		endState = Idle,
		test = isNearTargetFlag,
	},
}

-- Make the state machine.
local defenderStateMachine: StateMachine = {
	name = "Defender",
	activeState = Idle,
	transitions = transitions,
	context = {
		character = character,
		humanoid = humanoid,
		humanoidRootPart = humanoidRootPart,
		currentFlagNumber = 1,
		targetFlag = nil,
		targetPlayer = nil,
		idleStartTime = os.clock(),
		lastAttackTime = 0,
	},
}

character:SetAttribute("state", defenderStateMachine.activeState.name)
character:SetAttribute("IsChasing", false)

--print(defenderStateMachine)
-- Tick the state machine every heartbeat.
RunService.Heartbeat:Connect(function()
	SimpleStateMachine.tick(defenderStateMachine)
end)
