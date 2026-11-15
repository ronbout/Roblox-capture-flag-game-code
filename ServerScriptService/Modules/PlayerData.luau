local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameInfo = ReplicatedStorage:WaitForChild('GameInfo')
local playerDataSchema = require(GameInfo.PlayerDataSchema)
local Players = game:GetService("Players")

local PlayerData = {}

-- Canonical runtime data
local dataCache = {}

------------------------------------------------------------
-- Internal utility: Create or update the leaderstats UI
------------------------------------------------------------
local function syncLeaderstat(player, key, value)
	local info = playerDataSchema[key]
	if not info or not info.loadType or info.loadType ~= "leaderstats" then return end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local stat = leaderstats:FindFirstChild(key)
	if not stat then
		stat = Instance.new(info.type)
		stat.Name = key
		stat.Parent = leaderstats
	end

	stat.Value = value
end


--------------------------------------------------------------------------------------------
-- Internal utility: route data to either leaderstats or attribute... or potentionally other
--------------------------------------------------------------------------------------------
local function udpGameData(player, key, value, loadType )
	if 'leaderstats' == loadType then
		syncLeaderstat(player, key, value)
	elseif 'attribute' == loadType then
		player:SetAttribute(key, value)
	--elseif 'tools' == loadType then
		--**** for now, let's leave the tool functionality to the PlayerRoutines script
		--setTools(player, value)
	end
end

------------------------------------------------------------
-- Public API: Initialize player data
------------------------------------------------------------
function PlayerData.Init(player, dbData)
	local uid = player.UserId
	dataCache[uid] = dbData or {}
	
	--print ('playerDataSchema: ', playerDataSchema)

	-- Fill missing schema-defined fields
	for key, info in pairs(playerDataSchema) do
		if dataCache[uid][key] == nil then
			dataCache[uid][key] = info.default
		end

		udpGameData(player, key, dataCache[uid][key], info.loadType)

	end
end

------------------------------------------------------------
-- Set a data field (= behavior)
------------------------------------------------------------
function PlayerData.Set(player, key, value, addFlag)
	local uid = player.UserId
	local info = playerDataSchema[key]
	if not info then return -1 end

	if addFlag then
		if key == "Tools" then
			if not table.find(dataCache[uid].Tools, value) then
				table.insert(dataCache[uid].Tools, value)
			end
		elseif type(dataCache[uid][key]) ~= "number" or type(value) ~= "number" then 
			return -2 
		else
			dataCache[uid][key] += value
		end
	else
		dataCache[uid][key] = value
	end
	udpGameData(player, key, dataCache[uid][key], info.loadType)

end

------------------------------------------------------------
-- Read data
------------------------------------------------------------
function PlayerData.Get(player, key)
	return dataCache[player.UserId][key]
end

------------------------------------------------------------
-- Get canonical data for saving
------------------------------------------------------------
function PlayerData.Export(player)
	return dataCache[player.UserId]
end

return PlayerData

