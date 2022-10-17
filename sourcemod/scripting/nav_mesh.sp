#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <nav_mesh>

#pragma semicolon 1
#pragma newdecls required

enum
{
    OS_LINUX,
    OS_WINDOWS
}

// Offsets
int m_placeCountOffset,
    m_nwCornerOffset,
    m_seCornerOffset,
    m_placeOffset,
    m_neZOffset,
    m_swZOffset,
// Other
    g_serverOS;

// SDK Functions
Handle
    NavArea_GetRandomPointFunc,
    NavArea_IsConnectedFunc,
    NavMesh_PlaceToNameFunc,
    NavMesh_GetNearestNavAreaFunc;

// Forward Declarations
GlobalForward
    NavMesh_OnPlayerEnterFwd,
    NavMesh_OnPlayerExitFwd;

TheNavMesh g_TheNavMesh;
TheNavAreas g_TheNavAreas;

NavArea g_PrevNavArea[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "Nav Mesh",
    author = "Natanel 'LuqS', Omer 'KoNLiG'",
    description = "API for CS:GO AI Nav Mesh.",
    version = "1.0.0",
    url = "https://github.com/Natanel-Shitrit/Retakes"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    // Lock the use of this plugin for CS:GO only.
    if (GetEngineVersion() != Engine_CSGO)
    {
        strcopy(error, err_max, "This plugin was made for use with CS:GO only.");
        return APLRes_Failure;
    }
    
    // Initialzie API stuff.
    InitializeAPI();
    
    return APLRes_Success;
}

public void OnPluginStart()
{
    InitializeSDK();
}

//================================[ Events ]================================//

// Client events.
public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_PreThink, Hook_OnPreThink);
}

public void OnClientDisconnect(int client)
{
    g_PrevNavArea[client] = NULL_NAV_AREA;
}

// Used to catch whenever a client exits a navigation area and enters a new one.
void Hook_OnPreThink(int client)
{
    float origin[3];
    GetClientAbsOrigin(client, origin);
    
    NavArea nav_area = TheNavMesh.GetNearestNavArea(origin);
    if (!nav_area || nav_area.GetPlace() <= 0)
    {
        return;
    }
    
    if (nav_area != g_PrevNavArea[client] && g_PrevNavArea[client])
    {
        Call_OnPlayerEnter(client, nav_area);
        Call_OnPlayerExit(client, g_PrevNavArea[client]);
    }
    
    g_PrevNavArea[client] = nav_area;
}

//================================[ API ]================================//

void InitializeAPI()
{
    CreateNatives();
    CreateForwards();
    
    RegPluginLibrary("nav_mesh");
}

// Natives.
void CreateNatives()
{
    // void GetNWCorner(float corner[3])
    CreateNative("NavAreaCriticalData.GetNWCorner", Native_GetNWCorner);
    
    // void GetSECorner(float corner[3])
    CreateNative("NavAreaCriticalData.GetSECorner", Native_GetSECorner);
    
    // float neZ
    CreateNative("NavAreaCriticalData.neZ.get", Native_GetneZ);
    
    // float swZ
    CreateNative("NavAreaCriticalData.swZ.get", Native_GetswZ);
    
    // void GetRandomPoint(float pos[3])
    CreateNative("NavArea.GetRandomPoint", Native_GetRandomPoint);
    
    // int GetPlace()
    CreateNative("NavArea.GetPlace", Native_GetPlace);
    
    // bool IsConnected(NavArea area, NavDirType dir = NUM_DIRECTIONS)
    CreateNative("NavArea.IsConnected", Native_IsConnected);
    
    // int PlaceToName(int place_index, char[] buffer, int maxlength)
    CreateNative("TheNavMesh.PlaceToName", Native_PlaceToName);
    
    // NavArea GetNearestNavArea(const float pos[3], bool anyZ = false, float maxDist = 10000.0, bool checkLOS = false, bool checkGround = true)
    CreateNative("TheNavMesh.GetNearestNavArea", Native_GetNearestNavArea);
    
    // int GetPlaceCount()
    CreateNative("TheNavMesh.PlaceCount.get", Native_GetPlaceCount);
    
    // TheNavAreas()
    CreateNative("TheNavAreas.TheNavAreas", Native_TheNavAreas);
}

any Native_GetNWCorner(Handle plugin, int numParams)
{
    NavArea nav_area = view_as<NavArea>(GetNativeCell(1));
    if (!nav_area)
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid NavArea pointer.");
    }
    
    float buffer[3];
    LoadVectorFromOffset(
        view_as<Address>(nav_area) + view_as<Address>(m_nwCornerOffset),
        buffer
    );
    
    SetNativeArray(2, buffer, sizeof(buffer));
    
    return 0;
}

any Native_GetSECorner(Handle plugin, int numParams)
{
    NavArea nav_area = view_as<NavArea>(GetNativeCell(1));
    if (!nav_area)
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid NavArea pointer.");
    }
    
    float buffer[3];
    LoadVectorFromOffset(
        view_as<Address>(nav_area) + view_as<Address>(m_seCornerOffset),
        buffer
    );
    
    SetNativeArray(2, buffer, sizeof(buffer));
    
    return 0;
}

any Native_GetneZ(Handle plugin, int numParams)
{
    NavArea nav_area = view_as<NavArea>(GetNativeCell(1));
    if (!nav_area)
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid NavArea pointer.");
    }

    return LoadFromAddress(
        view_as<Address>(nav_area) + view_as<Address>(m_neZOffset),
        NumberType_Int32
    );
}

any Native_GetswZ(Handle plugin, int numParams)
{
    NavArea nav_area = view_as<NavArea>(GetNativeCell(1));
    if (!nav_area)
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid NavArea pointer.");
    }

    return LoadFromAddress(
        view_as<Address>(nav_area) + view_as<Address>(m_swZOffset),
        NumberType_Int32
    );
}

any Native_GetRandomPoint(Handle plugin, int numParams)
{
    NavArea nav_area = view_as<NavArea>(GetNativeCell(1));
    if (!nav_area)
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid NavArea pointer.");
    }
    
    float position[3];
    SDKCall(
        NavArea_GetRandomPointFunc, 	// sdkcall function
        nav_area,  						// this
        position, sizeof(position) 		// return vector
    );
    
    SetNativeArray(2, position, sizeof(position));
    
    return 0;
}

any Native_GetPlace(Handle plugin, int numParams)
{
    NavArea nav_area = view_as<NavArea>(GetNativeCell(1));
    if (!nav_area)
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid NavArea pointer.");
    }
    
    return LoadFromAddress(
        view_as<Address>(nav_area) + view_as<Address>(m_placeOffset),
        NumberType_Int32
    );
}

any Native_IsConnected(Handle plugin, int numParams)
{
    NavArea nav_area = view_as<NavArea>(GetNativeCell(1));
    if (!nav_area)
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid NavArea pointer.");
    }
    
    NavArea area = GetNativeCell(2);
    if (!area)
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid area pointer.");
    }
    
    NavDirType dir = GetNativeCell(3);
    
    return SDKCall(
        NavArea_IsConnectedFunc, 	
        nav_area,
        area,
        dir
    );
}

any Native_PlaceToName(Handle plugin, int numParams)
{
    int place_index = GetNativeCell(1);
    if (!(0 <= place_index <= TheNavMesh.GetPlaceCount))
    {
        ThrowNativeError(SP_ERROR_NATIVE, "Invalid area place index.");
    }
    
    char buffer[256];
    
    // Call `CNavMesh::PlaceToName`
    // For Linux, we need to pass |this| ptr.
    if (g_serverOS == OS_LINUX)
    {
        SDKCall(
            NavMesh_PlaceToNameFunc,
            g_TheNavMesh,
            buffer,
            sizeof(buffer),
            place_index
        );
    }
    else // Otherwise, we are on Windows.
    {
        // Windows doesn't need |this| ptr.
        SDKCall(
            NavMesh_PlaceToNameFunc,
            buffer,
            sizeof(buffer),
            place_index
        );
    }
    
    SetNativeString(2, buffer, GetNativeCell(3));
    
    return strlen(buffer);
}

any Native_GetNearestNavArea(Handle plugin, int numParams)
{
    float pos[3];
    GetNativeArray(1, pos, sizeof(pos));
    
    bool anyZ = GetNativeCell(2);
    float maxDist = GetNativeCell(3);
    bool checkLOS = GetNativeCell(4);
    bool checkGround = GetNativeCell(5);
    
    return view_as<NavArea>(SDKCall(NavMesh_GetNearestNavAreaFunc, g_TheNavMesh, pos, anyZ, maxDist, checkLOS, checkGround));
}

any Native_GetPlaceCount(Handle plugin, int numParams)
{
    return LoadFromAddress(
        view_as<Address>(g_TheNavMesh) + view_as<Address>(m_placeCountOffset),
        NumberType_Int32
    );
}

any Native_TheNavAreas(Handle plugin, int numParams)
{
    return g_TheNavAreas;
}

// Forwards.
void CreateForwards()
{
    NavMesh_OnPlayerEnterFwd = new GlobalForward(
        "NavMesh_OnPlayerEnter",
        ET_Ignore,
        Param_Cell, // int client
        Param_Cell	// NavArea nav_area
    );
    
    NavMesh_OnPlayerExitFwd = new GlobalForward(
        "NavMesh_OnPlayerExit",
        ET_Ignore,  
        Param_Cell, // int
        Param_Cell	// NavArea nav_area
    );
}

void Call_OnPlayerEnter(int client, NavArea nav_area)
{
    Call_StartForward(NavMesh_OnPlayerEnterFwd);
    Call_PushCell(client);
    Call_PushCell(nav_area);
    Call_Finish();
}

void Call_OnPlayerExit(int client, NavArea nav_area)
{
    Call_StartForward(NavMesh_OnPlayerExitFwd);
    Call_PushCell(client);
    Call_PushCell(nav_area);
    Call_Finish();
}

//================================[ SDK ]================================//

GameData g_GameData;

void InitializeSDK()
{
    g_GameData = new GameData("nav_mesh.games");
    
    InitializeSDKGlobals();
    InitializeSDKOffsets();
    InitializeSDKFunctions();
    
    delete g_GameData;
}

void InitializeSDKGlobals()
{
    g_serverOS = LoadGameDataOffset("OS");
    g_TheNavMesh = view_as<TheNavMesh>(LoadGameDataAddress("TheNavMesh"));
    g_TheNavAreas = view_as<TheNavAreas>(LoadGameDataAddress("TheNavAreas"));
}

void InitializeSDKOffsets()
{
    m_nwCornerOffset = LoadGameDataOffset("CNavAreaCriticalData::m_nwCorner");
    m_seCornerOffset = LoadGameDataOffset("CNavAreaCriticalData::m_seCorner");
    m_neZOffset = LoadGameDataOffset("CNavAreaCriticalData::m_neZ");
    m_swZOffset = LoadGameDataOffset("CNavAreaCriticalData::m_swZ");
    m_placeOffset = LoadGameDataOffset("CNavArea::m_place");
    m_placeCountOffset = LoadGameDataOffset("CNavMesh::m_placeCount");
}

void InitializeSDKFunctions()
{
    // Vector GetRandomPoint( void ) const;
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(g_GameData, SDKConf_Signature, "CNavArea::GetRandomPoint");
    
    PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByValue); // Vector
    
    if (!(NavArea_GetRandomPointFunc = EndPrepSDKCall()))
    {
        SetFailState("Missing signature 'CNavArea::GetRandomPoint'");
    }
    
    // bool IsConnected( const CNavArea *area, NavDirType dir ) const;
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(g_GameData, SDKConf_Signature, "CNavArea::IsConnected");
    
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // const CNavArea *area
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // NavDirType dir
    
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
    
    if (!(NavArea_IsConnectedFunc = EndPrepSDKCall()))
    {
        SetFailState("Missing signature 'CNavArea::IsConnected'");
    }
    
    // Setup `CNavMesh_PlaceToName` SDKCall.
    // const char *CNavMesh::PlaceToName( Place place ) const
    // Linux takes |this| ptr, Windows doesn't.
    StartPrepSDKCall(g_serverOS == OS_LINUX ? SDKCall_Raw : SDKCall_Static);
    PrepSDKCall_SetFromConf(g_GameData, SDKConf_Signature, "CNavMesh::PlaceToName");
    
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain); // Place place (Place == unsigned int)
    
    PrepSDKCall_SetReturnInfo(SDKType_String, SDKPass_Pointer); // const char*
    
    if (!(NavMesh_PlaceToNameFunc = EndPrepSDKCall()))
    {
        SetFailState("Missing signature 'CNavMesh::PlaceToName'");
    }
    
    // Setup `GetNearestNavArea` SDKCall.
    // CNavArea *GetNearestNavArea( const Vector &pos, bool anyZ = false, float maxDist = 10000.0f, bool checkLOS = false, bool checkGround = true ) const;
    StartPrepSDKCall(SDKCall_Raw);
    PrepSDKCall_SetFromConf(g_GameData, SDKConf_Signature, "CNavMesh::GetNearestNavArea");
    
    PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef); // const Vector &pos
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain); 	 // bool anyZ = false
    PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);  // float maxDist = 10000.0f
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);   // bool checkLOS = false
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);   // bool checkGround = true
    
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain); // CNavArea*
    
    if (!(NavMesh_GetNearestNavAreaFunc = EndPrepSDKCall()))
    {
        SetFailState("Missing signature 'CNavMesh::GetNearestNavArea'");
    }
}

int LoadGameDataOffset(const char[] name)
{
    int offset = g_GameData.GetOffset(name);
    if (offset == -1)
    {
        SetFailState("Failed to load game data offset '%s'", name);
    }
    
    return offset;
}

Address LoadGameDataAddress(const char[] name)
{
    Address addr = g_GameData.GetAddress(name);
    if (addr == Address_Null)
    {
        SetFailState("Failed to load game data address '%s'", name);
    }
    
    return addr;
}

//================================[ Functions ]================================//

void LoadVectorFromOffset(Address addr, float vector[3])
{
    for (int i; i < sizeof(vector); i++)
    {
        vector[i] = LoadFromAddress(addr + view_as<Address>(i * 4), NumberType_Int32);
    }
}

//================================================================//