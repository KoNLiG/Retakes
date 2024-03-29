/*
 * • Mainly acts as an instant defuse script.
 *
 * • Retake is a game mode where players get bored real quick if things
 * 	 move too slow, therefore we want to preserve as much as time possible.
 *
 * • Defuse logic is responsible for allowing attackers to instantly defuse
 * 	 the planted c4, when meeting the required conditions.
 *
 * • Required conditions to instantly defuse a planted c4:
 *		1. There is enough time to defuse the bomb. (5.0s using defuse kit, 10.0s without)
 * 		2. Zero defenders alive.
 * 		3. No active inferno enemy near the planted c4.
 */

#assert defined COMPILING_FROM_MAIN

bool g_SentNotification;

ConVar inferno_max_range;
ConVar mp_round_restart_delay;
ConVar mp_friendlyfire;

void DefuseLogic_OnPluginStart()
{
    if (!(inferno_max_range = FindConVar("inferno_max_range")))
    {
        SetFailState("Failed to find convar 'inferno_max_range'");
    }

    if (!(mp_round_restart_delay = FindConVar("mp_round_restart_delay")))
    {
        SetFailState("Failed to find convar 'mp_round_restart_delay'");
    }

    if (!(mp_friendlyfire = FindConVar("mp_friendlyfire")))
    {
        SetFailState("Failed to find convar 'mp_friendlyfire'");
    }
}

void DefuseLogic_OnBeginDefuse(int client, int planted_c4)
{
    if (!retakes_instant_defuse.BoolValue)
    {
        return;
    }

    InstaDefuseAttemptEx(client, planted_c4);
}

void DefuseLogic_OnBombDefused()
{
    PrintToChatAll("%T%T", "Messages Prefix", LANG_SERVER, "Success Defuse", LANG_SERVER);
}

void DefuseLogic_OnPlayerDeath(int client)
{
    if (!retakes_instant_defuse.BoolValue)
    {
        return;
    }

    if (GetClientTeam(client) != CS_TEAM_T)
    {
        return;
    }

    int defuser = FindDefuser();
    if (defuser == -1)
    {
        return;
    }

    int planted_c4 = GetPlantedC4();
    if (planted_c4 == -1)
    {
        return;
    }

    InstaDefuseAttemptEx(defuser, planted_c4);
}

void DefuseLogic_OnInfernoExpire()
{
    if (!retakes_instant_defuse.BoolValue)
    {
        return;
    }

    int defuser = FindDefuser();
    if (defuser == -1)
    {
        return;
    }

    int planted_c4 = GetPlantedC4();
    if (planted_c4 == -1)
    {
        return;
    }

    InstaDefuseAttemptEx(defuser, planted_c4);
}

void DefuseLogic_OnRoundPreStart()
{
    g_SentNotification = false;
}

// 'InstaDefuseAttempt' wrapper.
void InstaDefuseAttemptEx(int client, int planted_c4)
{
    DataPack dp = new DataPack();
    dp.WriteCell(g_Players[client].user_id);
    dp.WriteCell(EntIndexToEntRef(planted_c4));
    RequestFrame(InstaDefuseAttempt, dp);
}

// DataPack format:
// 1. [defuser userid] - cell
// 2. [c4 entity reference] - cell
void InstaDefuseAttempt(DataPack dp)
{
    dp.Reset();

    int client = dp.ReadCell(); // Userid.
    int planted_c4 = dp.ReadCell(); // Entity reference.

    dp.Close();

    // Validate entity indexes.
    if (!(client = GetClientOfUserId(client)) || (planted_c4 = EntRefToEntIndex(planted_c4)) == -1)
    {
        return;
    }

    int alive_defenders = GetTeamAliveClientCount(CS_TEAM_T);
    if (alive_defenders)
    {
        return;
    }

    // Time left till the bomb explosion. In seconds.
    float remaining_time = GetEntPropFloat(planted_c4, Prop_Send, "m_flC4Blow") - GetGameTime();

    // Time taken for the defuser to successfully defuse the bomb. (accounts for defuse kits)
    float defuse_time = GetEntPropFloat(planted_c4, Prop_Send, "m_flDefuseLength");

    // Note: Enough time to defuse would be: [remaining_time >= defuse_time]

    if (remaining_time >= defuse_time && IsInfernoNearC4(planted_c4, client))
    {
        if (!g_SentNotification)
        {
            PrintToChatAll("%T%T", "Messages Prefix", LANG_SERVER, "Close Inferno", LANG_SERVER);
            g_SentNotification = true;
        }

        return;
    }
    else
    {
        g_SentNotification = false;
    }

    if (remaining_time < defuse_time)
    {
        if (!g_SentNotification)
        {
            PrintToChatAll("%T%T", "Messages Prefix", LANG_SERVER, "Fail Defuse", LANG_SERVER, remaining_time);

            if (retakes_explode_no_time.BoolValue)
            {
                SetEntPropFloat(planted_c4, Prop_Send, "m_flC4Blow", 1.0);
            }

            // TODO: Check if round termination is needed even if 'retakes_explode_no_time' is enabled.
            CS_TerminateRound(mp_round_restart_delay.FloatValue - 1.0, CSRoundEnd_TerroristsPlanted);

            g_SentNotification = true;
        }

        return;
    }

    DefusePlantedC4(planted_c4);
}

void DefusePlantedC4(int planted_c4)
{
    SetEntPropFloat(planted_c4, Prop_Send, "m_flDefuseCountDown", 0.0);
}

int GetTeamAliveClientCount(int team)
{
    int count;

    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && GetClientTeam(current_client) == team && IsPlayerAlive(current_client))
        {
            count++;
        }
    }

    return count;
}

bool IsInfernoNearC4(int planted_c4, int defuser)
{
    // Retrieve the planted c4 origin.
    float c4_origin[3];
    GetEntPropVector(planted_c4, Prop_Send, "m_vecOrigin", c4_origin);

    int ent;
    while ((ent = FindEntityByClassname(ent, "inferno")) != -1)
    {
        // Exclude friendly inferno.
        // TODO: Check behavior when thrower leaves the game, is 'm_hOwnerEntity'
        // gonna be -1 and will fail due to invalid client index?
        int inferno_owner = GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity");
        if (defuser != inferno_owner && (!mp_friendlyfire.BoolValue && GetClientTeam(inferno_owner) == CS_TEAM_CT))
        {
            continue;
        }

        // Retrieve the inferno center origin and compare it to the planted c4 origin.
        float inferno_origin[3];
        GetEntPropVector(ent, Prop_Send, "m_vecOrigin", inferno_origin);

        if (GetVectorDistance(c4_origin, inferno_origin) <= inferno_max_range.FloatValue)
        {
            // Inferno is close enough to the planted c4, return true!
            return true;
        }
    }

    return false;
}

int FindDefuser()
{
    for (int current_client = 1; current_client <= MaxClients; current_client++)
    {
        if (IsClientInGame(current_client) && GetEntProp(current_client, Prop_Send, "m_bIsDefusing"))
        {
            return current_client;
        }
    }

    return -1;
}