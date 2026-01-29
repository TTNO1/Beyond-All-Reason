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
local GL = GL
local VFS = VFS

local screenCopyManager = WG['screencopymanager']
--local WG
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
-- #endregion
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
	args.type = "rect"
	args.centerX = (args.left + args.right) / 2
	args.centerZ = (args.top + args.bottom) / 2
	args.xSize = args.right - args.left
	args.zSize = args.top - args.bottom
	return args
end
function RectMapArea:isPointInside(x, z)
	return x >= self.left and x <= self.right and z >= self.bottom and z <= self.top
end
function RectMapArea:isBuildingInside(x, z, sizeX, sizeZ)
	local top, right, bottom, left = z + sizeZ/2, x + sizeX/2, z - sizeZ/2, x - sizeX/2
	return top <= self.top and right <= self.right and bottom >= self.bottom and left >= self.left
end
--Returns the Vec4 format of this area used in the map area shader
function RectMapArea:getVec4Representation()
	return {self.centerX, self.centerZ, self.xSize/2, self.zSize/2}
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
	args.type = "circle"
	return args
end
function CircleMapArea:isPointInside(x, z)
	return distance(x, z, self.x, self.z) <= self.radius
end
function CircleMapArea:isBuildingInside(x, z, sizeX, sizeZ)
	local top, right, bottom, left = z + sizeZ/2, x + sizeX/2, z - sizeZ/2, x - sizeX/2
	return self:isPointInside(left, top) and self:isPointInside(right, top) and self:isPointInside(right, bottom) and self:isPointInside(left, bottom)
end
--Returns the Vec4 format of this area used in the map area shader
function CircleMapArea:getVec4Representation()
	return {self.x, self.z, self.radius, -1}
end

-- #endregion

-- #region Configuration Constants

--Defines the maximum value of the coordinate system used in the hill area mod option
local mapAreaScale = 200

--Defines the default hill area used if the mod option string is invalid
local defaultHillArea = RectMapArea.new{left = 75*mapSizeX/mapAreaScale, right = 125*mapSizeX/mapAreaScale, top = 125*mapSizeZ/mapAreaScale, bottom = 75*mapSizeZ/mapAreaScale}

--Defines the default width of the UI box if there are no boxes below it to go off of
local defaultUIBoxWidth = 340

--Defines the top and bottom padding on the box in pixels
local uiBoxVerticalPadding = 10

--Defines the left coordinate of the progress bars relative to box width
local progressBarLeft = 0.05

--Defines the width of a team progress bar relative to box width
local progressBarWidth = 0.7

--Deifnes the height of a team progress bar in pixels
local progressBarHeight = 10

--Defines the vertical space between each team progress bar in pixels
local progressBarVerticalSpacing = 6

--The alpha value (opacity) to use for team colors in the progress bars
local progressBarColorAlpha = 0.4

--Deifnes the height of the capture progress bar in pixels
local captureProgressBarHeight = 15

--Progress bar shader file paths
local progressBarVertexShaderPath = "LuaUI/Widgets/Shaders/kingofthehillui.vert.glsl"
local progressBarFragmentShaderPath = "LuaUI/Widgets/Shaders/kingofthehillui.frag.glsl"

--The shaders for the progress bars
local progressBarShader = gl.CreateShader({vertex = VFS.LoadFile(progressBarVertexShaderPath),
											fragment = VFS.LoadFile(progressBarFragmentShaderPath)})
Spring.Log("KingOfTheHill_UI", "error", "Shader Log: \n" .. gl.GetShaderLog())

--The size of the progress bar fragment shader UBO in number of Vec4s
local progressBarFragmentShaderUBOVec4Size = 3

--Map area shader file paths
local mapAreaVertexShaderPath = "LuaUI/Widgets/Shaders/kingofthehillmaparea.vert.glsl"
local mapAreaFragmentShaderPath = "LuaUI/Widgets/Shaders/kingofthehillmaparea.frag.glsl"

--The shaders for the progress bars
local mapAreaShader = gl.CreateShader({vertex = VFS.LoadFile(mapAreaVertexShaderPath),
										fragment = VFS.LoadFile(mapAreaFragmentShaderPath):gsub("//##UBO##", gl.GetEngineUniformBuffer()),
										uniformInt = {depthBuffer = 0}})
Spring.Log("KingOfTheHill_UI", "error", "Shader Log: \n" .. gl.GetShaderLog())

--The size of the arrays in the map area fragment shader
local mapAreaFragmentShaderMaxTeams = 32

--The size of the progress bar fragment shader UBO in number of Vec4s
local mapAreaFragmentShaderUBOVec4Size = 2 * mapAreaFragmentShaderMaxTeams + 2

--Specifies the interval at which the UI is updated (i.e. updated every x frames)
local framesPerUpdate = 5

-- Used to update the position of the UI box multiple times after the screen is resized
-- since the ordering of the size updates from the lower widgets is unknown to me.
-- This represents the number of frames after the screen is resized for which we will
-- update the widget box size to match those below it
local maxScreenResizeCountdown = 6

-- #endregion

-- #region Mod Options

-- the MapArea defining the hill
local hillArea

-- whether or not players can build outside of their start area or the captured hill
local buildOutsideBoxes

-- the total time needed as king to win
local winKingTime

-- winKingTime in frames
local winKingTimeFrames

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

-- teamId to allyTeamId for all teams
local teamToAllyTeam = {}

-- array of allyTeamIds
local allyTeams = {}

-- the number of ally teams
local numAllyTeams = 0--TODO remove and replace with #allyTeams if not used frequently

-- allyTeamId to RectMapArea defining the allyTeam's starting area (faster than calling Spring functions every time start area is needed)
local startBoxes = {}

-- All game state variables below are only updated on an interval and may not exactly match the server at all times

-- allyTeamId to number of frames for which that team has held the hill
local allyTeamKingTime = {}

-- a table of allyTeamId to the average color of all the constituent teams
local allyTeamColors = {}

--The current king ally team's id.
local kingAllyTeam

--The frame on which the current king became king
local kingStartFrame

-- the allyTeamId of the ally team currently in the process of capturing the hill
local capturingAllyTeam

-- the frame at which the current capturing process will be complete (counting up or down, see below)
local capturingCompleteFrame

-- specifies the direction in which capturing progress is being made
-- true = up = progressing toward capturing the hill, false = down = losing progress that was previously made
local capturingCountingUp

--The UIElement for the box containing the progress bars
local uiBoxElement

-- allyTeamId to UIBar object for that team's progress bar
local allyTeamProgressBars = {}

-- The UIBar for the progress bar indicating the capture delay
local captureProgressBar

-- The UIMapAreas instance used for rendering start boxes and the hill
local uiMapAreasInstance;

-- Used to update the position of the UI box multiple times after the screen is resized
-- since the ordering of the size updates from the lower widgets is unknown to me
local screenResizeCountdown = 0

--Contains the position of the UI box. Used for WG API functions
local uiBoxPosition

-- #endregion

--//////////////////////////
-- #region       UI
--//////////////////////////

-- UI Util Functions
-- -----------------

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

-- Prevents switching shaders if it is currently active
local currentShader = nil
local function useShader(shader)
	if currentShader ~= shader then
		gl.UseShader(shader)
		currentShader = shader
	end
end

-- Gets the depth buffer based on various conditions
-- The logic in this function was copied from Beherith's Start Polygons widget
local advGroundShading = select(2, Spring.HaveAdvShading())
local function getDepthBufferTexture()
	if advGroundShading then
		return "$map_gbuffer_zvaltex"
	else
		return screenCopyManager.GetDepthCopy()
	end
end

-- UI Classes
-- ----------

-- A class for a generic UI element, by default, renders a basic FlowUI box
local UIElement = {
	mt = {}
}
UIElement.mt.__index = UIElement
function UIElement.new(args)
	args = args or {}
	setmetatable(args, UIElement.mt)
	args.top = args.top or 0
	args.bottom = args.bottom or 0
	args.left = args.left or 0
	args.right = args.right or 0
	args.children = args.children or Set.new()
	if args.parent then
		args.parent.children:add(args)
	end
	args.width = args.right - args.left
	args.height = args.top - args.bottom
	args.positionInvalid = true
	args.dataInvalid = true
	return args
end
-- Meant to be called every frame in draw callin. Updates and draws this element
function UIElement:drawFrame()
	if self.positionInvalid then
		self:updatePosition()
	end
	if self.dataInvalid then
		self:updateData()
	end
	self:draw()
end
-- draws this UI element
function UIElement:draw()
	gl.CallList(self.displayList)
end
-- updates the position data of the UI element (i.e. VBO vertices)
function UIElement:updatePosition()
	self:computeAbsoluteRect()
	self:updateData()
	self.positionInvalid = false
end
-- updates the data associated with this UI element (i.e. UBO, SSBO, etc.)
function UIElement:updateData()
	gl.DeleteList(self.displayList)
	self.displayList = gl.CreateList(function ()
		WG.FlowUI.Draw.Element(self.absLeft, self.absBottom, self.absRight, self.absTop, self.cornerTL, self.cornerTR, self.cornerBR, self.cornerBL, self.ptl, self.ptr, self.pbr, self.pbl,  self.opacity, self.color1, self.color2, self.bgpadding)
	end)
	self.dataInvalid = false
end
-- Invalidates the position data of this UI element (and all its children) so that it will be updated next render
function UIElement:invalidatePosition()
	self.positionInvalid = true
	for child in self.children:iter() do
		child:invalidatePosition()
	end
end
-- Invalidates the data associated with this UI element so that it will be updated next render
function UIElement:invalidateData()
	self.dataInvalid = true
end
function UIElement:setPos(args)
	if not ((args.top and args.top ~= self.top) or (args.right and args.right ~= self.right) or (args.bottom and args.bottom ~= self.bottom)
		or (args.left and args.left ~= self.left)) then
		return
	end
	self.top = args.top or self.top
	self.left = args.left or self.left
	self.bottom = args.bottom or self.bottom
	self.right = args.right or self.right
	self.width = self.right - self.left
	self.height = self.top - self.bottom
	self:invalidatePosition()
end
-- computes the absolute pixel coordinates of this UI element
-- abs coordinates are equivalent to x1 x2, y1 y2, relative coordinates are distance from side (like css)
function UIElement:computeAbsoluteRect()
	if self.parent then
		self.absLeft = self.parent.absLeft + (self.parent.absWidth * self.left)
		self.absRight = self.parent.absRight - (self.parent.absWidth * self.right)
		self.absBottom = self.parent.absBottom + (self.parent.absHeight * self.bottom)
		self.absTop = self.parent.absTop - (self.parent.absHeight * self.top)
		self.absWidth = self.absRight - self.absLeft
		self.absHeight = self.absTop - self.absBottom
	else
		self.absLeft = self.left
		self.absRight = self.right
		self.absBottom = self.bottom
		self.absTop = self.top
		self.absWidth = self.width
		self.absHeight = self.height
	end
end

-- A class for each UI progress bar
local UIBar = {
	mt = {},
	Type = {TEAM = 0, KING_TEAM = 1, CAPTURE = 2}--enum for type of progress bar
}
setmetatable(UIBar, UIElement.mt)
UIBar.mt.__index = UIBar
function UIBar.new(args)
	args = UIElement.new(args)
	if not args.color or not args.type then
		error("Missing one or more arguments for new UIBar", 2)
	end
	args.progress = args.progress or 0
	args.opacity = args.opacity or progressBarColorAlpha
	args.shader = args.shader or progressBarShader
	args.vbo = gl.GetVBO(GL.ARRAY_BUFFER, false)
	args.vbo:Define(4, {{id = 0, name = "position", size = 2}, {id = 1, name = "uv", size = 2}})
	args.vao = gl.GetVAO()
	args.vao:AttachVertexBuffer(args.vbo)
	args.ubo = gl.GetVBO(GL.UNIFORM_BUFFER, false)
	args.ubo:Define(1, progressBarFragmentShaderUBOVec4Size)--seconds arg expects size in number of Vec4s
	setmetatable(args, UIBar.mt)
	return args
end
function UIBar:draw()
	self.ubo:BindBufferRange(6, nil, nil, GL.UNIFORM_BUFFER)
	useShader(self.shader)
	self.vao:DrawArrays(GL.TRIANGLE_STRIP)
	self.ubo:UnbindBufferRange(6, nil, nil, GL.UNIFORM_BUFFER)
end
function UIBar:updatePosition()
	self:computeAbsoluteRect()
	--Progress bar region clip positions
	local left = convertToClipSpace(self.absLeft, nil)
	local right = convertToClipSpace(self.absRight, nil)
	local top = convertToClipSpace(nil, self.absTop)
	local bottom = convertToClipSpace(nil, self.absBottom)
	--Triangle strip vertices with uv
	local vertices = {
		left, top, 0, 1,
		left, bottom, 0, 0,
		right, top, 1, 1,
		right, bottom, 1, 0
	}
	self.vbo:Upload(vertices)
	self.positionInvalid = false
end
function UIBar:updateData()
	local color = self.color
	local data = {color[1], color[2], color[3], self.opacity, self.progress, self.type}
	local remainingFloats = progressBarFragmentShaderUBOVec4Size * 4 - #data
	for i = 1, remainingFloats, 1 do
		table.insert(data, 0.0)
	end
	self.ubo:Upload(data)
	self.dataInvalid = false
end
function UIBar:setProgress(progress)
	if math.abs(progress - self.progress) * self.absWidth >= 1 then
		self.progress = progress
		self:invalidateData()
	end
end
function UIBar:setColor(color)
	if self.color[1] == color[1] and self.color[2] == color[2] and self.color[3] == color[3] then
		return
	end
	self.color = color
	self:invalidateData()
end
function UIBar:setType(type)
	if self.type == type then
		return
	end
	self.type = type
	self:invalidateData()
end

-- A class for map area outlines rendered on the world
local UIMapAreas = {
	mt = {}
}
setmetatable(UIMapAreas, UIElement.mt)
UIMapAreas.mt.__index = UIMapAreas
function UIMapAreas.new(args)
	args = UIElement.new(args)
	args.allyTeamToIndex = {}--table of allyTeamId to its index in the UBO array
	args.hillColorIndex = -1
	args.shader = args.shader or mapAreaShader
	args.vbo = gl.GetVBO(GL.ARRAY_BUFFER, false)
	args.vbo:Define(4, {{id = 0, name = "position", size = 2}, {id = 1, name = "uv", size = 2}, {id = 2, name = "nd", size = 2}})
	args.vao = gl.GetVAO()
	args.vao:AttachVertexBuffer(args.vbo)
	args.ubo = gl.GetVBO(GL.UNIFORM_BUFFER, false)
	args.ubo:Define(1, mapAreaFragmentShaderUBOVec4Size)--seconds arg expects size in number of Vec4s
	setmetatable(args, UIMapAreas.mt)
	--Populate UBO with static data
	local data = {}
	for i = 1, math.min(numAllyTeams, mapAreaFragmentShaderMaxTeams), 1 do
		local allyTeam = allyTeams[i]
		args.allyTeamToIndex[allyTeam] = i
		local dataOffset = (i - 1) * 4
		local startBoxVec4 = startBoxes[allyTeam]:getVec4Representation()
		local color = allyTeamColors[allyTeam]
		for j = 1, 4, 1 do
			data[dataOffset + j] = startBoxVec4[j]
			data[dataOffset + j + 4] = color[j]
		end
	end
	local hillAreaVec4 = hillArea:getVec4Representation()
	for i = 1, 4, 1 do
		data[mapAreaFragmentShaderMaxTeams * 8 + i] = hillAreaVec4[i]
	end
	data[mapAreaFragmentShaderMaxTeams * 8 + 5] = args.hillColorIndex
	data[mapAreaFragmentShaderMaxTeams * 8 + 6] = numAllyTeams
	local remainingFloats = mapAreaFragmentShaderUBOVec4Size * 4 - #data
	for i = 1, remainingFloats, 1 do
		table.insert(data, 0.0)
	end
	args.ubo:Upload(data)
	return args
end
function UIMapAreas:draw()
	self.ubo:BindBufferRange(6, nil, nil, GL.UNIFORM_BUFFER)
	gl.Texture(0, getDepthBufferTexture())
	useShader(self.shader)
	self.vao:DrawArrays(GL.TRIANGLE_STRIP)
	gl.Texture(0, false)
	self.ubo:UnbindBufferRange(6, nil, nil, GL.UNIFORM_BUFFER)
end
function UIMapAreas:updatePosition()
	self:computeAbsoluteRect()
	--Progress bar region clip positions
	local left = convertToClipSpace(self.absLeft, nil)
	local right = convertToClipSpace(self.absRight, nil)
	local top = convertToClipSpace(nil, self.absTop)
	local bottom = convertToClipSpace(nil, self.absBottom)
	--Triangle strip vertices with uv and NDC
	local vertices = {
		left, top, 0, 1, -1, 1,
		left, bottom, 0, 0, -1, -1,
		right, top, 1, 1, 1, 1,
		right, bottom, 1, 0, 1, -1
	}
	self.vbo:Upload(vertices)
	self.positionInvalid = false
end
function UIMapAreas:updateData()
	self.vbo:Upload({self.hillColorIndex, numAllyTeams, 0, 0}, nil, mapAreaFragmentShaderUBOVec4Size - 1)
	self.dataInvalid = false
end
function UIMapAreas:setKingAllyTeam(kingAllyTeamId)
	local newHillColorIndex = self.allyTeamToIndex[kingAllyTeamId] or -1
	if self.hillColorIndex ~= newHillColorIndex then
		self.hillColorIndex = newHillColorIndex
		self:invalidateData()
	end
end

--///////////////
-- #endregion
--///////////////


--TODO add WG api functions (GetPosition)


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
	winKingTime = (tonumber(modOptions.kingofthehillwinkingtime) or 10) * 60 * 1000
	winKingTimeFrames = fps * winKingTime / 1000
	captureDelay = (tonumber(modOptions.kingofthehillcapturedelay) or 20) * 1000
	captureDelayFrames = fps * captureDelay / 1000
	healthMultiplier = tonumber(modOptions.kingofthehillhealthmultiplier) or 1
	kingGlobalLos = modOptions.kingofthehillkinggloballos
	
	-- Initialize the main box UIElement
	uiBoxElement = UIElement.new()
	
	local gaiaAllyTeamID
	if Spring.GetGaiaTeamID() then
		gaiaAllyTeamID = select(6, Spring.GetTeamInfo(Spring.GetGaiaTeamID()))
	end
	
	uiMapAreasInstance = UIMapAreas.new()
	
	--Populate the startBoxes table with all allyTeam start boxes in the form of RectMapAreas
	--Populate teamAllyTeams
	--Compute average color for ally team
	--Populate allyTeamProgressBars
	for _, allyTeamId in ipairs(Spring.GetAllyTeamList()) do
		if allyTeamId ~= gaiaAllyTeamID then
			table.insert(allyTeams, allyTeamId)
			numAllyTeams = numAllyTeams + 1
			allyTeamKingTime[allyTeamId] = 0
			
			local left, bottom, right, top = Spring.GetAllyTeamStartBox(allyTeamId)
			startBoxes[allyTeamId] = RectMapArea.new{left = left, top = top, right = right, bottom = bottom}
			
			local red, green, blue = 0, 0, 0
			local numTeams = 0
			
			for _, teamId in ipairs(Spring.GetTeamList(allyTeamId)) do
				teamToAllyTeam[teamId] = allyTeamId
				
				-- color average computed using squares (https://youtu.be/LKnqECcg6Gw)
				--TODO remove defaults
				local teamRed, teamGreen, teamBlue = Spring.GetTeamColor(teamId)
				red = red + teamRed ^ 2
				green = green + teamGreen ^ 2
				blue = blue + teamBlue ^ 2
				numTeams = numTeams + 1
			end
			
			-- r g b = 1 2 3
			local averageColor = {math.sqrt(red/numTeams), math.sqrt(green/numTeams), math.sqrt(blue/numTeams)}
			allyTeamColors[allyTeamId] = averageColor
			
			allyTeamProgressBars[allyTeamId] = UIBar.new({color = averageColor, type = UIBar.Type.TEAM, parent = uiBoxElement})
		end
	end
	
	-- color gets set when a team starts capturing
	captureProgressBar = UIBar.new({color = {0, 0, 0}, type = UIBar.Type.CAPTURE, parent = uiBoxElement})
	
	--Remove the call-in that cancels unpermitted build commands if building outside boxes is allowed
	if buildOutsideBoxes then
		widgetHandler.RemoveCallIn(nil, "AllowCommand")--TODO see if there is a widget side to this else remove
	end
	
	vsx, vsy = Spring.GetViewGeometry()
	widget:ViewResize(vsx, vsy)
	
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
	local top = math.ceil(belowBoxPos[1])
	local left = math.floor(belowBoxPos[2])
	local bottom = math.floor(belowBoxPos[3])
	local right = math.ceil(belowBoxPos[4])
	local scale = belowBoxPos[5]
	
	local scaledBoxVerticalPadding = math.ceil(uiBoxVerticalPadding * scale)
	local scaledBarHeight = math.ceil(progressBarHeight * scale)
	local scaledBarVerticalSpacing = math.ceil(progressBarVerticalSpacing * scale)
	local scaledCaptureBarHeight = math.ceil(captureProgressBarHeight * scale)
	local scaledUIBoxHeight = ((scaledBarHeight + scaledBarVerticalSpacing) * numAllyTeams) + (2 * scaledBoxVerticalPadding) + scaledCaptureBarHeight
	
	uiBoxPosition = {
		left = left,
		right = right,
		top = top + scaledUIBoxHeight,
		bottom = top,
		width = right - left,
		height = scaledUIBoxHeight,
		scale = scale
	}
	
	uiBoxElement:setPos(uiBoxPosition)
	
	local relativeBarHeight = scaledBarHeight / uiBoxPosition.height
	local relativeBarVerticalSpacing = scaledBarVerticalSpacing / uiBoxPosition.height
	local relativeBoxVerticalPadding = scaledBoxVerticalPadding / uiBoxPosition.height
	
	local barTopRelCoord = relativeBoxVerticalPadding
	for allyTeamId, uiBar in pairs(allyTeamProgressBars) do
		uiBar:setPos({top = barTopRelCoord, bottom = 1 - (barTopRelCoord + relativeBarHeight), left = progressBarLeft, right = 1 - (progressBarLeft + progressBarWidth)})
		barTopRelCoord = barTopRelCoord + relativeBarHeight + relativeBarVerticalSpacing
	end
	
	local captureBarRelativeHeight = scaledCaptureBarHeight / uiBoxPosition.height
	captureProgressBar:setPos({top = barTopRelCoord, bottom = 1 - (barTopRelCoord + captureBarRelativeHeight), left = progressBarLeft, right = 1 - (progressBarLeft + progressBarWidth)})
	
end

-- Called whenever the window is resized
function widget:ViewResize(vs_x, vs_y)
	vsx = vs_x
	vsy = vs_y
	--WG = _G.WG TODO localize flow ui
	uiMapAreasInstance:setPos({right = vsx, top = vsy})
	-- Call here as well as in widget:DrawScreen because I have no idea the order
	-- of other widgets resizing so we want the best chance of getting it right
	updateUIBoxPosition()
	screenResizeCountdown = maxScreenResizeCountdown
end

local updateCounter = 0
-- Called for every game simulation frame
-- Used to update the progress bar when there is a king
function widget:GameFrame(frame)
	updateCounter = updateCounter + 1
	if updateCounter < framesPerUpdate then
		return
	end
	updateCounter = 0
	
	local newKingStartFrame = Spring.GetGameRulesParam("kingStartFrame")
	local kingChanged = newKingStartFrame ~= kingStartFrame--King may still be the same if it changed and then changed back before we updated
	--														 but we still need to updated times if that is the case
	
	if kingChanged then
		local newKingAllyTeam = Spring.GetGameRulesParam("kingAllyTeam")
		if newKingAllyTeam ~= kingAllyTeam then--Prevent unnecessary invalidation of UIBar data if the king is what we still think it is
			if kingAllyTeam then
				allyTeamProgressBars[kingAllyTeam]:setType(UIBar.Type.TEAM)
			end
			if newKingAllyTeam then
				allyTeamProgressBars[newKingAllyTeam]:setType(UIBar.Type.KING_TEAM)
			end
			kingAllyTeam = newKingAllyTeam
			uiMapAreasInstance:setKingAllyTeam(kingAllyTeam)
		end
		
		for _, allyTeamId in ipairs(allyTeams) do
			local kingTime = Spring.GetGameRulesParam("allyTeamKingTime" .. allyTeamId)
			allyTeamKingTime[allyTeamId] = kingTime
			local progress = math.abs(kingTime) / winKingTimeFrames--TODO handle disqualified teams (negative time)
			allyTeamProgressBars[allyTeamId]:setProgress(progress)
		end
		kingStartFrame = newKingStartFrame
	end
	
	if kingAllyTeam then
		local newKingProgress = (allyTeamKingTime[kingAllyTeam] + (frame - kingStartFrame)) / winKingTimeFrames
		allyTeamProgressBars[kingAllyTeam]:setProgress(newKingProgress)
	end
	
	local newCapturingCompleteFrame = Spring.GetGameRulesParam("capturingCompleteFrame")
	local capturingTeamChanged = newCapturingCompleteFrame ~= capturingCompleteFrame
	
	capturingCountingUp = Spring.GetGameRulesParam("capturingCountingUp")
	
	if capturingTeamChanged then
		capturingCompleteFrame = newCapturingCompleteFrame
		capturingAllyTeam = Spring.GetGameRulesParam("capturingAllyTeam")
		if capturingAllyTeam then
			captureProgressBar:setColor(allyTeamColors[capturingAllyTeam])
		end
	end
	
	local captureProgress = (capturingCompleteFrame - frame) / captureDelayFrames
	captureProgress = math.max(captureProgress, 0)
	if capturingCountingUp then
		captureProgress = 1 - captureProgress
	end
	captureProgressBar:setProgress(captureProgress)
	
	--TODO test if updating vbo is faster than making new one
end

-- No documentation. This is the call-in that many other widgets use to draw UI.
function widget:DrawScreen()
	
	if screenResizeCountdown > 0 then
		-- Call here as well as in widget:ViewResize because I have no idea the order
		-- of other widgets resizing so we want the best chance of getting it right
		updateUIBoxPosition()
		screenResizeCountdown = screenResizeCountdown - 1
	end
	
	gl.DepthTest(false)
	gl.DepthMask(false)
	
	uiBoxElement:drawFrame()
	
	for allyTeamId, uiBar in pairs(allyTeamProgressBars) do
		uiBar:drawFrame()
	end
	
	captureProgressBar:drawFrame()
	
	useShader(0)
	
end

function widget:Shutdown()
	
	gl.DeleteShader(progressBarShader)
	
	--TODO delete map circle shader
	
	--TODO remove WG API functions
	
end