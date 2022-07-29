#if defined _retakes_included
 #endinput
#endif
#define _retakes_included

#define RETAKES_MAX_NAME_LENGTH 32
#define RETAKES_PREFIX_MENU "Retakes"
#define RETAKES_PREFIX "\x04[" ... RETAKES_PREFIX_MENU ... "]\x01"

// Bombsite declarations.
enum
{
    Bombsite_None = -1,
    Bombsite_A,
    Bombsite_B,
    Bombsite_Max
}

enum struct BombSite
{
    // Bombsite A = 0, Bombsite B = 1
    int bombsite_index;

    // Bombsite mins, maxs and center.
    float mins[3];
    float maxs[3];
    float center[3];
}

// SpawnRole declarations.
// Used to determine a player's spawn area.
enum
{
    SpawnRole_None = 0,
    SpawnRole_Planter,
    SpawnRole_Defender,
    SpawnRole_Attacker
}

enum
{
    NavMeshArea_Defender,
    NavMeshArea_Attacker,
    NavMeshArea_Max
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
