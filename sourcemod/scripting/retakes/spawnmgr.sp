/*
 * • Responsible for managing and generating random players spawns.
 */

#assert defined COMPILING_FROM_MAIN

#define max(%1,%2) (((%1) > (%2)) ? (%1) : (%2))

// This is the the error distance that the player can spawn from the plant area.
#define SPAWN_PLANT_ERROR 15.0

// The operation system of the server, this is needed because `CNavMesh::PlaceToName` takes |this| ptr only for Linux.
int g_OS;
enum
{
    OS_LINUX, 
    OS_WINDOWS
}

// Address of `TheNavMesh`, 
Address TheNavMesh;

// Number of places in the nav mesh.
int m_placeCount

// Translates a place index to a place name.
Handle CNavMesh_PlaceToNameFunc;

BombSite g_BombSites[Bombsite_Max];

void InitializeSpawnManager()
{
    GameData gamedata = new GameData("retakes.games");

    // Load `TheNavMesh` from the gamedata file.
    if ((TheNavMesh = gamedata.GetAddress("TheNavMesh")) == Address_Null)
    {
        SetFailState("Failed to load TheNavMesh from gamedata.");
    }

    // Print TheNavMesh address.
    PrintToServer("TheNavMesh address: 0x%x\n", TheNavMesh);

    // Load `m_placeCount` offset from the gamedata file.
    int m_placeCountOffset;
    if ((m_placeCountOffset = gamedata.GetOffset("CNavMesh::m_placeCount")) == 0)
    {
        SetFailState("Failed to load m_placeCount from gamedata.");
    }

    // Get m_placeCount.
    m_placeCount = LoadFromAddress(TheNavMesh + view_as<Address>(m_placeCountOffset), NumberType_Int32);

    // Print m_placeCount.
    PrintToServer("m_placeCount (offset: %d): %d\n", m_placeCountOffset, m_placeCount);

    // Load `m_placeCount` address from the gamedata file.
    Address m_placeCountAddress;
    if ((m_placeCountAddress = gamedata.GetAddress("TheNavMesh::m_placeCount")) == Address_Null)
    {
        SetFailState("Failed to load TheNavMesh from gamedata.");
    }

    // load `m_placeCount` from the address.
    m_placeCount = LoadFromAddress(m_placeCountAddress, NumberType_Int32);

    // Load os from the gamedata file.
    if ((g_OS = gamedata.GetOffset("OS")) == -1)
    {
        SetFailState("Failed to load os from gamedata.");
    }

    // Setup `CNavMesh_PlaceToName` SDKCall.
    // const char *CNavMesh::PlaceToName( Place place ) const
    
    // Linux takes |this| ptr, Windows doesn't.
    StartPrepSDKCall(g_OS == OS_LINUX ? SDKCall_Raw : SDKCall_Static);
    PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CNavMesh::PlaceToName");
    // Place place (Place == unsigned int)
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    // const char*
    PrepSDKCall_SetReturnInfo(SDKType_String, SDKPass_Pointer);
    
    if (!(CNavMesh_PlaceToNameFunc = EndPrepSDKCall()))
    {
        SetFailState("Missing signature 'CNavMesh::PlaceToName'");
    }
    /*
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CNavMesh::LoadPlaceDatabase");

    Handle CNavMesh_LoadPlaceDatabase;
    if (!(CNavMesh_LoadPlaceDatabase = EndPrepSDKCall()))
    {
        SetFailState("Missing signature 'CNavMesh::LoadPlaceDatabase'");
    }

    SDKCall(CNavMesh_LoadPlaceDatabase, TheNavMesh);
    */

    // Hook events.
    HookEvent("player_spawn", Event_PlayerSpawn);

    RegConsoleCmd("sm_show_bombsites", Command_ShowBombSites);
    RegConsoleCmd("sm_print_places", Command_PrintPlaces);
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

        PrintToServer(
            "Found bomb site %s at {%.2f %.2f %.2f} to {%.2f %.2f %.2f}.\n",
            new_site.bombsite_index == Bombsite_A ? "A" : "B",
            new_site.mins[0], new_site.mins[1], new_site.mins[2],
            new_site.maxs[0], new_site.maxs[1], new_site.maxs[2]
        );
    }

    // Print the number of places in the nav mesh.
    PrintToServer("Nav mesh has %d places.\n", m_placeCount);

    // Print all places.
    char place_name[64];
    for (int i = 1; i <= 10; i++)
    {
        CNavMesh_PlaceToName(i, place_name, sizeof(place_name));
        PrintToServer("Place %d: %s\n", i, place_name);
    }
}

int CNavMesh_PlaceToName(int place_index, char[] buffer, int buf_size)
{
    // Call CNavMesh::PlaceToName.
    // For Linux, we need to pass |this| ptr.
    if (g_OS == OS_LINUX)
    {
        SDKCall(
            CNavMesh_PlaceToNameFunc,
            TheNavMesh,
            buffer,
            buf_size,
            place_index
        );
    }
    else // Otherwise, we are on Windows. 
    {
        // Windows doesn't need |this| ptr.
        SDKCall(
            CNavMesh_PlaceToNameFunc,
            buffer,
            buf_size,
            place_index
        );
    }
    
    return strlen(buffer);
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

        PrintToChatAll(
            "In Bombsite %s: %d\n",
            g_BombSites[current_bombsite].bombsite_index == Bombsite_A ? "A" : "B",
            IsVecBetween(
                client_pos,
                g_BombSites[current_bombsite].mins,
                g_BombSites[current_bombsite].maxs,
                SPAWN_PLANT_ERROR
            )
        );
    }

    return Plugin_Handled;
}

Action Command_PrintPlaces(int client, int argc)
{

    return Plugin_Handled;
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

void LaserP(const float start[3], const float end[3], int color[4])
{
    TE_SetupBeamPoints(start, end, PrecacheModel("materials/sprites/laser.vmt"), 0, 0, 0, 15.0, 3.0, 3.0, 7, 0.0, color, 0);
    TE_SendToAll();
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