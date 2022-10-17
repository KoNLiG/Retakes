/*
 * • Responsible for managing players.
 */

#assert defined COMPILING_FROM_MAIN

void PlayerManager_OnPluginStart()
{
    
}

void PlayerManager_RoundPreStart()
{
    PrintToChatAll("[PlayerManager_RoundPreStart]");
    
    // TODO: Switch players team.
    
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client))
        {
            // GetClientTeam returns equivalent values to the spawn roles enum.
            g_Players[current_client].spawn_role = GetClientTeam(current_client);
        }
    }
    
    // Generate a random planter from the defender team.
    int planter = SelectPlanter();
    if (planter != -1)
    {
        g_Players[planter].spawn_role = SpawnRole_Planter;
    }
}

stock int GetPlanter()
{
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && g_Players[current_client].spawn_role == SpawnRole_Planter)
        {
            return current_client;
        }
    }
    
    return -1;
}

int SelectPlanter()
{
    int clients_count;
    int[] clients = new int[MaxClients];
    
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && g_Players[current_client].spawn_role == SpawnRole_Defender)
        {
            clients[clients_count++] = current_client;
        }
    }
    
    return clients_count ? clients[GetRandomInt(0, clients_count - 1)] : -1;
} 