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

-- Walk towards the spotted player and attack if close enough.
local function chase(context: Context)
	local targetCharacter = context.targetPlayer.Character
	if not targetCharacter then
		return
	end

	if context.character:GetAttribute("IsChasing") then
		--print ('IsChasing tick')
		return
	end

	local targetPosition = targetCharacter:GetPivot().Position

	local function shouldAbort()
		--	-- the tick check could switch to attack, so we need to stop this if that happens
		if context.character:GetAttribute("state") ~= "Chase" then
			context.character:SetAttribute("IsChasing", false)
			return true
		end
		-- check if the target has strayed too far from the original target position.
		-- If so, abort the pathfinding and recalc a new path.
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

	local _pathResult = pathfindingObj:StartPath()

	pathfindingObj.OnComplete:Connect(function()
		print("Pathfinding completed for ", context.character.Name, context.targetFlag.Name)
		context.character:SetAttribute("IsChasing", false)
		pathfindingObj:Destroy()
		pathfindingObj = nil
	end)

	pathfindingObj.OnNoProgress:Connect(function()
		print("Pathfinding not making progress ")
		context.character:SetAttribute("IsChasing", false)
		pathfindingObj:Destroy()
		pathfindingObj = nil
	end)

	pathfindingObj.OnAbort:Connect(function()
		print("Walking to flag aborted ")
		context.character:SetAttribute("IsChasing", false)
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
	--		warn ("waypoints not reached.  ".. i .. " of ".. #waypoints .. " going to " .. context.targetFlag.Name .. " for " .. context.character.Name)
	--		return
	--	end
	--end
	--context.character:SetAttribute("IsChasing", false)
end

local function onEnter(context: Context)
	context.humanoid.WalkSpeed = 14
end

local function onExit(context: Context)
	context.humanoid.WalkSpeed = 12
end

local Chase: State = {
	name = "Chase",
	onEnter = onEnter,
	onExit = onExit,
	onStay = chase,
}

return Chase
