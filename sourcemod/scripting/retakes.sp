#include <sourcemod>
#include <sdktools>
#include <retakes>

#pragma newdecls required
#pragma semicolon 1

#define COMPILING_FROM_MAIN
#include "retakes/spawnmgr.sp"
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
	if (GetEngineVersion() != Engine_CSGO)
	{
		strcopy(error, err_max, "This plugin was made for use with CS:GO only.");
		return APLRes_Failure;
	}
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	// Hook 
	HookSpawnMgr();
} 