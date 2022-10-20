/*
 * • Responsible for hooking and provind a semi interface for game events.
 */

#assert defined COMPILING_FROM_MAIN

// Hook events.
void Events_OnPluginStart()
{
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("bomb_planted", Event_BombPlanted);
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }
    
    PlayerManager_OnPlayerSpawn(client);
    SpawnManager_OnPlayerSpawn(client);
    
    // WeaponAllocator_OnPlayerSpawn(client);
}

void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
    Gameplay_RoundPreStart();
    PlayerManager_RoundPreStart();
    PlantLogic_RoundPreStart();
}

void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    PlantLogic_RoundFreezeEnd();
}

void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }
    
    int bombsite_index = event.GetInt("site");
    
    int planted_c4 = FindEntityByClassname(-1, "planted_c4");
    if (planted_c4 != -1)
    {
        PlantLogic_OnBombPlanted(client, bombsite_index, planted_c4);
    }
} 