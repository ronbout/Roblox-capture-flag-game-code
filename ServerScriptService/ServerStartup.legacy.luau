local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local ServerModules = ServerScriptService:WaitForChild("Modules")
local GameData = require(ServerModules:WaitForChild("GameData"))

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameInfo = ReplicatedStorage:WaitForChild("GameInfo")
local GameParameters = require(GameInfo.GameParameters)

local activeMap = workspace:WaitForChild("ActiveMap")
local levelSpawn = activeMap:WaitForChild("LevelSpawn")

-- only run this code if the map is "Castle"
if GameParameters.LevelParms[GameData.CurrentLevel].levelMap ~= "Castle" then return end

-- make the railings smooth to discourage the NPC's from climbing/walking up them

local function smoothRailings(railingModel)
	for _, part in railingModel:GetChildren() do
		if part:IsA("BasePart") then
			-- TODO: set all the surfaces to smooth
			part.TopSurface = Enum.SurfaceType.Smooth
			part.BottomSurface = Enum.SurfaceType.Smooth
			part.LeftSurface = Enum.SurfaceType.Smooth
			part.RightSurface = Enum.SurfaceType.Smooth
			part.FrontSurface = Enum.SurfaceType.Smooth
			part.BackSurface = Enum.SurfaceType.Smooth
		end
	end
end
local connected = {}
local conn

local objTag = "Railing"
conn = CollectionService:GetInstanceAddedSignal(objTag):Connect(function(railingModel)
	smoothRailings(railingModel)
end)

local railings = CollectionService:GetTagged(objTag)
for _, railingModel in pairs(railings) do
	smoothRailings(railingModel)
end

