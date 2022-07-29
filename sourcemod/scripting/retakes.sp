#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <retakes>
#include <nav_mesh>

#pragma newdecls required
#pragma semicolon 1

#define COMPILING_FROM_MAIN
#include "retakes/player_manager.sp"
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
    InitializePlayerManager();
    
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
}