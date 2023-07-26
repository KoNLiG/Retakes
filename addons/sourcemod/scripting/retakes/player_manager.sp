/*
 * • Responsible for managing players.
 */

#assert defined COMPILING_FROM_MAIN

#define DEFAULT_SKIRMISH_ID "0"
#define RETAKES_SKIRMISH_ID "12"

ConVar sv_skirmish_id;

Queue g_QueuedPlayers;

// Index of the last winning team.
int g_LastWinnerTeam;

void PlayerManager_OnPluginStart()
{
    if (!(sv_skirmish_id = FindConVar("sv_skirmish_id")))
    {
        SetFailState("Failed to find convar 'sv_skirmish_id'");
    }

    g_QueuedPlayers = new Queue();
}

void PlayerManager_OnMapStart()
{
    // Disable any manual team menu interaction for players.
    GameRules_SetProp("m_bIsQueuedMatchmaking", true);
}

void PlayerManager_OnRoundEnd(int winner)
{
    g_LastWinnerTeam = winner;
}

void PlayerManager_OnRoundPreStart()
{
    HandleQueuedClients();

    if (g_IsWaitingForPlayers)
    {
        // Set all players spawn role to None if we're waiting for players.
        for (int current_client = 1; current_client <= MaxClients; current_client++)
        {
            if (IsClientInGame(current_client) && IsRetakeClient(current_client))
            {
                g_Players[current_client].spawn_role = SpawnRole_None;
            }
        }

        return;
    }

    HandleClientTeams();

    ResetPlayersPoints();
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

void PlayerManger_OnClientPutInServer()
{
    if (g_IsWaitingForPlayers && !ShouldWaitForPlayers())
    {
        SetWaitingForPlayersState(false);
    }
}

// Handle players who joined in the middle of a round.
void PlayerManager_OnPlayerSpawn(int client)
{
    // Too early here.
    RequestFrame(DisableClientRetakeMode, g_Players[client].user_id);

    DisarmClient(client);
}

void PlayerManager_OnPlayerConnectFull(int client)
{
    // First player joined.
    if (GetRetakeClientCount() == 1)
    {
        CS_TerminateRound(0.1, CSRoundEnd_Draw);
    }

    SetPlayerTeam(client, CS_TEAM_SPECTATOR);

    // Add the player to the end of the queue.
    g_QueuedPlayers.Push(g_Players[client].user_id);

    // Notify the player.
    char place[16];
    OrdinalSuffix(g_QueuedPlayers.Length, place, sizeof(place));
    PrintToChat(client, "%T%T", "Messages Prefix", client, "Placed In Queue", client, place);
}

void PlayerManager_OnPlayerTeam(int client, int team, bool disconnect)
{
    if (!disconnect)
    {
        g_Players[client].spawn_role = GetTeamSpawnRole(team);
    }
}

void PlayerManager_OnPlayerHurt(int attacker, int dmg_health)
{
    g_Players[attacker].points += dmg_health;
}

void HandleClientTeams()
{
    switch (g_LastWinnerTeam)
    {
        case CS_TEAM_T:
        {
            // Reset a planter's spawn role, in order to generate a new random planter.
            int planter = GetPlanter();
            if (planter != -1)
            {
                g_Players[planter].spawn_role = SpawnRole_Defender;
            }

            BalanceTeams();
        }
        case CS_TEAM_CT:
        {
            BalanceTeams(true);
        }
    }
}

// Balances (or swaps) teams.
void BalanceTeams(bool swap = false)
{
    // Initialize attackers.
    ArrayList attackers = new ArrayList(sizeof(Player));

    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && IsRetakeClient(current_client) && GetClientTeam(current_client) == CS_TEAM_CT)
        {
            attackers.PushArray(g_Players[current_client]);
        }
    }

    // Sort the attackers arraylist by their points.
    attackers.SortCustom(ADTSortByPoints);

    // Erase any excesses.
    while (attackers.Length > retakes_max_attackers.IntValue)
    {
        attackers.Erase(attackers.Length - 1);
    }

    // Initialize defenders. (who does not appear in 'attackers')
    ArrayList defenders = new ArrayList(sizeof(Player));

    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && IsRetakeClient(current_client) && attackers.FindValue(current_client, Player::index) == -1)
        {
            defenders.PushArray(g_Players[current_client]);
        }
    }

    // Sort the defenders arraylist by their points.
    defenders.SortCustom(ADTSortByPoints);

    // Initialize spectators. (excesses from 'defenders')
    ArrayList spectators = new ArrayList(sizeof(Player));

    while (defenders.Length > retakes_max_defenders.IntValue)
    {
        SwapArrayData(defenders, defenders.Length - 1, spectators);
    }

    // Balance teams.
    //
    // There's no need to balance teams if there's no preferred team configurated
    // (retakes_preferred_team.IntValue == -1), or both teams have an equal amount of players.
    if (retakes_preferred_team.IntValue != -1 && defenders.Length != attackers.Length)
    {
        // 'iterations' = amount of potential team moves necessary in order to properly balance both teams.
        for (int iterations = IntAbs(defenders.Length - attackers.Length); iterations > 0; iterations--)
        {
            // More CTs than Ts, and preferred team is CT.
            if (attackers.Length > defenders.Length)
            {
                if (!swap && iterations == 1 && retakes_preferred_team.IntValue != CS_TEAM_T)
                {
                    break;
                }

                SwapArrayData(attackers, swap ? attackers.Length - 1 : 0, defenders);
            }
            // More Ts than CTs, and preferred team is T.
            else if (defenders.Length > attackers.Length)
            {
                if (!swap && iterations ==  1&& retakes_preferred_team.IntValue != CS_TEAM_CT)
                {
                    break;
                }

                SwapArrayData(defenders, swap ? defenders.Length - 1 : 0, attackers);
            }
        }
    }

    // Assign new teams.
    MovePlayersArray(attackers, swap ? CS_TEAM_T : CS_TEAM_CT);
    MovePlayersArray(defenders, swap ? CS_TEAM_CT : CS_TEAM_T);
    MovePlayersArray(spectators, CS_TEAM_SPECTATOR); // Move exceeding players to their new team - Spectators.

    delete attackers;
    delete defenders;
    delete spectators;
}

/**
 * @return              -1 if first should go before second
 *                      0 if first is equal to second
 *                      1 if first should go after second
 */
int ADTSortByPoints(int index1, int index2, Handle array, Handle hndl)
{
    ArrayList arr = view_as<ArrayList>(array);

    Player player1; arr.GetArray(index1, player1);
    Player player2; arr.GetArray(index2, player2);

    return FloatCompare(float(player2.points), float(player1.points));
}

void SwapArrayData(ArrayList source, int idx, ArrayList dest)
{
    any[] data = new any[source.BlockSize];
    source.GetArray(idx, data);
    source.Erase(idx);

    dest.PushArray(data);
}

void HandleQueuedClients()
{
    int max_players = GetRetakeMaxHumanPlayers();

    while (!g_QueuedPlayers.Empty && GetRetakeClientCount() < max_players)
    {
        int client = GetClientOfUserId(g_QueuedPlayers.Pop());
        if (client)
        {
            SetPlayerTeam(client, retakes_queued_players_team.IntValue);

#if defined DEBUG
            PrintToChatAll("Placed queued player in desired team. %N", client);
#endif
        }
    }
}

void MovePlayersArray(ArrayList array, int team)
{
    for (int current_idx, client; current_idx < array.Length; current_idx++)
    {
        client = array.Get(current_idx, Player::index);

        SetPlayerTeam(client, team);
    }
}

void ResetPlayersPoints()
{
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && IsRetakeClient(current_client))
        {
            g_Players[current_client].points = 0;
        }
    }
}

void DisableClientRetakeMode(int userid)
{
    int client = GetClientOfUserId(userid);
    if (client)
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

void SetPlayerTeam(int client, int team)
{
    // 'CS_SwitchTeam()' function does not supports spectator team, for some reason...
    if (team == CS_TEAM_SPECTATOR)
    {
        ChangeClientTeam(client, team);
    }
    else
    {
        CS_SwitchTeam(client, team);
    }
}

int IntAbs(int val)
{
   return (val < 0) ? -val : val;
}

void OrdinalSuffix(int number, char[] buffer, int maxlen)
{
    static const char InternalPrefix[][] = { "", "st", "nd", "rd", "th" };

    int idx = (number % 10);
    if (idx > 3)
    {
        idx = sizeof(InternalPrefix) - 1;
    }

    Format(buffer, maxlen, "%d%s", number, InternalPrefix[idx]);
}