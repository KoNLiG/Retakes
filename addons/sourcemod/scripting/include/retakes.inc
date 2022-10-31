#if defined _retakes_included
 #endinput
#endif
#define _retakes_included

// Library name this plugin is registered under.
#define RETAKES_LIB_NAME "retakes"

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

/**
 * Retrieves the currently targeted bombsite.
 *
 * @return               Bombsite index. See the enum above.
 */
native int Retakes_GetTargetBombsite();

/**
 * Called once a target bombsite is being selected.
 *
 * Note: Do not use this forward if you want to get a positive bombsite index value,
 *       use 'Retakes_OnBombsiteSelectedPost' instead.
 *
 * @param bombsite_index     	 Bombsite index (by reference). See the enum above.
 */
forward void Retakes_OnBombsiteSelected(int &bombsite_index);

/**
 * Called after a target bombsite has been selected.
 *
 * @param bombsite_index     	 Bombsite index. See the enum above.
 */
forward void Retakes_OnBombsiteSelectedPost(int bombsite_index);

#if !defined REQUIRE_PLUGIN
public void __pl_retakes_SetNTVOptional()
{
    MarkNativeAsOptional("Retakes_GetTargetBombsite");
}
#endif

public SharedPlugin __pl_retakes =
{
    name = RETAKES_LIB_NAME,
    file = "retakes.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};
