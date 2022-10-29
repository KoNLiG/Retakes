/*
 * • Responsible for managing players.
 */

#assert defined COMPILING_FROM_MAIN

#define DEFAULT_SKIRMISH_ID "0"
#define RETAKES_SKIRMISH_ID "12"

ConVar sv_skirmish_id;

void PlayerManager_OnPluginStart()
{
    if (!(sv_skirmish_id = FindConVar("sv_skirmish_id")))
    {
        SetFailState("Failed to find convar 'sv_skirmish_id'");
    }
}

void PlayerManager_OnMapStart()
{
    // Disable any manual team menu interaction for players.
    GameRules_SetProp("m_bIsQueuedMatchmaking", true);
}

void PlayerManager_OnRoundPreStart()
{
    // TODO: Switch players team.

    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client))
        {
            // GetClientTeam returns equivalent values to the spawn roles enum.
            g_Players[current_client].spawn_role = GetClientTeam(current_client);
        }
    }
}

void PlayerManager_OnRoundFreezeEnd()
{
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client))
        {
            ReplicateRetakeMode(current_client, true);
        }
    }
}

// Handle players who joined in the middle of a round.
void PlayerManager_OnPlayerSpawn(int client)
{
    if (g_Players[client].spawn_role == SpawnRole_None)
    {
        g_Players[client].spawn_role = GetClientTeam(client);

        #if defined DEBUG
        LogMessage("Auto assigned spawn role %d for client %d", g_Players[client].spawn_role, client);
        #endif
    }

    // Too early here.
    RequestFrame(DisableClientRetakeMode, GetClientUserId(client));
}

void DisableClientRetakeMode(int client)
{
    if ((client = GetClientOfUserId(client)))
    {
        ReplicateRetakeMode(client, false);
    }
}

void ReplicateRetakeMode(int client, bool value)
{
    if (IsFakeClient(client))
    {
        return;
    }

    sv_skirmish_id.ReplicateToClient(client, value ? RETAKES_SKIRMISH_ID : DEFAULT_SKIRMISH_ID);
}