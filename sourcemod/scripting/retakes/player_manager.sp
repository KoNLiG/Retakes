/*
 * • Responsible for managing players.
 */

#assert defined COMPILING_FROM_MAIN

#define RETAKES_KILL_POINTS 25
#define RETAKES_HEADSHOT_POINTS 3
#define RETAKES_ASSIST_POINTS 8
#define RETAKES_DAMAGE_POINTS 5
#define RETAKES_LOSS_POINTS 1000

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
    if (g_SwapTeamsPerRoundStart)
        InitiateTeamSwap();

    else if (g_ScrambleTeamsPreRoundStart)
        InitiateTeamScramble();

    InitiateTeamBalance();

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

// WIP:
// Client Queue
// 1. Check clients in spectator and add them to a queue.
// 2. Check if client has reservation flag and move them to the front of the queue.
// 3. When the next "round_prestart" event comes around, flush players to available teams (CT, T)

// Scramble Teams
// 1. Scramble the teams.
// 2. When scrambling teams they cannot get un-balanced. aKa There should be the same amount of players on each team after scramble.
// InitiateTeamScramble();

// Balance Teams ( SortADTArrayCustom )
// 1. Team players should be balanced depending on their points.
// 2. We should try to even the amount of points per player on each team.
// InitiateTeamBalance();

void PlayerManager_PlayerDeath(Event event)
{
    int assister = GetClientOfUserId(event.GetInt("assister"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int victim = GetClientOfUserId(event.GetInt("userid"));
    bool headshot = event.GetBool("headshot");
    int points;
    
    points += (assister > 0) ? RETAKES_ASSIST_POINTS : 0;
    points += (headshot) ? RETAKES_HEADSHOT_POINTS : 0;

    if (attacker != victim)
        points += RETAKES_KILL_POINTS;
    else
        points -= RETAKES_KILL_POINTS;

    g_Players[attacker].points += points;
}

void PlayerManager_PlayerHurt(Event event)
{
    // int assister = GetClientOfUserId(event.GetInt("assister"));
    // int attacker = GetClientOfUserId(event.GetInt("attacker"));
    // int victim = GetClientOfUserId(event.GetInt("userid"));
    // int damage = event.GetInt("dmg_health");
    // int hitgroup = event.GetInt("hitgroup");
}

void InitiateTeamSwap()
{
    g_SwapTeamsPerRoundStart = false;
}

void InitiateTeamScramble()
{
    g_ScrambleTeamsPreRoundStart = false;
}

void InitiateTeamBalance()
{
    g_BalanceTeamsPreRoundStart = false;
}

bool IsTeamSlotOpen(int team)
{
    int count;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsClientConnected(i) || GetClientTeam(i) != team)
            continue;

        count++;
    }

    return (count < (team == CS_TEAM_CT ? g_MaxCounterTerrorist.IntValue : g_MaxTerrorist.IntValue));
}

void SwitchClientTeam(int client, int team)
{
    g_Players[client].spawn_role = team;
    CS_SwitchTeam(client, team);
}

int GetTotalRoundsPlayed()
{
    return GameRules_GetProp("m_totalRoundsPlayed");
}