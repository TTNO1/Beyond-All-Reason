function widget:GetInfo()
	return {
		name = "TransportPreview",
		desc = "Displays hologram of units to be unloaded from a transporter",
		author = "Saul Goodman",
		date = "2026",
		license = "MIT",
		layer = 0,
		enabled = true
	}
end

if not WG.DrawUnitShapeGL4 then
	return
end

local OWNER_ID = "transport_preview"
local UNIT_ALPHA = 0.5
local HALF_PI = math.pi / 2

local DrawUnitShapeGL4 = WG.DrawUnitShapeGL4
local StopDrawUnitShapeGL4 = WG.StopDrawUnitShapeGL4
local squareSize = Game.squareSize
local cmdUnloadUnits = CMD.UNLOAD_UNITS
local unitSquareSize = squareSize * 2
local UnitDefs = UnitDefs

local spGetActiveCommand = Spring.GetActiveCommand
local spGetSelectedUnitsSorted = Spring.GetSelectedUnitsSorted
local spGetUnitCommands = Spring.GetUnitCommands
local spGetUnitIsTransporting = Spring.GetUnitIsTransporting
local spGetUnitDefID = Spring.GetUnitDefID
local spGetBuildFacing = Spring.GetBuildFacing
local spTraceScreenRay = Spring.TraceScreenRay
local spGetMouseState = Spring.GetMouseState

local myTeamID = Spring.GetMyTeamID()
local buildingUnitDefs = {}
local transportUnitDefs = {}

for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.isBuilding or unitDef.isStaticBuilder then
		buildingUnitDefs[unitDefID] = unitDef
	end
	if unitDef.isTransport then
		transportUnitDefs[unitDefID] = unitDef
	end
end

--The update ID of the building preview under the cursor
local previewUpdateID
--The current active command ID
local activeCommandID

--Converts tables into strings. For debugging only. Copied from https://stackoverflow.com/a/27028488
local function dump(o)
	if type(o) == 'table' then
		local s = '{ '
		for k,v in pairs(o) do
			if type(k) ~= 'number' then k = '"'..k..'"' end
				s = s .. '['..k..'] = ' .. dump(v) .. ','
			end
		return s .. '} '
	else
		return tostring(o)
	end
end

--Gets the rotation angle corresponding to the build facing number
--facing 0=south(-z), 1=east(+x), 2=north(+z), 3=west(-x)
local function getRotationAngle(facing)
	return (-facing) * HALF_PI
end

local function addUnitHologram(unitDefID, outlineColor, x, y, z, updateID)
	local rotationY = getRotationAngle(spGetBuildFacing())
	return DrawUnitShapeGL4(unitDefID, x, y, z, rotationY, UNIT_ALPHA, myTeamID, nil, nil, updateID, OWNER_ID)
end

function widget:Initialize()
	
	Spring.Echo("LOLOL: " .. type(getfenv))
	
	--TODO handle changing teams, reloading, & spectator
	
end

function widget:CommandNotify(cmdID, cmdParams, cmdOptions)
	
	--Spring.Echo("notify: " .. tostring(cmdID))
	Spring.Echo("notify: " .. dump(cmdParams))
	
end

function widget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOptions, cmdTag)
	if unitTeam ~= myTeamID then
		return
	end
	if not transportUnitDefs[unitDefID] then
		return
	end
	local tranportees = spGetUnitIsTransporting(unitID)
	if #tranportees == 0 then
		return
	end
	
	local commandQueue = spGetUnitCommands(unitID, -1)
	for _, command in ipairs(commandQueue) do
		if command.id == cmdUnloadUnits then
			local firstBuildingUnitDef = buildingUnitDefs[spGetUnitDefID(tranportees[1])]
			
			
			return
		end
	end
	
end

function widget:ActiveCommandChanged(cmdID, cmdType)
	
	if activeCommandID == cmdUnloadUnits and previewUpdateID then
		StopDrawUnitShapeGL4(previewUpdateID)
		previewUpdateID = nil
	end
	
	activeCommandID = cmdID
	
end

function widget:Update()
	if activeCommandID ~= cmdUnloadUnits then
		return
	end
	
	local selectedTransport
	for unitDefID, unitIDs in pairs(spGetSelectedUnitsSorted()) do
		if transportUnitDefs[unitDefID] then
			if selectedTransport or #unitIDs > 1 then
				Spring.Echo("Multiple transporters")
				return
			end
			selectedTransport = unitIDs[1]
		end
	end
	if not selectedTransport then
		Spring.Echo("No Transporter")
		return
	end
	
	local tranportees = spGetUnitIsTransporting(selectedTransport)
	if #tranportees == 0 then
		Spring.Echo("No Transportees")
		return
	end
	
	local unitToUnload = tranportees[1]
	local unitToBeUnloadedDefID = spGetUnitDefID(unitToUnload)
	if not buildingUnitDefs[unitToBeUnloadedDefID] then
		Spring.Echo("Not A Building")
		return
	end
	--Spring.Echo("Is A Building")
	
	local mouseX, mouseY = spGetMouseState()
	
	local description, coords = spTraceScreenRay(mouseX, mouseY, true)
	if description == nil then -- off map
		return
	end
	local worldX, worldY, worldZ = coords[1], coords[2], coords[3]
	
	previewUpdateID = addUnitHologram(unitToBeUnloadedDefID, nil, worldX, worldY, worldZ, previewUpdateID)
	
end