/*
 * • Responsible for managing players.
 */

#assert defined COMPILING_FROM_MAIN

void PlayerManager_OnPluginStart()
{
}

void PlayerManager_OnMapStart()
{
    // Disable any manual team menu interaction for players.
    GameRules_SetProp("m_bIsQueuedMatchmaking", true);
}

void PlayerManager_RoundPreStart()
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
}