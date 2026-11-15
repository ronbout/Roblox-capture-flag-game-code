--Rescripted by Luckymaxer
--EUROCOW WAS HERE BECAUSE I MADE THE PARTICLES AND THEREFORE THIS ENTIRE SWORD PRETTY AND LOOK PRETTY WORDS AND I'D LIKE TO DEDICATE THIS TO MY FRIENDS AND HI LUCKYMAXER PLS FIX SFOTH SWORDS TY LOVE Y'ALl
--Updated for R15 avatars by StarWars
--Re-updated by TakeoHonorable

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEvents = ReplicatedStorage.Remotes.RemoteEvents
local GameInfo = ReplicatedStorage.GameInfo
local GameParameters = require(GameInfo.GameParameters)

local SwordAttackRemote = RemoteEvents:WaitForChild("SwordAttackRemote")

local Tool = script.Parent
local Handle = Tool:WaitForChild("Handle")

local attacking = false
local attackMode = "Slash"

local Character, Player, Humanoid, Torso

function Create(ty)
	return function(data)
		local obj = Instance.new(ty)
		for k, v in pairs(data) do
			if type(k) == 'number' then
				v.Parent = obj
			else
				obj[k] = v
			end
		end
		return obj
	end
end

local BaseUrl = "rbxassetid://"

DamageValues = {
	BaseDamage = 5,
	SlashDamage = 10,
	LungeDamage = 30
}

--For R15 avatars
Animations = {
	R15Slash = 522635514,
	R15Lunge = 522638767
}

Damage = DamageValues.BaseDamage

Grips = {
	Up = CFrame.new(0, 0, -1.70000005, 0, 0, 1, 1, 0, 0, 0, 1, 0),
	Out = CFrame.new(0, 0, -1.70000005, 0, 1, 0, 1, -0, 0, 0, 0, -1)
}

Sounds = {
	Slash = Handle:WaitForChild("SwordSlash"),
	Lunge = Handle:WaitForChild("SwordLunge"),
	Unsheath = Handle:WaitForChild("Unsheath")
}

ToolEquipped = true -- Changed for NPC, which always has it equipped.

--For Omega Rainbow Katana thumbnail to display a lot of particles.
for i, v in pairs(Handle:GetChildren()) do
	if v:IsA("ParticleEmitter") then
		v.Rate = 20
	end
end

Tool.Grip = Grips.Up
Tool.Enabled = true

function IsTeamMate(Player1, Player2)
	return (Player1 and Player2 and not Player1.Neutral and not Player2.Neutral and Player1.TeamColor == Player2.TeamColor)
end

function TagHumanoid(humanoid, player)
	local Creator_Tag = Instance.new("ObjectValue")
	Creator_Tag.Name = "creator"
	Creator_Tag.Value = player
	Debris:AddItem(Creator_Tag, 2)
	Creator_Tag.Parent = humanoid
end

function UntagHumanoid(humanoid)
	for i, v in pairs(humanoid:GetChildren()) do
		if v:IsA("ObjectValue") and v.Name == "creator" then
			v:Destroy()
		end
	end
end

local function isSwordInRightGrip(rightArm)
	for _, part in ipairs(rightArm:GetChildren()) do
		if part.Name == "RightGrip" and part:isA("Weld") then
			if part.Part0 == Handle or part.Part1 == Handle then
				return true
			end	
		end
	end
	return false
end

function Blow(Hit)
	local attackDebounce = Tool:GetAttribute("attackDebounce")
	if not attacking or attackDebounce then
		return
	end
	if not Hit or not Hit.Parent or not CheckIfAlive() or not ToolEquipped then
		return
	end
	local RightArm = Character:FindFirstChild("Right Arm") or Character:FindFirstChild("RightHand")
	if not RightArm then
		return
	end
	if not isSwordInRightGrip(RightArm) then
		return
	end
	--local RightGrip = RightArm:FindFirstChild("RightGrip")
	--if not RightGrip or (RightGrip.Part0 ~= Handle and RightGrip.Part1 ~= Handle) then
	--	return
	--end
	local character = Hit.Parent
	if character == Character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health == 0 then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	-- can only hurt another player in NO_MERCY mode
	if player and GameParameters.PvPMode ~= GameParameters.ENUM_PVP_MODE.NO_MERCY and Player then return end
	if player and (player == Player or IsTeamMate(Player, player)) then
		return
	end
	UntagHumanoid(humanoid)
	TagHumanoid(humanoid, Player)
	print ("Damage, Player Name, Hit Part: ", Damage, character, Hit)
	humanoid:TakeDamage(Damage)
	Tool:setAttribute("attackDebounce", true) 
	if Player then
		task.wait(0.3)
	else
		task.wait(0.5)
	end
	Tool:setAttribute("attackDebounce", false) 
end


function Attack()
	local charDamage = Character:GetAttribute("SwordDamage")
	Damage = charDamage or DamageValues.SlashDamage
	Sounds.Slash:Play()

	if Humanoid then
		if Humanoid.RigType == Enum.HumanoidRigType.R6 then
			local Anim = Instance.new("StringValue")
			Anim.Name = "toolanim"
			Anim.Value = "Slash"
			Anim.Parent = Tool
		elseif Humanoid.RigType == Enum.HumanoidRigType.R15 then
			local Anim = Tool:FindFirstChild("R15Slash")
			if Anim then
				local Track = Humanoid:LoadAnimation(Anim)
				Track:Play(0)
			end
		end
	end	
end

function Lunge()
	Damage = DamageValues.LungeDamage

	Sounds.Lunge:Play()

	if Humanoid then
		if Humanoid.RigType == Enum.HumanoidRigType.R6 then
			local Anim = Instance.new("StringValue")
			Anim.Name = "toolanim"
			Anim.Value = "Lunge"
			Anim.Parent = Tool
		elseif Humanoid.RigType == Enum.HumanoidRigType.R15 then
			local Anim = Tool:FindFirstChild("R15Lunge")
			if Anim then
				--local Track = Humanoid:LoadAnimation(Anim)
				local Track = Humanoid.Animator:LoadAnimation(Anim)
				Track:Play(0)
			end
		end
	end	
	--[[
	if CheckIfAlive() then
		local Force = Instance.new("BodyVelocity")
		Force.velocity = Vector3.new(0, 10, 0) 
		Force.maxForce = Vector3.new(0, 4000, 0)
		Debris:AddItem(Force, 0.4)
		Force.Parent = Torso
	end
	]]

	task.wait(0.1)
	Tool.Grip = Grips.Out
	task.wait(0.1)
	Tool.Grip = Grips.Up

	Damage = DamageValues.SlashDamage
	attackMode = "Slash"
end

Tool.Enabled = true
LastAttack = 0

function Activated()
	if not Tool.Enabled or not ToolEquipped or not CheckIfAlive() then
		--print("Returned", Tool.Enabled, ToolEquipped, CheckIfAlive())
		return
	end
	attacking = true
	task.delay(0.2, function()
		attacking = false
	end)
	Tool.Enabled = false
	local Tick = RunService.Stepped:wait()
	if (Tick - LastAttack < 0.3) then attackMode = "Lunge" end
	if attackMode == "Lunge" then
		print ("lunge")
		Lunge()
	else
		print("Slash")
		Attack()
	end
	LastAttack = Tick
	--wait(0.5)
	--Damage = DamageValues.BaseDamage
	local SlashAnim = (Tool:FindFirstChild("R15Slash") or Create("Animation"){
		Name = "R15Slash",
		AnimationId = BaseUrl .. Animations.R15Slash,
		Parent = Tool
	})

	local LungeAnim = (Tool:FindFirstChild("R15Lunge") or Create("Animation"){
		Name = "R15Lunge",
		AnimationId = BaseUrl .. Animations.R15Lunge,
		Parent = Tool
	})
	Tool.Enabled = true
end

function CheckIfAlive()
	return Humanoid.Health > 0
end

function Equipped()
	Character = Tool.Parent
	Player = Players:GetPlayerFromCharacter(Character)
	--print (Character, Player)
	Humanoid = Character:FindFirstChildOfClass("Humanoid")
	Torso = Character:FindFirstChild("Torso") or Character:FindFirstChild("HumanoidRootPart")
	if not CheckIfAlive() then
		return
	end
	ToolEquipped = true
	Sounds.Unsheath:Play()
end

function Unequipped()
	Tool.Grip = Grips.Up
	ToolEquipped = false
end

Tool.Activated:Connect(Activated)
Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)

Connection = Handle.Touched:Connect(Blow)

SwordAttackRemote.OnServerEvent:Connect(function(player, action)
	if player ~= Player or not ToolEquipped or not CheckIfAlive() then return end
	if action == "Lunge" then
		attackMode = "Lunge"
		Tool:Activate()
	end
end)