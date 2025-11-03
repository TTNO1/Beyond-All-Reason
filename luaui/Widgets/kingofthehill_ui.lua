---@diagnostic disable: unused-function
-----------------------------------------------------------------------------------------------
--
-- Copyright 2024
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the “Software”), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
-- the Software, and to permit persons to whom the Software is furnished to do so,
-- subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
-- FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
-- COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
-- IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
-- CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--
-----------------------------------------------------------------------------------------------
--
-- Name: King of the Hill
-- Description: This gadget modifies the game behavior for the king of the hill game mode when it is enabled
-- Author: 'Saul Goodman
--
-----------------------------------------------------------------------------------------------
--
-- Documentation
--
-- This widget adds the unsynced UI functionality for a King of the Hill game mode. This
-- widget adds a box to the stack of boxes in the bottom-right corner of the screen. The box
-- contains a progress bar with each ally team's color filling a portion of the progress bar
-- proportionate to the amount of time that they have been king. This widget also draws outlines
-- on the map around each team's starting box and the hill region.
-- TODO explain shaders and opengl once figured out
--
-- Note: In all comments and documentation, "holding the hill" means the same thing as being the king.
--
-- There are a number of classes used in this widget which are explained below.
-- Set:
--   The set class is just a collection of stuff. It mimics the Java Set class.
-- MapArea:
--   Defines an area on the map such as a startbox or the hill region. This class has subclasses
--   for each shape.
-- RectMapArea:
--   A subclass of MapArea for rectangular areas.
-- CircleMapArea:
--   A subclass of MapArea for circular areas.
--
--
-- TODO: add more documentation
--
-----------------------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name = "King of the Hill",
		desc = "Adds UI for King of the Hill game mode.",
		author = "'Saul Goodman",
		date = "2025",
		license = "MIT",
		layer = 0,
		enabled = true
	};
end

-- #region Global Constants and Functions
local Spring = Spring
local Game = Game
local mapSizeX = Game.mapSizeX
local mapSizeZ = Game.mapSizeZ
local UnitDefs = UnitDefs
local UnitDefNames = UnitDefNames
local fps = Game.gameSpeed
local vsx, vsy--view size x and y
local gl = gl
local VFS = VFS
-- #endregion

-- /////////////////////////////
-- #region     Utils
-- /////////////////////////////

-- ---- Util Classes ----
-- ----------------------

--A Set class based on the Java API Set
local Set = {
	mt = {}
}
Set.mt.__index = Set
function Set.new()
	local set = {size = 0, elements = {}}
	setmetatable(set, Set.mt)
	return set
end
function Set:add(element)
	if not self.elements[element] then
		self.elements[element] = true
		self.size = self.size + 1
	end
end
function Set:addAll(...)
	for _, value in ipairs({...}) do
		self:add(value)
	end
end
function Set:remove(element)
	if self.elements[element] then
		self.elements[element] = nil
		self.size = self.size - 1
	end
end
function Set:removeAll(...)
	for _, value in ipairs({...}) do
		self:remove(value)
	end
end
function Set:retain(...)
	local newElements = {}
	local newSize = 0
	for _, value in ipairs({...}) do
		if self.elements[value] then
			newElements[value] = true
			newSize = newSize + 1
		end
	end
	self.elements = newElements
	self.size = newSize
end
function Set:contains(element)
	return self.elements[element]
end
function Set:containsAll(...)
	for _, value in ipairs({...}) do
		if not self.elements[value] then
			return false
		end
	end
	return true
end
function Set:clear()
	self.elements = {}
	self.size = 0
end
function Set:iter()
	return function (invariantState, controlVariable)
		local element = next(invariantState, controlVariable)
		return element
	end, self.elements, nil
end
function Set:unpack(lastElement)
	local nextElement = next(self.elements, lastElement)
	if nextElement ~= nil then
		return nextElement, self:unpack(nextElement)
	end
end

-- ---- Util Functions & Variables ----
-- ------------------------------------

local tonumber = tonumber

local string = string

local math = math

table.unpack = table.unpack or unpack

local table = table

local function distance(x1, z1, x2, z2)
	return math.sqrt((x2-x1)^2 + (z2-z1)^2)
end

-- copied from https://stackoverflow.com/a/7615129
local function splitStr(inputstr, sep)
	if sep == nil then
		sep = "%s"
	end
	local t = {}
	for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
		table.insert(t, str)
	end
	return t
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

-- /////////////////////////////
-- #endregion  Utils
-- /////////////////////////////

-- #region Hill Area Classes
-- These classes define the hill area and provide general methods such as isInside(x,y) for various shapes (circle and square)

local MapArea = {
	mt = {}
}
MapArea.mt.__index = MapArea
function MapArea.new(args)
	args = args or {}
	setmetatable(args, MapArea.mt)
	return args
end

local RectMapArea = {
	mt = {}
}
setmetatable(RectMapArea, MapArea.mt)
RectMapArea.mt.__index = RectMapArea
function RectMapArea.new(args)
	if not args.left or not args.right or not args.top or not args.bottom then
		error("Missing one or more arguments for new RectMapArea", 2)
	end
	args = MapArea.new(args)
	setmetatable(args, RectMapArea.mt)
	return args
end
function RectMapArea:isPointInside(x, z)
	return x >= self.left and x <= self.right and z >= self.bottom and z <= self.top
end
function RectMapArea:isBuildingInside(x, z, sizeX, sizeZ)
	local top, right, bottom, left = z + sizeZ/2, x + sizeX/2, z - sizeZ/2, x - sizeX/2
	return top <= self.top and right <= self.right and bottom >= self.bottom and left >= self.left
end

local CircleMapArea = {
	mt = {}
}
setmetatable(CircleMapArea, MapArea.mt)
CircleMapArea.mt.__index = CircleMapArea
function CircleMapArea.new(args)
	if not args.x or not args.z or not args.radius then
		error("Missing one or more arguments for new CircleMapArea", 2)
	end
	args = MapArea.new(args)
	setmetatable(args, CircleMapArea.mt)
	return args
end
function CircleMapArea:isPointInside(x, z)
	return distance(x, z, self.x, self.z) <= self.radius
end
function CircleMapArea:isBuildingInside(x, z, sizeX, sizeZ)
	local top, right, bottom, left = z + sizeZ/2, x + sizeX/2, z - sizeZ/2, x - sizeX/2
	return self:isPointInside(left, top) and self:isPointInside(right, top) and self:isPointInside(right, bottom) and self:isPointInside(left, bottom)
end

-- #endregion

-- #region Configuration Constants

--Defines the maximum value of the coordinate system used in the hill area mod option
local mapAreaScale = 200

--Defines the default hill area used if the mod option string is invalid
local defaultHillArea = RectMapArea.new{left = 75*mapSizeX/mapAreaScale, right = 125*mapSizeX/mapAreaScale, top = 125*mapSizeZ/mapAreaScale, bottom = 75*mapSizeZ/mapAreaScale}

--Defines the number of frames per each update of KOTH related states
local framesPerUpdate = 6

--Defines the unscaled UI box height
local uiBoxHeight = 44

--Defines the default width of the UI box if there are no boxes below it to go off of
local defaultUIBoxWidth = 340

--Defines the margins arounf the progress bar as a proportion of the total UI box size
local progressBarXMargin = 0.125
local progressBarYMargin = 0.25

--Shader file paths
local vertexShaderPath = "LuaUI/Shaders/kingofthehill.vert.glsl"
local progressBarFragmentShaderPath = "LuaUI/Shaders/kingofthehillui.frag.glsl"

-- #endregion

-- #region Mod Options

-- the MapArea defining the hill
local hillArea

-- whether or not players can build outside of their start area or the captured hill
local buildOutsideBoxes

-- game duration in milliseconds
local gameDuration

-- gameDuration in frames
local gameDurationFrames

-- the number of milliseconds an ally team must occupy the hill to capture it
local captureDelay

-- captureDelay in frames
local captureDelayFrames

-- health multiplier for capture qualified units
local healthMultiplier

--Whether the king has globalLOS
local kingGlobalLos

-- #endregion

-- #region Main Variables

-- teamId to allyTeamId for all teams (faster than calling Spring functions every time a team's allyTeam is needed)
local teamToAllyTeam = {}

-- allyTeamId to RectMapArea defining the allyTeam's starting area (faster than calling Spring functions every time start area is needed)
local startBoxes = {}

--The OpenGL DisplayList for the UI box
local uiBoxDisplayList

--Whether the screen was resized and the UI needs to be regenerated
local screenResized

--The current UI box position
local uiBoxPosition

--The VBO and VAO for the progress bar rectangle
local progressBarVBO
local progressBarVAO

--The shaders for the progress bar
local progressBarShader

-- #endregion Main Variables


--TODO add WG api functns (GetPosition)


-- Parses the string modoption that defines the hill area and returns a MapArea object
local function parseAreaString(string)
	local words = splitStr(string)
	if #words < 4 then
		--TODO not sure if Spring.Log works in synced
		Spring.Log("KOTH", "error", "Not enough arguments in area string. Resorting to default area box.")
		return defaultHillArea
	end
	local shape = words[1]
	local nums = {}
	local numArgumentCount
	if shape == "rect" then
		numArgumentCount = 4
	elseif shape == "circle" then
		numArgumentCount = 3
	else
		Spring.Log("KOTH", "error", "Invalid shape in area string. Resorting to default area box.")
		return defaultHillArea
	end
	
	for i = 1, numArgumentCount, 1 do
		local num = tonumber(words[i+1])
		if not num or num < 0 or num > mapAreaScale then
			Spring.Log("KOTH", "error", "Invalid number in area string. Resorting to default area box.")
			return defaultHillArea
		end
		nums[i] = num
	end
	
	if shape == "rect" then
		return RectMapArea.new({left = nums[1]*mapSizeX/mapAreaScale, top = nums[2]*mapSizeZ/mapAreaScale, right = nums[3]*mapSizeX/mapAreaScale, bottom = nums[4]*mapSizeZ/mapAreaScale})
	elseif shape == "circle" then
		return CircleMapArea.new({x = nums[1]*mapSizeX/mapAreaScale, z = nums[2]*mapSizeZ/mapAreaScale, radius = nums[3]*math.max(mapSizeX, mapSizeZ)/mapAreaScale})
	end
	
end

--Called when the addon is (re)loaded.
function widget:Initialize()
	
	--Get mod options to see if KOTH is enabled and, if so, get related settings
	local modOptions = Spring.GetModOptions()
	
	--Disable this widget if KOTH game mode is not enabled
	if not modOptions.kingofthehillenabled then
		widgetHandler.RemoveWidget()
		return
	end
	
	--Get and parse KOTH related mod options
	hillArea = parseAreaString(modOptions.kingofthehillarea)
	buildOutsideBoxes = not modOptions.kingofthehillbuildoutsideboxes
	gameDuration = (tonumber(modOptions.kingofthehillgameduration) or 30) * 60 * 1000
	gameDurationFrames = fps * gameDuration / 1000
	captureDelay = (tonumber(modOptions.kingofthehillcapturedelay) or 20) * 1000
	captureDelayFrames = fps * captureDelay / 1000
	healthMultiplier = tonumber(modOptions.kingofthehillhealthmultiplier) or 1
	kingGlobalLos = modOptions.kingofthehillkinggloballos
	
	local gaiaAllyTeamID
	if Spring.GetGaiaTeamID() then
		gaiaAllyTeamID = select(6, Spring.GetTeamInfo(Spring.GetGaiaTeamID()))
	end
	
	--Populate the startBoxes table with all allyTeam start boxes in the form of RectMapAreas
	--and populate teamAllyTeams
	for _, allyTeamId in ipairs(Spring.GetAllyTeamList()) do
		if allyTeamId == gaiaAllyTeamID then
			goto continue
		end
		local left, bottom, right, top = Spring.GetAllyTeamStartBox(allyTeamId)
		startBoxes[allyTeamId] = RectMapArea.new{left = left, top = top, right = right, bottom = bottom}
		for _, teamId in ipairs(Spring.GetTeamList(allyTeamId)) do
			teamToAllyTeam[teamId] = allyTeamId
		end
	    ::continue::
	end
	
	--Remove the call-in that cancels unpermitted build commands if building outside boxes is allowed
	if buildOutsideBoxes then
		widgetHandler.RemoveCallIn(nil, "AllowCommand")
	end
	
	vsx, vsy = Spring.GetViewGeometry()
	widget:ViewResize(vsx, vsy)
	
	progressBarVBO = gl.GetVBO(GL.ARRAY_BUFFER, false)
	progressBarVAO = gl.GetVAO()
	
	progressBarShader = gl.CreateShader({vertex = VFS.LoadFile(vertexShaderPath), fragment = VFS.LoadFile(progressBarFragmentShaderPath)})
	
end

-- Gets the position on the screen of the ui box of the widget below our box
-- We make our box the same width as the below box and put it right above
-- Returns top, left, bottom, right, scale
local function getBelowBoxPosition()
	
	local belowWidgetsInOrder = {"displayinfo", "unittotals", "music", "advplayerlist_api"}
	
	for _, widgetName in ipairs(belowWidgetsInOrder) do
		local widgetWG = WG[widgetName]
		if widgetWG then
			if widgetWG.GetPosition then
				local widgetPos = widgetWG.GetPosition()
				if widgetPos then
					return widgetPos
				end
			end
		end
	end
	
	local scale = Spring.GetConfigFloat("ui_scale", 1)
	return {0, math.floor(vsx-(defaultUIBoxWidth*scale)), 0, vsx, scale}
	
end

-- Updates uiBoxPosition to the correct value
local function updateUIBoxPosition()
	local belowBoxPos = getBelowBoxPosition()
	local top = belowBoxPos[1]
	local left = belowBoxPos[2]
	local bottom = belowBoxPos[3]
	local right = belowBoxPos[4]
	local scale = belowBoxPos[5]

	local scaledUIBoxHeight = math.ceil(uiBoxHeight * scale)
	uiBoxPosition = {
		left = left,
		right = right,
		top = top + scaledUIBoxHeight,
		bottom = top,
		width = right - left,
		height = scaledUIBoxHeight
	}
end

-- Called whenever the window is resized
function widget:ViewResize(vs_x, vs_y)
	vsx = vs_x
	vsy = vs_y
	-- Call here as well as in widget:DrawScreen because I have no idea the order
	-- of other widgets resizing so we want the best chance of getting it right
	updateUIBoxPosition()
	screenResized = true
end

-- Converts the given x and y screen coordinates to clip space (-1 to 1)
local function convertToClipSpace(x, y)
	if x and y then
		return 2*x/vsx - 1, 2*y/vsy - 1
	elseif x then
		return 2*x/vsx - 1
	elseif y then
		return 2*y/vsy - 1
	else
		return nil
	end
end

local function generateUIBoxDisplayList()
	gl.DeleteList(uiBoxDisplayList)
	uiBoxDisplayList = gl.CreateList(function ()
		WG.FlowUI.Draw.Element(uiBoxPosition.left, uiBoxPosition.bottom, uiBoxPosition.width, uiBoxPosition.height, 1, 0, 0, 1,  1, 0, 0, 1)
	end)
end

local function generateProgressBarVertices()
	local progBarXMargPixels = math.floor(uiBoxPosition.width * progressBarXMargin)
	local progBarYMargPixels = math.floor(uiBoxPosition.height * progressBarYMargin)
	local progBarPosClip = {
		left = convertToClipSpace(uiBoxPosition.left + progBarXMargPixels, nil),
		right = convertToClipSpace(uiBoxPosition.right - progBarXMargPixels, nil),
		top = convertToClipSpace(nil, uiBoxPosition.top - progBarYMargPixels),
		bottom = convertToClipSpace(nil, uiBoxPosition.bottom + progBarYMargPixels)
	}

	local progBarVertices = {
		progBarPosClip.left, progBarPosClip.top,
		progBarPosClip.left, progBarPosClip.bottom,
		progBarPosClip.right, progBarPosClip.top,
		progBarPosClip.right, progBarPosClip.bottom
	}

	progressBarVBO:define(#progBarVertices / 2, { { id = 0, name = "position", size = 2 } })
	progressBarVBO:upload(progBarVertices)
	progressBarVAO:AttachVertexBuffer(progressBarVBO)
end

-- No documentation. This is the call-in that many other widgets use to draw UI.
function widget:DrawScreen()
	
	if screenResized then
		
		--Call here as well as in widget:ViewResize because I have no idea the order
		-- of other widgets resizing so we want the best chance of getting it right
		updateUIBoxPosition()
		
		generateUIBoxDisplayList()
		
		generateProgressBarVertices()
		
		screenResized = false
		
	end
	
	gl.CallList(uiBoxDisplayList)
	
	gl.DepthTest(false)
	gl.DepthMask(false)
	
	gl.UseShader(progressBarShader)
	progressBarVAO:DrawArrays(GL.TRIANGLE_STRIP)
	gl.UseShader(0)
	
end