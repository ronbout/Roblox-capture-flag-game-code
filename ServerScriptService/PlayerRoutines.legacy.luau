local DATA_STORE_NAME = "NPCPlayerData" -- eventually move this to a game-specific constants file
local Players = game:GetService("Players")
Players.CharacterAutoLoads = false
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local ServerModules = ServerScriptService:WaitForChild("Modules")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local LevelLoader = require(ServerModules:WaitForChild("LevelLoader"))
local RemoteEvents = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RemoteEvents")
local ResetFlagsDieEvent = RemoteEvents:WaitForChild("ResetFlagsDie")
local HideLevelGenerationScreenEvent = RemoteEvents:WaitForChild("HideLevelGenerationScreen")
local LoadingScreenReadyEvent = RemoteEvents:WaitForChild("LoadingScreenReady")
local TeleportEvent = RemoteEvents:WaitForChild("TeleportLobby")

local Utils = require(Modules:WaitForChild("Utils"))
local BonusTimeMgr = require(Modules:WaitForChild("BonusTimeMgr"))

local GameData = require(ServerModules:WaitForChild("GameData"))
local level = GameData.StartingLevel

GameData.CurrentLevel = level

local activeMap = LevelLoader.loadLevel(level)

local GameInfo = ReplicatedStorage:WaitForChild("GameInfo")
local PlayerData = require(ServerModules.PlayerData)
local DataStore = require(ServerModules.DataStore)
local GameParameters = require(GameInfo.GameParameters)

local autoSave = GameParameters.autoSave
local loadPlayerPosition = GameParameters.loadPlayerPosition
local ds = DataStore.new(DATA_STORE_NAME)

------------------------------------------------------------
-- Functions to Save and Load Player Position
------------------------------------------------------------
local function isValidPosition(position)
	return position.Y > -100
end

local function savePosition(player, position)
	local userId = player.UserId
	--print ("Save player: ", userId)
	--print ("Save position: ", position)
	
	PlayerData.Set(player, "Position", {position.X, position.Y, position.Z})

end

local function loadPosition(player, character)
	local userId = player.UserId

	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	
	--local savedCoords = PlayerData.Get(player, "Position")
	--print ("savedCoords", savedCoords)

	local playerLevelSpawn = activeMap:WaitForChild("LevelSpawn")
	local spawnCFrame = playerLevelSpawn.CFrame
	
	--print("Moving character to LevelSpawn:", levelSpawn:GetFullName(), levelSpawn.Position)

	--local pos = CFrame.new(spawnPos.X, spawnPos.Y, spawnPos.Z)
	task.defer(function()
		if character.Parent and player.Parent and humanoidRootPart then
			character:PivotTo(spawnCFrame)
			--print("Character pivot after move:", character:GetPivot().Position)
		end
	end)
end

------------------------------------------------------------
local function onCharacterAdded(character, player)
	local humanoid = character:WaitForChild("Humanoid")
	--warn("character added")

	--if loadPlayerPosition then
	--	loadPosition(player, character)
	--end
	
	loadPosition(player, character)

	local function onDied()
		print ("player died: ", player)
		PlayerData.Set(player, "LevelPoints", 0, false)
		activeMap = workspace:WaitForChild("ActiveMap")
		humanoid:UnequipTools()
		Utils.ProcessPlayerTools(player, Utils.Enums.ToolLoc.Both ,function(tool)
			tool.Parent = activeMap
		end)
		-- need to clear out the flags folder and reset the flag positions
		local plrFlagsFolder = player:WaitForChild("Flags")
		local capturedFlagsInfo = {}
		if plrFlagsFolder then
			for _, flag in pairs(plrFlagsFolder:GetChildren()) do
				--set up the data to send to the client to restore the flag
				table.insert(capturedFlagsInfo, {
					Name = flag.Name,
					Position = flag.Position.Value,
					Size = flag.Size.Value,
				})
				flag:Destroy()
			end
		end
		PlayerData.Set(player, "LevelPoints", 0, false)
		
		-- need to call remote event to reset the Flags Gui
		ResetFlagsDieEvent:FireClient(player, capturedFlagsInfo)
		player:LoadCharacter()
		
	end
	humanoid.Died:Connect(onDied)
end

local function onPlayerAdded(player)
	-- check for teleport data
	local difficulty = "Easy" -- default
	if not GameParameters.Difficulty then
		local joinData = player:GetJoinData()
		if joinData then
			local teleportData = joinData.TeleportData
			if teleportData then
				 difficulty = teleportData.Difficulty
			end
		end
		print ("Difficulty: ", difficulty)
		GameParameters.Difficulty = difficulty
		LevelLoader.loadGuards(GameData.CurrentLevel, difficulty, activeMap)
	end
	player:SetAttribute("ready", false)	
	local plrFlagsFolder = Instance.new("Folder")
	plrFlagsFolder.Name = "Flags"
	plrFlagsFolder.Parent = player

	local dbData = {}

	local success, result = ds:Get(player.UserId)

	if success then
		if result and next(result) ~= nil then
			--print ('success', result)
			dbData = result
			-- just for testing, always start with the default
			dbData = {}
			if dbData.Level ~= GameData.CurrentLevel then

			--[[
			
			TODO: the big question.  Do we just change the player's Level
					or do we re-run the levelLoader to match the player?
					
					This leads to la bigger game loop question of single/multi player
					and how the rounds/levels apply if multi players
					
			FOR NOW: just change the player data
			
			]]
				dbData.Level = GameData.CurrentLevel
			end
		else
			--print ('No record found')
			--dbData = {}
		end
	else
		print ("Fail.  Error: ", result)
		dbData = {}
	end

	PlayerData.Init(player, dbData)

	player:LoadCharacter()
	
	if player.Character then
		onCharacterAdded(player.Character, player)
	end
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(character, player)
	end)

	player.CharacterRemoving:Connect(function(character)
		-- just update the position in memory as the playerRemoved handles the datastore
		if isValidPosition(character:GetPivot().Position) then
			savePosition(player, character:GetPivot().Position)
		end
	end)

	if autoSave > 0 then
		coroutine.wrap(function()
			while player.Parent do
				task.wait(autoSave)
				-- update player position	
				
				if player.Character and isValidPosition(player.Character:GetPivot().Position) then
				savePosition(player, player.Character:GetPivot().Position)
			end
				local data = PlayerData.Export(player)
				local success, result = ds:Set(player.UserId, data)
				if not success then
					warn("Failed to save data for", player.Name, ":", result)
				else
					print ("Player data auto saved: ", player.Name, data)
				end
			end
		end)()
	end
end

-- Process players already in the game
for _, player in ipairs(Players:GetPlayers()) do
	task.defer(onPlayerAdded, player)
end

Players.PlayerAdded:Connect(onPlayerAdded)


-- SAVE DATA
Players.PlayerRemoving:Connect(function(player, reason)
	local data = PlayerData.Export(player)
	-- not saving LevelPoints (for now)
	if data.LevelPoints then data.LevelPoints = nil end
	--print ("player removing")
	
	--print ('data: ',data)
	--print (reason)

	local success, result = ds:Set(player.UserId, data)
	--print ('Player data save: ', success, result)

end)

LoadingScreenReadyEvent.OnServerEvent:Connect(function(player)
	-- if this player's level/map is already ready, hide now
	local activeMap = workspace:WaitForChild("ActiveMap")
	local playerLevelSpawn = activeMap:WaitForChild("LevelSpawn")
	HideLevelGenerationScreenEvent:FireClient(player)
	player:SetAttribute("ready", true)
	BonusTimeMgr.beginBonusRound(level)
end)

TeleportEvent.OnServerEvent:Connect(function(player)
	local lobbyPlaceId = GameParameters.lobbyPlaceId
	local teleportOptions = Instance.new("TeleportOptions")
	local success, err = pcall(function()
		TeleportService:TeleportAsync(lobbyPlaceId, {player})
	end)
	if not success then
		warn("Teleport failed: " .. err)
	end
end)

