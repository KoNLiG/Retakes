#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <retakes>
#include <nav_mesh>

#pragma newdecls required
#pragma semicolon 1

enum struct Bombsite
{
    // Bombsite A = 0, Bombsite B = 1
    int bombsite_index;

    // Bombsite mins, maxs and center.
    float mins[3];
    float maxs[3];
    float center[3];
}

enum struct Player
{
    // Bombsite index used in edit mode.
    int edit_mode_bombsite;

    bool in_edit_mode;

	int spawn_role;
	
    //============================================//

    void Close()
    {
        this.edit_mode_bombsite = 0;
        this.in_edit_mode = false;
        this.spawn_role = SpawnRole_None;
    }
}

Player g_Players[MAXPLAYERS + 1];

int g_LaserIndex;

#define COMPILING_FROM_MAIN
#include "retakes/spawn_manager.sp"
#include "retakes/configuration.sp"
#undef COMPILING_FROM_MAIN

public Plugin myinfo =
{
    name = "[CS:GO] Retakes",
    author = "Natanel 'LuqS', Omer 'KoNLiG'",
    description = "The new generation of Retakes gameplay!",
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
    // InitializeAPI();
    
    return APLRes_Success;
}

public void OnPluginStart()
{
    // Perform necessary hooks for the spawn & player manager.
    InitializeSpawnManager();
    // InitializePlayerManager();
    
    // Register all convars.
    RegisterConVars();
    
    // Register all commands.
    RegisterCommands();
    
    // Parse the retakes config once.
    // The config can be reparsed by running the server command 'retakes_reloadcfg'
    ParseRetakesConfig();
}

public void OnMapStart()
{
    InitializeBombsites();

    g_LaserIndex = PrecacheModel("materials/sprites/laser.vmt");
}

public void OnClientDisconnect(int client)
{
    g_Players[client].Close();
}

void GetClientAimPosition(int client, float position[3])
{	
	float cl_origin[3], cl_angles[3];
	GetClientEyePosition(client, cl_origin);
	GetClientEyeAngles(client, cl_angles);
	
	TR_TraceRayFilter(cl_origin, cl_angles, MASK_ALL, RayType_Infinite, Filter_ExcludeMyself, client);
	TR_GetEndPosition(position);
}

bool Filter_ExcludeMyself(int entity, int mask, int data)
{
	return entity != data;
}