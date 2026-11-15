local DataStoreService = game:GetService("DataStoreService")

local MAX_RETRIES	= 5
local BASE_DELAY	= 0.5


local DataStore = {}

DataStore.__index = DataStore

-- CONSTRUCTOR
function DataStore.new(dataStoreName)
	local self = setmetatable({}, DataStore)

	self.dataStore = DataStoreService:GetDataStore(dataStoreName)

	return self
end


-- STATIC HELPER METHODS
function DataStore.RetryWrapper(callback, callbackName, key)
	local lastError, success, result
	for attempt = 1, MAX_RETRIES do

		success, result = pcall(callback)

		if success then
			--print ("[DataStore] Success: " .. callbackName .. " for key " .. tostring(key))
			return true, result
		else
			lastError = result
			warn(("[DataStore] %s failed for key %s (attempt %d/%d): %s")
				:format(callbackName, tostring(key), attempt, MAX_RETRIES, tostring(result)))

			-- small delay, maybe exponential-ish
			task.wait(BASE_DELAY * attempt)
		end
	end
	-- we tried; still failed
	warn(("[DataStore] %s permanently failed for key %s: %s")
		:format(callbackName, tostring(key), tostring(lastError)))

	return false, nil
end


-- INSTANCE METHODS
function DataStore:Get(key)

	local function getFn()
		return self.dataStore:GetAsync(key)
	end

	return DataStore.RetryWrapper(getFn, "GetAsync", key)
	-- code in question below ***
	--return DataStore.RetryWrapper(self.dataStore:GetAsync, "GetAsync", key)
end

function DataStore:Set(key, data)

	local function setFn()
		return self.dataStore:SetAsync(key, data)
	end

	return DataStore.RetryWrapper(setFn, "SetAsync", key)
end

return DataStore