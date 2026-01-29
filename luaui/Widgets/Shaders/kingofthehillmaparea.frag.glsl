#version 450 core

// This shader is used by the King of the Hill widget for drawing the outlines of start boxes and the hill

const int MAX_TEAMS = 32;// Arbitrary array size

const vec4 DEFAULT_HILL_COLOR = vec4(0.5, 0.5, 0.5, 0.5);// The hill outline color when no one is king

const float LINE_THICKNESS = 1;// The thickness of the outlines in world space units

const float BLUR_FACTOR = 80;// How much blur there should be around the edges of the outlines (higher number = less blur)

//##UBO##

layout (std140, binding = 6) uniform data
{
	mat2x4[MAX_TEAMS] startAreas;// First column - x,y = center; rect: z,w = half size | circle: z = radius, w = -1
	//								Second column - color
	
	vec4 hillArea;// x,y = center; rect: z,w = half size | circle: z = radius, w = -1
	
	int hillColorIndex;// The teamColors index for the hill color or -1 for DEFAULT_HILL_COLOR
	
	int numTeams;// The actual number of current teams
};

uniform sampler2D depthBuffer;

in vec2 uvCoord;

in vec2 ndCoord;

out vec4 fragColor;

float signedDistanceBox(vec2 point, vec2 box, float radius)
{
    vec2 d = abs(point) - box + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

float signedDistanceCircle(vec2 point, float radius)
{
    return length(point) - r;
}

// Gets the number to multiply this line's color by to add to the frag color
// area - the map area using the format above
// worldPos - the world position of this fragment
// lineThickness - the half thickness of the outline in world coord units
// blurFactor - how much blur there should be around the edges of the outline (higher number = less blur)
//
// returns - number between 0 and 1 inclusive
float getOutlineFactor(vec4 area, vec4 worldPos, float lineThickness, float blurFactor)
{
	float sd;
	if(area.w == -1) {//Circle
		sd = signedDistanceCircle(worldPos.xy - area.xy, area.z);
	} else {//Rect
		sd = signedDistanceBox(worldPos.xy - area.xy, area.zw, 0.0);//TODO remove radius param if not using
	}
	return min(max((lineThickness - abs(sd)) * blurFactor, 0), 1);
}

void main()
{
	//The depth value of the current fragment from the depth buffer
	float depth = texture(depthBuffer, uvCoord).x;
	//The fragment in normalized device coordinates [-1, 1]
	vec4 ndcPos = vec4(ndCoord, depth, 1.0);
	//The world position of the current fragment in world coords
	vec4 worldPos = cameraViewProjInv * ndcPos;
	worldPos = worldPos / worldPos.w;
	
	//return early if world coord is not within the map
	if(worldPos.x < 0 || worldPos.z < 0 || worldPos.y < mapHeight.x || worldPos.y > mapHeight.y || worldPos.x > mapSize.x || worldPos.z > mapSize.z) {
		return;
	}
	
	//check each team outline and color in this fragment if it is on the outline
	for(int i = 0; i < numTeams; i++) {
		mat2x4 area = startAreas[i];
		fragColor = fragColor + area[1] * getOutlineFactor(area[0], worldPos, LINE_THICKNESS, BLUR_FACTOR);
	}
	
	//color in this fragment if it is on the hill outline
	vec4 hillColor = hillColorIndex == -1 ? DEFAULT_HILL_COLOR : startAreas[hillColorIndex][1];
	fragColor = fragColor + hillColor * getOutlineFactor(hillArea, worldPos, LINE_THICKNESS, BLUR_FACTOR);
	
}