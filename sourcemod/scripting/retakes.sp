#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <cstrike>
#include <retakes>
#include <nav_mesh>
#include <autoexecconfig>

#pragma newdecls required
#pragma semicolon 1

// Enable debug mode.
#define DEBUG

#if defined DEBUG
#include <profiler>
#endif

enum
{
    NavMeshArea_Defender,
    NavMeshArea_Attacker,
    NavMeshArea_Max
}

enum struct Bombsite
{
    // Bombsite A = 0, Bombsite B = 1
    int bombsite_index;

    // Bombsite mins, maxs and center.
    float mins[3];
    float maxs[3];
    float center[3];

    //=============================================//
    bool IsValid()
    {
        return !IsVectorZero(this.mins) && !IsVectorZero(this.maxs) && !IsVectorZero(this.center);
    }

    void Reset()
    {
        this.mins = { 0.0, 0.0, 0.0 };
        this.maxs = { 0.0, 0.0, 0.0 };
        this.center = { 0.0, 0.0, 0.0 };
    }
}

enum struct EditMode
{
    bool in_edit_mode;

    int bombsite_index;

    NavArea nav_area;

    void Enter()
    {
        this.in_edit_mode = true;
    }

    void Exit()
    {
        this.Reset();
    }

    void Reset()
    {
        this.in_edit_mode = false;
        this.bombsite_index = 0;
        this.nav_area = NULL_NAV_AREA;
    }

    void NextBombsite()
    {
        this.bombsite_index = ++this.bombsite_index % Bombsite_Max;
    }

    // Returns the selected nav area if not null, otherwise returns the nav area from the aiming position.
    NavArea GetNavArea(int client)
    {
        if (this.nav_area != NULL_NAV_AREA)
        {
            return this.nav_area;
        }

        float aim_position[3];
        GetClientAimPosition(client, aim_position);

        return TheNavMesh.GetNearestNavArea(aim_position);
    }
}

enum struct Player
{
    EditMode edit_mode;

    int spawn_role;

    int userid;

    int points;

    //============================================//
    void Initiate(int client)
    {
        this.userid = GetClientUserId(client);
        this.points = GetRandomInt(0, 120);
    }

    void Reset()
    {
        this.edit_mode.Reset();

        this.spawn_role = SpawnRole_None;
    }

    bool InEditMode()
    {
        return this.edit_mode.in_edit_mode;
    }
}

Player g_Players[MAXPLAYERS + 1];

int g_LaserIndex;
int g_WinRowCount;
bool g_ScrambleTeamsPreRoundStart;
bool g_BalanceTeamsPreRoundStart;
bool g_SwapTeamsPerRoundStart;

// Server tickrate. (64.0|128.0|...)
float g_ServerTickrate;

ConVar g_MinimumPlayers;
ConVar g_CountBotsAsPlayers;
ConVar g_MaxRoundWinsBeforeScramble;
ConVar g_MaxCounterTerrorist;
ConVar g_MaxTerrorist;

// Must be included after all definitions.
#define COMPILING_FROM_MAIN
#include "retakes/events.sp"
#include "retakes/gameplay.sp"
#include "retakes/database.sp"
#include "retakes/spawn_manager.sp"
#include "retakes/player_manager.sp"
#include "retakes/configuration.sp"
#include "retakes/sdk.sp"
#include "retakes/plant_logic.sp"
#include "retakes/defuse_logic.sp"
#undef COMPILING_FROM_MAIN

public Plugin myinfo =
{
    name = "[CS:GO] Retakes",
    author = "Natanel 'LuqS', Omer 'KoNLiG', DRANIX",
    description = "The new generation of Retakes gameplay!",
    version = "1.0.0",
    url = "https://github.com/KoNLiG/Retakes"
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
    // InitializeAPI();

    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("retakes.phrases");
    LoadTranslations("localization.phrases");

    Gameplay_OnPluginStart();
    Database_OnPluginStart();
    SpawnManager_OnPluginStart();
    PlayerManager_OnPluginStart();
    Configuration_OnPluginStart();
    SDK_OnPluginStart();
    Events_OnPluginStart();
    PlantLogic_OnPluginStart();
    DefuseLogic_OnPluginStart();

    // Get the server tickrate once.
    g_ServerTickrate = 1.0 / GetTickInterval();
}

public void OnMapStart()
{
    Configuration_OnMapStart();
    SpawnManager_OnMapStart();
    PlayerManager_OnMapStart();

    g_LaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
}

public void OnClientDisconnect(int client)
{
    PlantLogic_OnClientDisconnect(client);

    g_Players[client].Reset();
}

void GetClientAimPosition(int client, float result[3])
{
    float origin[3], angles[3];
    GetClientEyePosition(client, origin);
    GetClientEyeAngles(client, angles);

    TR_TraceRayFilter(origin, angles, MASK_ALL, RayType_Infinite, Filter_ExcludeMyself, client);
    TR_GetEndPosition(result);
}

bool Filter_ExcludeMyself(int entity, int mask, int data)
{
    return entity != data;
}

void StringToLower(char[] str)
{
    for (int current_char; str[current_char]; current_char++)
    {
        str[current_char] = CharToLower(str[current_char]);
    }
}

void DisarmClient(int client)
{
    int max_weapons = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");

    for (int current_weapon, ent; current_weapon < max_weapons; current_weapon++)
    {
        if ((ent = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", current_weapon)) != -1)
        {
            RemovePlayerItem(client, ent);
            RemoveEntity(ent);
        }
    }
}

bool IsVectorZero(float vec[3])
{
    return !FloatCompare(vec[0], 0.0) && !FloatCompare(vec[1], 0.0) && !FloatCompare(vec[2], 0.0);
}

int GetPlantedC4()
{
    return FindEntityByClassname(-1, "planted_c4");
}

bool IsWarmupPeriod()
{
    return view_as<bool>(GameRules_GetProp("m_bWarmupPeriod"));
}

bool IsWaitingForPlayers()
{
    int count;

    if (g_CountBotsAsPlayers.BoolValue)
        count = GetClientCount(false);
    else
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i))
                continue;

            count++;
        }
    }

    if (count >= g_MinimumPlayers.IntValue)
        return false;

    return true;
}