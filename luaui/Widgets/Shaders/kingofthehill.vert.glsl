#version 330 core

// This shader is used by the King of the Hill widget for drawing the progress bar and the boundary lines.

layout (location = 0) in vec2 vertex_position;

void main()
{
	gl_Position = vec4(vertex_position.xy, 0.0, 1.0);
}