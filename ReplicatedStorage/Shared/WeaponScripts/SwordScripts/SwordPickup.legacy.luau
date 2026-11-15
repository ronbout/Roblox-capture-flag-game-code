local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerModules = ServerScriptService:WaitForChild("Modules")
local GameData = require(ServerModules:WaitForChild("GameData"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEvents = ReplicatedStorage.Remotes.RemoteEvents
local GameInfo = ReplicatedStorage.GameInfo
local GameParameters = require(GameInfo.GameParameters)

local sword = script.Parent
local pickupPart = sword.Parent:FindFirstChild("SwordPickupPart")
if not pickupPart then return end
local swordName = sword.Name

local debounce = false

pickupPart.Touched:Connect(function(hit)
	if debounce then return end
	debounce = true
	task.delay(2, function()
		debounce = false
	end)
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then return end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if not character:FindFirstChild("Humanoid") then return end
	if table.find(GameData.PlayerWeaponPickup, player) then return end
	
	table.insert(GameData.PlayerWeaponPickup, player)

	if not player.Backpack:FindFirstChild(swordName) and not character:FindFirstChild(swordName) then
		local newSword = sword:Clone()
		newSword.Handle.CanTouch = true
		newSword.Handle.CanCollide = true
		newSword.Handle.Anchored = false
		local swordPickupScript =newSword:FindFirstChild("SwordPickup")
		if swordPickupScript then
			swordPickupScript:Destroy()
		end
		if not character:FindFirstChild(swordName) then
			newSword.Parent = character
		else
			newSword.Parent = player.Backpack
		end

		RemoteEvents.HideSword:FireClient(player, sword)
		-- if NO_MERCY is set, then no other player can get that sword
		if GameParameters.PvPMode == GameParameters.ENUM_PVP_MODE.NO_MERCY then
			sword:Destroy()
			pickupPart:Destroy()
		end
	end
end)
