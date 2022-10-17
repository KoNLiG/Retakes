/*
 * • Responsible for hooking and provind a semi interface for game events.
 */

#assert defined COMPILING_FROM_MAIN

// Hook events.
void Events_OnPluginStart()
{
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_PostNoCopy);
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }
    
    SpawnManager_OnPlayerSpawn(client);
    
    // WeaponAllocator_OnPlayerSpawn(client);
}

void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
    Gameplay_RoundPreStart();
    
    PlayerManager_RoundPreStart();
} 