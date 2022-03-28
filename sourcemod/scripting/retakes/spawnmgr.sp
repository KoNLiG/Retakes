/*
 * • Responsible for managing and generating random players spawns.
 */

#assert defined COMPILING_FROM_MAIN

#define max(%1,%2) (((%1) > (%2)) ? (%1) : (%2))

float m_bombsiteCenter[Bombsite_Max][3];

void HookSpawnEvents()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
}

void InitializeMapSites()
{
	int cs_player_manager = GetPlayerResourceEntity();
	if (cs_player_manager != -1)
	{
		GetEntPropVector(cs_player_manager, Prop_Send, "m_bombsiteCenterA", m_bombsiteCenter[Bombsite_A]);
		GetEntPropVector(cs_player_manager, Prop_Send, "m_bombsiteCenterB", m_bombsiteCenter[Bombsite_B]);
	}
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	/*
	float position[3], mins[3], maxs[3];
	GenerateSpawnLocation(client, mins, maxs, position);
	
	TeleportEntity(client, position);
	*/
}

// Generates a randomized origin vector with the given boundaries. (mins[3], maxs[3])
void GenerateSpawnLocation(int entity, float mins[3], float maxs[3], float result[3])
{
	// Initialize the entity's mins and maxs vectors
	float ent_mins[3], ent_maxs[3];
	
	GetEntPropVector(entity, Prop_Send, "m_vecMins", ent_mins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", ent_maxs);
	
	// Generate random spawn vectors, and don't stop until a valid one has found
	do
	{
		result[0] = GetRandomFloat(mins[0], maxs[0]);
		result[1] = GetRandomFloat(mins[1], maxs[1]);
		result[2] = max(mins[2], maxs[2]);
	} while (!IsValidSpawn(result, ent_mins, ent_maxs));
}

bool IsValidSpawn(float pos[3], float ent_mins[3], float ent_maxs[3])
{
	// Create a global trace ray to verify the floor the entity is spawning on
	TR_TraceRayFilter(pos, { 90.0, 0.0, 0.0 }, MASK_PLAYERSOLID, RayType_Infinite, Filter_ExcludePlayers);
	
	// Initialize the end position of the floor position
	TR_GetEndPosition(pos);
	
	// Spawn higher up from the ground to not get stuck.
	pos[2] += 10.0;
	
	// Create a global trace hull that will ensure the entity will not stuck inside the world/another entity
	TR_TraceHull(pos, pos, ent_mins, ent_maxs, MASK_ALL);
	
	// If the trace hull did hit something, the position is invalid.
	return !TR_DidHit();
}

bool Filter_ExcludePlayers(int entity, int contentsMask)
{
	return !(1 <= entity <= MaxClients);
}

// Builds an angles vector towards pt2 from pt1.
void MakeAnglesFromPoints(const float pt1[3], const float pt2[3], float angles[3])
{
	float result[3];
	MakeVectorFromPoints(pt1, pt2, result);
	GetVectorAngles(result, angles);
} 