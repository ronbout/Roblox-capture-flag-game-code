--[[
	local ServerScriptService = game:GetService("ServerScriptService")
	local ServerModules = ServerScriptService:WaitForChild('Modules')
	local CoinService = require(ServerModules:WaitForChild('CoinService'))
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local ServerModules = ServerScriptService:WaitForChild('Modules')
local PlayerData = require(ServerModules:WaitForChild("PlayerData"))
local coinsFolder, coins
local coinsGet = SoundService:WaitForChild("CoinsGet")
local RemoteEvents = ReplicatedStorage.Remotes.RemoteEvents
local coinCollectedEvent = RemoteEvents.CoinCollected

local DEFAULT_COOLDOWN = 0 -- # of seconds before coin reappears; 0 = never
local SPIN_SPEED = 1.5
local SHRINK_TIME = 0.45

local CoinService = {}

-- Shrink animation
local function shrinkCoin(coin)
	local coinBase = coin.Coin.Base
	local shrinkTweenInfo = TweenInfo.new(SHRINK_TIME)
	TweenService:Create(coinBase, shrinkTweenInfo, {Size = Vector3.one *0.1}):Play()
	TweenService:Create(coin.Coin.Logo, shrinkTweenInfo, {Size = Vector3.one *0.1}):Play()

end

-- Spinning animation
local function spinCoin(coinModel)
	local alignOrientationAtt = coinModel.Coin.Base.AlignOrientation.Attachment0
	return RunService.Heartbeat:Connect(function()
		--print ("spin heartbeat")
		alignOrientationAtt.Orientation += Vector3.yAxis * SPIN_SPEED
	end)
end

function CoinService.MapInit(map, cooldown)
	if cooldown == nil then 
		cooldown = DEFAULT_COOLDOWN
	end
	coinsFolder = map:FindFirstChild('Coins', true)
	coins = coinsFolder:GetChildren()
	
	-- Defining the event handler
	local function onCoinTouched(otherPart, coin, spinConnection, spinThread, hitboxConnection)
		if coin:GetAttribute("Enabled") then
			local coinValue = coin:GetAttribute("CoinValue") or 1
			local character = otherPart.Parent
			local player = Players:GetPlayerFromCharacter(character)
			if player then
				-- Player touched a coin
				
				local coinBase = coin.Coin.Base
				local coinPos = coinBase.Position
				
				coroutine.close(spinThread)
				spinConnection:Disconnect()

				Debris:AddItem(coin, 3)
				hitboxConnection:Disconnect()
				coinBase:SetNetworkOwner(player)

				shrinkCoin(coin)
				local rootAtt = character.HumanoidRootPart.RootAttachment
				coinBase.AlignPosition.Attachment1 = rootAtt
				coinBase.AlignOrientation.Attachment1 = rootAtt

				coinCollectedEvent:FireClient(player, coinPos, coinValue)
				
				coin:SetAttribute("Enabled", false)
				PlayerData.Set(player, "LevelPoints", coinValue, true)
				coinsGet:Play()
				--print("Player collected " .. coinValue .. " coins")
				if cooldown > 0 then
					task.wait(cooldown)
					coin.Transparency = 0
					coin:SetAttribute("Enabled", true)
				end
			end
		end
	end


	-- Setting up event listeners
	for _, coin in coins do
		coin:SetAttribute("Enabled", true)
		coin.HitBox.Transparency = 1
		local spinThread = coroutine.create(spinCoin)
		local success, spinConnection = coroutine.resume(spinThread, coin)
		local hitboxConnection = nil
		hitboxConnection = coin.HitBox.Touched:Connect(function(otherPart)
			onCoinTouched(otherPart, coin, spinConnection, spinThread, hitboxConnection)
		end)
	end
	
end

return CoinService
