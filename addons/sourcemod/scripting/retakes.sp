#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <cstrike>
#include <retakes>
#include <nav_mesh>
#include <autoexecconfig>
#include <queue>

#pragma newdecls required
#pragma semicolon 1

// Enable debug mode.
#define DEBUG

#define PLUGIN_TAG "Retakes"

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
    int index;

    int user_id;

    int account_id;

    EditMode edit_mode;

    StringMap weapons_map;

    CSWeaponID weapons_id[8];

    bool kit;

    bool assult_suit;

    bool kevlar;

    char current_loadout_name[32];

    int current_loadout_view;

    bool close_menu;

    int old_team;

    int spawn_role;

    int points;

    //============================================//
    void Initiate(int client)
    {
        this.index = client;

        this.user_id = GetClientUserId(this.index);

        this.account_id = GetSteamAccountID(this.index);

        this.weapons_map = new StringMap();

        this.current_loadout_name[0] = '\n';

        this.close_menu = false;

        this.points = 0;
    }

    void ClearLoadout()
    {
        for (int i; i < 8; i++)
        {
            this.weapons_id[i] = CSWeapon_NONE;
        }

        this.kit = false;
        this.kevlar = false;
        this.assult_suit = false;
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

// Server tickrate. (64.0|128.0|...)
float g_ServerTickrate;

// ConVar definitions. handled in 'configuration.sp'
ConVar retakes_preferred_team;
ConVar retakes_queued_players_team;
ConVar retakes_player_min;
ConVar retakes_bots_are_players;
ConVar retakes_max_wins_scramble;
ConVar retakes_max_attackers;
ConVar retakes_max_defenders;
ConVar retakes_adjacent_tree_layers;
ConVar retakes_auto_plant;
ConVar retakes_instant_plant;
ConVar retakes_unfreeze_planter;
ConVar retakes_lockup_bombsite;
ConVar retakes_skip_freeze_period;
ConVar retakes_instant_defuse;
ConVar retakes_max_consecutive_rounds_same_target_site;
ConVar retakes_database_entry;
ConVar retakes_database_table_spawns;
ConVar retakes_database_table_distributer;
ConVar retakes_distributer_enable;
ConVar retakes_distributer_grace_period;
ConVar retakes_distributer_force_weapon;
ConVar retakes_distributer_ammo_limit;
ConVar retakes_explode_no_time;

// Must be included after all definitions.
#define COMPILING_FROM_MAIN
#include "retakes/events.sp"
#include "retakes/gameplay.sp"
#include "retakes/database.sp"
#include "retakes/spawn_manager.sp"
#include "retakes/player_manager.sp"
#include "retakes/configuration.sp"
#include "retakes/distributer.sp"
#include "retakes/sdk.sp"
#include "retakes/plant_logic.sp"
#include "retakes/defuse_logic.sp"
#include "retakes/api.sp"
#undef COMPILING_FROM_MAIN

public Plugin myinfo =
{
    name = "[CS:GO] Retakes",
    author = "Natanel 'LuqS', Omer 'KoNLiG', Daniel 'DRANIX'",
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
    InitializeAPI();

    return APLRes_Success;
}

public void OnPluginStart()
{
    LoadTranslations("retakes.phrases");
    LoadTranslations("retakes_weapons.phrases");
    LoadTranslations("localization.phrases");

    Configuration_OnPluginStart();
    Distributer_OnPluginStart();
    Gameplay_OnPluginStart();
    Database_OnPluginStart();
    SpawnManager_OnPluginStart();
    PlayerManager_OnPluginStart();
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
    Gameplay_OnMapStart();

    g_LaserIndex = PrecacheModel("materials/sprites/laserbeam.vmt");
}

public void OnConfigsExecuted()
{
    Distributer_OnConfigsExecuted();
    SpawnManager_OnConfigsExecuted();

    // Late load support.
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client))
        {
           OnClientPutInServer(current_client);
        }
    }
}

public void OnClientPutInServer(int client)
{
    g_Players[client].Initiate(client);

    PlayerManger_OnClientPutInServer();
    Distributer_OnClientPutInServer(client);
}

public void OnClientDisconnect(int client)
{
    PlantLogic_OnClientDisconnect(client);
    Distributer_OnClientDisconnect(client);

    g_Players[client].Reset();
}

public void OnClientDisconnect_Post(int client)
{
	Gameplay_OnClientDisconnectPost();
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

void DisarmClientFirearms(int userid)
{
    int client = GetClientOfUserId(userid);

    if (!client)
    {
        return;
    }

    char classname[32];
    int max_weapons = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");

    for (int weapon, ent; weapon < max_weapons; weapon++)
    {
        if ((ent = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", weapon)) == -1
         || (GetEntityClassname(ent, classname, sizeof(classname)) && IsKnifeClassname(classname)))
        {
            continue;
        }

        RemovePlayerItem(client, ent);
        RemoveEntity(ent);
    }
}

bool IsKnifeClassname(const char[] classname)
{
    return (StrContains(classname, "knife") != -1 || StrContains(classname, "bayonet") != -1);
}

bool IsVectorZero(float vec[3])
{
    return !FloatCompare(vec[0], 0.0) && !FloatCompare(vec[1], 0.0) && !FloatCompare(vec[2], 0.0);
}

int GetPlantedC4()
{
    return FindEntityByClassname(-1, "planted_c4");
}

bool ShouldWaitForPlayers()
{
    return GetRetakeClientCount() < retakes_player_min.IntValue;
}

int GetRetakeClientCount()
{
    if (retakes_bots_are_players.BoolValue)
    {
        return GetClientCount();
    }

    int count;
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && !IsFakeClient(current_client))
        {
            count++;
        }
    }

    return count;
}

bool IsRetakeClient(int client)
{
    return retakes_bots_are_players.BoolValue || !retakes_bots_are_players.BoolValue && !IsFakeClient(client);
}

int GetTeamSpawnRole(int team)
{
    return team == CS_TEAM_SPECTATOR ? SpawnRole_None : team;
}

// Doesn't include spectator slots.
int GetRetakeMaxHumanPlayers()
{
	return retakes_max_attackers.IntValue + retakes_max_defenders.IntValue;
}

void FixMenuGap(Menu menu)
{
    int max = (6 - menu.ItemCount);
    for (int i; i < max; i++)
    {
        menu.AddItem("", "", ITEMDRAW_NOTEXT);
    }
}

int SelectRandomClient(int spawn_role = -1)
{
    int clients_count;
    int[] clients = new int[MaxClients];

    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client))
        {
            if (spawn_role >= SpawnRole_None)
            {
                if (g_Players[current_client].spawn_role == spawn_role)
                {
                    clients[clients_count++] = current_client;
                }
            }

            else
            {
                clients[clients_count++] = current_client;
            }
        }
    }

    return clients_count ? clients[GetURandomInt() % clients_count] : -1;
}