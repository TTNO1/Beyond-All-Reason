#version 450 core

// This shader is used by the King of the Hill widget for drawing the start box and hill outlines.

layout (location = 0) in vec2 vertex_position;

layout (location = 1) in vec2 uv_coord;

layout (location = 2) in vec2 nd_coord;

out vec2 uvCoord;

out vec2 ndCoord;

void main()
{
	gl_Position = vec4(vertex_position.xy, 0.0, 1.0);
	uvCoord = uv_coord;
	ndCoord = nd_coord;
}