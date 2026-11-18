-- Chase and attack the spotted player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SimpleStateMachine = require(ReplicatedStorage.Shared.SimpleStateMachine)

type State = SimpleStateMachine.State
type Context = SimpleStateMachine.Context

local ATTACK_RANGE = 10
local ATTACK_COOLDOWN = 1

-- Walk directly towards the spotted player and attack if close enough.
local function attack(context: Context)
	local humanoid = context.humanoid
	local hrp = context.humanoidRootPart
	local targetCharacter = context.targetPlayer.Character
	if not targetCharacter then
		return
	end

	if context.character:GetAttribute("IsAttacking") then
		return
	end

	local targetDirection = (targetCharacter:GetPivot().Position - hrp.Position).Unit
	local stoppingDistance = 4
	local targetPosition = targetCharacter:GetPivot().Position - (targetDirection * stoppingDistance)

	--local NPCParams = {
	--	AgentRadius = 2,
	--	AgentHeight = 5.8,
	--	AgentCanJump = false,
	--	AgentCanClimb = false,
	--}
	--local path = PathFindingService:CreatePath(NPCParams)
	--path:ComputeAsync(hrp.Position, targetPosition)
	--local waypoints = path:GetWaypoints()
	--for _, waypoint in ipairs(waypoints) do
	--	humanoid:MoveTo(waypoint.Position)
	--	local reached = humanoid.MoveToFinished:Wait()
	--	if not reached then
	--		return
	--	end
	--end
	context.character:SetAttribute("IsAttacking", true)
	humanoid:MoveTo(targetPosition)
	humanoid.MoveToFinished:Wait()
	hrp.CFrame = CFrame.lookAt(hrp.Position, targetCharacter:GetPivot().Position)

	-- after looking at the target, turn just 10 degrees to the left for better attack angle
	hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(10), 0)

	local character = context.character :: Model
	local distance = (character:GetPivot().Position - targetCharacter:GetPivot().Position).Magnitude

	if distance <= ATTACK_RANGE and os.clock() - context.lastAttackTime >= ATTACK_COOLDOWN then
		local tool = character:FindFirstChildOfClass("Tool")
		if tool and tool:FindFirstChild("Handle") then
			tool:Activate()
		end
		context.lastAttackTime = os.clock()
	end

	context.character:SetAttribute("IsAttacking", false)
end

local function onEnter(context: Context)
	context.lastAttackTime = 0
	context.character:SetAttribute("IsChasing", false)
end

local Attack: State = {
	name = "Attack",
	onEnter = onEnter,
	onStay = attack,
}

return Attack
