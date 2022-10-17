/*
 * • Responsible for managing and generating random players spawns.
 */

#assert defined COMPILING_FROM_MAIN

#define max(%1,%2) (((%1) > (%2)) ? (%1) : (%2))

// This is the the error distance that the player can spawn from the plant area.
#define SPAWN_PLANT_ERROR 15.0

Bombsite g_Bombsites[Bombsite_Max];

ArrayList g_BombsiteSpawns[Bombsite_Max][NavMeshArea_Max];

void SpawnManager_OnPluginStart()
{
    for (int i; i < sizeof(g_BombsiteSpawns); i++)
    {
        for (int j; j < sizeof(g_BombsiteSpawns[]); j++)
        {
            g_BombsiteSpawns[i][j] = new ArrayList();
        }
    }
}

void SpawnManager_OnMapStart()
{
    // InitializeBombsites();
}

// HACK: apparently initializing the bombsites on 'OnMapStart' is too early,
// 		 'OnConfigsExecuted' is a decent alternative since it's called 
// 		 once per map and it's more delayed.
public void OnConfigsExecuted()
{
    InitializeBombsites();
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

void SpawnManager_OnPlayerSpawn(int client)
{
    float origin[3];
    if (!GetRandomSpawnLocation(client, origin))
    {
        return;
    }
    
    float dest[3]; dest = g_Bombsites[g_TargetSite].center;
    
    // TODO: find a better way of calculating our desired angle.
    // 		 this way in some locations the player will look directly
    // 		 at a wall, which is something we want to avoid.
    float angles[3];
    MakeAnglesFromPoints(origin, dest, angles);
    
    TeleportEntity(client, origin, angles);
}

bool GetRandomSpawnLocation(int client, float origin[3])
{
    if (g_Players[client].spawn_role == SpawnRole_Planter)
    {
        GenerateSpawnLocation(client, g_Bombsites[g_TargetSite].mins, g_Bombsites[g_TargetSite].maxs, origin);
        return true;
    }
    
    NavArea nav_area = GetSuitableNavArea(client);
    if (nav_area == NULL_NAV_AREA)
    {
        // Apparently there are no nav areas configurated.
        return false;
    }
    
    float mins[3], maxs[3];
    GetClientMins(client, mins);
    GetClientMaxs(client, maxs);
    
    // Generate random spawn vectors, and don't stop until a valid one has found
    do
    {
        nav_area.GetRandomPoint(origin);
    } while (!ValidateSpawn(origin, mins, maxs));
    
    return true;
}

NavArea GetSuitableNavArea(int client)
{
    ArrayList suitable_areas = g_BombsiteSpawns[g_TargetSite][g_Players[client].spawn_role - (SpawnRole_Max - NavMeshArea_Max)];
    if (!suitable_areas.Length)
    {
        return NULL_NAV_AREA;
    }
    
    return suitable_areas.Get(GetURandomInt() % suitable_areas.Length);
}

// Generates a randomized origin vector with the given boundaries. (mins[3], maxs[3])
void GenerateSpawnLocation(int client, float mins[3], float maxs[3], float result[3])
{
    float cl_mins[3], cl_maxs[3];
    GetClientMins(client, cl_mins);
    GetClientMaxs(client, cl_maxs);
    
    // Generate random spawn vectors, and don't stop until a valid one has found
    do
    {
        result[0] = GetRandomFloat(mins[0], maxs[0]);
        result[1] = GetRandomFloat(mins[1], maxs[1]);
        result[2] = max(mins[2], maxs[2]);
    } while (!ValidateSpawn(result, cl_mins, cl_maxs, mins, maxs));
}

bool ValidateSpawn(float origin[3], float ent_mins[3], float ent_maxs[3], float mins[3] = NULL_VECTOR, float maxs[3] = NULL_VECTOR)
{
    origin[2] += 64.0; // 64.0 units as for the player model height.
    
    TR_TraceRayFilter(origin, { 90.0, 0.0, 0.0 }, MASK_SOLID_BRUSHONLY, RayType_Infinite, Filter_WorldOnly);
    
    float normal[3];
    TR_GetPlaneNormal(INVALID_HANDLE, normal);
    TR_GetEndPosition(origin);
    
    if (!(normal[2] < 0.5 && normal[2] > -0.5))
    {
        NegateVector(normal);
        
        origin[0] += normal[0] * -3;
        origin[1] += normal[1] * -3;
        origin[2] += normal[2] * -3;
    }
    
    if (!IsNullVector(mins) && !IsNullVector(maxs) && !IsVecBetween(origin, mins, maxs))
    {
        return false;
    }
    
    float hull_origin[3]; hull_origin = origin;
    hull_origin[2] += normal[2] * -3;
    
    TR_TraceHullFilter(hull_origin, hull_origin, ent_mins, ent_maxs, MASK_ALL, Filter_WorldOnly);
    
    return !TR_DidHit();
}

bool Filter_WorldOnly(int entity, int contentsMask)
{
    return !entity;
}

bool IsVecBetween(float vec[3], float mins[3], float maxs[3], float err = 0.0)
{
    return (
        (mins[0] - err <= vec[0] <= maxs[0] + err) && 
        (mins[1] - err <= vec[1] <= maxs[1] + err) && 
        (mins[2] - err <= vec[2] <= maxs[2] + err)
        );
}

// Builds an angles vector towards pt2 from pt1.
stock void MakeAnglesFromPoints(const float pt1[3], const float pt2[3], float angles[3])
{
    float result[3];
    MakeVectorFromPoints(pt1, pt2, result);
    GetVectorAngles(result, angles);
    
    NormalizeYaw(angles[1]);
}

void NormalizeYaw(float &yaw)
{
    while (yaw > 180.0)
    {
        yaw -= 360.0;
    }
    
    while (yaw < -180.0)
    {
        yaw += 360.0;
    }
} 