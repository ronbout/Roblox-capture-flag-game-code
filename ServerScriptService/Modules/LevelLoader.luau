local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local GuardsFolder = ServerStorage:WaitForChild("Guards")
local WeaponsFolder = ServerStorage:WaitForChild("Weapons")
local MapsFolder = ServerStorage:WaitForChild("Maps")
local LightingFolder = ServerStorage:WaitForChild("Lighting")
local TerrainObjsFolder = ServerStorage:WaitForChild("Terrain")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local LightingService = game:GetService("Lighting")
local Players = game:GetService("Players")
local Utils = require(ReplicatedStorage.Modules.Utils)
local GameInfo = ReplicatedStorage:WaitForChild("GameInfo")
local GameParameters = require(GameInfo.GameParameters)

local ServerScriptService = game:GetService("ServerScriptService")
local ServerModules = ServerScriptService:WaitForChild("Modules")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = require(ServerModules:WaitForChild("GameData"))
local CoinService = require(ServerModules:WaitForChild('CoinService'))
local PlayerData = require(ServerModules:WaitForChild("PlayerData"))
local BonusTimeMgr = require(Modules:WaitForChild("BonusTimeMgr"))

local RemoteEvents = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvents")
local LevelScreenReadyEvent = RemoteEvents:WaitForChild("LevelScreenReady")

local testMapMode = GameParameters.testMapMode

local connected = {}

local LevelLoader = {}

local loadLocalScripts = function(player, scripts)
	local playerGui = player:WaitForChild("PlayerGui")
	if not playerGui then return end
	local playerGuiScripts = playerGui:FindFirstChild("Scripts")
	if not playerGuiScripts then
		playerGuiScripts = Instance.new("Folder")
		playerGuiScripts.Name = "Scripts"
		playerGuiScripts.Parent = playerGui
	else
		for _, script in pairs(playerGuiScripts:GetChildren()) do
			script:Destroy()
		end
	end
	for _, script in pairs(scripts) do
		local newScript = script:Clone()
		newScript.Parent = playerGuiScripts
		newScript.Enabled = true
	end
end

local setCapturedItemsGui = function(player)
	local capturedFlagsGui = GameParameters.LevelParms[GameData.CurrentLevel].levelCapturedFlagGui
	local playerGui = player:WaitForChild("PlayerGui")
	if GameData.CurrentLevel > 1 then
		local oldCapturedFlagsGui = GameParameters.LevelParms[GameData.CurrentLevel - 1].levelCapturedFlagGui
		playerGui:WaitForChild(oldCapturedFlagsGui).Enabled = false
	end
	playerGui:WaitForChild(capturedFlagsGui).Enabled = true
end

local preparePlayer = function(player, flagsMapFolder)
	local character = player.Character or player.CharacterAdded:Wait()
	if not character then return end
	local humanoid = character:WaitForChild("Humanoid")
	if not humanoid then return end
	-- reset the humanoid state
	humanoid.Health = humanoid.MaxHealth
	--humanoid.WalkSpeed = 16
	--humanoid.JumpPower = 50
	--humanoid.JumpHeight = 7.2
	-- empty the Flags folder for all players
	local flagsFolder = player:WaitForChild("Flags")
	if flagsFolder then
		for _, flag in pairs(flagsFolder:GetChildren()) do
			flag:Destroy()
		end
	end

	if GameParameters.findNewToolPerLevel then
		humanoid:UnequipTools()
		Utils.ProcessPlayerTools(player, Utils.Enums.ToolLoc.Both ,function(tool)
				tool:Destroy()
		end)
		---- also check the character and remove any weapons there
		--if character:FindFirstChildOfClass("Tool") then
		--	character:FindFirstChildOfClass("Tool"):Destroy()
		--end
		---- also check the backpack and remove any weapons there
		--for _, item in pairs(player.Backpack:GetChildren()) do
		--	if item:IsA("Tool") then
		--		item:Destroy()
		--	end
		--end
	end
	setCapturedItemsGui(player)
end

local loadLightingObjects = function(objs)
	for _, obj in pairs(LightingService:GetChildren()) do
		obj:Destroy()
	end
	for _, obj in pairs(objs) do
		obj:Clone().Parent = LightingService
	end
end

function LevelLoader.loadGuards(level, difficulty, map)
	local levelParms = GameParameters.LevelParms[level]

	for _, guard in pairs(levelParms.levelGuards[difficulty]) do
		local newGuard = GuardsFolder:WaitForChild(guard.GuardType):Clone()
		local weapon = WeaponsFolder:WaitForChild(guard.WeaponType):Clone()
		local humanoid = newGuard:WaitForChild("Humanoid")
		local guardRootPart = newGuard:WaitForChild("HumanoidRootPart")
		humanoid.WalkSpeed = math.floor(humanoid.WalkSpeed * guard.WalkMultiplier)
		humanoid.MaxHealth = guard.MaxHealth
		humanoid.Health = guard.MaxHealth
		humanoid.DisplayName = guard.Name
		newGuard.Name = guard.Name
		newGuard.HumanoidRootPart.CFrame = CFrame.new(guard.Position.X, guard.Position.Y, guard.Position.Z)
		newGuard:SetAttribute("DetectionDistance", guard.DetectionDistance)
		newGuard:SetAttribute("SwordDamage", guard.SwordDamage)
		weapon.Parent = newGuard

		local defenderScript = ReplicatedStorage.Shared["Guard Script"].Defender:Clone()
		defenderScript.Parent = newGuard
		defenderScript.Enabled = true
		newGuard.Parent = map
		--[[
			TODO: before setting network owner, need to make sure that the guard is part of the workspace
		]]
		--guardRootPart:SetNetworkOwner(nil)
		table.insert(GameData.Guards, newGuard)
		-- add RayVisual part if raycastDebug is true
		if GameParameters.raycastDebug then
			local rayVisual = Instance.new("Part")
			rayVisual.Name = "RayVisual" .. guard.Name
			rayVisual.Transparency = 1
			rayVisual.CFrame = CFrame.new(0, -1000, 0) -- Move it off-screen
			rayVisual.Anchored = true
			rayVisual.Parent = newGuard
		end
		
		humanoid.Died:Connect(function()
			local creatorTag = humanoid:FindFirstChild("creator")
			if creatorTag and creatorTag:IsA("ObjectValue") and creatorTag.Value then
				local killerPlayer = creatorTag.Value
				if killerPlayer and killerPlayer:IsA("Player") and killerPlayer.Character then
					local killPoints = guard.KillPoints or GameParameters.default_guard_kill_value
					PlayerData.Set(killerPlayer, "LevelPoints", killPoints, true)
				end
			end
			
		end)
	end

	-- load sword scripts
	local SwordServerScript = ReplicatedStorage.Shared.WeaponScripts.SwordScripts.SwordServerScript
	local SwordLocalScript = ReplicatedStorage.Shared.WeaponScripts.SwordScripts.SwordLocalScript
	local SwordPickupScript = ReplicatedStorage.Shared.WeaponScripts.SwordScripts.SwordPickup
	local function installSwordSripts(sword)
		-- check if the sword script exists as the starterPack sword is getting run twice
		if not sword:FindFirstChild("SwordServerScript") then 
			local script = SwordServerScript:Clone()
			script.Parent = sword
			script.Enabled = true
		end
		if not sword:FindFirstChild("SwordLocalScript") then 
			local script = SwordLocalScript:Clone()
			script.Parent = sword
			script.Enabled = true
		end
		if not sword:FindFirstChild("SwordPickup") and sword.Parent:FindFirstChild("SwordPickupPart") then 
			local script = SwordPickupScript:Clone()
			script.Parent = sword
			script.Enabled = true
		end
	end

	-- Collection service setup swords to install scripts
	local tag = "Sword"
	CollectionService:GetInstanceAddedSignal(tag):Connect(installSwordSripts)
	--CollectionService:GetInstanceRemovedSignal(tag):Connect(function(taggedObject)
	--	if taggedObject then
	--		taggedObject:Destroy()
	--	end
	--end)

	local swords = CollectionService:GetTagged(tag)

	for _, sword in pairs(swords) do
		installSwordSripts(sword)
	end
	-- end of swords collection
end

local function loadCoins(map, coinLevel, coinRegenTime)
	local coinModel = ServerStorage.Coins.CoinModel
	local coinsFolder = map:FindFirstChild("Coins", true)
	for i, coin in ipairs(coinLevel) do
		local x = coin[1]
		local y = coin[2]
		local z = coin[3]
		local coinValue = coin[4]
		local newCoin = coinModel:Clone()
		newCoin.Name = "Coin_" .. i
		newCoin:SetAttribute("CoinValue", coinValue)
		newCoin.HitBox.Position = Vector3.new(x, y, z)
		--newCoin.Coin.Base.Position = Vector3.new(x, y, z)
		newCoin.Parent = coinsFolder
	end
end

--local function checkForTerrainLoaded(levelSpawn)
--	local rayOrigin = levelSpawn.Position
--	local rayDirection = Vector3.new(0, -50, 0)

--	local raycastParams = RaycastParams.new()
--	raycastParams.FilterType = Enum.RaycastFilterType.Include
--	raycastParams.FilterDescendantsInstances = { workspace.Terrain }

--	local terrainHit
--	local maxGroundDistance = 10

--	repeat
--		terrainHit = workspace:Raycast(
--			levelSpawn.Position,
--			Vector3.new(0, -50, 0),
--			raycastParams
--		)

--		if not terrainHit
--			or terrainHit.Distance > maxGroundDistance then

--			terrainHit = nil
--			task.wait(0.1)
--		end
--	until terrainHit
--end

function LevelLoader.loadLevel(level)
	
	-- *** delete any previous level data
	connected = {}
	
	-- empty the GameData Guards table and the weapons pickup
	GameData.Guards = {}
	GameData.PlayerWeaponPickup = {}
	
	--empty anything in the Workspace Terrain folder 
	for _, child in pairs(workspace.Terrain:GetChildren()) do
		child:Destroy()
	end
	
	print ("loading level ", level)
	
	-- reset parameters
	local levelParms = GameParameters.LevelParms[level]
	
	-- load new map
	local map
	if testMapMode then 
		map = workspace:WaitForChild("_mapTesting"):WaitForChild(GameParameters.testMapName)
		warn("Loading test map... NOT server storage version!")
	else
		local testMap = workspace:FindFirstChild("_mapTesting")
		if testMap then 
			testMap:Destroy() 
		end
		map = MapsFolder[levelParms.levelMap]:Clone()
	end	
	-- destroy previous map
	if workspace:FindFirstChild("ActiveMap") then
		workspace.ActiveMap:Destroy()
	end
	local flagsMapFolder = map:WaitForChild("Flags")
	local levelSpawn = map:WaitForChild("LevelSpawn")
	
	workspace.Terrain:Clear()
	local terrainRegion = map:FindFirstChild("TerrainRegion")
	if terrainRegion then 
		workspace.Terrain:PasteRegion(terrainRegion, workspace.Terrain.MaxExtents.Min, true)
		--print("before terrain check on server")
		--checkForTerrainLoaded(levelSpawn)
		--print("after terrain check on server")
		--task.wait(5)
	end
	
	local function prepPlayerLevel(player)
		return preparePlayer(player, flagsMapFolder)
	end
	
	Utils.ProcessPlayers(prepPlayerLevel)
		
	-- load new guards if difficulty is already set.  Otherwise, this will be done when
	-- a player is teleported in with the difficulty data
	if GameParameters.Difficulty then
		LevelLoader.loadGuards(level, GameParameters.Difficulty, map)
	end
	
	for _, terrainObj in pairs(levelParms.terrain) do
		local levelObj = TerrainObjsFolder:FindFirstChild(terrainObj)
		if levelObj then
			local terrainClone = levelObj:Clone()
			terrainClone.Parent = workspace.Terrain
		end
	end
	
	for property, value in pairs(levelParms.lighting) do
		if typeof(value) == "table" then
			for prop, val in pairs(value) do
				LightingService[property][prop] = val
			end
		else
			LightingService[property] = value
		end
	end
	
	local lightingObjectsFolder = levelParms.lightingObjects or "default"
	local lightingObjects = LightingFolder:FindFirstChild(lightingObjectsFolder):GetChildren()
	loadLightingObjects(lightingObjects)
	
	local coinRegenTime = levelParms.coinRegenTime or GameParameters.default_coin_regen_time
	loadCoins(map, levelParms.levelCoins, coinRegenTime)
	CoinService.MapInit(map, coinRegenTime)

	map.Name = "ActiveMap"
	map.Parent = workspace
	
	-- Collection service setup for objective/flag touch events
	local conn

	-- ObjectivesSetup is unique per map, stored under the Flags folder
	local ObjectivesSetup = require(flagsMapFolder:WaitForChild("ObjectivesSetup"))
	local function setupObjTouchEvents(flagModel)
		if not flagModel:FindFirstAncestor("ActiveMap") then return end
		if connected[flagModel.Name] then return end
		connected[flagModel.Name] = true
		local flagPoints = flagModel:GetAttribute("Points")
		if not flagPoints then
			flagPoints = levelParms.levelFlagPoints or GameParameters.default_flag_points
			flagModel:SetAttribute("Points", flagPoints)
		end
		ObjectivesSetup.setup(flagModel, function()
			LevelLoader.loadLevel(level + 1)
		end)
	end
	
	local objTag = "Flag"
	conn = CollectionService:GetInstanceAddedSignal(objTag):Connect(function(flagModel)
		setupObjTouchEvents(flagModel)
	end)
	
	local flags = CollectionService:GetTagged(objTag)
	for _, flagModel in pairs(flags) do
		setupObjTouchEvents(flagModel)
	end
	
	return map
	
end

Players.PlayerAdded:Connect(function(player)
	local activeMap = workspace:WaitForChild("ActiveMap")
	local flagsMapFolder = activeMap:WaitForChild("Flags")
	local localFlagsScripts = flagsMapFolder:WaitForChild("LocalScripts")
	loadLocalScripts(player, localFlagsScripts:GetChildren())
	setCapturedItemsGui(player)
end)


LevelScreenReadyEvent.OnServerEvent:Connect(function(player)
	-- if this player's level/map is already ready, hide now
	local activeMap = workspace:WaitForChild("ActiveMap")
	local flagsMapFolder = activeMap:WaitForChild("Flags")
	local localFlagsScripts = flagsMapFolder:WaitForChild("LocalScripts")
	loadLocalScripts(player, localFlagsScripts:GetChildren())

	local playerLevelSpawn = activeMap:WaitForChild("LevelSpawn")
	local spawnPos = playerLevelSpawn:GetPivot().Position

	local pos = CFrame.new(spawnPos.X, spawnPos.Y, spawnPos.Z)
	task.defer(function()
		player.character:PivotTo(pos)
	end)
	--preparePlayer(player, flagsMapFolder)
	--HideLevelGenerationScreenEvent:FireClient(player)
	player:SetAttribute("ready", true)
	BonusTimeMgr.beginBonusRound(GameData.CurrentLevel)
end)

return LevelLoader
