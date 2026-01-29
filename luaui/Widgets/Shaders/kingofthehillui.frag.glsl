#version 450 core

// This shader is used by the King of the Hill widget for drawing the progress bars

const vec4 BACKGROUND_COLOR = vec4(0.1, 0.1, 0.1, 0.35);// Background color of progress bar

const vec4 BORDER_COLOR = vec4(0.5, 0.5, 0.5, 0.5);// The color of the progress bar outline

const float BORDER_THICKNESS = 1;// Thickness of outline in pixels

const float BORDER_RADIUS = 2;// The border radius of the progress bar in pixels

layout (std140, binding = 6) uniform data
{
	vec4 color;// Color of progress bar
	
	float progress;// The progress level
	
	int type;// The type of progress bar that this is (0 = normal team bar, 1 = king team bar, 2 = capture bar)
};

in vec2 uvCoord;

out vec4 fragColor;

float signedDistanceBox(vec2 point, vec2 box, float radius)
{
    vec2 d = abs(point) - box + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

void main()
{
	//used to change colors for filled portion and unfilled portion of bar
	float fillFactor = max(min(((progress * 1.01) - uvCoord.x) * 80, 1), 0);
	//creates a vertical gradient along the bar
	float verticalGradientFactor = 0.8 + uvCoord.y * uvCoord.y * 0.5;
	
	fragColor = (color * fillFactor * verticalGradientFactor) + ((1 - fillFactor) * BACKGROUND_COLOR);
	
	//aspect ratio scaling to create circular corners
	//assumes width >= height
	float duvdyCoarse = dFdyCoarse(uvCoord.y);
	float duvdxCoarse = dFdxCoarse(uvCoord.x);
	vec2 scaledBox = vec2(0.5 / duvdxCoarse, 0.5 / duvdyCoarse);
	vec2 scaledPos = vec2((uvCoord.x - 0.5) / duvdxCoarse, (uvCoord.y - 0.5) / duvdyCoarse);
	
	float sd = signedDistanceBox(scaledPos, scaledBox, BORDER_RADIUS);
	float borderFactor = min(max((sd + BORDER_THICKNESS) * 100, 0), 1);
	float aplhaFactor = max(min(-sd * 10, 1), 0);
	
	vec4 borderColor = type == 2 ? BORDER_COLOR : vec4(color.xyz, BORDER_COLOR.w);
	
	fragColor = ((1 - borderFactor) * fragColor) + (borderFactor * borderColor);
	fragColor.w = fragColor.w * aplhaFactor;
}