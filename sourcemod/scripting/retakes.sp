#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <cstrike>
#include <retakes>
#include <nav_mesh>

#pragma newdecls required
#pragma semicolon 1

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
		this.in_edit_mode   = false;
		this.bombsite_index = 0;
		this.nav_area       = NULL_NAV_AREA;
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

	//============================================//

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

// Must be included after all definitions.
#define COMPILING_FROM_MAIN
#include "retakes/gameplay.sp"
#include "retakes/database.sp"
#include "retakes/spawn_manager.sp"
#include "retakes/player_manager.sp"
#include "retakes/configuration.sp"
#include "retakes/sdk.sp"
#include "retakes/events.sp"
#undef COMPILING_FROM_MAIN

public Plugin myinfo =
{
	name        = "[CS:GO] Retakes",
	author      = "Natanel 'LuqS', Omer 'KoNLiG'",
	description = "The new generation of Retakes gameplay!",
	version     = "1.0.0",
	url         = "https://github.com/Natanel-Shitrit/Retakes"
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
	LoadTranslations("localization.phrases");

	Gameplay_OnPluginStart();
	Database_OnPluginStart();
	SpawnManager_OnPluginStart();
	PlayerManager_OnPluginStart();
	Configuration_OnPluginStart();
	SDK_OnPluginStart();
	Events_OnPluginStart();
}

public void OnMapStart()
{
	Configuration_OnMapStart();
	SpawnManager_OnMapStart();
	Gameplay_OnMapStart();

	g_LaserIndex = PrecacheModel("materials/sprites/laser.vmt");
}

public void OnClientDisconnect(int client)
{
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