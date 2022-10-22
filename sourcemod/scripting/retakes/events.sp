/*
 * • Responsible for hooking and provind a semi interface for game events.
 */

#assert defined COMPILING_FROM_MAIN

// Hook events.
void Events_OnPluginStart()
{
    HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_connect_full", Event_PlayerConnectFull);
    HookEvent("bomb_planted", Event_BombPlanted);
    HookEvent("bomb_defused", Event_BombDefused);
    HookEvent("bomb_begindefuse", Event_BeginDefuse);
    HookEvent("inferno_expire", Event_InfernoExpire);
}

void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
    Gameplay_RoundPreStart();
    PlayerManager_RoundPreStart();
    PlantLogic_RoundPreStart();
    DefuseLogic_RoundPreStart();
}

void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    PlantLogic_RoundFreezeEnd();
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
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    DefuseLogic_PlayerDeath(client);
}

void Event_PlayerConnectFull(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    // PlayerManager_OnPlayerConnectFull(client);
}

void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    int bombsite_index = event.GetInt("site");

    int planted_c4 = GetPlantedC4();
    if (planted_c4 != -1)
    {
        PlantLogic_OnBombPlanted(client, bombsite_index, planted_c4);
    }
}

void Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    int bombsite_index = event.GetInt("site");

    int planted_c4 = GetPlantedC4();
    if (planted_c4 != -1)
    {
        DefuseLogic_OnBombPlanted(client, bombsite_index, planted_c4);
    }
}

void Event_BeginDefuse(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    bool haskit = event.GetBool("haskit");

    int planted_c4 = GetPlantedC4();
    if (planted_c4 != -1)
    {
        DefuseLogic_OnBeginDefuse(client, haskit, planted_c4);
    }
}

void Event_InfernoExpire(Event event, const char[] name, bool dontBroadcast)
{
    int entity = event.GetInt("entityid");

    float origin[3];
    origin[0] = event.GetFloat("x");
    origin[1] = event.GetFloat("y");
    origin[2] = event.GetFloat("z");

    DefuseLogic_InfernoExpire(entity, origin);
}