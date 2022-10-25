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
}

void PlayerManager_OnMapStart()
{
    // Disable any manual team menu interaction for players.
    GameRules_SetProp("m_bIsQueuedMatchmaking", true);
}

void PlayerManager_OnRoundPreStart()
{
    int userid;
    int client;

    g_TerroristList.Clear();
    g_CounterTerroristList.Clear();
    g_PlayersList.Clear();

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
    
    int iSetCount = 1;

    if (g_PlayerCount % 2 == 1)
    {
        for (int i = 1; i <= g_PlayerCount - 2; i += 2)
        {
            if (iSetCount % 2)
            {
                g_TerroristList.Push(g_PlayerScores[i][CLIENT_USERID]);
                g_CounterTerroristList.Push(g_PlayerScores[i + 1][CLIENT_USERID]);
            }

            else
            {
                g_TerroristList.Push(g_PlayerScores[i][CLIENT_USERID]);
                g_CounterTerroristList.Push(g_PlayerScores[i + 1][CLIENT_USERID]);
            }

            iSetCount++;
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
            if (iSetCount % 2)
            {
                g_CounterTerroristList.Push(g_PlayerScores[i][CLIENT_USERID]);
                g_TerroristList.Push(g_PlayerScores[i + 1][CLIENT_USERID]);
            }

            else
            {
                g_TerroristList.Push(g_PlayerScores[i][CLIENT_USERID]);
                g_CounterTerroristList.Push(g_PlayerScores[i + 1][CLIENT_USERID]);
            }

            iSetCount++;
        }
    }

    for (int i; i < g_CounterTerroristList.Length; i++)
    {
        userid = g_CounterTerroristList.Get(i);
        client = GetClientOfUserId(userid);

        if (!IsClientInGame(client))
            continue;

        SwitchClientTeam(client, CS_TEAM_CT);
    }
    
    for (int i; i < g_TerroristList.Length; i++)
    {
        userid = g_CounterTerroristList.Get(i);
        client = GetClientOfUserId(userid);

        if (!IsClientInGame(client))
            continue;

        SwitchClientTeam(client, CS_TEAM_T);
    }
}

void PlayerManager_OnRoundEnd()
{

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

void PlayerManager_OnPlayerConnectFull(int client)
{
    g_Players[client].Initiate(client);

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
