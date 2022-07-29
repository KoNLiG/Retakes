/*
 * • Responsible for managing players.
 */

#assert defined COMPILING_FROM_MAIN

int g_SpawnRole[MAXPLAYERS + 1];

void InitializePlayerManager()
{
    HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_PostNoCopy);
}

void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
    PrintToChatAll("[Event_RoundStart]");
    
    // TODO: Switch players team.
    
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client))
        {
            // GetClientTeam returns an equivalent values to the spawn roles enum.
            g_SpawnRole[current_client] = GetClientTeam(current_client);
        }
    }
    
    // Generate a random planter from the defender team.
    int planter = SelectPlanter();
    if (planter != -1)
    {
        g_SpawnRole[planter] = SpawnRole_Planter;
    }
}

stock int GetPlanter()
{
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && g_SpawnRole[current_client] == SpawnRole_Planter)
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
        if (IsClientInGame(current_client) && g_SpawnRole[current_client] == SpawnRole_Defender)
        {
            clients[clients_count++] = current_client;
        }
    }
    
    return clients_count ? clients[GetRandomInt(0, clients_count - 1)] : -1;
}