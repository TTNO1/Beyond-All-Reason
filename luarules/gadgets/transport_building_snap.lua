function gadget:GetInfo()
    return {
        name      = "Snap Transport Buildings",
        desc      = "Snaps buildings to the grid after they are unloaded from a transport",
        author    = "Saul Goodman",
        date      = "March 2026",
        license   = "MIT",
        layer     = -30,--Must be less than layer of 'unit_prevent_unload_hax.lua'
        enabled   = true
    }
end

if not gadgetHandler:IsSyncedCode() then
    return false
end

local table = table
table.unpack = table.unpack or unpack

local UnitDefs = UnitDefs

local buildingUnitDefs = {}

for unitDefID, unitDef in pairs(UnitDefs) do
	if unitDef.isBuilding or unitDef.isStaticBuilder then
		buildingUnitDefs[unitDefID] = unitDef
	end
end

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

function gadget:AllowUnitTransportUnload(transporterID, transporterUnitDefID, transporterTeam, transporteeID, transporteeUnitDefID, transporteeTeam, x, y, z)
	if not buildingUnitDefs[transporteeUnitDefID] then
		return true
	end
	
	local facing = Spring.GetUnitBuildFacing(transporteeID)
	
	-- 0 = BLOCKED, 1 = OCCUPIED, 2 = RECLAIMABLE or OPEN
	local blockedStatus, featureID = Spring.TestBuildOrder(transporteeUnitDefID, x, y, z, facing)
	local isBlocked = blockedStatus ~= 2 or featureID
	Spring.Echo("blckd: " .. tostring(blockedStatus) .. " featID: " .. tostring(featureID))
	
	--The engine sometimes thinks that the unit is blocked when it is not, so, if it is truly blocked, return
	--true and let the engine handle moving to a new location.
	--If it is not truly blocked, return false so that the engine cannot incorrectly think it is blocked.
	--Then we have to unload the unit ourselves.
	if isBlocked then
		Spring.Echo("It's Blocked")--TODO LEFT OFF: duplicate unload command locations messing things up
		return true
	end
	
	Spring.UnitDetach(transporteeID)
	--Spring.UnitDetachFromAir(transporteeID)
	
	return false
end

function gadget:UnitUnloaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
	if not buildingUnitDefs[unitDefID] then
		return
	end
	
	local x, y, z = Spring.GetUnitPosition(unitID)
	local facing = Spring.GetUnitBuildFacing(unitID)
	--Spring.Echo("facing: " .. tostring(facing) .. " " .. tostring(math.random()))
	local buildX, buildY, buildZ = Spring.Pos2BuildPos(unitDefID, x, y, z, facing)
	Spring.SetUnitPosition(unitID, buildX, buildY, buildZ)
	Spring.SetUnitHeadingAndUpDir(unitID, facing, 0, 1, 0)
	
end

function gadget:UnitCommand(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
	
	Spring.Echo("cmd: " .. tostring(cmdID))
	Spring.Echo(dump(cmdParams))
	
end