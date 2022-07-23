/*
 * • Responsible for managing and generating random players spawns.
 */

#assert defined COMPILING_FROM_MAIN

#define max(%1,%2) (((%1) > (%2)) ? (%1) : (%2))

// This is the the error distance that the player can spawn from the plant area.
#define SPAWN_PLANT_ERROR 15.0

enum struct SpawnArea
{    
    int nav_area_index;

    int spawn_roles[Bombsite_Max];
}

Bombsite g_Bombsites[Bombsite_Max];

StringMap g_MapPlaces;

void InitializeSpawnManager()
{
    g_MapPlaces = new StringMap();

    // Hook events.
    HookEvent("player_spawn", Event_PlayerSpawn);
}

void InitializeBombsites()
{
    int player_resource = GetPlayerResourceEntity();
    if (player_resource == -1)
    {
        SetFailState("Failed to get player resource entity.");
    }

    // Get the center position of bombsite A.
    float bombsite_centers[Bombsite_Max][3];
    GetEntPropVector(player_resource, Prop_Send, "m_bombsiteCenterA", bombsite_centers[Bombsite_A]);
    GetEntPropVector(player_resource, Prop_Send, "m_bombsiteCenterB", bombsite_centers[Bombsite_B]);

    // Find all bomb sites on the map.
    Bombsite new_site;
    int ent_index = -1;

    while ((ent_index = FindEntityByClassname(ent_index, "func_bomb_target")) != -1)
    {
        // Get the mins and maxs of the bomb site.
        GetEntPropVector(ent_index, Prop_Send, "m_vecMins", new_site.mins);
        GetEntPropVector(ent_index, Prop_Send, "m_vecMaxs", new_site.maxs);

        // Get the index of the bomb site.
        new_site.bombsite_index = IsVecBetween(
            bombsite_centers[Bombsite_A],
            new_site.mins,
            new_site.maxs
        ) ? Bombsite_A : Bombsite_B;

        // Get the center of the bomb site.
        new_site.center = bombsite_centers[new_site.bombsite_index];

        // Save bombsite.
        g_Bombsites[new_site.bombsite_index] = new_site;
    }
}

void InitializeMapPlaces()
{
    // Purge the old data.
    g_MapPlaces.Clear();
    
    int invalid_places_count;
    ArrayList spawn_areas;
    SpawnArea spawn_area;
    char place_name[256];
    NavArea nav_area;
	
    for (int current_nav_area = TheNavAreas().size - 1, place; current_nav_area >= 0; current_nav_area--)
    {
        if (!(nav_area = TheNavAreas().Get(current_nav_area)))
        {
            continue;
        }
		
        if ((place = nav_area.GetPlace()) <= 0)
        {
            invalid_places_count++;
            continue;
        }
        
        TheNavMesh.PlaceToName(place, place_name, sizeof(place_name));

        if (!g_MapPlaces.GetValue(place_name, spawn_areas))
        {
            g_MapPlaces.SetValue(place_name, (spawn_areas = new ArrayList(sizeof(SpawnArea))))
        }
        
        spawn_area.nav_area_index = current_nav_area;
        spawn_areas.PushArray(spawn_area);
    }

    //=======================[ Debug ]=======================//
    StringMapSnapshot snapshot = g_MapPlaces.Snapshot();
    
    int count;
    for (int i, size; i < snapshot.Length; i++)
    {
        size = snapshot.KeyBufferSize(i);
        char[] key = new char[size];

        snapshot.GetKey(i, key, size);

        if (g_MapPlaces.GetValue(key, spawn_areas))
        {
            count += spawn_areas.Length;

            PrintToServer("%s with %d places", key, spawn_areas.Length);
        }
    }
    
    PrintToServer("Verification: %d ?= %d", count, TheNavAreas().size - invalid_places_count);
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

bool IsVecBetween(float vecVector[3], float vecMin[3], float vecMax[3], float err = 0.0) {
    return (
        (vecMin[0] - err <= vecVector[0] <= vecMax[0] + err) &&
        (vecMin[1] - err <= vecVector[1] <= vecMax[1] + err) &&
        (vecMin[2] - err <= vecVector[2] <= vecMax[2] + err)
    );
}