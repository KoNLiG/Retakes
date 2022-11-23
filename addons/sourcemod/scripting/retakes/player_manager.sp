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

// Index of the last winning team.
int g_LastWinnerTeam;

void PlayerManager_OnPluginStart()
{
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

void PlayerManager_OnRoundEnd(int winner)
{
    g_LastWinnerTeam = winner;
}

void PlayerManager_OnRoundPreStart()
{
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

    if (g_LastWinnerTeam == CS_TEAM_CT)
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

        // Initialize attackers. (who does not appear in 'attackers')
        ArrayList defenders = new ArrayList(sizeof(Player));

        for (int current_client = 1; current_client <= MaxClients; current_client++)
        {
            if (IsClientInGame(current_client) && IsRetakeClient(current_client) && attackers.FindValue(current_client, Player::index) == -1)
            {
                defenders.PushArray(g_Players[current_client]);
            }
        }

        // Initialize attackers. (excesses from 'defenders')
        ArrayList spectators = new ArrayList(sizeof(Player));

        while (defenders.Length > retakes_max_defenders.IntValue)
        {
            SwapArrayData(defenders, sizeof(Player), defenders.Length - 1, spectators);
        }

        // Balance teams.
        if (retakes_preferred_team.IntValue != -1 && defenders.Length != attackers.Length)
        {
            for (int iterations = IntAbs(defenders.Length - attackers.Length); iterations; iterations--)
            {
                if (defenders.Length < attackers.Length && retakes_preferred_team.IntValue != CS_TEAM_T)
                {
                    SwapArrayData(attackers, sizeof(Player), attackers.Length - 1, defenders);
                }
                else if (defenders.Length > attackers.Length && retakes_preferred_team.IntValue != CS_TEAM_CT)
                {
                    SwapArrayData(defenders, sizeof(Player), defenders.Length - 1, attackers);
                }
            }
        }

        MovePlayersArray(attackers, CS_TEAM_T); // Move old attackers to their new team - Defenders/T.
        MovePlayersArray(defenders, CS_TEAM_CT); // Move old defenders to their new team - Attackers/CT.
        MovePlayersArray(spectators, CS_TEAM_SPECTATOR); // Move exceeding players to their new team - Spectators.

        delete attackers;
        delete defenders;
        delete spectators;
    }

    AssignPlayersSpawnRole();
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
    if (!g_IsWaitingForPlayers && g_Players[client].spawn_role == SpawnRole_None)
    {
        g_Players[client].spawn_role = GetTeamSpawnRole(GetClientTeam(client));

        #if defined DEBUG
        LogMessage("Auto assigned spawn role %d for client %d", g_Players[client].spawn_role, client);
        #endif
    }

    // Too early here.
    RequestFrame(DisableClientRetakeMode, GetClientUserId(client));
}

void PlayerManager_OnPlayerConnectFull(int client)
{
    g_Players[client].spawn_role = SpawnRole_None;

    SetPlayerTeam(client, CS_TEAM_SPECTATOR);
}

void PlayerManager_OnPlayerHurt(int attacker, int dmg_health)
{
    g_Players[attacker].points += dmg_health;
}

void SwapArrayData(ArrayList source, int size, int idx, ArrayList dest)
{
    any[] player = new any[size];
    source.GetArray(idx, player, size);
    source.Erase(idx);

    dest.PushArray(player);
}

/**
 * @return              -1 if first should go before second
 *                      0 if first is equal to second
 *                      1 if first should go after second
 */
int ADTSortByPoints(int index1, int index2, Handle array, Handle hndl)
{
    ArrayList al = view_as<ArrayList>(array);

    Player player1, player2;
    al.GetArray(index1, player1);
    al.GetArray(index2, player2);

    if (player1.points != player2.points)
    {
        return player1.points > player2.points ? -1 : 1;
    }

    return 0;
}

void MovePlayersArray(ArrayList array, int team)
{
    for (int current_idx, client; current_idx < array.Length; current_idx++)
    {
        client = array.Get(current_idx, Player::index);

#if defined DEBUG
        PrintToChatAll(" \x0CMoved %N to %d", client, team);
#endif

        SetPlayerTeam(client, team);
    }
}

void AssignPlayersSpawnRole()
{
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && IsRetakeClient(current_client))
        {
            g_Players[current_client].spawn_role = GetTeamSpawnRole(GetClientTeam(current_client));
        }
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