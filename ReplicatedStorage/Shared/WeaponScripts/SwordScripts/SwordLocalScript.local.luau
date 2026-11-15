local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RemoteEvents = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvents")

local SwordAttackRemote = RemoteEvents:WaitForChild("SwordAttackRemote")

local Tool = script.Parent
local Character, Player, Humanoid
local toolEquipped = false

local SWORD_ACTION = "Lunge"
--local SWORD_ACTION2 = "Slash"

local function handleSwordAction(actionName, inputState, _inputObject)
	if actionName ~= SWORD_ACTION then return end
	if inputState ~= Enum.UserInputState.Begin then return end
	if not toolEquipped then return end
	if not Character or not Player or not Humanoid then return end
	if Humanoid.Health <= 0 then return end
	SwordAttackRemote:FireServer(SWORD_ACTION)
end

local function Equipped()
	toolEquipped = true
	Character = Tool.Parent
	Player = Players:GetPlayerFromCharacter(Character)
	Humanoid = Character:WaitForChild("Humanoid")
	
	ContextActionService:BindAction(SWORD_ACTION, handleSwordAction, true, Enum.KeyCode.L, Enum.KeyCode.ButtonL1)
end

local function Unequipped()
	toolEquipped = false
	ContextActionService:UnbindAction(SWORD_ACTION)
end

Tool.Equipped:Connect(Equipped)
Tool.Unequipped:Connect(Unequipped)

-- TODO: use contextservice to trigger a sword event to the server, 
-- which will run the Lunch attack.  Use the 'l' key, a mouse button,
-- and some controller input.

