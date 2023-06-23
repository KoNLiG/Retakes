#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
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

    //============================================//
    void Close()
    {
        this.in_edit_mode = false;
        this.bombsite_index = 0;
        this.nav_area = NULL_NAV_AREA;
    }

    void Enter()
    {
        this.in_edit_mode = true;
    }

    void Exit()
    {
        this.Close();
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

enum struct Distributor
{
    StringMap weapons_map;

    CSWeaponID weapons_id[9];

    bool kit;

    bool assult_suit;

    bool kevlar;

    char current_loadout_name[32];

    int current_loadout_view;

    bool close_menu;

    //============================================//
    void Init()
    {
        this.weapons_map = new StringMap();
        this.weapons_id[8] = CSWeapon_KNIFE;
    }

    // Resets all unrelevant data on player disconnect.
    void Close()
    {
        delete this.weapons_map;

        for (int current_index; current_index < sizeof(this.weapons_id); current_index++)
        {
            this.weapons_id[current_index] = CSWeapon_NONE;
        }

        this.kit = false;
        this.assult_suit = false;
        this.kevlar = false;
        this.current_loadout_name[0] = '\0';
        this.current_loadout_view = 0;
        this.close_menu = false;
    }

    void ClearLoadout()
    {
        // 'sizeof(this.weapons_id) - 1' to exclude the knife index.
        for (int current_index; current_index < sizeof(this.weapons_id) - 1; current_index++)
        {
            this.weapons_id[current_index] = CSWeapon_NONE;
        }

        this.kit = false;
        this.assult_suit = false;
        this.kevlar = false;
    }
}

enum struct Player
{
    // Player slot index.
    int index;

    // Unique session user id.
    int user_id;

    // Player steam account id. (GetSteamAccountID - steamid3)
    int account_id;

    // All data related to spawns edit mode - implemented in configuration.sp.
    EditMode edit_mode;

    // All data related to the weapon distributor - implemented in distributor.sp.
    Distributor distributor;

    int spawn_role;

    int points;

    //============================================//
    void Init(int client)
    {
        this.index = client;
        this.user_id = GetClientUserId(this.index);
        this.account_id = GetSteamAccountID(this.index);

        this.distributor.Init();
    }

    void Close()
    {
        this.index = 0;
        this.user_id = 0;
        this.account_id = 0;

        this.edit_mode.Close();
        this.distributor.Close();

        this.spawn_role = SpawnRole_None;
        this.points = 0;
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
// ConVar retakes_max_wins_scramble;
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
ConVar retakes_database_table_distributor;
ConVar retakes_distributor_grace_period;
ConVar retakes_distributor_force_weapon;
ConVar retakes_distributor_ammo_limit;
ConVar retakes_explode_no_time;

// Must be included after all definitions.
#define COMPILING_FROM_MAIN
#include "retakes/events.sp"
#include "retakes/gameplay.sp"
#include "retakes/database.sp"
#include "retakes/spawn_manager.sp"
#include "retakes/player_manager.sp"
#include "retakes/configuration.sp"
#include "retakes/distributor.sp"
#include "retakes/sdk.sp"
#include "retakes/plant_logic.sp"
#include "retakes/defuse_logic.sp"
#include "retakes/api.sp"
#undef COMPILING_FROM_MAIN

bool g_Lateload;

public Plugin myinfo =
{
    name = "[CS:GO] Retakes",
    author = "Omer 'KoNLiG', DRANIX",
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

    g_Lateload = late;

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
    Distributor_OnPluginStart();
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
    Distributor_OnConfigsExecuted();
    SpawnManager_OnConfigsExecuted();

    // Late load support.
    Lateload();
}

public void OnClientPutInServer(int client)
{
    g_Players[client].Init(client);

    PlayerManger_OnClientPutInServer();
    Distributor_OnClientPutInServer(client);
}

public void OnClientDisconnect(int client)
{
    PlantLogic_OnClientDisconnect(client);
    Distributor_OnClientDisconnect(client);

    g_Players[client].Close();
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

void DisarmClient(int client, int slot_index = -1)
{
    static int m_hMyWeaponsOffset;
    if (!m_hMyWeaponsOffset)
    {
        m_hMyWeaponsOffset = FindSendPropInfo("CCSPlayer", "m_hMyWeapons");
    }

    static int max_weapons;
    if (!max_weapons)
    {
        // Always 64.
        max_weapons = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    }

    for (int weapon, ent; weapon < max_weapons; weapon++)
    {
        if ((ent = GetEntDataEnt2(client, m_hMyWeaponsOffset + weapon * 4)) == -1)
        {
            continue;
        }

        if (slot_index == -1 || GetPlayerWeaponSlot(client, slot_index) == ent)
        {
            SDKHooks_DropWeapon(client, ent);
            RemoveEntity(ent);
        }
    }
}

bool IsVectorZero(float vec[3])
{
    return !vec[0] && !vec[1] && !vec[2];
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

// Selects a random in-game client according to the given spawn role (SpawnRole_*).
// If 'spawn_role' is -1 then ALL players are inserted into the selection pool.
int SelectRandomClient(int spawn_role = -1)
{
    int clients_count;
    int[] clients = new int[MaxClients];

    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (!IsClientInGame(current_client))
        {
            continue;
        }

        if (spawn_role == -1 || (spawn_role != -1 && g_Players[current_client].spawn_role == spawn_role))
        {
            clients[clients_count++] = current_client;
        }
    }

    return clients_count ? clients[GetURandomInt() % clients_count] : -1;
}

// Called after every map change. (OnConfigsExecuted)
void Lateload()
{
    if (!g_Lateload)
    {
        return;
    }

    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client))
        {
            OnClientPutInServer(current_client);
        }
    }

    g_Lateload = false;
}

int IsValueInArray(int value, int[] arr, int size)
{
    for (int i; i < size; i++)
    {
        if (arr[i] == value)
        {
            return i;
        }
    }

    return -1;
}