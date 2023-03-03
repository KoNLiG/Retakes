/*
 * • Responsible for hooking and provind a semi interface for game events.
 */

#assert defined COMPILING_FROM_MAIN

// Hook events.
void Events_OnPluginStart()
{
    HookEvent("round_prestart", Event_RoundPreStart, EventHookMode_PostNoCopy);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_connect_full", Event_PlayerConnectFull);
    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("player_hurt", Event_PlayerHurt);
    HookEvent("bomb_planted", Event_BombPlanted);
    HookEvent("bomb_defused", Event_BombDefused);
    HookEvent("bomb_beginplant", Event_BeginPlant);
    HookEvent("bomb_begindefuse", Event_BeginDefuse);
    HookEvent("inferno_expire", Event_InfernoExpire);
}

void Event_RoundPreStart(Event event, const char[] name, bool dontBroadcast)
{
    Gameplay_OnRoundPreStart();
    PlayerManager_OnRoundPreStart();
    PlantLogic_OnRoundPreStart();
    DefuseLogic_OnRoundPreStart();
    Distributer_OnRoundPreStart();
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    Gameplay_OnRoundStart();
}

void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
    PlantLogic_OnRoundFreezeEnd();
    PlayerManager_OnRoundFreezeEnd();
    Gameplay_OnRoundFreezeEnd();
    Distributer_OnRoundFreezeEnd();
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    int winner = event.GetInt("winner");

    PlayerManager_OnRoundEnd(winner);
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
    Distributer_OnPlayerSpawn(client);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    DefuseLogic_OnPlayerDeath(client);
}

void Event_PlayerConnectFull(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    PlayerManager_OnPlayerConnectFull(client);
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    int team = event.GetInt("team"), oldteam = event.GetInt("oldteam");
    bool disconnect = event.GetBool("disconnect");

    PlayerManager_OnPlayerTeam(client, team, oldteam, disconnect);
}

void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (!attacker)
    {
        return;
    }

    int dmg_health = event.GetInt("dmg_health");
    PlayerManager_OnPlayerHurt(attacker, dmg_health);
}

void Event_BombPlanted(Event event, const char[] name, bool dontBroadcast)
{
    PlantLogic_OnBombPlanted();
}

void Event_BombDefused(Event event, const char[] name, bool dontBroadcast)
{
    DefuseLogic_OnBombDefused();
}

void Event_BeginPlant(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    int weapon_c4 = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon_c4 != -1)
    {
        PlantLogic_OnBeginPlant(weapon_c4);
    }
}

void Event_BeginDefuse(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    int planted_c4 = GetPlantedC4();
    if (planted_c4 != -1)
    {
        DefuseLogic_OnBeginDefuse(client, planted_c4);
    }
}

void Event_InfernoExpire(Event event, const char[] name, bool dontBroadcast)
{
    DefuseLogic_OnInfernoExpire();
}