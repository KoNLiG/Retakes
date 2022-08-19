#if defined _retakes_included
 #endinput
#endif
#define _retakes_included

#define RETAKES_MAX_NAME_LENGTH 32
#define RETAKES_PREFIX_MENU "[Retakes]"
#define RETAKES_PREFIX " \x04" ... RETAKES_PREFIX_MENU ... "\x01" 

// Bombsite enumeration.
enum
{
	Bombsite_None = -1,
	Bombsite_A,
	Bombsite_B,
	Bombsite_Max
}

char g_BombsiteNames[][] = 
{ 
    "A",
    "B" 
};

// SpawnRole declarations.
// Used to determine a player's spawn area.
enum
{
	SpawnRole_None,
	SpawnRole_Planter,
	SpawnRole_Defender,
	SpawnRole_Attacker,
	SpawnRole_Max
}

char g_SpawnRoleNames[][] = 
{ 
    "None",
    "Planter", 
    "Defender", 
    "Attacker" 
};

#if !defined REQUIRE_PLUGIN
public void __pl_retakes_SetNTVOptional()
{
	// MarkNativeAsOptional("");
}
#endif

public SharedPlugin __pl_retakes = 
{
	name = "retakes", 
	file = "retakes.smx", 
#if defined REQUIRE_PLUGIN
    required = 1, 
#else
    required = 0, 
#endif
};
