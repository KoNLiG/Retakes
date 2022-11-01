/*
 * • Responsible for managing players.
 */

#assert defined COMPILING_FROM_MAIN

#define RETAKES_KILL_POINTS 25
#define RETAKES_HEADSHOT_POINTS 3
#define RETAKES_ASSIST_POINTS 8
#define RETAKES_DAMAGE_POINTS 5
#define RETAKES_LOSS_POINTS 1000

#define POINTS 0
#define CLIENT_USERID 1

#define DEFAULT_SKIRMISH_ID "0"
#define RETAKES_SKIRMISH_ID "12"

ConVar sv_skirmish_id;

ArrayList g_TerroristList;
ArrayList g_CounterTerroristList;
ArrayList g_PlayersList;

int g_PlayerCount;
int g_PlayerScores[MAXPLAYERS][2];

void PlayerManager_OnPluginStart()
{
    g_TerroristList = new ArrayList();
    g_CounterTerroristList = new ArrayList();
    g_PlayersList = new ArrayList(2);

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

void PlayerManager_OnRoundEnd()
{
    g_PlayerCount = 0;
    g_TerroristList.Clear();
    g_CounterTerroristList.Clear();
    g_PlayersList.Clear();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        if (GetClientTeam(i) > CS_TEAM_SPECTATOR)
            continue;

        g_PlayerScores[i][POINTS] = g_Players[i].points;
        g_PlayerScores[i][CLIENT_USERID] = g_Players[i].userid;
        g_PlayersList.PushArray(g_PlayerScores[i]);

        g_PlayerCount++;
    }
}

void PlayerManager_OnRoundPreStart()
{
    if (g_IsWaitingForPlayers)
    {
        // Set all players spawn role to None if we're waiting for players.
        for (int current_client = 1; current_client <= MaxClients; current_client++)
        {
            if (IsClientInGame(current_client))
            {
                g_Players[current_client].spawn_role = SpawnRole_None;
            }
        }

        return;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i))
            continue;

        if (GetClientTeam(i) <= CS_TEAM_SPECTATOR)
            continue;

        g_PlayerScores[i][POINTS] = g_Players[i].points;
        g_PlayerScores[i][CLIENT_USERID] = g_Players[i].userid;
        g_PlayersList.PushArray(g_PlayerScores[i]);

        g_PlayerCount++;
    }

    SortADTArrayCustom(g_PlayersList, SortScoreAscending);

    int set_count = 1;

    if (g_PlayerCount % 2 == 1)
    {
        for (int i = 1; i <= g_PlayerCount - 2; i += 2)
        {
            if (set_count % 2)
            {
                g_TerroristList.Push(g_PlayerScores[i][CLIENT_USERID]);
                g_CounterTerroristList.Push(g_PlayerScores[i + 1][CLIENT_USERID]);
            }

            else
            {
                g_TerroristList.Push(g_PlayerScores[i][CLIENT_USERID]);
                g_CounterTerroristList.Push(g_PlayerScores[i + 1][CLIENT_USERID]);
            }

            set_count++;
        }

        if (GetRandomInt(0, 1) == 0)
            g_CounterTerroristList.Push(g_PlayerScores[g_PlayerCount][CLIENT_USERID]);

        else
            g_TerroristList.Push(g_PlayerScores[g_PlayerCount][CLIENT_USERID]);
    }

    else
    {
        for (int i = 1; i <= g_PlayerCount - 1; i += 2)
        {
            if (set_count % 2)
            {
                g_CounterTerroristList.Push(g_PlayerScores[i][CLIENT_USERID]);
                g_TerroristList.Push(g_PlayerScores[i + 1][CLIENT_USERID]);
            }

            else
            {
                g_TerroristList.Push(g_PlayerScores[i][CLIENT_USERID]);
                g_CounterTerroristList.Push(g_PlayerScores[i + 1][CLIENT_USERID]);
            }

            set_count++;
        }
    }

    for (int i, client; i < g_CounterTerroristList.Length; i++)
    {
        if (!(client = GetClientOfUserId(g_CounterTerroristList.Get(i))))
            continue;

        SwitchClientTeam(client, CS_TEAM_CT);
    }

    for (int i, client; i < g_TerroristList.Length; i++)
    {
        if (!(client = GetClientOfUserId(g_TerroristList.Get(i))))
            continue;

        SwitchClientTeam(client, CS_TEAM_T);
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

void PlayerManger_OnClientPutInServer(int client)
{
    if (g_IsWaitingForPlayers && !ShouldWaitForPlayers())
    {
        SetWaitingForPlayersState(false);
    }
}

// Handle players who joined in the middle of a round.
void PlayerManager_OnPlayerSpawn(int client)
{
    if (!g_IsWaitingForPlayers && g_Players[client].spawn_role == SpawnRole_None)
    {
        g_Players[client].spawn_role = GetClientTeam(client);

        #if defined DEBUG
        LogMessage("Auto assigned spawn role %d for client %d", g_Players[client].spawn_role, client);
        #endif
    }

    // Too early here.
    RequestFrame(DisableClientRetakeMode, GetClientUserId(client));
}

void PlayerManager_OnPlayerConnectFull(int client)
{
    g_Players[client].spawn_role = CS_TEAM_SPECTATOR;

    ChangeClientTeam(client, CS_TEAM_SPECTATOR);
}

void PlayerManager_OnPlayerDeath(Event event)
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

void PlayerManager_OnPlayerHurt(Event event)
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

int SortScoreAscending(int position, int position_two, Handle array, Handle hndl)
{
    int client[2]; GetArrayArray(array, position, client, 2);
    int client_two[2]; GetArrayArray(array, position_two, client_two, 2);

    int points = client[POINTS];
    int points_two = client_two[POINTS];

    if (points > points_two)
        return -1;

    return points < points_two;
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
