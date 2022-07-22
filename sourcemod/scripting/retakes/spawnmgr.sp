/*
 * • Responsible for managing and generating random players spawns.
 */

#assert defined COMPILING_FROM_MAIN

#include "spawnmgr/nav_mesh.sp"

#define max(%1,%2) (((%1) > (%2)) ? (%1) : (%2))

// This is the the error distance that the player can spawn from the plant area.
#define SPAWN_PLANT_ERROR 15.0

BombSite g_BombSites[Bombsite_Max];

void InitializeSpawnManager()
{
    InitializeNavMesh();
    // Hook events.
    HookEvent("player_spawn", Event_PlayerSpawn);

    RegConsoleCmd("sm_show_bombsites", Command_ShowBombSites);
    RegConsoleCmd("sm_print_places", Command_PrintPlaces);
    RegConsoleCmd("sm_show_area", Command_ShowArea);
    RegConsoleCmd("sm_show_place", Command_ShowPlace);
    RegConsoleCmd("sm_show_all_places", Command_ShowAllPlaces);
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
    BombSite new_site;
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
        g_BombSites[new_site.bombsite_index] = new_site;
    }
}

Action Command_ShowBombSites(int client, int argc)
{
    float client_pos[3];
    GetClientAbsOrigin(client, client_pos);

    float client_mins[3], client_maxs[3];
    GetClientMins(client, client_mins);
    GetClientMaxs(client, client_maxs);

    for (int current_bombsite; current_bombsite < sizeof(g_BombSites); current_bombsite++)
    {
        LaserBOX(g_BombSites[current_bombsite].mins, g_BombSites[current_bombsite].maxs);
    }

    return Plugin_Handled;
}

Action Command_PrintPlaces(int client, int argc)
{
    ArrayList place_indexes = new ArrayList();
    NavArea nav_area;
    char place_name[64];

    for (int i, place; i < g_TheNavAreas.Count(); i++)
    {
        if (!(nav_area = g_TheNavAreas.GetArea(i)) || !(place = nav_area.GetPlace()) || place_indexes.FindValue(place) != -1)
        {
            continue;
        }
        
        place_indexes.Push(place);
        
        g_TheNavMesh.PlaceToName(place, place_name, sizeof(place_name));
        PrintToServer("Place %d: (%s)", i, place_name);
    }

    PrintToServer("Found %d places", place_indexes.Length);

    delete place_indexes;
    return Plugin_Handled;
}

Action Command_ShowArea(int client, int argc)
{
    if (argc < 1)
    {
        ReplyToCommand(client, "Usage: sm_show_area <area_index>");
        return Plugin_Handled;
    }

    int area_index = GetCmdArgInt(1);

    if (!(0 <= area_index < g_TheNavAreas.Count()))
    {
        ReplyToCommand(client, "Invalid area index.");
        return Plugin_Handled;
    }

    NavArea nav_area = g_TheNavAreas.GetArea(area_index);

    if (!nav_area)
    {
        ReplyToCommand(client, "Failed to get area.");
        return Plugin_Handled;
    }
    
    float nw_corner[3], se_corner[3], ne_corner[3], sw_corner[3];

    nav_area.GetNWCorner(nw_corner);
    nav_area.GetSECorner(se_corner);
    nav_area.GetNECorner(ne_corner);
    nav_area.GetSWCorner(sw_corner);

    // Print corners.
    PrintToServer("NW: %.2f %.2f %.2f", nw_corner[0], nw_corner[1], nw_corner[2]);
    PrintToServer("SE: %.2f %.2f %.2f", se_corner[0], se_corner[1], se_corner[2]);
    PrintToServer("NE: %.2f %.2f %.2f", ne_corner[0], ne_corner[1], ne_corner[2]);
    PrintToServer("SW: %.2f %.2f %.2f", sw_corner[0], sw_corner[1], sw_corner[2]);
    
    LaserP(nw_corner, ne_corner);
    LaserP(ne_corner, se_corner);
    LaserP(se_corner, sw_corner);
    LaserP(sw_corner, nw_corner);

    TeleportEntity(client, nw_corner);

    return Plugin_Handled;
}

Action Command_ShowPlace(int client, int argc)
{
    if (argc < 1)
    {
        ReplyToCommand(client, "Usage: sm_show_place <place_name>");
        return Plugin_Handled;
    }

    char place_name[64];
    GetCmdArg(1, place_name, sizeof(place_name));

    int place_index = g_TheNavMesh.NameToPlace(place_name);

    if (place_index == -1)
    {
        ReplyToCommand(client, "Failed to get place.");
        return Plugin_Handled;
    }

    float nw_corner[3], se_corner[3], ne_corner[3], sw_corner[3];
    NavArea nav_area;
    for (int i; i < g_TheNavAreas.Count(); i++)
    {
        if (!(nav_area = g_TheNavAreas.GetArea(i)) || nav_area.GetPlace() != place_index)
        {
            continue;
        }

        nav_area.GetNWCorner(nw_corner);
        nw_corner[2] += 5.0;
        nav_area.GetSECorner(se_corner);
        se_corner[2] += 5.0;
        nav_area.GetNECorner(ne_corner);
        ne_corner[2] += 5.0;
        nav_area.GetSWCorner(sw_corner);
        sw_corner[2] += 5.0;

        LaserP(nw_corner, ne_corner);
        LaserP(ne_corner, se_corner);
        LaserP(se_corner, sw_corner);
        LaserP(sw_corner, nw_corner);
    }

    return Plugin_Handled;
}

Action Command_ShowAllPlaces(int client, int argc)
{
    Frame_ShowPlace(0);
    return Plugin_Handled;
}

void Frame_ShowPlace(int next_place)
{
    if (next_place == g_TheNavAreas.Count())
    {
        return;
    }

    NavArea nav_area = g_TheNavAreas.GetArea(next_place);

    if (!nav_area)
    {
        return;
    }

    float nw_corner[3], se_corner[3], ne_corner[3], sw_corner[3];
    nav_area.GetNWCorner(nw_corner);
    nw_corner[2] += 5.0;
    nav_area.GetSECorner(se_corner);
    se_corner[2] += 5.0;
    nav_area.GetNECorner(ne_corner);
    ne_corner[2] += 5.0;
    nav_area.GetSWCorner(sw_corner);
    sw_corner[2] += 5.0;

    LaserP(nw_corner, ne_corner);
    LaserP(ne_corner, se_corner);
    LaserP(se_corner, sw_corner);
    LaserP(sw_corner, nw_corner);

    RequestFrame(Frame_ShowPlace, next_place + 1);
}

void LaserBOX(float mins[3], float maxs[3])
{
    float posMin[4][3], posMax[4][3];
    
    posMin[0] = mins;
    posMax[0] = maxs;
    posMin[1][0] = posMax[0][0];
    posMin[1][1] = posMin[0][1];
    posMin[1][2] = posMin[0][2];
    posMax[1][0] = posMin[0][0];
    posMax[1][1] = posMax[0][1];
    posMax[1][2] = posMax[0][2];
    posMin[2][0] = posMin[0][0];
    posMin[2][1] = posMax[0][1];
    posMin[2][2] = posMin[0][2];
    posMax[2][0] = posMax[0][0];
    posMax[2][1] = posMin[0][1];
    posMax[2][2] = posMax[0][2];
    posMin[3][0] = posMax[0][0];
    posMin[3][1] = posMax[0][1];
    posMin[3][2] = posMin[0][2];
    posMax[3][0] = posMin[0][0];
    posMax[3][1] = posMin[0][1];
    posMax[3][2] = posMax[0][2];
    
    //BORDER
    LaserP(posMin[0], posMax[3], { 255, 255, 255, 255 } );
    LaserP(posMin[1], posMax[2], { 255, 255, 255, 255 } );
    LaserP(posMin[3], posMax[0], { 255, 255, 255, 255 } );
    LaserP(posMin[2], posMax[1], { 255, 255, 255, 255 } );
    //CROSS
    LaserP(posMin[3], posMax[2], { 255, 255, 255, 255 } );
    LaserP(posMin[1], posMax[0], { 255, 255, 255, 255 } );
    LaserP(posMin[2], posMax[3], { 255, 255, 255, 255 } );
    LaserP(posMin[3], posMax[1], { 255, 255, 255, 255 } );
    LaserP(posMin[2], posMax[0], { 255, 255, 255, 255 } );
    LaserP(posMin[0], posMax[1], { 255, 255, 255, 255 } );
    LaserP(posMin[0], posMax[2], { 255, 255, 255, 255 } );
    LaserP(posMin[1], posMax[3], { 255, 255, 255, 255 } );
    
    
    //TOP
    
    //BORDER
    LaserP(posMax[0], posMax[1], { 255, 255, 255, 255 } );
    LaserP(posMax[1], posMax[3], { 255, 255, 255, 255 } );
    LaserP(posMax[3], posMax[2], { 255, 255, 255, 255 } );
    LaserP(posMax[2], posMax[0], { 255, 255, 255, 255 } );
    //CROSS
    LaserP(posMax[0], posMax[3], { 255, 255, 255, 255 } );
    LaserP(posMax[2], posMax[1], { 255, 255, 255, 255 } );
    
    //BOTTOM
    
    //BORDER
    LaserP(posMin[0], posMin[1], { 255, 255, 255, 255 } );
    LaserP(posMin[1], posMin[3], { 255, 255, 255, 255 } );
    LaserP(posMin[3], posMin[2], { 255, 255, 255, 255 } );
    LaserP(posMin[2], posMin[0], { 255, 255, 255, 255 } );
    //CROSS
    LaserP(posMin[0], posMin[3], { 255, 255, 255, 255 } );
    LaserP(posMin[2], posMin[1], { 255, 255, 255, 255 } );
    
}

void LaserP(const float start[3], const float end[3], int color[4] = { 255, 255, 255, 255 })
{
    // Randomize color
    color[0] = GetRandomInt(0, 255);
    color[1] = GetRandomInt(0, 255);
    color[2] = GetRandomInt(0, 255);

    TE_SetupBeamPoints(start, end, PrecacheModel("materials/sprites/laser.vmt"), 0, 0, 0, 15.0, 3.0, 3.0, 7, 0.0, color, 0);
    TE_SendToAllInRange(start, RangeType_Visibility);
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