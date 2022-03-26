#if defined _retakes_included
 #endinput
#endif
#define _retakes_included

// Bombsite declarations.
enum
{
	Bombsite_None,
	Bombsite_A,
	Bombsite_B,
	Bombsite_Max
};

// SpawnRole declarations.
// Used to determine a player's spawn area.
enum
{
	SpawnRole_None,
	SpawnRole_Planter,
	SpawnRole_Terrorist,
	SpawnRole_CounterTerrorist,
	SpawnRole_Max
};

// Represents a zone in the map area where players with specified roles are able to spawn in.
enum struct SpawnZone
{
	// SpawnRole this zone is restricted to. See the enum above.
	int restricted_role;
	
	// Zone boundaries.
	float mins[3];
	float maxs[3];
}

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
