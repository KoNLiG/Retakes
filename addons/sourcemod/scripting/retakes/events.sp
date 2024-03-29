/*
 * • Responsible for hooking and provind a semi interface for game events.
 */

#assert defined COMPILING_FROM_MAIN

#define TIME_CONVERSION_FACTOR 1000.0

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
#if defined DEBUG
    static Profiler profiler;
    if (!profiler)
    {
        profiler = new Profiler();
    }
    profiler.Start();
#endif

    Gameplay_OnRoundPreStart();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[Gameplay_OnRoundPreStart] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
    profiler.Start();
#endif

    PlayerManager_OnRoundPreStart();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[PlayerManager_OnRoundPreStart] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
    profiler.Start();
#endif

    PlantLogic_OnRoundPreStart();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[PlantLogic_OnRoundPreStart] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
    profiler.Start();
#endif

    DefuseLogic_OnRoundPreStart();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[DefuseLogic_OnRoundPreStart] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
    profiler.Start();
#endif

    Distributor_OnRoundPreStart();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[Distributor_OnRoundPreStart] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
#endif
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
#if defined DEBUG
    static Profiler profiler;
    if (!profiler)
    {
        profiler = new Profiler();
    }
    profiler.Start();
#endif

    Gameplay_OnRoundStart();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[Gameplay_OnRoundStart] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
    profiler.Start();
#endif

    Distributor_OnRoundStart();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[Distributor_OnRoundStart] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
#endif
}

void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast)
{
#if defined DEBUG
    static Profiler profiler;
    if (!profiler)
    {
        profiler = new Profiler();
    }
    profiler.Start();
#endif

    PlantLogic_OnRoundFreezeEnd();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[PlantLogic_OnRoundFreezeEnd] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
    profiler.Start();
#endif

    PlayerManager_OnRoundFreezeEnd();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[PlayerManager_OnRoundFreezeEnd] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
    profiler.Start();
#endif

    Gameplay_OnRoundFreezeEnd();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[Gameplay_OnRoundFreezeEnd] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
    profiler.Start();
#endif

    Distributor_OnRoundFreezeEnd();

#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[Distributor_OnRoundFreezeEnd] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
#endif
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

    // DO NOT notify about bots being controlled.
    // Apparently, 'player_spawn' event is called after every player
    // controlling a bot, which is a behavior we don't want.
    if (IsControllingBot(client))
    {
        return;
    }

    int team = event.GetInt("teamnum");

#if defined DEBUG
    static Profiler profiler;
    if (!profiler)
    {
        profiler = new Profiler();
    }

    profiler.Start();
#endif

    PlayerManager_OnPlayerSpawn(client);
#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[PlayerManager_OnPlayerSpawn] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);

    profiler.Start();
#endif

    if (team > CS_TEAM_SPECTATOR)
    {
        SpawnManager_OnPlayerSpawn(client);
    }
#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[SpawnManager_OnPlayerSpawn] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);

    profiler.Start();
#endif

    if (team > CS_TEAM_SPECTATOR)
    {
        Distributor_OnPlayerSpawn(client);
    }
#if defined DEBUG
    profiler.Stop();
    PrintToConsoleAll("[Distributor_OnPlayerSpawn] VPROF: %fs, %fms", profiler.Time, profiler.Time * TIME_CONVERSION_FACTOR);
#endif
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
    Distributor_OnPlayerConnectFull(client);
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!client)
    {
        return;
    }

    int team = event.GetInt("team");
    bool disconnect = event.GetBool("disconnect");

    PlayerManager_OnPlayerTeam(client, team, disconnect);
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