-- Chase and attack the spotted player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SimpleStateMachine = require(ReplicatedStorage.Shared.SimpleStateMachine)
local ServerScriptService = game:GetService("ServerScriptService")
local ServerModules = ServerScriptService:WaitForChild("Modules")
local Pathfinding = require(ServerModules:WaitForChild("Pathfinding"))

local GameInfo = ReplicatedStorage:WaitForChild("GameInfo")
local GameParameters = require(GameInfo.GameParameters)

type State = SimpleStateMachine.State
type Context = SimpleStateMachine.Context

local function canSee(viewChar, target)
	local raycastParams = RaycastParams.new()

	local detectionDistance = viewChar:GetAttribute("DetectionDistance") or 100

	raycastParams.ExcludeInstances = { viewChar }
	local head = viewChar:FindFirstChild("Head")
	local charEyePosition
	if head:IsA("MeshPart") then
		charEyePosition = head.Position
	elseif head:IsA("Model") then
		charEyePosition = head:FindFirstChild("Handle").Position
	else
		-- if can't find head, just take character getPivot and go up 2 studs
		charEyePosition = viewChar:GetPivot().Position + Vector3.new(0, 2, 0)
	end

	local rayDirection = (target:GetPivot().Position - charEyePosition).Unit * detectionDistance
	local raycastResult = workspace:Raycast(charEyePosition, rayDirection, raycastParams)

	if raycastResult and raycastResult.Instance:IsDescendantOf(target) then
		return true
	else
		return false
	end
end

-- Walk towards the spotted player and attack if close enough.
local function chase(context: Context)
	local targetCharacter = context.targetPlayer.Character
	if not targetCharacter then
		return
	end

	if context.character:GetAttribute("IsChasing") then
		--print ('IsChasing tick')

		-- check if the target has strayed too far from the original target position, and it can be seen.
		-- The distance check is based on a percentage of the distance that the NPC is currently from the target.
		-- If so, abort the pathfinding and recalc a new path by setting the recalcPath attribute to true

		if not canSee(context.character, targetCharacter) then
			-- if we cannot see the target, then we just continue on our current pathfinding path.
			-- print("cannot see")
			return
		end

		if not context.origTargetPosition then
			-- print("origTargetPosition is nil")
			return
		end
		local minTolerance = 10 -- we don't wan to recalc too much as we get closer
		local toleranceRatio = 0.25 -- we want to recalc more as we get further away

		local npcDistance = (context.humanoidRootPart.Position - context.origTargetPosition).Magnitude
		local targetDistance = (targetCharacter:GetPivot().Position - context.origTargetPosition).Magnitude
		local tolerance = math.max(minTolerance, npcDistance * toleranceRatio)

		-- print("targetDistance: ", targetDistance, " tolerance: ", tolerance)

		if targetDistance > tolerance then
			-- print("Target has moved too far from original position.  Recalc path.")
			context.character:SetAttribute("recalcPath", true)
		end
		return
	end

	local targetPosition = targetCharacter:GetPivot().Position

	local function shouldAbort()
		--	-- the tick check could switch to attack, so we need to stop this if that happens
		if context.character:GetAttribute("state") ~= "Chase" then
			context.character:SetAttribute("IsChasing", false)
			return true
		end

		if context.character:GetAttribute("recalcPath") then
			return true
		end
		return false
	end

	local NPCParams = {
		AgentRadius = 2,
		AgentHeight = 5.46,
		AgentCanJump = false,
		AgentCanClimb = true,
	}

	local pathOptions = {
		npcParams = NPCParams,
		debugFlag = GameParameters.pathfindDebug or false,
		shouldAbort = shouldAbort,
		debugColor = Color3.new(1, 1, 0),
	}

	--local path = PathFindingService:CreatePath(NPCParams)
	context.character:SetAttribute("IsChasing", true)
	local pathfindingObj = Pathfinding.new(context.character, targetPosition, pathOptions)
	--path:ComputeAsync(context.humanoidRootPart.Position, targetPosition)
	if pathfindingObj.pathStatus ~= Enum.PathStatus.Success then
		--if path.Status ~= Enum.PathStatus.Success then
		context.character:SetAttribute("IsChasing", false)
		warn(
			"Chase path not successful for ",
			context.character.Name,
			" from ",
			context.humanoidRootPart.Position,
			" to ",
			targetPosition
		)
		pathfindingObj:Destroy()
		pathfindingObj = nil
		return
	end
	context.origTargetPosition = targetPosition
	local _pathResult = pathfindingObj:StartPath()

	pathfindingObj.OnComplete:Connect(function()
		print("Pathfinding completed for ", context.character.Name, context.targetPlayer.Name)
		context.character:SetAttribute("IsChasing", false)
		context.origTargetPosition = nil
		pathfindingObj:Destroy()
		pathfindingObj = nil
	end)

	pathfindingObj.OnNoProgress:Connect(function()
		print("Pathfinding not making progress ")
		context.character:SetAttribute("IsChasing", false)
		context.origTargetPosition = nil
		pathfindingObj:Destroy()
		pathfindingObj = nil
	end)

	pathfindingObj.OnAbort:Connect(function()
		if context.character:GetAttribute("recalcPath") == true then
			context.character:SetAttribute("recalcPath", false)
			print("Chase aborted to recalc path for ", context.character.Name, context.targetPlayer.Name)
		else
			print("Chase aborted for ", context.character.Name, context.targetPlayer.Name)
		end
		context.character:SetAttribute("IsChasing", false)
		context.origTargetPosition = nil
		pathfindingObj:Destroy()
		pathfindingObj = nil
	end)
	--local waypoints = path:GetWaypoints()
	--local waypointParts = drawWaypoints(waypoints)
	--if GameParameters.pathfindDebug then LeaveTrail.Start(context.character, 3) end
	----task.wait(10)
	----print ('waypoints: ', waypoints)
	--for i, waypoint in ipairs(waypoints) do
	--	-- the tick check could switch to attack, so we need to stop this if that happens
	--	if context.character:GetAttribute("state") == "Attack" then
	--		context.character:SetAttribute("IsChasing", false)
	--		return
	--	end
	--	-- bail out on the last waypoint so the NPC doesn't walk into the player
	--	if i == #waypoints then
	--		waypointParts[i]:Destroy()
	--		break
	--	end
	--	humanoid:MoveTo(waypoint.Position)
	--	local reached = humanoid.MoveToFinished:Wait()
	--	waypointParts[i]:Destroy()

	--	if not reached then
	--		context.character:SetAttribute("IsChasing", false)
	--		if context.character:GetAttribute("state") == "Attack" then
	--			-- this is expected so no warning
	--			return
	--		end
	--		--warn ('waypoint not reached!!  Waypoint action: ', waypoint.Action)
	--		warn ("waypoints not reached.  ".. i .. " of ".. #waypoints .. " going to " .. context.targetPlayer.Name .. " for " .. context.character.Name)
	--		return
	--	end
	--end
	--context.character:SetAttribute("IsChasing", false)
end

local function onEnter(context: Context)
	context.humanoid.WalkSpeed = 14
	context.character:SetAttribute("IsAttacking", false)
end

local function onExit(context: Context)
	context.humanoid.WalkSpeed = 12
	context.character:SetAttribute("IsChasing", false)
end

local Chase: State = {
	name = "Chase",
	onEnter = onEnter,
	onExit = onExit,
	onStay = chase,
}

return Chase
