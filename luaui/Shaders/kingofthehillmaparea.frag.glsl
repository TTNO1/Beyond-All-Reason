#version 450 core

// This shader is used by the King of the Hill widget for drawing the outlines of start boxes and the hill

const int MAX_TEAMS = 32;// Arbitrary array size

const vec4 DEFAULT_HILL_COLOR = vec4(0.65, 0.65, 0.65, 1.0);// The hill outline color when no one is king

const float LINE_THICKNESS = 1.0;// The thickness of the outlines in fragments

const float BLUR_FACTOR = 50.0;// How much blur there should be around the edges of the outlines (higher number = less blur)

//##UBO##

layout (std140, binding = 6) uniform allyTeamColors
{
	vec4[MAX_TEAMS] colors;// Colors of each ally team
};

uniform vec4[MAX_TEAMS] startAreas;// x,y = center (x,z); rect: z,w = half size | circle: z = radius, w = -1
	
uniform vec4 hillArea;// x,y = center (x,z); rect: z,w = half size | circle: z = radius, w = -1
	
uniform int numTeams;// The actual number of current teams

uniform int hillColorIndex;// The startAreas index for the hill color or -1 for DEFAULT_HILL_COLOR

//uniform int mapNormalsType;// 0 = $normals, 1 = $ssmf_normals, 2 = $map_gbuffer_normtex

uniform sampler2D depthBuffer;

uniform sampler2D mapNormals;

in vec2 uvCoord;

in vec2 ndCoord;

out vec4 fragColor;

float signedDistanceBox(vec2 point, vec2 box)
{
    vec2 d = abs(point) - box;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float signedDistanceCircle(vec2 point, float radius)
{
    return length(point) - radius;
}

// Gets the normal vector depending on the type of normal texture used
//
// worldPos - the world space position of the fragment
/*
vec4 getNormalVec(vec4 worldPos)
{
	vec2 normalTexSampleCoord = mapNormalsType == 2 ? uvCoord : worldPos.xz / mapSize.xz;
	vec4 normalVec = texture(mapNormals, normalTexSampleCoord);
	//For $normals, the normal texture stores the x and z components of the unit vec in the x and w coords of the returned vec4
	//If $normals, reconstruct the whole normal vec given that it should have a magnitude of 1; else wiki says we must do *2 -1
	if(mapNormalsType == 0) {
		normalVec = vec4(normalVec.x, sqrt(1.0 - dot(normalVec.xw, normalVec.xw)), normalVec.w, 0.0);
	} else if(mapNormalsType == 1) {
		normalVec = (normalVec * 2.0 - 1.0).xzyw;
	} else if(mapNormalsType == 2) {
		normalVec = normalVec * 2.0 - 1.0;
	}
	return normalVec;
}
*/

// Computes a unit vector that would be tangent to the given outline if the outline were thick enough to touch worldPos
//
// area - the map area using the format above
// worldPos - the world position to find the tangent at
vec2 getOutlineTangent(vec4 area, vec4 worldPos)
{
	vec2 localPos = worldPos.xz - area.xy;
	if(area.w == -1.0) {//Circle
		return normalize(vec2(-localPos.y, localPos.x));
	} else {//Rect
		vec2 absLocalPos = abs(localPos);
		if(absLocalPos.x > area.z || absLocalPos.y > area.w) {//Outside the rect
			vec2 radius = max(absLocalPos - area.zw, 0.0);
			return normalize(vec2(-radius.y, radius.x) * (2.0 * step(0.0, localPos) - 1.0));
		} else {//Inside the rect
			vec2 sdComponents = area.zw - absLocalPos;
			vec2 result = step(sdComponents.yx, sdComponents);
			result.x = max(result.x - result.y, 0.0);
			return result;
		}
	}
}

// Gets the number to multiply this line's color by to add to the frag color
//
// area - the map area using the format above
// worldPos - the world position of this fragment
// lineThickness - the half thickness of the outline in world coord units
// blurFactor - how much blur there should be around the edges of the outline (higher number = less blur)
//
// returns - number between 0 and 1 inclusive
float getOutlineFactor(vec4 area, vec4 worldPos, float lineThickness, float blurFactor)
{
	float sd;
	if(area.w == -1.0) {//Circle
		sd = signedDistanceCircle(worldPos.xz - area.xy, area.z);
	} else {//Rect
		sd = signedDistanceBox(worldPos.xz - area.xy, area.zw);
	}
	return min(max((lineThickness - abs(sd)) * blurFactor, 0.0), 1.0);
}

// Gets the number to multiply the pixel line thickess by to convert it to world coords
//
// fragSizeX - the horizontal size of the fragment in world coords
// fragSizeY - the vertical size of the fragment in world coords
// outlineTangent - a unit vector that would be tangent to the outline if it were thick enough to reach the fragment
// normalizedCameraRightVecXZ - a unit vector for the x and z components of the world space vector that points left to right across the screen
// normalizedCameraUpVecXZ - a unit vector for the x and z components of the world space vector that points bottom to top across the screen
float getLineThicknessFactor(float fragSizeX, float fragSizeY, vec2 outlineTangent, vec2 normalizedCameraRightVecXZ, vec2 normalizedCameraUpVecXZ)
{
	return (fragSizeY * abs(dot(outlineTangent, normalizedCameraRightVecXZ))) + (fragSizeX * abs(dot(outlineTangent, normalizedCameraUpVecXZ)));
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
	
	fragColor = vec4(0.0);
	
	//return early if world coord is not within the map (add 5 to height for FPE on perfectly flat maps)
	if(worldPos.x < 0.0 || worldPos.z < 0.0 || worldPos.y < mapHeight.x - 5.0 || worldPos.y > mapHeight.y + 5.0 || worldPos.x > mapSize.x || worldPos.z > mapSize.z) {
		return;
	}
	
	//The position of the camera in world coords
	vec4 cameraWorldPos = cameraViewInv[3];
	
	//The vector from the camera to the world position of the fragment in world coords
	vec4 depthVec = worldPos - cameraWorldPos;
	
	//The unit vector looking into the screen in world coords ~= normalize(depthVec)
	//vec4 cameraFowardVec = -cameraViewInv[2];
	
	//The unit vector looking right across the screen in world coords
	vec4 cameraRightVec = cameraViewInv[0];
	//The normalized x and z component of cameraRightVec
	vec2 normalizedCameraRightVecXZ = normalize(cameraRightVec.xz);
	
	//The unit vector looking up the screen in world coords
	vec4 cameraUpVec = cameraViewInv[1];
	//The normalized x and z component of cameraUpVec
	vec2 normalizedCameraUpVecXZ = normalize(cameraUpVec.xz);
	
	//The normal vector 
	vec4 normalVec = texture(mapNormals, worldPos.xz / mapSize.xz);
	//For $normals, the normal texture stores the x and z components of the unit vec in the x and w coords of the returned vec4
	//Reconstruct the whole normal vec given that it should have a magnitude of 1
	normalVec = vec4(normalVec.x, sqrt(1.0 - dot(normalVec.xw, normalVec.xw)), normalVec.w, 0.0);
	
	//tan(FOV_y/2) extracted from the projection matrix
	float tanHalfFOVY = 1.0 / cameraProj[1][1];
	
	//The distance to the near plane of the frustum
	float near = viewGeometry.y / (2.0 * tanHalfFOVY);//TODO replace with uniform if it is possible to check when camera/FOV changes in lua
	
	//We want to scale the line thickness so it is a constant number of pixels instead of constant number of
	//world units to prevent it from getting too thin and flickering when we zoom out.
	//To do this, we calculate the size of the fragment in world coords.
	//If the camera were always looking straight down, the frag size would be given as follows.
	float perpendicularFragSize = length(depthVec) / near;
	//To account for the camera being angled or the terrain not being flat, we could divide the above quantity by the cosine of the
	//angle between depthVec and normalVec. However, this would assume that the horizontal (x) and vertical (y) fragment sizes are the same.
	//To consider the actual fragment size in both x and y, we take the surface normal vector and rotate it around the axis of either
	//cameraRightVec or cameraUpVec for the x or y fragment size respectively until it aligns with the plane spanned by d and
	//cameraRightVec or cameraUpVec respectively. Then we take the cosine of the angle between d and this new rotated vector.
	//Dividing the perpendicular frag size by this cosine gives the x and y sizes of the fragment.
	float intermediateDotProdX = dot(cameraRightVec, normalVec);
	float cosThetaX = sqrt(1.0 - intermediateDotProdX * intermediateDotProdX);
	float intermediateDotProdY = dot(cameraUpVec, normalVec);
	float cosThetaY = sqrt(1.0 - intermediateDotProdY * intermediateDotProdY);
	//Horizontal and vertical sizes of the fragment in world coords
	float fragSizeX = perpendicularFragSize / cosThetaX;
	float fragSizeY = perpendicularFragSize / cosThetaY;	
	

	//check each team outline and color in this fragment if it is on the outline
	for(int i = 0; i < numTeams; i++) {
		vec4 area = startAreas[i];
		vec4 color = colors[i];
		vec2 outlineTangent = getOutlineTangent(area, worldPos);
		float lineThickness = LINE_THICKNESS * getLineThicknessFactor(fragSizeX, fragSizeY, outlineTangent, normalizedCameraRightVecXZ, normalizedCameraUpVecXZ);
		fragColor = fragColor + color * getOutlineFactor(area, worldPos, lineThickness, BLUR_FACTOR);
	}
	
	//color in this fragment if it is on the hill outline
	vec4 hillColor = hillColorIndex == -1 ? DEFAULT_HILL_COLOR : colors[hillColorIndex];
	vec2 hillOutlineTangent = getOutlineTangent(hillArea, worldPos);
	float hillLineThickness = LINE_THICKNESS * getLineThicknessFactor(fragSizeX, fragSizeY, hillOutlineTangent, normalizedCameraRightVecXZ, normalizedCameraUpVecXZ);
	fragColor = fragColor + hillColor * getOutlineFactor(hillArea, worldPos, hillLineThickness, BLUR_FACTOR);
	
	//Debug normals texture
	//fragColor = vec4(normalVec.xyz, 1);
	
}