-- Walk towards a random adjacent flag in the patrol sequence.
-- *** This is no longer just flags.  It is now checkpoints that the guards move between 
-- *** when they are not chasing/attacking a player.  Flags can be checkpoints, but they are
-- *** functionally different.
-- *** Some of the variables may still refer to "flags" in this script, but they should eventually
-- *** be renamed to "checkpoints" to make this more clear.
--[[
TODO:  REPLACE ALL "flag" references with "checkpoint"
TODO:  Rename this script to WalkToRandomCheckpoint
TODO:  Rename the script that uses this to WalkToRandomCheckpoint
]]
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
--local PathFindingService = game:GetService("PathfindingService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerModules = ServerScriptService:WaitForChild("Modules")
local Pathfinding = require(ServerModules:WaitForChild("Pathfinding"))



local GameInfo = ReplicatedStorage.GameInfo
local GameParameters = require(GameInfo.GameParameters)

local LeaveTrail = require(ReplicatedStorage:WaitForChild("Debug"):WaitForChild("LeaveTrail"))

local ServerScriptService = game:GetService("ServerScriptService")
local ServerModules = ServerScriptService:WaitForChild("Modules")
local GameData = require(ServerModules:WaitForChild("GameData"))

local SimpleStateMachine = require(ReplicatedStorage.Shared.SimpleStateMachine)
local activeMap = workspace:WaitForChild("ActiveMap")

type State = SimpleStateMachine.State
type Context = SimpleStateMachine.Context

-- Get all the checkpoints.
local checkpoints = {}
for i = 1, GameParameters.LevelParms[GameData.CurrentLevel].levelPathPointsCount do
	-- since this is not limited to the workspace, we need to make sure they are descendants of activeMap
	local collectedCheckpoints = CollectionService:GetTagged("Checkpoint"..i)
	for _, flg in pairs(collectedCheckpoints) do
		if flg:FindFirstAncestor("ActiveMap") then
			table.insert(checkpoints, flg)
			break
		end
	end
end

-- Pick the next flag number: current +/- 1, wrapping around.
local NUM_CHECKPOINTS = #checkpoints
local function pickNextFlagNumber(currentFlagNumber: number): number
	return math.random(1, NUM_CHECKPOINTS)
end

-- Pick the next flag and store it in context.
local function setNextFlag(context: Context)
	local nextFlagNumber = pickNextFlagNumber(context.currentFlagNumber)
	--nextFlagNumber = 4
	context.currentFlagNumber = nextFlagNumber
	context.targetFlag = checkpoints[nextFlagNumber]
	--print ("target flag: ",context.currentFlagNumber, context.targetFlag)
end

--local function drawWaypoints(waypoints: {PathWaypoint}) : {BasePart}
--	local partsTable = {}
--	for i, waypoint in ipairs(waypoints) do
--		local part = Instance.new("Part")
--		part.Name = "Waypoint"
--		part.Size = Vector3.new(1, 0.4, 1)
--		part.Position = waypoint.Position
--		part.Anchored = true
--		part.CanCollide = false
--		part.Parent = activeMap
--		part.BrickColor = BrickColor.new("Really red")
--		if not GameParameters.pathfindDebug then part.Transparency = 1 end
--		partsTable[i] = part
--	end
--	--print ("partsTable: ", partsTable)
--	return partsTable
--end

-- Walk towards the target flag.
local function walkTowardsFlag(context: Context)
	if context.character:GetAttribute("IsWalking") then
		return
	end

	local NPCParams = {
		AgentRadius = 2,
		AgentHeight = 5.46,
		AgentCanJump = false,
		AgentCanClimb = true,
	}

	local function checkCharStateForAbort()
		local charState = context.character:GetAttribute("state")
		--print ("charState: ", charState)
		if charState == "Attack" or charState == "Chase" then 
			return true
		else
			return false
		end
	end
	
	local characterPosition = context.humanoidRootPart.Position
	local flagPosition = context.targetFlag:GetPivot().Position :: Vector3
	--flagPosition = Vector3.new(flagPosition.X, characterPosition.Y, flagPosition.Z)
	local targetDirection = (flagPosition - characterPosition).Unit
	local stoppingDistance = 2
	--local targetPosition = flagPosition - (targetDirection * stoppingDistance)
	local targetPosition = flagPosition
	
	--local path = PathFindingService:CreatePath(NPCParams)
	local pathOptions = {
		npcParams = NPCParams,
		debugFlag = GameParameters.pathfindDebug or false,
		shouldAbort = checkCharStateForAbort,
	}
	context.character:SetAttribute("IsWalking", true)
	local pathfindingObj = Pathfinding.new(context.character, targetPosition, pathOptions)
	--path:ComputeAsync(context.humanoidRootPart.Position, targetPosition)
	if pathfindingObj.pathStatus ~= Enum.PathStatus.Success then 
	--if path.Status ~= Enum.PathStatus.Success then 
		context.character:SetAttribute("IsWalking", false)
		warn ('Walking path not successful  for ', context.character.Name, ' from ', context.humanoidRootPart.Position, ' to flag ', context.targetFlag, ' at ', targetPosition)
		setNextFlag(context)
		pathfindingObj:Destroy()
		pathfindingObj = nil
		return
	end
	--print ('Walking path WAS successful for ', context.character.Name, ' from ', context.humanoidRootPart.Position, ' to flag ', context.targetFlag, ' at ', targetPosition)
	local pathResult = pathfindingObj:StartPath()
	
	pathfindingObj.OnComplete:Connect(function()
		print ("Pathfinding completed for ", context.character.Name, context.targetFlag.Name)
		context.character:SetAttribute("IsWalking", false)
		setNextFlag(context)
		pathfindingObj:Destroy()
		pathfindingObj = nil
	end)

	pathfindingObj.OnNoProgress:Connect(function()
		print ("Pathfinding not making progress ")
		context.character:SetAttribute("IsWalking", false)
		setNextFlag(context)
		pathfindingObj:Destroy()
		pathfindingObj = nil
	end)

	pathfindingObj.OnAbort:Connect(function()
		print ("Walking to flag aborted ")
		context.character:SetAttribute("IsWalking", false)
		pathfindingObj:Destroy()
		pathfindingObj = nil
	end)
	--local waypoints = path:GetWaypoints()
	--local waypointParts = drawWaypoints(waypoints)
	----print ("IsWalking: ", context.character:GetAttribute("IsWalking"))
	--if GameParameters.pathfindDebug then LeaveTrail.Start(context.character, 3) end
	--for i, waypoint in ipairs(waypoints) do
	--	-- the tick check could switch to attack or chase, so we need to stop this if that happens
	--	local charState = context.character:GetAttribute("state")
	--	if charState == "Attack" or charState == "Chase" then 
	--		print ("leaving walking to ".. charState)
	--		context.character:SetAttribute("IsWalking", false)
	--		return 
	--	end
	--	-- bail out on the last waypoint so the NPC doesn't walk into the flag
	--	if i == #waypoints then
	--		waypointParts[i]:Destroy()
	--		break
	--	end
	--	context.humanoid:MoveTo(waypoint.Position)
	--	local reached = context.humanoid.MoveToFinished:Wait()
	--	waypointParts[i]:Destroy()
	--	if not reached then
	--		warn ("waypoints not reached.  ".. i .. " of ".. #waypoints .. " going to " .. context.targetFlag.Name .. " for " .. context.character.Name)
	--		context.character:SetAttribute("IsWalking", false)
	--		return
	--	end
	--end
	--print ("all waypoints reached... can set another one after this")
	--context.character:SetAttribute("IsWalking", false)
end

local WalkToRandomFlag: State = {
	name = "WalkToRandomFlag",
	onEnter = setNextFlag,
	onStay = walkTowardsFlag,
}

return WalkToRandomFlag
